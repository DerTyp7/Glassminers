// Jai modules
#load "compiler.jai";
#load "basic.jai";
#load "sort.jai";
#load "window.jai";
#load "hash_table.jai";
#load "ui.jai";
#load "mixer.jai";
#load "threads.jai";
#load "random.jai";
#load "virtual_connection.jai";
#load "graphics_engine/graphics_engine.jai";

#load "stb/stb_image_write.jai";
#load "file_watcher.jai";

// Shared
#load "../shared/messages.jai";
#load "../shared/shared.jai";
#load "../shared/bucket_array.jai";
#load "../shared/VERSION_STRING.jai";

// Client
#load "draw.jai";
#load "entity.jai";
#load "assets.jai";
#load "hud.jai";
#load "sounds.jai";
#load "particles.jai";

DEVELOPER :: #run compiler_is_user_option_present("Developer");
BAKE_ASSETS :: !DEVELOPER;
DEFAULT_INFO_TEXT_TIMER: f32 : 5;
TARGET_FRAMES_PER_SECOND: f32 : 144;

Game_State :: enum {
    Main_Menu;
    Connecting;
    Lobby;
    Ingame;
    Game_Over;
}

Previous_Game_Result :: enum {
    We_Won;
    We_Lost;
    Connection_Lost;
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
    
    engine_pool: Memory_Pool;
    engine_allocator: Allocator;
    epoch_time: f32;
    
    current_state: Game_State;
    next_state: Game_State;
    previous_game_result: Previous_Game_Result;
    info_text: string;
    info_text_t: f32;
    
    //
    // Assets
    //
    ui_font, title_font: Font;
    ui_pipeline: *GE_Pipeline;
    entity_pipeline: *GE_Pipeline;
    sprite_atlases: [SPRITE_ATLAS_COUNT]*GE_Texture;
    sounds: [Sound_Index.Count]Sound_Data;
    sounds_played_this_frame: [Sound_Index.Count]bool;
    
#if DEVELOPER {
    sound_watchdog: File_Watcher;
    sprite_watchdog: File_Watcher;
}

    //
    // Input System
    //
    input_bindings: [Input_Action.Count][]Input_Binding;
    active_input_device: Input_Device;
    
    //
    // Networking
    //
    server_data: Shared_Server_Data = .{ .Closed, 0 };
    server_thread: Thread;
    connection: Virtual_Connection;
    sent_connection_request: bool;
    remote_clients: [..]Remote_Client;
    my_player_pid: Pid;
    my_name: string;
    
    //
    // Game Data
    //
    world_pool: Memory_Pool;
    world_allocator: Allocator;
    requested_campaign: Campaign = .Tutorial; // Lobby screen
    immediately_start_game: bool = false; // Lobby screen, when coming from a single player
    pause_menu_open: bool;
    game_seed: s64;
    world_size: v2i;
    tick_time: f32;
    camera: Camera;
    hud: Hud;
    my_entity_pid: Pid;
    #using em: Entity_Manager;
}



Log_Level :: enum {
    Debug;
    Warning;
    Error;
}

logprint :: (level: Log_Level, format: string, args: ..Any) {
    print("[CLIENT][%] ", enum_names(Log_Level)[level]);
    print(format, ..args);
    print("\n");
}

set_info_text :: (client: *Client, time: f32, format: string, args: ..Any) {
    deallocate_string(*client.engine_allocator, *client.info_text);
    client.info_text = print_into_allocator(*client.engine_allocator, format, args);
    client.info_text_t = time;
}



Input_Device :: enum {
    Keyboard;
    Gamepad;
}

Input_Action :: enum {
    Toggle_Pause_Menu;
    Toggle_Fullscreen;

    Move_North;
    Move_East;
    Move_South;
    Move_West;
    Look_North;
    Look_East;
    Look_South;
    Look_West;

    Interact_Primary;
    Interact_Secondary;
    
    Crafting_Menu_Toggle;
    Crafting_Menu_Confirm;
    Crafting_Menu_Left;
    Crafting_Menu_Right;
}

Input_Binding :: struct {
    kind: enum {
        Keyboard;
        Gamepad_Button;
        Gamepad_Gesture;
    };

    #using data: union {
        keycode: Key_Code;
        gamepad_button: Window_Gamepad_Button_Code;
        gamepad_gesture: Window_Gamepad_Gesture_Code;
    };
}

register_all_input_bindings :: (client: *Client) {
    keycode :: (keycode: Key_Code) -> Input_Binding {
        binding: Input_Binding = ---;
        binding.kind = .Keyboard;
        binding.keycode = keycode;
        return binding;
    }

    gamepad_button :: (button: Window_Gamepad_Button_Code) -> Input_Binding {
        binding: Input_Binding = ---;
        binding.kind = .Gamepad_Button;
        binding.gamepad_button = button;
        return binding;
    }

    gamepad_gesture :: (gesture: Window_Gamepad_Gesture_Code) -> Input_Binding {
        binding: Input_Binding = ---;
        binding.kind = .Gamepad_Gesture;
        binding.gamepad_gesture = gesture;
        return binding;
    }
    
    //
    // The input bindings need to live forever, but making slices in here allocates them on the
    // stack (and so they are dead when the procedure exists).
    // Therefore, for easier setup I construct them locally here, and then copy them into the
    // engine allocator later on.
    //

    ib: [Input_Action.Count][]Input_Binding = ---;
    ib[.Toggle_Pause_Menu]     = .[ keycode(.Escape), gamepad_button(.PS_Options), gamepad_button(.XBox_Start) ];
    ib[.Toggle_Fullscreen]     = .[ keycode(.F11) ];
    ib[.Move_North]            = .[ keycode(.W), gamepad_gesture(.Left_Swipe_Up) ];
    ib[.Move_East]             = .[ keycode(.D), gamepad_gesture(.Left_Swipe_Right) ];
    ib[.Move_South]            = .[ keycode(.S), gamepad_gesture(.Left_Swipe_Down) ];
    ib[.Move_West]             = .[ keycode(.A), gamepad_gesture(.Left_Swipe_Left) ];
    ib[.Look_North]            = .[ keycode(.Arrow_Up), gamepad_gesture(.Right_Swipe_Up) ];
    ib[.Look_East]             = .[ keycode(.Arrow_Right), gamepad_gesture(.Right_Swipe_Right) ];
    ib[.Look_South]            = .[ keycode(.Arrow_Down), gamepad_gesture(.Right_Swipe_Down) ];
    ib[.Look_West]             = .[ keycode(.Arrow_Left), gamepad_gesture(.Right_Swipe_Left) ];
    ib[.Interact_Primary]      = .[ keycode(.Space), gamepad_button(.PS_Cross), gamepad_button(.XBox_A) ];
    ib[.Interact_Secondary]    = .[ keycode(.Shift), gamepad_button(.PS_Square), gamepad_button(.XBox_X) ];
    ib[.Crafting_Menu_Toggle]  = .[ keycode(.Shift), gamepad_button(.PS_Square), gamepad_button(.XBox_X) ];
    ib[.Crafting_Menu_Confirm] = .[ keycode(.Space), gamepad_button(.PS_Cross), gamepad_button(.XBox_A) ];
    ib[.Crafting_Menu_Left]    = .[ keycode(.A), keycode(.Arrow_Left), gamepad_button(.Left_Bumper), gamepad_gesture(.Left_Swipe_Left) ];
    ib[.Crafting_Menu_Right]   = .[ keycode(.D), keycode(.Arrow_Right), gamepad_button(.Right_Bumper), gamepad_gesture(.Left_Swipe_Right) ];

    for i := 0; i < ib.Capacity; ++i {
        client.input_bindings[i] = copy_array(*client.engine_allocator, ib[i]);
    }
}
    
input_action_fired :: (client: *Client, action: Input_Action) -> bool {
    for i := 0; i < client.input_bindings[action].count; ++i {
        binding := client.input_bindings[action][i];
        
        if #complete binding.kind == {
          case .Keyboard;
            if client.window.keys[binding.keycode] & .Pressed {
                client.active_input_device = .Keyboard;
                return true;
            }
            
          case .Gamepad_Button;
            if client.window.connected_gamepads && client.window.gamepads[0].buttons[binding.gamepad_button] & .Pressed {
                client.active_input_device = .Gamepad;
                return true;
            }

          case .Gamepad_Gesture;
            if client.window.connected_gamepads && client.window.gamepads[0].gestures[binding.gamepad_gesture] {
                client.active_input_device = .Gamepad;
                return true;
            }
        }
    }

    return false;
}



host_server :: (client: *Client, port: u16) {
    logprint(.Debug, "Hosting server '%'...", port);
    server_entry_point :: (data: *Shared_Server_Data) -> u32 #foreign;

    client.server_data.state = .Starting;
    client.server_data.requested_port = port;
    client.server_thread = create_thread(server_entry_point, *client.server_data, false);
    while atomic_load(cast(*s64) *client.server_data.state) == Server_State.Starting {}
}

join_server :: (client: *Client, name: string, host: string, port: u16) {
    logprint(.Debug, "Joining server '%:%'...", host, port);

    //
    // :ConnectionRequest
    // We are using non-blocking TCP sockets. That includes the initial connect() call in the virtual
    // connection module. This allows the game to not freeze while attempting to open a connection. However,
    // this also means that we have to wait with writing the first packets until the TCP handshake has
    // happened, which can obviously take a while when talking over the internet. Therefore, our
    // own connection request packets need to wait for the TCP handshake to have happened, which is why
    // that happens inside the connection screen.
    //
    client.sent_connection_request = false;

    result := create_client_connection(*client.connection, NETWORK_PROTOCOL, host, port);
    if result == .Success {
        client.my_name    = copy_string(*client.engine_allocator, name);
        client.next_state = .Connecting;
    } else {
        set_info_text(client, DEFAULT_INFO_TEXT_TIMER, "Could not connect to server: %.", result);
        disconnect_from_server(client);
        maybe_shutdown_server(client);
    }
}

disconnect_from_server :: (client: *Client) {
    logprint(.Debug, "Disconnecting from the server...");

    send_connection_closed_packet(*client.connection, 5);
    os_sleep(NETWORK_CONNECTION_DIE_SPEED);
    destroy_connection(*client.connection);
    maybe_shutdown_server(client);
    deallocate_string(*client.engine_allocator, *client.my_name);
    
    for i := 0; i < client.remote_clients.count; ++i {
        deallocate_string(*client.world_allocator, *array_get_pointer(*client.remote_clients, i).name);
    }
    
    array_clear(*client.remote_clients);
}

start_lobby :: (client: *Client) {
    msg := make_message(Request_Game_Start_Message);
    msg.request_game_start.campaign = client.requested_campaign;
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
            deallocate_string(*client.world_allocator, *rc.name);
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
      case .Request_Game_Start, .Guy_Input; // Ignore

      case .Player_Information;
        if msg.player_information.player_pid != client.my_player_pid {
            rc := find_client_by_pid(client, msg.player_information.player_pid);
            
            if rc == null {
                rc            = array_push(*client.remote_clients);
                rc.player_pid = msg.player_information.player_pid;
                rc.name       = copy_string(*client.world_allocator, msg.player_information.name);
                rc.entity_pid = msg.player_information.entity_pid;
            } else if msg.player_information.entity_pid != INVALID_PID {
                rc.entity_pid = msg.player_information.entity_pid;
            }
        } else if msg.player_information.entity_pid != INVALID_PID {
            client.my_entity_pid = msg.player_information.entity_pid;

            // Calculate the initial camera position to avoid lerping the first few frames...
            player := get_entity(client, client.my_entity_pid);
            update_camera_matrices(*client.camera, *client.window); // Initialize the camera size
            client.camera.center = calculate_camera_target_position(client, player.physical_position);
        }
    
      case .Player_Disconnect;
        remove_client_by_pid(client, msg.player_disconnect.player_pid);

      case .Game_Start;
        create_hud(client);
        create_entity_manager(client);
        client.my_entity_pid = INVALID_PID;
        client.pause_menu_open = false;
        client.game_seed  = msg.game_start.seed;
        client.world_size = msg.game_start.size;
        client.next_state = .Ingame;
        
      case .Game_Over;
        if msg.game_over.you_won {
            client.previous_game_result = .We_Won;
        } else {
            client.previous_game_result = .We_Lost;
        }
        client.next_state = .Game_Over;
        
      case .Create_Entity;
        create_entity_with_pid(client, msg.create_entity.entity_pid, msg.create_entity.kind, msg.create_entity.position, msg.create_entity.rotation);

      case .Destroy_Entity;
        entity := get_entity(client, msg.destroy_entity.entity_pid);
        entity.marked_for_removal = true;

        // Play death sounds
        if entity.entity_kind == {
          case .Frog; play_sound_once_per_frame(client, .Frog_Death_0);
          case .Goblin; play_sound_once_per_frame(client, .Goblin_Death_0);
        }
        
      case .Move_Entity;
        entity := get_entity(client, msg.move_entity.entity_pid);
        entity.physical_position = msg.move_entity.position;
        entity.physical_rotation = msg.move_entity.rotation;

      case .Entity_Health;
        entity := get_entity(client, msg.entity_health.entity_pid);
        entity.health = msg.entity_health.current_health;

        // Play damage sounds
        sound_index: Sound_Index = .Count;
        
        if entity.entity_kind == {
          case .Frog; sound_index = .Frog_Hurt_0;
          case .Goblin; sound_index = .Goblin_Hurt_0;
        }

        if sound_index != .Count && entity.sound_cooldown <= 0 && !sound_active(client, entity.sound_pid) {
            entity.sound_pid      = play_sound_once_per_frame(client, sound_index);
            entity.sound_cooldown = get_sound_length_in_seconds(client, sound_index) * 2;
        }
        
      case .Guy_State;
        entity := get_entity(client, msg.guy_state.entity_pid);
        guy := down(entity, Guy);

        // State Transitions
        if guy.state != msg.guy_state.state {
            stop_sound(client, *guy.sound_pid);

            if #complete msg.guy_state.state == {
              case .Digging;      guy.sound_pid = play_sound(client, .Pickaxe_0, true);
              case .Carrying;     guy.sound_pid = play_sound(client, .Pickup_0, false);
              case .Resurrecting; guy.resurrection_t = 0;
              case .Dead;         guy.sound_pid = play_sound(client, .Guy_Death_0, false);
              case .Idle; if guy.state == .Carrying guy.sound_pid = play_sound(client, .Placedown_0, false);
            }
        }

        guy.state           = msg.guy_state.state;
        guy.target_position = msg.guy_state.target_position;
        guy.carrying_item   = msg.guy_state.carrying_item;
        guy.strength_t      = msg.guy_state.strength_t;
        
      case .Emitter_State;
        entity := get_entity(client, msg.emitter_state.entity_pid);
        emitter := down(entity, Emitter);
        emitter.time_left_in_seconds = msg.emitter_state.time_left_in_seconds;
        
      case .Receiver_State;
        entity := get_entity(client, msg.receiver_state.entity_pid);
        receiver := down(entity, Receiver);
        receiver.progress_time_in_seconds = msg.receiver_state.progress_time_in_seconds;

      case .Item_Stack_State;
        entity := get_entity(client, msg.item_stack_state.entity_pid);
        item_stack := down(entity, Item_Stack);
        item_stack.item_kind = msg.item_stack_state.item_kind;
        item_stack.count     = msg.item_stack_state.count;

      case .Frog_State;
        entity := get_entity(client, msg.frog_state.entity_pid);
        frog := down(entity, Frog);

        if frog.state != msg.frog_state.state {
            frog.state_t = 0;

            if msg.frog_state.state == {
              case .Attacking;
                frog.sound_pid = play_sound_once_per_frame(client, .Frog_Attack_0);
            }
        }

        frog.state = msg.frog_state.state;

      case .Goblin_State;
        entity := get_entity(client, msg.goblin_state.entity_pid);
        goblin := down(entity, Goblin);

        if goblin.state != msg.goblin_state.state {
            goblin.state_t = 0;

            if msg.goblin_state.state == {
              case .Attacking;
                goblin.sound_pid = play_sound_once_per_frame(client, .Goblin_Attack_0);
            }
        }

        goblin.state = msg.goblin_state.state;
    }
}

read_incoming_packets :: (client: *Client) {
    while read_packet(*client.connection) {
        packet :: *client.connection.incoming_packet;
        
        update_virtual_connection_information_for_packet(*client.connection, *packet.header);
        
        if packet.header.packet_type == {
          case Packet_Type.Connection_Request; // Ignore
          
          case Packet_Type.Connection_Established;
            if client.next_state == .Connecting {
                client.my_player_pid = packet.header.sender_client_id;
                client.connection.info.client_id = client.my_player_pid;
                client.next_state = .Lobby;
                
                msg := make_message(Player_Information_Message);
                msg.player_information.player_pid = client.my_player_pid;
                msg.player_information.name = client.my_name;
                send_reliable_message(*client.connection, *msg);
            }
          
          case Packet_Type.Connection_Closed;
            client.previous_game_result = .Connection_Lost;
            client.next_state = .Game_Over;

          case Packet_Type.Ping;
            
          case Packet_Type.Message;
            msg: Message = ---;
            while read_message(packet, *msg) {
                handle_incoming_message(client, *msg);
            }
        }
    }
}

handle_server_timeout :: (client: *Client, next_screen: Game_State, info_text: string) {
    if os_convert_hardware_time(os_get_hardware_time() - client.connection.time_of_last_received_packet, .Seconds) > NETWORK_TIMEOUT {
        client.previous_game_result = .Connection_Lost;
        client.next_state = next_screen;

        set_info_text(client, DEFAULT_INFO_TEXT_TIMER, info_text);
    } else if os_convert_hardware_time(os_get_hardware_time() - client.connection.time_of_last_sent_packet, .Seconds) > NETWORK_PING_INTERVAL {
        send_ping_packet(*client.connection);
    }
}



switch_to_next_state :: (client: *Client) {
    logprint(.Debug, "Switching from '%' to '%'...", client.current_state, client.next_state);

    if #complete client.current_state == {
      case .Main_Menu, .Game_Over;

      case .Connecting;
        if client.next_state != .Lobby {
            disconnect_from_server(client);
            maybe_shutdown_server(client);
        }

      case .Lobby;
        if client.next_state != .Ingame {
            stop_all_sounds(client);
            destroy_entity_manager(client);
            disconnect_from_server(client);
            maybe_shutdown_server(client);
            reset_allocator(*client.world_allocator);
        }
        
      case .Ingame;
        stop_all_sounds(client);
        destroy_entity_manager(client);
        disconnect_from_server(client);
        maybe_shutdown_server(client);
        reset_allocator(*client.world_allocator);
    }

    client.current_state = client.next_state;
}



do_campaign_selector :: (client: *Client) {
    ui :: *client.ui;

    if ui_push_dropdown(ui, "Campaign", .Vertical, true, enum_names(Campaign)[client.requested_campaign]) {
        for i := 0; i < Campaign.Count; ++i {
            if !DEVELOPER && i == Campaign.Developer continue;

            if ui_button(ui, enum_names(Campaign)[i]) {
                client.requested_campaign = i;
            }
        }
    }
    ui_pop_dropdown(ui);
}

do_main_menu :: (client: *Client) {
    ui :: *client.ui;
    
    DEFAULT_PORT: s64 : 9876;
    WINDOW_WIDTH: f32 : 256;
    APPROX_WINDOW_HEIGHT: f32 : 256;
    
    ui_push_width(ui, .Pixels, WINDOW_WIDTH, 1);

    window_position :: (client: *Client, index: s64) -> UI_Vector2 {
        screen := UI_Vector2.{ (xx client.window.w / 2 + (xx index - 0.5) * WINDOW_WIDTH * 1.1),
                               (xx client.window.h / 2 - APPROX_WINDOW_HEIGHT * 0.65) };
        return .{ screen.x / (cast(f32) client.window.w - WINDOW_WIDTH), screen.y / (cast(f32) client.window.h - APPROX_WINDOW_HEIGHT) };
    }

    if client.server_data.state != .Closed {
        set_info_text(client, 0.5, "Your local server is still closing...");
    }
    
    // Host Window
    {
        ui_push_window(ui, "Host", .Default, window_position(client, -1));
        ui_label(ui, false, "Name:");
        name := ui_text_input(ui, "Enter your name", .Everything);
        ui_divider(ui, true);
        ui_label(ui, false, "Port");
        port := ui_text_input(ui, "Enter the port", .Integer);
        ui_divider(ui, true);
        
        if client.server_data.state == .Closed && ui_button(ui, "Host!") {
#if DEVELOPER {
            if !name._string.count then { name._string = "Victor"; name.valid = true; }
            if !port.valid then { port._int = DEFAULT_PORT; port.valid = true; }
}
    
            if name.valid && port.valid {
                host_server(client, port._int);
                join_server(client, name._string, "localhost", port._int);
                client.immediately_start_game = false;
            }
        }
        
        ui_pop_window(ui);
    }

    // Single Player Window
    {
        ui_push_window(ui, "Single Player", .Default, window_position(client, 0));

        do_campaign_selector(client);
        ui_divider(ui, false);

        if client.server_data.state == .Closed && ui_button(ui, "Play!") {
            host_server(client, DEFAULT_PORT);
            join_server(client, "YOU", "localhost", DEFAULT_PORT);
            client.immediately_start_game = true;
        }
        
        ui_pop_window(ui);
    }
    
    // Join Window
    {
        ui_push_window(ui, "Join", .Default, window_position(client, +1));
        ui_label(ui, false, "Name:");
        name := ui_text_input(ui, "Enter your name", .Everything);
        ui_divider(ui, true);
        ui_label(ui, false, "Host");
        host := ui_text_input(ui, "Enter the address", .Everything);
        ui_label(ui, false, "Port");
        port := ui_text_input(ui, "Enter the port", .Integer);
        ui_divider(ui, true);
        
        if client.server_data.state == .Closed && ui_button(ui, "Join!") {
#if DEVELOPER {
            if !name._string.count then { name._string = "Surreal"; name.valid = true; }
            if !host._string.count then { host._string = "localhost"; host.valid = true; }
            if !port.valid then { port._int = DEFAULT_PORT; port.valid = true; }
}
                
            if name.valid && host.valid && port.valid {
                join_server(client, name._string, host._string, port._int);
                client.immediately_start_game = false;
            }
        }
        
        ui_pop_window(ui);
    }

    // Quit Window
    {
        ui_push_window(ui, "Quit?", .Default, .{ 0.5, 0.8 });

        if ui_button(ui, "Quit to Desktop") client.window.should_close = true;
        
        ui_pop_window(ui);
    }
    
    ui_pop_width(ui);
}

do_connecting_screen :: (client: *Client) {
    read_incoming_packets(client);
    handle_server_timeout(client, .Main_Menu, "The server could not be reached.");
    
    if !client.sent_connection_request && has_tcp_handshake_occurred(*client.connection) {
        send_connection_request_packet(*client.connection, 1);
        client.sent_connection_request = true;
    }
    
    {
        ui :: *client.ui;
        ui_push_width(ui, .Pixels, 256, 1);
        ui_push_window(ui, "Connecting...", .Default, .{ .5, .5 });
        ui_label(ui, false, "...");
        ui_divider(ui, true);
        if ui_button(ui, "Cancel!") {
            client.next_state = .Main_Menu;
        }
        ui_pop_window(ui);
        ui_pop_width(ui);
    }    
}

do_lobby_screen :: (client: *Client) {
    read_incoming_packets(client);
    handle_server_timeout(client, .Main_Menu, "The server died.");

    if client.immediately_start_game {
        start_lobby(client);
    }
    
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
        do_campaign_selector(client);

        if ui_button(ui, "Start!") {
            start_lobby(client);
        }
        
        ui_divider(ui, true);
        if ui_button(ui, "Disconnect!") {
            client.next_state = .Main_Menu;
        }
        ui_pop_window(ui);
        ui_pop_width(ui);
    }
}

do_game_over_screen :: (client: *Client) {
    ui :: *client.ui;
    ui_push_width(ui, .Pixels, 256, 1);
    ui_push_window(ui, "Game Over!", .Default, .{ .5, .5 });

    if client.previous_game_result == {
        case .We_Won; ui_label(ui, true, "You won!");
        case .We_Lost; ui_label(ui, true, "You lost!");
        case .Connection_Lost; ui_label(ui, true, "Connection died!");
    }
    
    ui_divider(ui, true);
    if ui_button(ui, "Back to Main Menu!") {
        client.next_state = .Main_Menu;
    }
    ui_pop_window(ui);
    ui_pop_width(ui);
}

calculate_camera_target_position :: (client: *Client, target_center_position: v2i) -> v2f {
    custom_clamp :: (value, low, high: $T) -> T {
        if low < high {
            return clamp(value, low, high);
        } else {
            return (low + high) * 0.5;
        }
    }

    room_position := v2f.{ floor(xx target_center_position.x / VISUAL_ROOM_SIZE.x) * VISUAL_ROOM_SIZE.x + VISUAL_ROOM_OFFSET.x, 
                           floor(xx target_center_position.y / VISUAL_ROOM_SIZE.y) * VISUAL_ROOM_SIZE.y + VISUAL_ROOM_OFFSET.y };

    half_size := v2f.{ client.camera.size.x / 2 - 0.5, client.camera.size.y / 2 - 0.5 };
    
    target_camera_position := v2f.{
        custom_clamp(room_position.x, half_size.x, xx client.world_size.x - half_size.x - 1),
        custom_clamp(room_position.y, half_size.y, xx client.world_size.y - half_size.y - 1) };
    
    return target_camera_position;
}

calculate_camera_position :: (client: *Client, current_camera_position: v2f, target_center_position: v2i) -> v2f {
    target_camera_position := calculate_camera_target_position(client, target_center_position);
    speed := 10 * client.tick_time;
    return .{ lerp_with_snap(current_camera_position.x, target_camera_position.x, speed),
              lerp_with_snap(current_camera_position.y, target_camera_position.y, speed) };
}

get_available_resources_for_guy :: (client: *Client, guy: *Guy) -> [..]Item_Kind {
    result: [..]Item_Kind;
    result.allocator = *temp;

    if guy.state == .Carrying && guy.carrying_item != .Count {
        array_add(*result, guy.carrying_item);
    }

    standing_on := find_entity_of_kind_at_position(client, .Item_Stack, guy.physical_position);
    if standing_on {
        item_stack := down(standing_on, Item_Stack);

        for i := 0; i < item_stack.count; ++i {
            array_add(*result, item_stack.item_kind);
        }
    }
    
    return result;
}

do_game_tick :: (client: *Client) {
    client.tick_time = client.window.frame_time;
    
    read_incoming_packets(client);
    handle_server_timeout(client, .Game_Over, "");

    client.sounds_played_this_frame = .[ false ];
    
    //
    // Update all local entities based on the information received by the server.
    // This also does some basic client-side prediction
    //
    {
        for i := 0; i < client.emitters.slot_count; ++i {
            emitter, occupied := index_bucket_array(*client.emitters, i);
            if occupied then update_emitter(client, emitter);
        }

        for i := 0; i < client.slabs.slot_count; ++i {
            slab, occupied := index_bucket_array(*client.slabs, i);
            if occupied then update_slab(client, slab);
        }

        for i := 0; i < client.guys.slot_count; ++i {
            guy, occupied := index_bucket_array(*client.guys, i);
            if occupied then update_guy(client, guy);
        }
        
        for i := 0; i < client.frogs.slot_count; ++i {
            frog, occupied := index_bucket_array(*client.frogs, i);
            if occupied then update_frog(client, frog);
        }

        for i := 0; i < client.all_entities.slot_count; ++i {
            entity, occupied := index_bucket_array(*client.all_entities, i);
            if occupied then interpolate_visuals_and_play_sounds(client, entity, entity.entity_flags & .Disable_Visual_Rotation);
        }

        for i := 0; i < client.particle_systems.slot_count; ++i {
            system, occupied := index_bucket_array(*client.particle_systems, i);
            if occupied then update_particle_system(system, client.tick_time);
        }
    }

    outgoing_messages: [..]Message;
    outgoing_messages.allocator = *temp;

    // Do the pause menu
    {
        if input_action_fired(client, .Toggle_Pause_Menu) client.pause_menu_open = !client.pause_menu_open;

        if client.pause_menu_open {
            ui :: *client.ui;
            ui_push_window(ui, "Glassminers", .Default, .{ 0.5, 0.5 });
            ui_push_width(ui, .Pixels, 256, 1);
            ui_push_height(ui, .Pixels, 32, 1);

            ui_label(ui, true, "Seed: %", client.game_seed);
            ui_slider(ui, "Audio", *client.mixer.volumes[.Master], 0, 1);

            ui_divider(ui, true);
            if ui_button(ui, "Continue!") then client.pause_menu_open = false;
            ui_divider(ui, false);
            if ui_button(ui, "Back to Main Menu!") then client.next_state = .Main_Menu;

            ui_pop_height(ui);
            ui_pop_width(ui);
            ui_pop_window(ui);
        }
    }
    
    // Update the camera
    {
        guy := get_entity(client, client.my_entity_pid);
        client.camera.center = calculate_camera_position(client, client.camera.center, .{ xx guy.physical_position.x, xx guy.physical_position.y });
        update_camera_matrices(*client.camera, *client.window);
    }

    // Update the hud
    {
        update_hud(client);
    }

    // Forward guy input to the server
    {
        guy_entity := get_entity(client, client.my_entity_pid);
        guy := down(guy_entity, Guy);

        read_any_input := client.hud.crafting_recipe_input_this_frame != .Count;
        
        input: Guy_Input_Message = ---;
        input.entity_pid       = client.my_entity_pid;
        input.position         = guy.physical_position;
        input.wants_to_move    = false;
        input.aim_direction    = guy.physical_rotation;
        input.interaction_kind = .Count;
        input.crafting_recipe  = client.hud.crafting_recipe_input_this_frame;
        
        if !client.hud.was_open_this_frame {
            if input_action_fired(client, .Move_North) {
                input.position.x    = guy.physical_position.x;
                input.position.y    = guy.physical_position.y - 1;
                input.aim_direction = .North;
                input.wants_to_move = true;
                read_any_input = true;
            }

            if input_action_fired(client, .Move_West) {
                input.position.x    = guy.physical_position.x - 1;
                input.position.y    = guy.physical_position.y;
                input.aim_direction = .West;
                input.wants_to_move = true;
                read_any_input = true;
            }

            if input_action_fired(client, .Move_South) {
                input.position.x    = guy.physical_position.x;
                input.position.y    = guy.physical_position.y + 1;
                input.aim_direction = .South;
                input.wants_to_move = true;
                read_any_input = true;
            }

            if input_action_fired(client, .Move_East) {
                input.position.x    = guy.physical_position.x + 1;
                input.position.y    = guy.physical_position.y;
                input.aim_direction = .East;
                input.wants_to_move = true;
                read_any_input = true;
            }

            if input_action_fired(client, .Look_North) { input.aim_direction = .North; read_any_input = true; }
            if input_action_fired(client, .Look_West)  { input.aim_direction = .West;  read_any_input = true; }
            if input_action_fired(client, .Look_South) { input.aim_direction = .South; read_any_input = true; }
            if input_action_fired(client, .Look_East)  { input.aim_direction = .East;  read_any_input = true; }
            if input_action_fired(client, .Interact_Primary)   { input.interaction_kind = .Primary; read_any_input = true; }
            if input_action_fired(client, .Interact_Secondary) { input.interaction_kind = .Secondary; read_any_input = true; }
        }
            
        if !client.pause_menu_open && read_any_input {
            msg := make_message_from(input);
            array_add(*outgoing_messages, msg);
        }
    }

    // Send all outgoing messages
    {
        for i := 0; i < outgoing_messages.count; ++i {
            send_reliable_message(*client.connection, array_get_pointer(*outgoing_messages, i));
        }
    }
    
    physically_remove_dead_particle_systems(client);
    physically_remove_all_marked_entities(client);
}

main :: (args: []string) -> s32 {
    //
    // Start up the engine
    //
    set_working_directory_to_executable_path();
    os_enable_high_resolution_timer();
    create_temp_allocator(128 * Memory_Unit.Megabytes);
    
    client: Client;
    create_memory_pool(*client.engine_pool, 32 * Memory_Unit.Megabytes, 128 * Memory_Unit.Kilobytes);
    client.engine_allocator = allocator_from_memory_pool(*client.engine_pool);
    create_memory_pool(*client.world_pool, 32 * Memory_Unit.Megabytes, 128 * Memory_Unit.Kilobytes);
    client.world_allocator = allocator_from_memory_pool(*client.world_pool);

#if DEVELOPER {
    create_file_watcher(*client.sprite_watchdog, *client.engine_allocator);
    if !pack_sprite_atlases_with_watchdog(*client, "data") return -1;
}

    window_mode: Window_Style_Flags = ifx !DEVELOPER then (.Fullscreen | .Maximized) else .Default;
    window_width: s32 = ifx DEVELOPER then cast(s32) (720 * 1.8) else cast(s32) WINDOW_DONT_CARE;
    window_height: s32 = ifx DEVELOPER then 720 else cast(s32) WINDOW_DONT_CARE;

    create_window(*client.window, "Glassminers", WINDOW_DONT_CARE, WINDOW_DONT_CARE, window_width, window_height, window_mode);

#if OS == .Windows {
    set_window_icon_from_resource_name(*client.window, "IDI_ICON1");
}
    
    create_draw_data(*client);
    create_ui(*client.ui, 1024, draw_ui_callbacks(*client), UI_Dark_Theme, *client.window, *client.ui_font);
    create_mixer(*client.mixer, 16);
    create_sound_data(*client);
    register_all_input_bindings(*client);
    
    client.remote_clients.allocator = *client.world_allocator;
    client.current_state = .Count;
    client.next_state    = .Main_Menu;
    switch_to_next_state(*client);

#if DEVELOPER {
    client.mixer.volumes[.Master] = 0.0;
    client.requested_campaign = .Developer;
}
    
    //
    // Main loop
    //
    while !client.window.should_close {
        frame_start := os_get_hardware_time();

        //
        // Check for hot-reloading
        //
#if DEVELOPER {
    changed_sprites := update_file_watcher(*client.sprite_watchdog, *temp);
    if changed_sprites.count {
        if pack_sprite_atlases_with_watchdog(*client, "data") {
            reload_sprite_atlases_from_disk(*client);
        }
    }

    changed_sounds := update_file_watcher(*client.sound_watchdog, *temp);
    for i := 0; i < changed_sounds.count; ++i {
        filepath := array_get(*changed_sounds, i);
        sound_index := find_sound_index_from_filepath(filepath);
        if sound_index != .Count {
            destroy_sound_data(*client.sounds[i]);
            status: Sound_File_Status = ---;
            client.sounds[sound_index], status = create_sound_data_from_file(filepath);
            if status == .Success {
                logprint(.Debug, "Hot-loaded the sound '%'.", sound_index);
            } else {
                logprint(.Error, "Failed to load the sound '%': %.", filepath, status);
            }
        } else {
            logprint(.Warning, "Registered a non-cataloged sound change: '%'.", filepath);
        }
    }
}
        
        //
        // Handle transitions
        //
        if client.current_state != client.next_state switch_to_next_state(*client);

        if input_action_fired(*client, .Toggle_Fullscreen) {
            if client.window.fullscreen {
                set_window_style(*client.window, .Maximized);
            } else {
                set_window_style(*client.window, .Fullscreen);                
            }
        }
        
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

            client.info_text_t -= client.tick_time;
        }
        
        //
        // Draw one frame
        //
        {
            ge_clear_screen(*client.graphics, .{ 40, 40, 50, 255 });
            
            if #complete client.current_state == {
              case .Main_Menu, .Connecting, .Lobby, .Game_Over;
                draw_text_screen_space(*client, *client.title_font, "GlassMiners", .{ xx client.window.w / 2, xx client.window.h / 4 }, .Center | .Median, .{ 255, 255, 255, 255 });
                if client.info_text_t > 0 {
                    draw_text_screen_space(*client, *client.ui_font, client.info_text, .{ xx client.window.w / 2, xx (client.window.h / 4 + client.title_font.line_height) }, .Center | .Median, .{ 252, 238, 28, 255 });
                }
            
              case .Ingame;
                draw_world(*client);
                draw_hud(*client);
                if client.pause_menu_open draw_rect_screen_space(*client, .{ 0, 0 }, .{ xx client.window.w, xx client.window.h }, .{ 0, 0, 0, 160 });
                ge_imm2d_flush(*client.graphics);
            }

            draw_ui_frame(*client.ui);

            draw_text_screen_space(*client, *client.ui_font, VERSION_STRING, .{ 10, xx client.window.h - 10 }, .Left | .Bottom, .{ 255, 255, 255, 150 });
            ge_imm2d_flush(*client.graphics);
            
            ge_swap_buffers(*client.graphics);
        }

        //
        // Render one audio frame
        //
        {
            update_mixer(*client.mixer);
        }
        
        client.epoch_time += client.window.frame_time;
        release_temp_allocator(0);
        
        frame_end := os_get_hardware_time();
        os_sleep_to_tick_rate(frame_start, frame_end, TARGET_FRAMES_PER_SECOND);
    }
    
    // Shut down all resources that might currently be in use
    client.next_state = .Count;
    switch_to_next_state(*client);
    
    //
    // Destroy the engine
    //
    destroy_all_sounds(*client);
    destroy_mixer(*client.mixer);
    destroy_ui(*client.ui);
    destroy_draw_data(*client);
    destroy_window(*client.window);
    destroy_memory_pool(*client.world_pool);
    destroy_memory_pool(*client.engine_pool);
    destroy_temp_allocator();
    return 0;
}
