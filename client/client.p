// Prometheus modules
#load "basic.p";
#load "window.p";
#load "ui.p";
#load "mixer.p";
#load "threads.p";
#load "virtual_connection.p";
#load "graphics_engine/graphics_engine.p";

// Shared
#load "../shared/messages.p";
#load "../shared/world.p";

// Client
#load "draw.p";
#load "world.p";

// @Volatile: Must be in sync with server/server.p
Shared_Server_Data :: struct {
    state: enum {
        Starting;
        Running;
        Closing;
        Closed;
    };

    requested_port: u16;
}

Game_State :: enum {
    Main_Menu;
    Connecting;
    Lobby;
    Ingame;
}

Remote_Client :: struct {
    player_pid: Pid;
    entity_pid: Pid;
    name: string;
}

Client :: struct {
    //
    // Engine structure
    //
    window: Window;
    graphics: Graphics_Engine;
    ui: UI;
    mixer: Mixer;

    perm_pool: Memory_Pool;
    perm: Allocator;

    ui_font, title_font: Font;
    sprite_atlas: *GE_Texture;

    //
    // Networking
    //
    server_data: Shared_Server_Data = .{ .Closed, 0 };
    server_thread: Thread;
    connection: Virtual_Connection;
    remote_clients: [..]Remote_Client;
    my_player_pid: Pid;
    my_name: string;
    
    //
    // Game Data
    //
    state: Game_State;
    game_seed: s64;
    world: World;
    camera: Camera;
    my_entity_pid: Pid;
}




logprint :: (format: string, args: ..Any) {
    print(format, ..args);
    print("\n");
}




host_server :: (client: *Client, port: u16) {
    server_entry_point :: (data: *Shared_Server_Data) -> u32 #foreign;

    client.server_data.state = .Starting;
    client.server_data.requested_port = port;
    client.server_thread = create_thread(server_entry_point, *client.server_data, false);
    while client.server_data.state == .Starting {}
}

join_server :: (client: *Client, name: string, host: string, port: u16) {
    if create_client_connection(*client.connection, .UDP, host, port) == .Success {
        send_connection_request_packet(*client.connection, 5);
        client.my_name = copy_string(*client.perm, name);
        switch_to_state(client, .Connecting);
    } else {
        maybe_shutdown_server(client);
    }
}

disconnect_from_server :: (client: *Client) {
    send_connection_closed_packet(*client.connection, 5);
    destroy_connection(*client.connection);
    maybe_shutdown_server(client);
    deallocate_string(*client.perm, *client.my_name);
    
    for i := 0; i < client.remote_clients.count; ++i {
        deallocate_string(*client.perm, *array_get_pointer(*client.remote_clients, i).name);
    }
    
    array_clear(*client.remote_clients);
    
    switch_to_state(client, .Main_Menu);
}

start_lobby :: (client: *Client) {
    msg := make_message(Request_Game_Start_Message);
    send_reliable_message(*client.connection, *msg);
}

maybe_shutdown_server :: (client: *Client) {
    if client.server_data.state != .Closed {
        client.server_data.state = .Closing;
        join_thread(*client.server_thread);
    }
}

remove_client_by_pid :: (client: *Client, pid: Pid) {
    for i := 0; i < client.remote_clients.count; ++i {
        rc := array_get_pointer(*client.remote_clients, i);
        if rc.player_pid == pid {
            deallocate_string(*client.perm, *rc.name);
            array_remove_index(*client.remote_clients, i);
        }        
    }
}

find_client_by_pid :: (client: *Client, pid: Pid) -> *Remote_Client {
    for i := 0; i < client.remote_clients.count; ++i {
        rc := array_get_pointer(*client.remote_clients, i);
        if rc.player_pid == pid return rc;
    }
    
    return null;
}

handle_incoming_message :: (client: *Client, msg: *Message) {
    if #complete msg.type == {
      case .Request_Game_Start; // Ignore

      case .Player_Information;
        if msg.player_information.player_pid != client.my_player_pid {
            rc := find_client_by_pid(client, msg.player_information.player_pid);
            
            if rc == null {
                rc            = array_push(*client.remote_clients);
                rc.player_pid = msg.player_information.player_pid;
                rc.name       = copy_string(*client.perm, msg.player_information.name);
                rc.entity_pid = msg.player_information.entity_pid;
            } else if msg.player_information.entity_pid != INVALID_PID {
                rc.entity_pid = msg.player_information.entity_pid;
            }
        } else if msg.player_information.entity_pid != INVALID_PID {
            client.my_entity_pid = msg.player_information.entity_pid;
        }
    
      case .Player_Disconnect;
        remove_client_by_pid(client, msg.player_disconnect.player_pid);

      case .Game_Start;
        client.game_seed = msg.game_start.seed;
        switch_to_state(client, .Ingame);

      case .Create_Entity;
        create_entity_with_pid(*client.world, msg.create_entity.pid, msg.create_entity.kind, msg.create_entity.position);

      case .Destroy_Entity;
        mark_entity_for_removal(*client.world, msg.destroy_entity.pid);

      case .Move_Entity;
        entity := get_entity(*client.world, msg.move_entity.pid);
        if entity {
            entity.physical_position = msg.move_entity.position;
            entity.visual_position   = .{ xx entity.physical_position.x, xx entity.physical_position.y };
        }
    }
}

read_incoming_packets :: (client: *Client) {
    msg: Message = ---;
    
    while read_packet(*client.connection) {
        update_virtual_connection_information_for_packet(*client.connection, *client.connection.incoming_packet.header);
        
        if client.connection.incoming_packet.header.packet_type == {
          case Packet_Type.Connection_Request; // Ignore
          
          case Packet_Type.Connection_Established;
            if client.state == .Connecting {
                client.my_player_pid = client.connection.incoming_packet.header.sender_client_id;
                client.connection.info.client_id = client.my_player_pid;
                switch_to_state(client, .Lobby);
                
                msg := make_message(Player_Information_Message);
                msg.player_information.player_pid = client.my_player_pid;
                msg.player_information.name = client.my_name;
                send_reliable_message(*client.connection, *msg);
            }
          
          case Packet_Type.Connection_Closed;
            disconnect_from_server(client); // Server closed on us
          
          case Packet_Type.Message;
            read_message(*client.connection, *msg);
            handle_incoming_message(client, *msg);
        }
    }
}



switch_to_state :: (client: *Client, state: Game_State) {
    if #complete client.state == {
      case .Main_Menu;

      case .Connecting;
        if state != .Lobby {
            maybe_shutdown_server(client);
        }

      case .Lobby;
        if state != .Ingame {
            destroy_world(*client.world);
            maybe_shutdown_server(client);
        }
        
      case .Ingame;
        destroy_world(*client.world);
        maybe_shutdown_server(client);
    }

    client.state = state;
    
    if #complete client.state == {
      case .Main_Menu, .Connecting;
      
      case .Lobby;
        // We already create the world here because otherwise we cannot guarantee
        // the world has been created before the entities arrive from the server (since
        // our protocol does not guarantee the order in which messages will arrive.
        create_world(*client.world, *client.perm);
        client.camera.center = .{ 4, 2 };
        client.my_entity_pid = INVALID_PID;
        
      case .Ingame;
    }
}



do_main_menu :: (client: *Client) {
    ui :: *client.ui;
    
    ui_push_width(ui, .Pixels, 256, 1);

    // Host Window
    {
        ui_push_window(ui, "Host", .Default, .{ 0.33, 0.4 });
        ui_label(ui, false, "Name:");
        name := ui_text_input(ui, "Enter your name", .Everything);
        ui_divider(ui, true);
        ui_label(ui, false, "Port");
        port := ui_text_input(ui, "Enter the port", .Integer);
        ui_divider(ui, true);
        
        if ui_button(ui, "Host!") && name.valid && port.valid {
            host_server(client, port._int);
            join_server(client, name._string, "localhost", port._int);
        }
        
        ui_pop_window(ui);
    }

    // Join Window
    {
        ui_push_window(ui, "Join", .Default, .{ 0.66, 0.4 });
        ui_label(ui, false, "Name:");
        name := ui_text_input(ui, "Enter your name", .Everything);
        ui_divider(ui, true);
        ui_label(ui, false, "Host");
        host := ui_text_input(ui, "Enter the address", .Everything);
        ui_label(ui, false, "Port");
        port := ui_text_input(ui, "Enter the port", .Integer);
        ui_divider(ui, true);
        
        if ui_button(ui, "Join!") && name.valid && host.valid && port.valid {
            join_server(client, name._string, host._string, port._int);
        }
        
        ui_pop_window(ui);
    }
        
    ui_pop_width(ui);
}

do_connecting_screen :: (client: *Client) {
    read_incoming_packets(client);

    {
        ui :: *client.ui;
        ui_push_width(ui, .Pixels, 256, 1);
        ui_push_window(ui, "Connecting...", .Default, .{ .5, .5 });
        ui_label(ui, false, "...");
        ui_divider(ui, true);
        if ui_button(ui, "Cancel!") {
            disconnect_from_server(client);
        }
        ui_pop_window(ui);
        ui_pop_width(ui);
    }    
}

do_lobby_screen :: (client: *Client) {
    read_incoming_packets(client);

    {
        ui :: *client.ui;
        ui_push_width(ui, .Pixels, 256, 1);
        ui_push_window(ui, "Lobby!", .Default, .{ .5, .5 });
        
        ui_label(ui, false, client.my_name);
        
        for i := 0; i < client.remote_clients.count; ++i {
            rc := array_get_pointer(*client.remote_clients, i);
            ui_label(ui, false, rc.name);
        }

        ui_divider(ui, true);
        if ui_button(ui, "Start!") {
            start_lobby(client);
        }
        
        ui_divider(ui, true);
        if ui_button(ui, "Disconnect!") {
            disconnect_from_server(client);
        }
        ui_pop_window(ui);
        ui_pop_width(ui);
    }
}

do_game_tick :: (client: *Client) {
    read_incoming_packets(client);

    outgoing_messages: [..]Message;
    outgoing_messages.allocator = *temp;
    
    // Update the camera
    {
        if client.window.keys[.Arrow_Left]  & .Repeated client.camera.center.x -= 1;
        if client.window.keys[.Arrow_Right] & .Repeated client.camera.center.x += 1;
        if client.window.keys[.Arrow_Up]    & .Repeated client.camera.center.y -= 1;
        if client.window.keys[.Arrow_Down]  & .Repeated client.camera.center.y += 1;
        update_camera_matrices(*client.camera, *client.window);
    }

    // Move the player
    {
        velocity: v2i = .{ 0, 0 };

        if client.window.keys[.A] & .Repeated velocity.x -= 1;
        if client.window.keys[.D] & .Repeated velocity.x += 1;
        if client.window.keys[.W] & .Repeated && velocity.x == 0 velocity.y -= 1;
        if client.window.keys[.S] & .Repeated && velocity.x == 0 velocity.y += 1;

        if velocity.x != 0 || velocity.y != 0 {
            entity := get_entity(*client.world, client.my_entity_pid);

            msg := make_message(Move_Entity_Message);
            msg.move_entity.pid = entity.pid;
            msg.move_entity.position.x = entity.physical_position.x + velocity.x;
            msg.move_entity.position.y = entity.physical_position.y + velocity.y;
            array_add(*outgoing_messages, msg);
        }
    }

    // Send all outgoing messages
    {
        for i := 0; i < outgoing_messages.count; ++i {
            send_reliable_message(*client.connection, array_get_pointer(*outgoing_messages, i));
        }
    }
    
    remove_all_marked_entities(*client.world);
}

main :: () -> s32 {
    //
    // Start up the engine
    //
    set_working_directory_to_executable_path();
    os_enable_high_resolution_timer();
    create_temp_allocator(128 * Memory_Unit.Megabytes);
    
    client: Client;
    create_memory_pool(*client.perm_pool, 32 * Memory_Unit.Megabytes, 128 * Memory_Unit.Kilobytes);
    client.perm = allocator_from_memory_pool(*client.perm_pool);

    create_window(*client.window, "Glassminers", WINDOW_DONT_CARE, WINDOW_DONT_CARE, WINDOW_DONT_CARE, WINDOW_DONT_CARE, .Default);
    ge_create(*client.graphics, *client.window, *client.perm);
    ge_create_font_from_file(*client.graphics, *client.ui_font, "data/font.ttf", 12, .Ascii);
    ge_create_font_from_file(*client.graphics, *client.title_font, "data/font.ttf", 45, .Ascii);
    client.sprite_atlas = ge_create_texture_from_file(*client.graphics, "data/sprite_atlas.png");
    create_ui(*client.ui, draw_ui_callbacks(*client), UI_Dark_Theme, *client.window, *client.ui_font);
    create_mixer(*client.mixer, 1);

    client.remote_clients.allocator = *client.perm;
    client.state = .Count;
    
    switch_to_state(*client, .Main_Menu); // Potentially initialize resources

    //
    // Main loop
    //
    while !client.window.should_close {
        frame_start := os_get_hardware_time();
        
        //
        // Do one frame
        //
        {
            update_window(*client.window);
            begin_ui_frame(*client.ui, .{ 128, 24 });
            
            if #complete client.state == {
              case .Main_Menu;  do_main_menu(*client);
              case .Connecting; do_connecting_screen(*client);
              case .Lobby;      do_lobby_screen(*client);
              case .Ingame;     do_game_tick(*client);
            }
        }
        
        //
        // Draw one frame
        //
        {
            ge_clear_screen(*client.graphics, .{ 40, 40, 50, 255 });
            
            if #complete client.state == {
              case .Main_Menu, .Connecting, .Lobby;
                draw_text(*client, *client.title_font, "GlassMiners", xx client.window.w / 2, xx client.window.h / 4, .Center | .Median, .{ 255, 255, 255, 255 });
                draw_ui_frame(*client.ui);
            
              case .Ingame;
                draw_world(*client);
                draw_ui_frame(*client.ui);
            }
                        
            ge_swap_buffers(*client.graphics);
        }

        release_temp_allocator(0);
        
        frame_end := os_get_hardware_time();
        os_sleep_to_tick_rate(frame_start, frame_end, 144);
    }

    switch_to_state(*client, .Count); // Shut down all resources that might currently be in use
        
    //
    // Destroy the engine
    //
    destroy_mixer(*client.mixer);
    destroy_ui(*client.ui);
    ge_destroy_texture(*client.graphics, client.sprite_atlas);
    ge_destroy_font(*client.graphics, *client.ui_font);
    ge_destroy_font(*client.graphics, *client.title_font);
    ge_destroy(*client.graphics);
    destroy_window(*client.window);
    destroy_memory_pool(*client.perm_pool);
    destroy_temp_allocator();

    return 0;
}
