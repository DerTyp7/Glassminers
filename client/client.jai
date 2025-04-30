// Prometheus modules
#load "compiler.jai";
#load "basic.jai";
#load "window.jai";
#load "ui.jai";
#load "mixer.jai";
#load "threads.jai";
#load "virtual_connection.jai";
#load "graphics_engine/graphics_engine.jai";

// Shared
#load "../shared/messages.jai";
#load "../shared/world.jai";
#load "../shared/shared.jai";

// Client
#load "draw.jai";
#load "world.jai";
#load "assets.jai";

DEVELOPER :: #run compiler_is_user_option_present("Developer");

Game_State :: enum {
    Main_Menu;
    Connecting;
    Lobby;
    Ingame;
    Game_Over;
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
    ui_pipeline: *GE_Pipeline;
    entity_pipeline: *GE_Pipeline;
    
    epoch_time: f32;
    
    current_state: Game_State;
    next_state: Game_State;

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
    game_seed: s64;
    world: World;
    camera: Camera;
    my_entity_pid: Pid;
    won_last_game: bool;
    tick_time: f32;
}



Log_Level :: enum {
    Debug;
    Warning;
    Error;
}

logprint :: (level: Log_Level, format: string, args: ..Any) {
    print("[%] ", enum_names(Log_Level)[level]);
    print(format, ..args);
    print("\n");
}



host_server :: (client: *Client, port: u16) {
    server_entry_point :: (data: *Shared_Server_Data) -> u32 #foreign;

    client.server_data.state = .Starting;
    client.server_data.requested_port = port;
    client.server_thread = create_thread(server_entry_point, *client.server_data, false);
    while atomic_load(cast(*s64) *client.server_data.state) == Server_State.Starting {}
}

join_server :: (client: *Client, name: string, host: string, port: u16) {
    if create_client_connection(*client.connection, .UDP, host, port) == .Success {
        send_connection_request_packet(*client.connection, 5);
        client.my_name = copy_string(*client.perm, name);
        transition_to_state(client, .Connecting);
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
    
    transition_to_state(client, .Main_Menu);
}

start_lobby :: (client: *Client) {
    msg := make_message(Request_Game_Start_Message);
    send_reliable_message(*client.connection, *msg);
}

maybe_shutdown_server :: (client: *Client) {
    previous, success := atomic_compare_and_exchange(cast(*s64) *client.server_data.state, Server_State.Running, Server_State.Closing);
    if success {
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
    if #complete msg.msg_type == {
      case .Request_Game_Start, .Player_Interact, .Player_Move; // Ignore

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
        client.world.size = msg.game_start.size;
        transition_to_state(client, .Ingame);
        
      case .Game_Over;
        client.won_last_game = msg.game_over.you_won;
        transition_to_state(client, .Game_Over);
        
      case .Create_Entity;
        create_entity_with_pid(*client.world, msg.create_entity.entity_pid, msg.create_entity.kind, msg.create_entity.position, msg.create_entity.rotation);

      case .Destroy_Entity;
        entity := get_entity(*client.world, msg.destroy_entity.entity_pid);
        entity.marked_for_removal = true;

      case .Move_Entity;
        entity := get_entity(*client.world, msg.move_entity.entity_pid);
        entity.physical_position = msg.move_entity.position;
        entity.physical_rotation = msg.move_entity.rotation;
        entity.visual_position   = .{ xx entity.physical_position.x, xx entity.physical_position.y };
        entity.visual_rotation   = visual_from_physical_rotation(entity.physical_rotation);

      case .Entity_Health;
        entity := get_entity(*client.world, msg.entity_health.entity_pid);
        entity.health = msg.entity_health.current_health;
        
      case .Player_State;
        entity := get_entity(*client.world, msg.player_state.entity_pid);
        player := down(entity, Player);
        player.state = msg.player_state.state;
        player.target_position = msg.player_state.target_position;
        player.carrying_item = msg.player_state.carrying_item;

      case .Emitter_State;
        entity := get_entity(*client.world, msg.emitter_state.entity_pid);
        emitter := down(entity, Emitter);
        emitter.time_left_in_seconds = msg.emitter_state.time_left_in_seconds;
        
      case .Receiver_State;
        entity := get_entity(*client.world, msg.receiver_state.entity_pid);
        receiver := down(entity, Receiver);
        receiver.progress_time_in_seconds = msg.receiver_state.progress_time_in_seconds;
    }
}

read_incoming_packets :: (client: *Client) {
    while read_packet(*client.connection) {
        update_virtual_connection_information_for_packet(*client.connection, *client.connection.incoming_packet.header);
        
        if client.connection.incoming_packet.header.packet_type == {
          case Packet_Type.Connection_Request; // Ignore
          
          case Packet_Type.Connection_Established;
            if client.next_state == .Connecting {
                client.my_player_pid = client.connection.incoming_packet.header.sender_client_id;
                client.connection.info.client_id = client.my_player_pid;
                transition_to_state(client, .Lobby);
                
                msg := make_message(Player_Information_Message);
                msg.player_information.player_pid = client.my_player_pid;
                msg.player_information.name = client.my_name;
                send_reliable_message(*client.connection, *msg);
            }
          
          case Packet_Type.Connection_Closed;
            disconnect_from_server(client); // Server closed on us

          case Packet_Type.Ping;
            
          case Packet_Type.Message;
            msg: Message = ---;
            while read_message(*client.connection, *msg) {
                handle_incoming_message(client, *msg);
            }
        }
    }
}

handle_server_timeout :: (client: *Client) {
    if os_convert_hardware_time(os_get_hardware_time() - client.connection.time_of_last_received_packet, .Seconds) > NETWORK_TIMEOUT {
        // @Cleanup: We should probably inform the player on why they were disconnected, by showing
        // a message in the main menu?
        disconnect_from_server(client);
    } else if os_convert_hardware_time(os_get_hardware_time() - client.connection.time_of_last_sent_packet, .Seconds) > NETWORK_PING_INTERVAL {
        send_ping_packet(*client.connection);
    }
}



transition_to_state :: (client: *Client, state: Game_State) {
    client.next_state = state;
}

switch_to_next_state :: (client: *Client) {
    if #complete client.current_state == {
      case .Main_Menu, .Game_Over;

      case .Connecting;
        if client.next_state != .Lobby {
            maybe_shutdown_server(client);
        }

      case .Lobby;
        if client.next_state != .Ingame {
            destroy_world(*client.world);
            maybe_shutdown_server(client);
        }
        
      case .Ingame;
        destroy_world(*client.world);
        disconnect_from_server(client);
        maybe_shutdown_server(client);
    }

    client.current_state = client.next_state;
    
    if #complete client.current_state == {
      case .Main_Menu, .Connecting, .Ingame, .Game_Over;
      
      case .Lobby;
        // We already create the world here because otherwise we cannot guarantee
        // the world has been created before the entities arrive from the server (since
        // our protocol does not guarantee the order in which messages will arrive.
        create_world(*client.world, *client.perm);
        client.camera.center = .{ 4, 2 };
        client.my_entity_pid = INVALID_PID;
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
        
        if ui_button(ui, "Host!") {
#if DEVELOPER {
            if !name._string.count then { name._string = "Victor"; name.valid = true; }
            if !port.valid then { port._int = 9876; port.valid = true; }
}
    
            if name.valid && port.valid {
                host_server(client, port._int);
                join_server(client, name._string, "localhost", port._int);
            }
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
        
        if ui_button(ui, "Join!") {
#if DEVELOPER {
            if !name._string.count then { name._string = "Surreal"; name.valid = true; }
            if !host._string.count then { host._string = "localhost"; host.valid = true; }
            if !port.valid then { port._int = 9876; port.valid = true; }
}
                
            if name.valid && host.valid && port.valid {
                join_server(client, name._string, host._string, port._int);
            }
        }
        
        ui_pop_window(ui);
    }
        
    ui_pop_width(ui);
}

do_connecting_screen :: (client: *Client) {
    read_incoming_packets(client);
    handle_server_timeout(client);
    
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
    handle_server_timeout(client);

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

do_game_over_screen :: (client: *Client) {
    ui :: *client.ui;
    ui_push_width(ui, .Pixels, 256, 1);
    ui_push_window(ui, "Game Over!", .Default, .{ .5, .5 });

    if client.won_last_game {
        ui_label(ui, true, "You won!");    
    } else {
        ui_label(ui, true, "You lost!");
    }
    
    ui_divider(ui, true);
    if ui_button(ui, "Back to Main Menu!") {
        disconnect_from_server(client);
    }
    ui_pop_window(ui);
    ui_pop_width(ui);
}

do_game_tick :: (client: *Client) {
    clamp_camera_position :: (client: *Client, target_position: v2f) -> v2f {
        ROOM_OFFSET :: v2f.{ 4, 2 };
        ROOM_SIZE   :: v2f.{ 9, 5 };
        
        room_position := v2f.{ floor(target_position.x / ROOM_SIZE.x) * ROOM_SIZE.x + ROOM_OFFSET.x, 
                               floor(target_position.y / ROOM_SIZE.y) * ROOM_SIZE.y + ROOM_OFFSET.y };
        half_size     := v2f.{ floor(client.camera.size.x / 2), floor(client.camera.size.y / 2) };
        
        return .{ clamp(room_position.x, half_size.x, xx client.world.size.x - half_size.x - 1),
                  clamp(room_position.y, half_size.y, xx client.world.size.y - half_size.y - 1) };
    }

    client.tick_time = client.window.frame_time;
    
    read_incoming_packets(client);
    handle_server_timeout(client);

    //
    // Update all local entities based on the information received by the server.
    // This also does some basic client-side prediction
    //
    {
        for i := 0; i < client.world.entities.count; ++i {
            entity := array_get_pointer(*client.world.entities, i);

            if entity.kind == {
              case .Emitter;
                emitter := down(entity, Emitter);
                
                if emitter.time_left_in_seconds > 0 {
                    emitter.time_left_in_seconds -= client.tick_time;
                }

                recalculate_emitter(*client.world, entity, emitter);

              case .Receiver;
                receiver := down(entity, Receiver);

                if receiver.progress_time_in_seconds < RECEIVER_TIME_TO_CHARGE {
                    receiver.progress_time_in_seconds += client.tick_time;
                }
            }
        }
    }

    outgoing_messages: [..]Message;
    outgoing_messages.allocator = *temp;
    
    // Update the camera
    {
        player := get_entity(*client.world, client.my_entity_pid);
        client.camera.center = clamp_camera_position(client, player.visual_position);
        update_camera_matrices(*client.camera, *client.window);
    }

    // Forward player input to the server
    {
        send_player_move := false;
        new_position: v2i = ---;
        new_aim_direction: Direction = ---;
        
        if client.window.keys[.A] & .Repeated {
            entity := get_entity(*client.world, client.my_entity_pid);
            new_position.x    = entity.physical_position.x - 1;
            new_position.y    = entity.physical_position.y;
            new_aim_direction = .West;
            send_player_move  = true;
        }

        if client.window.keys[.D] & .Repeated {
            entity := get_entity(*client.world, client.my_entity_pid);
            new_position.x = entity.physical_position.x + 1;
            new_position.y = entity.physical_position.y;
            new_aim_direction = .East;
            send_player_move = true;
        }

        if client.window.keys[.W] & .Repeated {
            entity := get_entity(*client.world, client.my_entity_pid);
            new_position.x = entity.physical_position.x;
            new_position.y = entity.physical_position.y - 1;
            new_aim_direction = .North;
            send_player_move = true;
        }

        if client.window.keys[.S] & .Repeated {
            entity := get_entity(*client.world, client.my_entity_pid);
            new_position.x = entity.physical_position.x;
            new_position.y = entity.physical_position.y + 1;
            new_aim_direction = .South;
            send_player_move = true;
        }

        if client.window.keys[.Arrow_Left] & .Pressed {
            new_aim_direction = .West;
            send_player_move = true;
        }

        if client.window.keys[.Arrow_Right] & .Pressed {
            new_aim_direction = .East;
            send_player_move = true;
        }

        if client.window.keys[.Arrow_Up] & .Pressed {
            new_aim_direction = .North;
            send_player_move = true;
        }

        if client.window.keys[.Arrow_Down] & .Pressed {
            new_aim_direction = .South;
            send_player_move = true;
        }
        
        if send_player_move {
            msg := make_message(Player_Move_Message);
            msg.player_move.entity_pid    = client.my_entity_pid;
            msg.player_move.position      = new_position;
            msg.player_move.aim_direction = new_aim_direction;
            array_add(*outgoing_messages, msg);
        }
        
        if client.window.keys[.Space] & .Pressed {
            msg := make_message(Player_Interact_Message);
            msg.player_interact.entity_pid = client.my_entity_pid;
            msg.player_interact.interaction_kind = .Primary;
            array_add(*outgoing_messages, msg);
        }
        
        if client.window.keys[.Shift] & .Pressed {
            msg := make_message(Player_Interact_Message);
            msg.player_interact.entity_pid = client.my_entity_pid;
            msg.player_interact.interaction_kind = .Secondary;
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

    window_mode: Window_Style_Flags = ifx !DEVELOPER then (.Fullscreen | .Maximized) else .Default; // nocheckin
    create_window(*client.window, "Glassminers", WINDOW_DONT_CARE, WINDOW_DONT_CARE, WINDOW_DONT_CARE, WINDOW_DONT_CARE, window_mode);
    create_draw_data(*client);
    create_ui(*client.ui, 1024, draw_ui_callbacks(*client), UI_Dark_Theme, *client.window, *client.ui_font);
    create_mixer(*client.mixer, 1);

    client.remote_clients.allocator = *client.perm;
    client.current_state = .Count;
    client.next_state    = .Count;
    
    transition_to_state(*client, .Main_Menu); // Potentially initialize resources
    switch_to_next_state(*client);

    //
    // Main loop
    //
    while !client.window.should_close {
        frame_start := os_get_hardware_time();

        if client.current_state != client.next_state switch_to_next_state(*client);
        
        //
        // Do one frame
        //
        {
            update_window(*client.window);
            begin_ui_frame(*client.ui, .{ 128, 24 });
            
            if #complete client.current_state == {
              case .Main_Menu;  do_main_menu(*client);
              case .Connecting; do_connecting_screen(*client);
              case .Lobby;      do_lobby_screen(*client);
              case .Ingame;     do_game_tick(*client);
              case .Game_Over;  do_game_over_screen(*client);
            }
        }
        
        //
        // Draw one frame
        //
        {
            ge_clear_screen(*client.graphics, .{ 40, 40, 50, 255 });
            
            if #complete client.current_state == {
              case .Main_Menu, .Connecting, .Lobby, .Game_Over;
                draw_text_screen_space(*client, *client.title_font, "GlassMiners", .{ xx client.window.w / 2, xx client.window.h / 4 }, .Center | .Median, .{ 255, 255, 255, 255 });
            
              case .Ingame;
                draw_world(*client);
            }
             
            draw_ui_frame(*client.ui);
            ge_swap_buffers(*client.graphics);
        }

        client.epoch_time += client.window.frame_time;
        release_temp_allocator(0);
        
        frame_end := os_get_hardware_time();
        os_sleep_to_tick_rate(frame_start, frame_end, 144);
    }
    
    // Shut down all resources that might currently be in use
    transition_to_state(*client, .Count);
    switch_to_next_state(*client);
    
    //
    // Destroy the engine
    //
    destroy_mixer(*client.mixer);
    destroy_ui(*client.ui);
    destroy_draw_data(*client);
    destroy_window(*client.window);
    destroy_memory_pool(*client.perm_pool);
    destroy_temp_allocator();
    return 0;
}
