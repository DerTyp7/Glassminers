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
#load "tweak_file.jai";
#load "graphics_engine/graphics_engine.jai";
#load "screen_saver_inhibit.jai";

#load "stb/stb_image_write.jai";
#load "file_watcher.jai";
#load "profiler.jai";

// Shared
#load "../shared/messages.jai";
#load "../shared/shared.jai";
#load "../shared/bucket_array.jai";
#load "../shared/lightmap.jai";
#load "../shared/VERSION_STRING.jai";

// Client
#load "config.jai";
#load "tick.jai";
#load "input_bindings.jai";
#load "entity.jai";
#load "particles.jai";
#load "sprite_packer.jai";
#load "sounds.jai";
#load "animation.jai";
#load "hud.jai";
#load "draw.jai";
#load "aseprite.jai";

GE_ACTIVE_BACKEND :: GE_Backend.GL_Fixed;
ENABLE_PROFILING :: DEVELOPER;

DEVELOPER :: #run compiler_is_user_option_present("Developer");
MEMORY_DEBUGGING :: false;
BAKE_ASSETS :: !DEVELOPER;
DEFAULT_INFO_TEXT_TIMER: f32 : 5;

Log_Level :: enum {
    Debug;
    Info;
    Warning;
    Error;
}

Game_State :: enum {
    Main_Menu;
    Connecting;
    Lobby;
    Ingame;
    Game_Over;
}

Remote_Player :: struct {
    local_player_index: s64 = -1;
    client_pid: Pid = INVALID_PID;
    guy_pid: Pid = INVALID_PID;
    name: string = "";
}

Local_Player :: struct {
    name := "";
    guy_pid: Pid = INVALID_PID;
    entity_tracked_by_camera: Pid = INVALID_PID;
    viewport: [4]f32;
    camera: Camera;
    hud: Hud;
    input_binder: Input_Binder;
}

Test_Input :: struct {
    cpu_time: CPU_Time;
    local_player_index: s64;
    sprite_index: Sprite_Index;
}

Tutorial_Panel :: enum {
    About_Tutorial_Panels;
    Goal_Of_The_Game;
    Using_The_Crafting_Menu;
    Using_Mirrors_To_Kill;
}

#if DEVELOPER {
    Message_History_Entry :: struct {
        message: Message;
        size_in_bytes: s64;
        age: f32;
    }

    Message_History :: struct {
        entries: [16]Message_History_Entry;
        active: s64;
        total_bytes_received: s64;
    }
}

UI_Scale :: enum {
    Small;
    Normal;
    Big;
    Extra_Large;
}

UI_SCALING_VALUES: [UI_Scale.Count]f32 : .[ 0.75, 1, 2, 4 ];

Game_Summary :: struct {
    result: Game_Result;
    score: u64;
    player_stat_message: string;
    global_stat_message: string;
}

Client :: struct {
    //
    // Engine structure
    //
    window: Window;
    graphics: Graphics_Engine;
    ui: UI;
    mixer: Mixer;
    config: Config;
    
    engine_pool: Memory_Pool;
    engine_allocator: Allocator;
    
    current_state: Game_State;
    next_state: Game_State;
    state_transition_t: f32; // We will only transition from the current state to the next state once this value reaches 0. Before that, we will just fade out the current state
    state_transition_duration: f32;
    random: Random_Generator;

    previous_game_summary: Game_Summary;
    info_text: string;
    info_text_t: f32;
    
    //
    // Assets
    //
    ui_font, title_font, hud_font: Font;
    ui_pipeline: *GE_Pipeline;
    entity_pipeline: *GE_Pipeline;
    sprite_atlases: [SPRITE_ATLAS_COUNT]*GE_Texture;
    animations: [Animation_Index.Count]Animation;
    animation_groups: [Animation_Group_Index.Count]Animation_Group;
    sounds: [Sound_Index.Count]Sound_Data;
    sounds_played_this_frame: [Sound_Index.Count]bool;
    
#if DEVELOPER {
    checkerboard_texture: *GE_Texture;
    draw_entities_with_checkerboard_texture := false;

    sound_watchdog: File_Watcher;
    sprite_watchdog: File_Watcher;
    pack_watchdog: File_Watcher;
}

    //
    // Input System
    //
    input_bindings: [Input_Action.Count][]Input_Binding;
    input_action_repetition_intervals: [Input_Action.Count]f32 = .[ MAX_F32 ]; // For every action, we can define the interval in which the action is considered "repeated". Repeated means: When the player keeps pressing the button (or holding the gesture, etc) for this interval, the action shall be triggered again
    input_binding_tracker: Input_Binding_Tracker;
    global_input_binder: Input_Binder;    

    input_bindings_panel_state: UI_Window_State = .Closed;
    input_bindings_panel_position: UI_Vector2 = .{ 1.0, 0.0 };

    //
    // Networking
    //
    server_data: Shared_Server_Data;
    server_thread: Thread;
    connection: Virtual_Connection;
    sent_connection_request: bool;
    remote_players: [..]Remote_Player;
    my_client_pid: Pid;
    latest_rtt: f32;
    outgoing_messages: [..]Message;

    //
    // Lobby Screen
    //
    immediately_start_game: bool = false; // Lobby screen, after pressing "single player" in the main menu
    new_local_player_name: string = "";
    test_inputs: [..]Test_Input;

    //
    // Tutorial panels
    // We track a permanent list of panels that have been requested by the game code ever. A panel
    // is requested when a certain action happens in the game world, which makes this panel necessary
    // for the user. A panel isn't added to this list twice though, since we only want to show each
    // panel once.
    // The game will only ever show one panel at a time, so if there's multiple requested we will
    // progress through the list at a later time.    
    //
    requested_tutorial_panels: [..]Tutorial_Panel;
    current_tutorial_panel := 0;

    //
    // Game Data
    //
    world_pool: Memory_Pool;
    world_allocator: Allocator;
    tick_arena: Memory_Arena; // For stuff that only needs to live for one update tick. If the game is paused, one tick might span over a lot of frames, so we cannot use temp for this!
    tick_allocator: Allocator;
    
    pause_menu_open: bool;
    server_paused_game: bool;
    requested_game_forfeit := false;
    current_biome: Biome_Type;
    current_section: [2]s32;

    game_seed: s64;
    game_score: u64;
    game_mode: Game_Mode;
    world_size: v2i;

    tick_time: f32;
    game_epoch_time: f32;

    local_players: [MAX_LOCAL_PLAYERS]Local_Player;
    local_player_count := 1;

    #using em: Entity_Manager;
    #using pm: Particle_Manager;
    lightmap: Lightmap;
    global_particle_system: Pid;
    stat_hud: Stat_Hud;
    
    //
    // Debugging
    // 
#if DEVELOPER {
    developer_panel_state: UI_Window_State;
    developer_panel_position: UI_Vector2;
    
    free_camera_enabled: bool;
    sound_hud_enabled: bool;
    shadow_hud_enabled: bool;

    total_update_time: f32;
    total_draw_time: f32;
    draw_time_before_ui: f32;
    total_frame_time_without_sleep: f32;
    draw_call_count_before_ui: s64;

    incoming_message_history: Message_History;
    outgoing_message_history: Message_History;
    message_history_panel_state: UI_Window_State;
    message_history_panel_position: UI_Vector2;
    message_history_paused := false;
}

#if MEMORY_DEBUGGING {
    memory_debug_printer: File_Printer;
}
}

logprint :: (level: Log_Level, format: string, args: ..Any) {
    ff :: (value: s64) -> Print_Format {
        return format_int(value, .Decimal, true, false, 2);
    }

    time := os_get_time(.Local);

    buffer: Print_Buffer = ---;
    create_stdio_printer(*buffer, *temp);
    print_into_buffer(*buffer, "[%:%:%]", ff(time.hour), ff(time.minute), ff(time.second));
    print_into_buffer(*buffer, "[CLIENT][%] ", enum_names(Log_Level)[level]);
    print_into_buffer(*buffer, format, ..args);
    print_into_buffer(*buffer, "\n");
    flush_print_buffer(*buffer);
}

set_info_text :: (client: *Client, time: f32, format: string, args: ..Any) {
    deallocate_string(*client.engine_allocator, *client.info_text);
    client.info_text = print_into_allocator(*client.engine_allocator, format, args);
    client.info_text_t = time;
}

set_temp_info_text :: (client: *Client, format: string, args: ..Any) {
    deallocate_string(*client.engine_allocator, *client.info_text);
    client.info_text = print_into_allocator(*client.engine_allocator, format, args);
    client.info_text_t = 0;
}
    
host_server :: (client: *Client, port: u16) -> bool {
    logprint(.Debug, "Hosting server '%'...", port);
    server_entry_point :: (data: *Shared_Server_Data) -> u32 #foreign;

    client.server_data.state          = .Starting;
    client.server_data.requested_port = port;
    client.server_data.startup_error  = .Success;

    client.server_thread = create_thread(server_entry_point, *client.server_data, false);
    while atomic_load(cast(*s64) *client.server_data.state) == Server_State.Starting {}

    if client.server_data.state != .Running {
        set_info_text(client, DEFAULT_INFO_TEXT_TIMER, "The server could not be started: %.", client.server_data.startup_error);
        initiate_state_transition(client, .Main_Menu, 0);
    }

    return client.server_data.state == .Running;
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
        client.local_players[0].name = copy_string(*client.engine_allocator, name);
        if client.local_players[0].input_binder.allowed_input_devices == 0 then client.local_players[0].input_binder.allowed_input_devices = .Keyboard | .Gamepad;
        initiate_state_transition(client, .Connecting, 0);
    } else {
        set_info_text(client, DEFAULT_INFO_TEXT_TIMER, "The server could not be reached: %.", result);
        disconnect_from_server(client);
        maybe_shutdown_server(client);
    }
}

disconnect_from_server :: (client: *Client) {
    logprint(.Debug, "Disconnecting from the server...");

    send_connection_closed_packet(*client.connection, 1, .[]);

    for i := 0; i < client.remote_players.count; ++i {
        deallocate_string(*client.engine_allocator, *array_get_pointer(*client.remote_players, i).name);
    }
    array_clear(*client.remote_players);

    destroy_connection(*client.connection);
}

maybe_shutdown_server :: (client: *Client) {
    previous, success := atomic_compare_and_exchange(cast(*s64) *client.server_data.state, Server_State.Running, Server_State.Closing);
    if success detach_thread(*client.server_thread);
}

find_remote_player_by_pid_and_local_index :: (client: *Client, pid: Pid, index: s64) -> *Remote_Player {
    for i := 0; i < client.remote_players.count; ++i {
        remote_player := array_get_pointer(*client.remote_players, i);
        if remote_player.client_pid == pid && remote_player.local_player_index == index return remote_player;
    }
    
    return null;
}

find_player_name_from_guy_pid :: (client: *Client, pid: Pid) -> string {
    for i := 0; i < client.remote_players.count; ++i {
        remote_player := array_get_pointer(*client.remote_players, i);
        if remote_player.guy_pid == pid { return remote_player.name; }
    }

    for i := 0; i < client.local_player_count; ++i {
        local_player := *client.local_players[i];
        if local_player.guy_pid == pid { return local_player.name; }
    }

    return "?UNKNOWN?";
}

is_local_guy_pid :: (client: *Client, pid: Pid) -> bool {
    for i := 0; i < client.local_player_count; ++i {
        if client.local_players[i].guy_pid == pid then return true;
    }

    return false;
}

initiate_state_transition :: (client: *Client, next_state: Game_State, t: f32) {
    client.next_state = next_state;
    client.state_transition_t = t;
    client.state_transition_duration = t;
}

maybe_transition_to_next_state :: (client: *Client) {
    if client.current_state == client.next_state return;

    if client.state_transition_t > 0 {
        client.state_transition_t -= client.tick_time;
        return;
    }

    // logprint(.Debug, "Switching from '%' to '%'...", client.current_state, client.next_state);

    if #complete client.current_state == {
      case .Main_Menu;

      case .Connecting;
        if client.next_state != .Lobby {
            disconnect_from_server(client);
            maybe_shutdown_server(client);
        }

      case .Lobby;
        if client.next_state != .Ingame {
            disconnect_from_server(client);
            maybe_shutdown_server(client);
        }

        array_clear(*client.test_inputs);
        
      case .Ingame;
        stop_all_sounds(client);
        destroy_lightmap(*client.lightmap);
        destroy_entity_manager(client);
        destroy_particle_manager(client);
        disconnect_from_server(client);
        maybe_shutdown_server(client);
        reset_allocator(*client.world_allocator);
        array_clear(*client.requested_tutorial_panels);
        
        // Stop any active rumbling effect
        for i := 0; i < client.local_player_count; ++i {
            local_player := *client.local_players[i];
            set_gamepad_properties(*client.window, local_player.input_binder.gamepad_index, 0, 0, 255, 255, 255);
        }

      case .Game_Over;
        deallocate_string(*client.engine_allocator, *client.previous_game_summary.player_stat_message);
        deallocate_string(*client.engine_allocator, *client.previous_game_summary.global_stat_message);
    }

    client.current_state = client.next_state;
}

maybe_update_ui_scale :: (client: *Client) {
    if client.ui.pixel_scaling != UI_SCALING_VALUES[client.config.ui_scale] {
        client.ui.pixel_scaling = UI_SCALING_VALUES[client.config.ui_scale];
        create_ui_scaled_draw_data(client);
        change_ui_font(*client.ui, *client.ui_font); // Force-update all cached label sizes
    }
}

maybe_add_local_player :: (client: *Client) {
    if client.local_player_count >= MAX_LOCAL_PLAYERS || client.new_local_player_name.count == 0 return;

    client.local_players[client.local_player_count].name = client.new_local_player_name;
    client.local_players[client.local_player_count].input_binder.allowed_input_devices = .Gamepad;
    ++client.local_player_count;

    if client.local_players[0].input_binder.allowed_input_devices == .ALL then client.local_players[0].input_binder.allowed_input_devices = .Keyboard;

    send_player_information_message(client, client.local_player_count - 1);
    client.new_local_player_name = .{};
}

main :: (args: []string) -> s32 {
    install_crash_handler();

    //
    // Start up the engine
    //
    set_working_directory(cut_file_name_from_path(args[0]));
    os_enable_high_resolution_timer();
    create_temp_allocator(128 * Memory_Unit.Megabytes);

    logprint(.Info, "Starting the client...");
    
    underlying_client: Client;
    client := *underlying_client;

    create_memory_pool(*client.engine_pool, 32 * Memory_Unit.Megabytes, 128 * Memory_Unit.Kilobytes);
    client.engine_allocator = allocator_from_memory_pool(*client.engine_pool);
    create_memory_pool(*client.world_pool, 32 * Memory_Unit.Megabytes, 128 * Memory_Unit.Kilobytes);
    client.world_allocator = allocator_from_memory_pool(*client.world_pool);
    create_memory_arena(*client.tick_arena, 32 * Memory_Unit.Megabytes, 128 * Memory_Unit.Kilobytes, false);
    client.tick_allocator = allocator_from_memory_arena(*client.tick_arena);

    create_config(client);

#if MEMORY_DEBUGGING {
    create_file_printer(*client.memory_debug_printer, *temp, "memory.log");
    //create_stdio_printer(*client.memory_debug_printer, *temp);
    callback: Allocator_Callback = .{ ---, allocator_callback_procedure, client };
    install_allocator_callback(*callback);
}
    
#if DEVELOPER {
    create_file_watcher(*client.pack_watchdog, *client.engine_allocator);
    add_file_to_watch(*client.pack_watchdog, "data/animation-pack.txt");
    add_file_to_watch(*client.pack_watchdog, "data/sprite-pack.txt");
}

    create_window(*client.window, "Glassminers", client.window.x, client.window.y, client.window.w, client.window.h, desired_window_style(client));

    if !os_inhibit_screen_saver(true) then logprint(.Warning, "Failed to inhibit the screen saver");
    defer os_inhibit_screen_saver(false);

#if OS == .Windows {
    set_window_icon_from_resource_name(*client.window, "IDI_ICON1");
}
    
    create_ui(*client.ui, 1024, draw_ui_callbacks(client), UI_Dark_Theme, *client.window, *client.ui_font);
    create_mixer(*client.mixer, *client.engine_allocator, 16);
    register_all_input_bindings(client);

    startup_success := create_draw_data(client) && create_animation_data(client) && create_sound_data(client);
    if !startup_success return -1;
        
    client.remote_players.allocator = *client.engine_allocator;
    client.test_inputs.allocator    = *client.engine_allocator;
    client.requested_tutorial_panels.allocator = *client.engine_allocator;
    client.outgoing_messages.allocator = *temp;
    client.current_state = .Count;
    initiate_state_transition(client, .Main_Menu, 0);
    maybe_transition_to_next_state(client);
    
    //
    // Main loop
    //
    while !client.window.should_close {
        frame_start := os_get_cpu_time();
            
        //
        // Check for hot-reloading
        //
#if DEVELOPER {
        changed_sprites := update_file_watcher(*client.sprite_watchdog, *temp);
        if changed_sprites.count {
            reload_sprite_atlases_from_disk(client);
        }

        changed_sounds := update_file_watcher(*client.sound_watchdog, *temp);
        for i := 0; i < changed_sounds.count; ++i {
            filepath := array_get(*changed_sounds, i);
            sound_index := find_sound_index_from_filepath(filepath);
            if sound_index != .Count {
                destroy_sound_data(*client.mixer, *client.sounds[i]);
                status: Sound_File_Status = ---;
                client.sounds[sound_index], status = create_sound_data_from_file(*client.engine_allocator, filepath);
                if status == .Success {
                    logprint(.Debug, "Hot-loaded the sound '%'.", sound_index);
                } else {
                    logprint(.Error, "Failed to load the sound '%': %.", filepath, status);
                }
            } else {
                logprint(.Warning, "Registered a non-cataloged sound change: '%'.", filepath);
            }
        }

        changed_packs := update_file_watcher(*client.pack_watchdog, *temp);
        for i := 0; i < changed_packs.count; ++i {
            filepath := array_get(*changed_packs, i);
            if filepath == "data/animation-pack.txt" {
                destroy_animation_data(client);
                create_animation_data(client);
            } else if filepath == "data/sprite-pack.txt" {
                reload_sprite_atlases_from_disk(client);
            }
        }

        maybe_reload_config(client);
}
        
        //
        // Handle transitions
        //
        client.tick_time = client.window.frame_time;
        maybe_transition_to_next_state(client);
        maybe_update_ui_scale(client);
        
        //
        // Do one frame
        //
        {
#if DEVELOPER {
            begin := os_get_cpu_time();
}
            
            update_window(*client.window);
            begin_ui_frame(*client.ui, .{ 128, 24 });
            reset_input_binding_tracker(client);

            if input_action_fired_globally(client, .Toggle_Fullscreen, .Pressed) {
                if client.window.fullscreen {
                    set_window_style(*client.window, .Maximized);
                } else {
                    set_window_style(*client.window, .Fullscreen);                
                }
            }
            
            if #complete client.current_state == {
              case .Main_Menu;  do_main_menu(client);
              case .Connecting; do_connecting_screen(client);
              case .Lobby;      do_lobby_screen(client);
              case .Ingame;     do_game_tick(client);
              case .Game_Over;  do_game_over_screen(client);
            }

            update_input_binders(client);

            #if DEVELOPER {
                client.total_update_time = os_convert_cpu_time(os_get_cpu_time() - begin, .Milliseconds);
            }
        }
        
        //
        // Draw one frame
        //
        {
            #if DEVELOPER {
                begin := os_get_cpu_time();
            }

            ge_clear_screen(*client.graphics, DARK_BLUE_COLOR);
            
            if #complete client.current_state == {
              case .Lobby #through;
                y: f32 = xx client.window.h - 34;
                x: f32 = xx client.window.w * 0.9;
                
                now := os_get_cpu_time();

                for i := client.test_inputs.count - 1; i >= 0; --i {
                    input := array_get_pointer(*client.test_inputs, i);
                    if input.local_player_index >= client.local_player_count continue;

                    time := os_convert_cpu_time(now - input.cpu_time, .Seconds);
                    alpha := 1 - smoothstep(time, 1, 2);
                    color := GE_Color.{ 200, 200, 200, cast(u8) (alpha * 255) };

                    text := tprint("%: ", client.local_players[input.local_player_index].name);
                    draw_text_screen_space(client, *client.ui_font, text, .{ x, y }, .Right | .Median, color, .Default);
                    draw_sprite_screen_space(client, input.sprite_index, .{ x + 16, y }, .{ 32, 32 }, 0, color, false);
                    
                    y -= 34;
                }

                if !client.test_inputs.count {
                    text := tprint("Try pressing %...", input_bindings_string(client, .Interact_Primary));
                    draw_text_screen_space(client, *client.ui_font, text, .{ x + 32, y }, .Right | .Median, GRAY_COLOR, .Default);

                }
                
              case .Main_Menu, .Connecting, .Game_Over;
                draw_text_screen_space(client, *client.title_font, "GlassMiners", .{ xx client.window.w / 2, xx client.window.h / 4 }, .Center | .Median, WHITE_COLOR, .Default);
                if client.info_text_t >= 0 {
                    draw_text_screen_space(client, *client.ui_font, client.info_text, .{ xx client.window.w / 2, xx (client.window.h / 4 + client.title_font.line_height) }, .Center | .Median, YELLOW_COLOR, .Default);
                    client.info_text_t -= client.tick_time;
                }
                
              case .Ingame;
                for i := 0; i < client.local_player_count; ++i {
                    draw_world(client, *client.local_players[i]);
                    draw_player_hud(client, *client.local_players[i]);
                }

                draw_viewport_information(client);
                draw_stat_hud(client);
                draw_global_hud(client);

                if client.pause_menu_open || client.server_paused_game draw_rect_screen_space(client, .{ 0, 0 }, .{ xx client.window.w, xx client.window.h }, .{ 0, 0, 0, 160 });

                if client.server_paused_game {
                    draw_text_screen_space(client, *client.title_font, "Game Paused!", .{ xx client.window.w / 2, xx client.window.h * 0.25 }, .Center | .Median, ORANGE_COLOR, .Shadow);
                }

                #if DEVELOPER {
                    if client.shadow_hud_enabled {
                        for i := 0; i < client.local_player_count; ++i {
                            draw_shadow_hud(client, *client.local_players[i]);
                        }
                    }

                    if client.sound_hud_enabled then draw_sound_hud(client);
                }
                
                ge_imm2d_flush(*client.graphics);
            }

            // Fade out a state transition if applicable
            if client.current_state != client.next_state {
                alpha := cast(u8) (clamp(1 - client.state_transition_t / client.state_transition_duration, 0, 1) * 255);

                FADE_COLOR: GE_Color : .{ 0, 0, 0, 255 };
                draw_rect_screen_space(client, .{ 0, 0 }, .{ xx client.window.w, xx client.window.h }, .{ FADE_COLOR.r, FADE_COLOR.g, FADE_COLOR.b, alpha });
            }

            draw_text_screen_space(client, *client.ui_font, VERSION_STRING, .{ 10, xx client.window.h - 10 }, .Left | .Bottom, GRAY_COLOR, .Default);

            #if DEVELOPER {
                ff :: (time: f32) -> Print_Format { return format_float(xx time, 0, 2); }

                timings := tprint("Update: % | Draw: % | Frame: %", ff(client.total_update_time), ff(client.total_draw_time), ff(client.window.frame_time * 1000));
                draw_text_screen_space(client, *client.ui_font, timings, .{ xx client.window.w - 10, xx 10 }, .Right | .Top, GRAY_COLOR, .Default);
                
                ge_imm2d_flush(*client.graphics);
                client.draw_call_count_before_ui = client.graphics.draw_call_count;
                client.draw_time_before_ui = os_convert_cpu_time(os_get_cpu_time() - begin, .Milliseconds);
            }

            draw_ui_frame(*client.ui);

            ge_imm2d_flush(*client.graphics);
            ge_swap_buffers(*client.graphics);

            #if DEVELOPER {
                client.total_draw_time = os_convert_cpu_time(os_get_cpu_time() - begin, .Milliseconds);
            }
        }

        //
        // Output gamepad vibration if desired
        //
        if client.current_state == .Ingame {
            for i := 0; i < client.local_player_count; ++i {
                local_player := *client.local_players[i];
                if local_player.input_binder.active_input_device != .Gamepad { continue; }

                full_health_color  :: GE_Color.{ 255, 55, 0, 255 };
                worst_health_color :: GE_Color.{  95, 55, 0, 255 };
                if local_player.guy_pid != INVALID_PID {
                    entity := get_entity(client, local_player.guy_pid);
                    guy := down(entity, Guy);

                    digging_vibration: f32 = ifx guy.state == .Digging then 0.2 else 0;
                    damage_vibration:  f32 = clamp(1 - guy.time_since_last_damage * 2, 0, 1); // When taking damage once, vibrate of 0.5 seconds

                    applied_vibration := ifx !client.server_paused_game && client.config.gamepad_vibration then max(damage_vibration, digging_vibration) else 0;

                    health := (entity.health - HEALTH_PER_HEART) / (DEFAULT_ENTITY_HEALTH[entity.entity_kind] - HEALTH_PER_HEART); // We want to show the worst color when you've only got one heart left
                    color: GE_Color = ge_mix_colors(full_health_color, worst_health_color, health);

                    set_gamepad_properties(*client.window, local_player.input_binder.gamepad_index, applied_vibration, applied_vibration, color.r, color.g, color.b);
                } else {
                    // This branch sometimes happens during game startup. 
                    applied_vibration: f32 = 0;
                    color := full_health_color;
                    set_gamepad_properties(*client.window, local_player.input_binder.gamepad_index, applied_vibration, applied_vibration, color.r, color.g, color.b);
                }
            }
        }
        
        //
        // Render one audio frame
        //
        {
            update_sound_players(client);
            update_mixer(*client.mixer);

            client.sounds_played_this_frame = .[ false ];
        }
        
        release_temp_allocator(0);
        
        frame_end := os_get_cpu_time();
        #if DEVELOPER { 
            client.total_frame_time_without_sleep = os_convert_cpu_time(frame_end - frame_start, .Milliseconds);
        }
        os_sleep_to_tick_rate(frame_start, frame_end, client.config.desired_fps);
    }
    
    // Shut down all resources that might currently be in use
    initiate_state_transition(client, .Count, 0);
    save_config(client);
    maybe_transition_to_next_state(client);

    //
    // Destroy the engine
    //
    destroy_config(client);
    destroy_all_sounds(client);
    destroy_mixer(*client.mixer);
    destroy_ui(*client.ui);
    destroy_draw_data(client);
    destroy_window(*client.window);
    destroy_memory_arena(*client.tick_arena);
    destroy_memory_pool(*client.world_pool);
    destroy_memory_pool(*client.engine_pool);

#if MEMORY_DEBUGGING {
    flush_file_printer(*client.memory_debug_printer);
    destroy_file_printer(*client.memory_debug_printer);
}
    
    logprint(.Info, "Stopped the client.");

    destroy_temp_allocator();
    return 0;
}
