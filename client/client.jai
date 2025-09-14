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
#load "profiler.jai";

// Shared
#load "../shared/messages.jai";
#load "../shared/shared.jai";
#load "../shared/bucket_array.jai";
#load "../shared/VERSION_STRING.jai";

// Client
#load "input_bindings.jai";
#load "entity.jai";
#load "particles.jai";
#load "assets.jai";
#load "sounds.jai";
#load "animation.jai";
#load "lightmap.jai";
#load "hud.jai";
#load "draw.jai";

DEVELOPER :: #run compiler_is_user_option_present("Developer");
MEMORY_DEBUGGING :: DEVELOPER && false;
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
        timestamp: CPU_Time;
        message: Message;
    }

    Message_History :: struct {
        entries: [16]Message_History_Entry;
        active: s64;
    }
}

UI_State :: struct {
    account_name: string;
    local_player_name: string = ""; // So that we can clear the text input when a player was added
    network_host: string;
    network_port := 9876;
}

UI_Scale :: enum {
    Small;
    Normal;
    Big;
    Extra_Large;
}

UI_SCALING_VALUES: [UI_Scale.Count]f32 : .[ 0.75, 1, 2, 4 ];

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

    ui_state: UI_State;
    desired_ui_scale: UI_Scale = .Normal; // We can't really provide a slider for a floating point value here as the actual slider would glitch around too hard...
    current_ui_scale: UI_Scale = .Normal;
    
    current_state: Game_State;
    next_state: Game_State;
    state_transition_t: f32; // We will only transition from the current state to the next state once this value reaches 0. Before that, we will just fade out the current state
    state_transition_duration: f32;
    random: Random_Generator;

    previous_game_result: Game_Result;
    info_text: string;
    info_text_t: f32;
    vibration_enabled := true;

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
    requested_game_mode: Game_Mode = .Tutorial; // Lobby screen
    immediately_start_game: bool = false; // Lobby screen, after pressing "single player" in the main menu
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
    enable_tutorial_panels := !DEVELOPER;

    //
    // Game Data
    //
    world_pool: Memory_Pool;
    world_allocator: Allocator;
    tick_arena: Memory_Arena; // For stuff that only needs to live for one update tick. If the game is paused, one tick might span over a lot of frames, so we cannot use temp for this!
    tick_allocator: Allocator;
    
    pause_menu_open: bool;
    server_paused_game: bool;

    game_seed: s64;
    game_score: u64;
    game_mode: Game_Mode;
    world_size: v2i;

    tick_time: f32;
    game_epoch_time: f32;

    local_players: [MAX_LOCAL_PLAYERS]Local_Player;
    local_player_count := 1;

    #using em: Entity_Manager;
    lightmap: Lightmap;
    global_particle_system: Pid;
    
    //
    // Debugging
    // 
#if DEVELOPER {
    developer_panel_state: UI_Window_State;
    developer_panel_position: UI_Vector2;

    free_camera_enabled: bool;
    sound_hud_enabled: bool;

    timing_update: f32;
    timing_draw: f32;
    timing_total_no_sleep: f32;

    incoming_message_history: Message_History;
    outgoing_message_history: Message_History;
    message_history_panel_state: UI_Window_State;
    message_history_panel_position: UI_Vector2;
}

#if MEMORY_DEBUGGING {
    memory_debug_printer: File_Printer;
}
}



Log_Level :: enum {
    Debug;
    Info;
    Warning;
    Error;
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

start_lobby :: (client: *Client) {
    msg := make_message(Request_Game_Start_Message);
    msg.request_game_start.game_mode = client.requested_game_mode;
    send_reliable_message(*client.connection, *msg);
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

handle_incoming_message :: (client: *Client, msg: *Message) {
    if #complete msg.msg_type == {
      case .Request_Game_Start, .Guy_Input; // Ignore
    
      case .Client_Disconnect;
        for i := 0; i < client.remote_players.count; {
            remote_player := array_get_pointer(*client.remote_players, i);
            if remote_player.client_pid == msg.client_disconnect.client_pid {
                deallocate_string(*client.engine_allocator, *remote_player.name);
                array_remove_index(*client.remote_players, i);
            } else {
                ++i;
            }
        }

      case .Remove_Local_Player;
        if msg.remove_local_player.client_pid == client.my_client_pid break;
        
        for i := 0; i < client.remote_players.count; {
            remote_player := array_get_pointer(*client.remote_players, i);
            if remote_player.client_pid == msg.remove_local_player.client_pid && remote_player.local_player_index == msg.remove_local_player.local_player_index {
                deallocate_string(*client.engine_allocator, *remote_player.name);
                array_remove_index(*client.remote_players, i);
            } else {
                ++i;
            }
        }
        
      case .Player_Information;
        if msg.player_information.client_pid != client.my_client_pid {
            remote_player := find_remote_player_by_pid_and_local_index(client, msg.player_information.client_pid, msg.player_information.local_player_index);
            
            if remote_player == null {
                remote_player = array_push(*client.remote_players);
                remote_player.local_player_index = msg.player_information.local_player_index;
                remote_player.client_pid = msg.player_information.client_pid;
                remote_player.guy_pid    = msg.player_information.guy_pid;
                remote_player.name       = copy_string(*client.engine_allocator, msg.player_information.name);
            } else if msg.player_information.guy_pid != INVALID_PID {
                remote_player.guy_pid = msg.player_information.guy_pid;
            }
        } else if msg.player_information.guy_pid != INVALID_PID {
            local_player := *client.local_players[msg.player_information.local_player_index];
            
            local_player.guy_pid = msg.player_information.guy_pid;

            // Calculate the initial camera position to avoid lerping the first few frames
            guy := get_entity(client, local_player.guy_pid);
            update_camera(client, *local_player.camera, .{ xx guy.physical_position.x, xx guy.physical_position.y }, local_player.viewport, 1, true);
        }

      case .Game_Pause;
        client.server_paused_game = msg.game_pause.should_pause;
        toggle_all_game_sounds(client, client.server_paused_game);
        
      case .Game_Start;
        client.pause_menu_open = false;
        client.server_paused_game = false;
        client.game_seed  = msg.game_start.seed;
        client.world_size = msg.game_start.size;
        client.game_mode  = msg.game_start.game_mode;
        initiate_state_transition(client, .Ingame, 0);

        seed_random_generator(*client.random, client.game_seed, client.game_seed, client.game_seed, client.game_seed);
        initialize_random_sounds(client);
        create_entity_manager(client);
        create_lightmap(*client.lightmap, *client.world_allocator, client.world_size);

        for i := 0; i < client.local_player_count; ++i {
            create_hud(client, i);
            client.local_players[i].guy_pid = INVALID_PID;
        }
        
        // Create the dust particles
        {
            system := create_particle_system(client, MAX_F32, .{ xx (client.world_size.x / 2), xx (client.world_size.y / 2) }, 1);
            emitter := create_particle_emitter(system, 0, client.world_size.x * 10);
            emitter.shape = .Box;
            emitter.box_half_size = .{ xx (client.world_size.x / 2) + 2, xx (client.world_size.y / 2) + 2 };
            emitter.random_initial_velocity = true;
            emitter.turbulence = 0.001;
            emitter.fadein     = 1;
            emitter.fadeout    = 3;
            emitter.size       = .[ .{ 0.02, 0.02 }, .{ 0.1, 0.1 } ];
            emitter.speed      = .[ 0.05, 0.2 ];
            emitter.lifetime   = .[ 2, 10 ];
            emitter.color      = .[ .{ 50, 50, 50, 130 }, .{ 200, 200, 200, 70 } ];
            emitter.particles_per_second = xx client.world_size.x;
            
            prewarm_particle_system(system, 5, 0.1);

            client.global_particle_system = system.pid;
        }

        request_tutorial_panel(client, .About_Tutorial_Panels);
        
        // Reset debug settings
        #if DEVELOPER {
            client.developer_panel_state = .Closed;
            client.free_camera_enabled = false;
        }
        
      case .Game_Over;
        client.game_score = msg.game_over.score;
        client.previous_game_result = msg.game_over.result;
        initiate_state_transition(client, .Game_Over, 5);

      case .Game_Score;
        client.game_score = msg.game_score.score;

      case .World_Resize;
        client.world_size = msg.world_resize.new_world_size;
        resize_lightmap(*client.lightmap, client.world_size);

        {
            system := get_particle_system(client, client.global_particle_system);
            system.world_position = .{ xx (client.world_size.x / 2), xx (client.world_size.y / 2) };
            emitter := *system.emitters[0];
            emitter.box_half_size = .{ xx (client.world_size.x / 2) + 2, xx (client.world_size.y / 2) + 2 };
        }
            
      case .Create_Entity;
        entity := create_entity_with_pid(client, msg.create_entity.entity_pid, msg.create_entity.kind, msg.create_entity.position, msg.create_entity.rotation);
        maybe_add_blocker(*client.lightmap, entity);
        
      case .Destroy_Entity;
        entity := get_entity(client, msg.destroy_entity.entity_pid);
        entity.marked_for_removal = true;

        // Play death sounds
        if entity.entity_kind == {
          case .Frog;   play_sound_on_entity(client, .Frog_Death_0,   entity, .Once_Per_Frame);
          case .Goblin; play_sound_on_entity(client, .Goblin_Death_0, entity, .Once_Per_Frame);
          case .Slime;  play_sound_on_entity(client, .Slime_Death_0,  entity, .Once_Per_Frame);
        }

        maybe_remove_blocker(*client.lightmap, entity);

        // edge-case: Update hole entity in case slime got killed in hole
        // (currently only possible with cheat)
        if entity.entity_kind == .Slime {
            hole_entity := find_entity_of_kind_at_position(client, .Slime_Hole, entity.physical_position);
            if hole_entity != null {
                update_slime_hole(client, hole_entity);
            }
        }
        
      case .Move_Entity;
        entity := get_entity(client, msg.move_entity.entity_pid);

        maybe_move_blocker(*client.lightmap, entity, msg.move_entity.position);

        entity.physical_position = msg.move_entity.position;
        entity.physical_rotation = msg.move_entity.rotation;

        // Play walking animations / rotate idle animations
        if entity.entity_kind == {
          case .Guy;
            maybe_play_animation_from_group_instead(client, entity, .Is_Idle | .Is_Walk, .Guy_Walk);
          case .Frog;
            maybe_play_animation_from_group_instead(client, entity, .Is_Idle, .Frog_Idle);
          case .Goblin;
            maybe_play_animation_from_group_instead(client, entity, .Is_Idle, .Goblin_Idle);
          case .Slime;
            maybe_play_animation_from_group_instead(client, entity, .Is_Idle | .Is_Walk, .Slime_Walk);
          case .Trader;
            maybe_play_animation_from_group_instead(client, entity, .Is_Idle, .Trader_Idle);
        }
        
      case .Entity_Health;
        entity := get_entity(client, msg.entity_health.entity_pid);

        // Play damage sounds
        sound_index: Sound_Index = .Count;
        
        if entity.entity_kind == {
          case .Frog;   sound_index = .Frog_Hurt_0;
          case .Goblin; sound_index = .Goblin_Hurt_0;
          case .Slime;  sound_index = .Slime_Hurt_0;
        }

        dropped_heart := floor(msg.entity_health.new_health / HEALTH_PER_HEART) < floor(entity.health / HEALTH_PER_HEART);
        gained_heart  := floor(msg.entity_health.new_health / HEALTH_PER_HEART) > floor(entity.health / HEALTH_PER_HEART);
        
        if sound_index != .Count && entity.sound_cooldown <= 0 && !sound_active(client, entity.sound) {
            entity.sound          = play_sound_on_entity(client, sound_index, entity, .Once_Per_Frame);
            entity.sound_cooldown = get_sound_length_in_seconds(client, sound_index) * 2;
        }

        // Play a potential damage animation
        if msg.entity_health.new_health < entity.health {
            if entity.entity_kind == {
              case .Guy; maybe_play_animation_from_group_instead(client, entity, .Is_Idle | .Is_Walk, .Guy_Damaged);
              case .Goblin; maybe_play_animation_from_group_instead(client, entity, .Is_Idle, .Goblin_Damaged);
              case .Frog; maybe_play_animation_from_group_instead(client, entity, .Is_Idle, .Frog_Damaged);
              case .Slime; maybe_play_animation_from_group_instead(client, entity, .Is_Idle | .Is_Walk, .Slime_Damaged);
            }
        }
            
        // Play damage particles & health bar animation
        if entity.entity_flags & .Living && dropped_heart {
            system := create_particle_system(client, 1.0, .{ xx entity.physical_position.x, xx entity.physical_position.y }, 1);
            emitter := create_particle_emitter(system, 0, 64);
            emitter.shape = .Box;
            emitter.box_half_size = .{ 0.15, 0.15 };
            emitter.drag     = 0.7;
            emitter.size     = .[ .{ 0.02, 0.02 }, .{ 0.05, 0.05 } ];
            emitter.speed    = .[ 3, 5 ];
            emitter.lifetime = .[ 0.6, 1.0 ];
            emitter.color    = .[ .{ 255, 0, 0, 255 }, .{ 184, 4, 70, 255 } ];
            emitter.particles_per_second = 1024;
            emitter.alive_t  = 0.6;
        }

        if entity.entity_flags & .Living {
            entity.health_bar_damage_animation_t = 1;
            entity.health_bar_damage_animation_base = ceil(entity.health / HEALTH_PER_HEART) * HEALTH_PER_HEART; // This is the heart that we just lost, since we want to animate that one.
        }
        
        // Play heal particles
        if entity.entity_flags & .Living && gained_heart {
            system, emitter := create_halo_particles(client, entity, 1);
            emitter.alive_t  = 0.5;
            emitter.color    = .[ .{ 255, 0, 0, 255 }, .{ 184, 4, 70, 255 } ];
        }
            
        entity.health = msg.entity_health.new_health;
        
      case .Guy_State;
        entity := get_entity(client, msg.guy_state.entity_pid);
        guy := down(entity, Guy);

        // State Transitions
        if guy.state != msg.guy_state.state {
            stop_sound(client, *guy.sound);

            if #complete msg.guy_state.state == {
              case .Digging;      guy.sound = play_sound_on_entity(client, .Guy_Digging_0, entity, .Looping);
              case .Carrying;     guy.sound = play_sound_on_entity(client, .Hud_Pickup_0, entity, .Default);
              case .Resurrecting; guy.resurrection_t = 0;
              case .Dead;
                guy.sound = play_sound_on_entity(client, .Guy_Death_0, entity, .Default);
                play_animation_from_group(client, guy, .Guy_Dead);
              case .Idle; if guy.state == .Carrying guy.sound = play_sound_on_entity(client, .Hud_Placedown_0, entity, .Default);
            }

            if msg.guy_state.state != .Dead {
                // If the player just stopped being dead, we want to switch away from the Death animation.
                // We want this death animation to keep being played as long as we are dead, which is why
                // no other part of the code does this specific job (i.e. when a dead guy is taking damage,
                // we *don't* want to play the damage animation, because he's already dead...)
                play_animation_from_group(client, guy, .Guy_Idle);
            }
        }

        guy.state           = msg.guy_state.state;
        guy.target_position = msg.guy_state.target_position;
        guy.carrying_item   = msg.guy_state.carrying_item;
        guy.strength_t      = msg.guy_state.strength_t;
        
        if is_local_guy_pid(client, guy.pid) && guy.state == .Carrying && guy.carrying_item == .Shard {
            request_tutorial_panel(client, .Using_The_Crafting_Menu);
        }

      case .Emitter_State;
        entity := get_entity(client, msg.emitter_state.entity_pid);
        emitter := down(entity, Emitter);

        previous_state := emitter.state;

        emitter.state = msg.emitter_state.state;
        
        if abs(msg.emitter_state.current_charge - emitter.current_charge) > (EMITTER_MAX_CHARGE[client.game_mode] / EMITTER_TIME_TO_POWER_UP) * 0.2 {
            // Only modify the client side prediction if it actually seems off, to not mess with
            // visuals and audio if not necessary
            emitter.current_charge = msg.emitter_state.current_charge;
        }

        if emitter.state == {
          case .Active; 
            if previous_state != .Active {
                stop_sound(client, *emitter.sound); // Stop the charging up sound
                emitter.sound = play_sound(client, .Hud_Success_0, .Default); // Don't spatialize this sound so that everyone can hear it
            }

          case .Off;
            should_play_sound := emitter.currently_charging_up && emitter.current_charge < EMITTER_MAX_CHARGE[client.game_mode]; // Avoid glitching at the end due to client side prediction
            if should_play_sound && !sound_active(client, emitter.sound) {
                emitter.sound = play_sound_on_entity(client, .Emitter_Charging, emitter, .Default);
                set_sound_playback_position(client, emitter.sound, emitter.current_charge / EMITTER_MAX_CHARGE[client.game_mode]);
            } else if !should_play_sound {
                stop_sound(client, *emitter.sound);
            }
        }

      case .Item_Stack_State;
        entity := get_entity(client, msg.item_stack_state.entity_pid);
        item_stack := down(entity, Item_Stack);
        item_stack.item_kind = msg.item_stack_state.item_kind;
        item_stack.count     = msg.item_stack_state.count;

      case .Chest_State;
        entity := get_entity(client, msg.chest_state.entity_pid);
        chest := down(entity, Chest);
        chest.inventory = msg.chest_state.inventory;
        chest.visually_open = msg.chest_state.visually_open;

      case .Frog_State;
        entity := get_entity(client, msg.frog_state.entity_pid);
        frog := down(entity, Frog);

        if frog.state != msg.frog_state.state {
            frog.state_t = 0;

            if msg.frog_state.state == {
              case .Idle; play_animation_from_group(client, frog, .Frog_Idle);
              case .Recovering; play_animation_from_group(client, frog, .Frog_Recovering);
              case .Attacking;
                frog.sound = play_sound_on_entity(client, .Frog_Attack_0, entity, .Once_Per_Frame);
                play_animation_from_group(client, frog, .Frog_Attacking);

                particles := create_particle_system(client, FROG_ATTACK_TIME, frog.visual_position, 1);
                emitter := create_particle_emitter(particles, 0, 256);
                emitter.shape    = .Cone;
                emitter.emissive = true;
                emitter.drag     = .9;
                emitter.speed    = .[ 4, 6 ];
                emitter.lifetime = .[ 0.5, 0.8 ];
                emitter.color    = .[ .{ 255, 241, 99, 255 }, .{ 255, 111, 52, 255 } ];
                emitter.particles_per_second = 1024;
                emitter.alive_t  = 0.5;

                theta := visual_from_physical_rotation(frog.physical_rotation);
                emitter.cone_angles = .[ theta - 0.03, theta + 0.03 ];
            }
        }

        frog.state = msg.frog_state.state;

      case .Goblin_State;
        entity := get_entity(client, msg.goblin_state.entity_pid);
        goblin := down(entity, Goblin);

        if goblin.state != msg.goblin_state.state {
            goblin.state_t = 0;

            if msg.goblin_state.state == {
              case .Idle; play_animation_from_group(client, goblin, .Goblin_Idle);
              case .Recovering; play_animation_from_group(client, goblin, .Goblin_Recovering);
              case .Attacking;
                goblin.sound = play_sound_on_entity(client, .Goblin_Attack_0, entity, .Once_Per_Frame);
                play_animation_from_group(client, goblin, .Goblin_Attacking);
            }
        }

        goblin.state = msg.goblin_state.state;

      case .Slime_State;
        entity := get_entity(client, msg.slime_state.entity_pid);
        slime := down(entity, Slime);

        if slime.state != msg.slime_state.state {
            if msg.slime_state.state == .Fleeing {
                play_sound_on_entity(client, .Slime_Scared_0, entity, .Once_Per_Frame);
            }
        }
        
        if msg.slime_state.state == {
          case .Hiding; bitfield_add(*slime.entity_flags, Entity_Flags.Disabled_Temporarily);
          case; bitfield_remove(*slime.entity_flags, Entity_Flags.Disabled_Temporarily);
        }

        slime.state = msg.slime_state.state;
        
        for i := 0; i < client.all_entities.slot_count; ++i {
            entity, occupied := index_bucket_array(*client.all_entities, i);
            if occupied && entity.entity_kind == .Slime_Hole then update_slime_hole(client, entity);
        }
    }
}

send_player_information_message :: (client: *Client, local_player_index: s64) {
    msg := make_message(Player_Information_Message);
    msg.player_information.local_player_index = local_player_index;
    msg.player_information.client_pid = client.my_client_pid;
    msg.player_information.name = client.local_players[local_player_index].name;
    send_reliable_message(*client.connection, *msg);
}

read_incoming_packets :: (client: *Client) {
    while read_packet(*client.connection) {
        packet :: *client.connection.incoming_packet;
        
        update_virtual_connection_information_for_packet(*client.connection, *packet.header);
        
        if packet.header.packet_type == {
          case Packet_Type.Connection_Established;
            if client.next_state == .Connecting {
                server_version: string = string.{ packet.body_size, packet.body };
                valid_connection: bool = server_version == VERSION_STRING;
                
                if !valid_connection {
                    set_info_text(client, DEFAULT_INFO_TEXT_TIMER, "The server is running a different version than you (% vs %)!", server_version, VERSION_STRING);
#if !DEVELOPER {
    client.next_state = .Main_Menu;
    break;
}
                }
                
                client.my_client_pid = packet.header.sender_client_id;
                client.connection.info.client_id = client.my_client_pid;
                client.next_state = .Lobby;

                for i := 0; i < client.local_player_count; ++i {
                    send_player_information_message(client, i);
                }
            }
          
          case Packet_Type.Connection_Closed;
            client.previous_game_result = .Connection_Lost;
            initiate_state_transition(client, .Game_Over, 0);
            
          case Packet_Type.Ping;
            timestamp: CPU_Time = ~(cast(*CPU_Time) *packet.body[0]);
            client.latest_rtt = os_convert_cpu_time(os_get_cpu_time() - timestamp, .Milliseconds);

          case Packet_Type.Message;
            msg: Message = ---;
            while read_message(packet, *msg) {
#if DEVELOPER   register_message_history(*client.incoming_message_history, msg);
                handle_incoming_message(client, *msg);
            }
        }
    }
}

handle_server_timeout :: (client: *Client, next_screen: Game_State, info_text: string) {
    if os_convert_cpu_time(os_get_cpu_time() - client.connection.time_of_last_received_packet, .Seconds) > NETWORK_TIMEOUT {
        client.previous_game_result = .Connection_Lost;
        initiate_state_transition(client, next_screen, 0);
        set_info_text(client, DEFAULT_INFO_TEXT_TIMER, info_text);
    } else if os_convert_cpu_time(os_get_cpu_time() - client.connection.time_of_last_sent_packet, .Seconds) > NETWORK_PING_INTERVAL {
        timestamp := os_get_cpu_time();
        send_ping_packet(*client.connection, .{ size_of(timestamp), xx *timestamp });
    }
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
      case .Main_Menu, .Game_Over;

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
        disconnect_from_server(client);
        maybe_shutdown_server(client);
        reset_allocator(*client.world_allocator);
        array_clear(*client.requested_tutorial_panels);
        
        // Stop any active rumbling effect
        for i := 0; i < client.local_player_count; ++i {
            local_player := *client.local_players[i];
            set_gamepad_properties(*client.window, local_player.input_binder.gamepad_index, 0, 0, 255, 255, 255);
        }
    }

    client.current_state = client.next_state;
}

recalculate_local_player_viewports :: (client: *Client) {
    #assert(MAX_LOCAL_PLAYERS == 4);

    if client.local_player_count == {
      case 1;
        client.local_players[0].viewport = .[ 0, 0, xx client.window.w, xx client.window.h ];
      case 2;
        center_x: f32 = floor(cast(f32) client.window.w * 0.5);
        client.local_players[0].viewport = .[ 0, 0, center_x, xx client.window.h ];
        client.local_players[1].viewport = .[ center_x + 1, 0, xx client.window.w, xx client.window.h ];
      case 3;
        center_x: f32 = floor(cast(f32) client.window.w * 0.5);
        center_y: f32 = floor(cast(f32) client.window.h * 0.5);
        client.local_players[0].viewport = .[ 0, 0, center_x, center_y ];
        client.local_players[1].viewport = .[ center_x + 1, 0, xx client.window.w, center_y ];
        client.local_players[2].viewport = .[ 0, center_y + 1, center_x, xx client.window.h ];
      case 4;
        center_x: f32 = floor(cast(f32) client.window.w * 0.5);
        center_y: f32 = floor(cast(f32) client.window.h * 0.5);
        client.local_players[0].viewport = .[ 0, 0, center_x, center_y ];
        client.local_players[1].viewport = .[ center_x + 1, 0, xx client.window.w, center_y ];
        client.local_players[2].viewport = .[ 0, center_y + 1, center_x, xx client.window.h ];
        client.local_players[3].viewport = .[ center_x + 1, center_y + 1, xx client.window.w, xx client.window.h ];
    }
}

reassign_gamepad_indices :: (client: *Client) {
    index := 0;

    for i := 0; i < client.local_player_count; ++i {
        client.local_players[i].input_binder.gamepad_index = index;
        if client.local_players[i].input_binder.allowed_input_devices & .Gamepad ++index;
    }
}

maybe_update_ui_scale :: (client: *Client) {
    if client.current_ui_scale == client.desired_ui_scale then return;

    client.current_ui_scale = client.desired_ui_scale;
    client.ui.pixel_scaling = UI_SCALING_VALUES[client.current_ui_scale];
    create_ui_scaled_draw_data(client);
    change_ui_font(*client.ui, *client.ui_font); // Force-update all cached label sizes
}

do_game_mode_selector :: (client: *Client) {
    ui :: *client.ui;

    if ui_push_dropdown(ui, "Campaign", .Vertical, true, enum_names(Game_Mode)[client.requested_game_mode]) {
        for i := 0; i < Game_Mode.Count; ++i {
            if !DEVELOPER && i == Game_Mode.Developer continue;

            if ui_button(ui, enum_names(Game_Mode)[i]) {
                client.requested_game_mode = i;
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

    if client.server_data.state != .Closed && client.info_text_t <= 0 { // Don't override other error conditions...
        set_temp_info_text(client, "Your local server is still running...");
    }
    
    // Host Window
    {
        ui_push_window(ui, "Host", .Default, window_position(client, -1));
        ui_label(ui, false, "Name:");
        ui_text_input_with_string(ui, "Enter your name", *client.ui_state.account_name, *client.engine_allocator);
        ui_divider(ui, true);
        ui_label(ui, false, "Port");
        ui_text_input_with_int(ui, "Enter the port", *client.ui_state.network_port);
        ui_divider(ui, true);
        
        if client.server_data.state == .Closed && ui_button(ui, "Host!") {
            if client.ui_state.account_name && host_server(client, client.ui_state.network_port) {
                join_server(client, client.ui_state.account_name, "localhost", client.ui_state.network_port);
                client.immediately_start_game = false;
            }
        }
        
        ui_pop_window(ui);
    }

    // Single Player Window
    {
        ui_push_window(ui, "Single Player", .Default, window_position(client, 0));

        do_game_mode_selector(client);
        ui_divider(ui, true);

        if client.server_data.state == .Closed && ui_button(ui, "Play!") && host_server(client, DEFAULT_PORT) {
            join_server(client, "YOU", "localhost", DEFAULT_PORT);
            client.immediately_start_game = true;
        }
        
        ui_pop_window(ui);
    }
    
    // Join Window
    {
        ui_push_window(ui, "Join", .Default, window_position(client, +1));
        ui_label(ui, false, "Name:");
        ui_text_input_with_string(ui, "Enter your name", *client.ui_state.account_name, *client.engine_allocator);
        ui_divider(ui, true);
        ui_label(ui, false, "Host");
        ui_text_input_with_string(ui, "Enter the address", *client.ui_state.network_host, *client.engine_allocator);
        ui_label(ui, false, "Port");
        ui_text_input_with_int(ui, "Enter the port", *client.ui_state.network_port);
        ui_divider(ui, true);
        
        if client.server_data.state == .Closed && ui_button(ui, "Join!") {
            if client.ui_state.account_name && client.ui_state.network_host {
                join_server(client, client.ui_state.account_name, client.ui_state.network_host, client.ui_state.network_port);
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
        send_connection_request_packet(*client.connection, 1, VERSION_STRING);
        client.sent_connection_request = true;
    }
    
    {
        ui :: *client.ui;
        ui_push_width(ui, .Pixels, 256, 1);
        ui_push_window(ui, "Connecting...", .Default, .{ .5, .5 });
        ui_label(ui, false, "...");
        ui_divider(ui, true);
        if ui_button(ui, "Cancel!") then initiate_state_transition(client, .Main_Menu, 0);
        ui_pop_window(ui);
        ui_pop_width(ui);
    }    
}

maybe_add_local_player :: (client: *Client) {
    if client.local_player_count >= MAX_LOCAL_PLAYERS || client.ui_state.local_player_name.count == 0 return;

    client.local_players[client.local_player_count].name = copy_string(*client.engine_allocator, client.ui_state.local_player_name);
    client.local_players[client.local_player_count].input_binder.allowed_input_devices = .Gamepad;
    ++client.local_player_count;

    if client.local_players[0].input_binder.allowed_input_devices == .ALL then client.local_players[0].input_binder.allowed_input_devices = .Keyboard;

    send_player_information_message(client, client.local_player_count - 1);

    deallocate_string(*client.engine_allocator, *client.ui_state.local_player_name);
}

do_lobby_screen :: (client: *Client) {
    input_device_widget :: (client: *Client, label: string, allowed_devices: *Input_Device) {
        Custom_State :: struct {
            allowed_devices: *Input_Device;
        }

        draw_input_device_widget :: (client: *Client, element: *UI_Element, state: *Custom_State) {
            index: Sprite_Index = ---;

            if ~state.allowed_devices == .Keyboard {
                index = .Hud_Keyboard;
            } else if ~state.allowed_devices == .Gamepad {
                index = .Hud_Gamepad;
            } else if ~state.allowed_devices == .ALL {
                index = .Hud_Keyboard_Gamepad;
            }

            center: GE_Vector2 = .{ round(element.screen_position.x + element.screen_size.x * 0.5), round(element.screen_position.y + element.screen_size.y * 0.5) };
            size_animation_factor := sinf(element.size_t * 10) * 0.2 + 1;
            size: GE_Vector2 = .{ element.screen_size.x * size_animation_factor, element.screen_size.y * size_animation_factor };
            draw_sprite_screen_space(client, index, center, size, 0, .{ 255, 255, 255, 255 }, false);
        }

        update_input_device_widget :: (client: *Client, element: *UI_Element, state: *Custom_State) {
            if element.signals & .Clicked {
                if ~state.allowed_devices == .Keyboard {
                    ~state.allowed_devices = .Gamepad;
                } else if ~state.allowed_devices == .Gamepad {
                    ~state.allowed_devices = .ALL;
                } else if ~state.allowed_devices == .ALL {
                    ~state.allowed_devices = .Keyboard;
                }
            }
        }

        data := ui_custom_widget(*client.ui, label, .Animate_Size_On_Hover | .Animate_Size_On_Activation, update_input_device_widget, draw_input_device_widget, size_of(Sprite_Index));
        state := cast(*Custom_State) data.custom_state;
        state.allowed_devices = allowed_devices;
    }

    read_incoming_packets(client);
    handle_server_timeout(client, .Main_Menu, "The server died.");

    if client.immediately_start_game {
        start_lobby(client);
        client.immediately_start_game = false;
    }

    // Do the lobby UI
    {
        ui :: *client.ui;
        ui_push_width(ui, .Pixels, 256, 1);
        ui_push_window(ui, "Lobby!", .Default, .{ .5, .4 });
        
        for i := 0; i < client.local_player_count; ++i {
            local_player := *client.local_players[i];

            ui_push_height(ui, .Pixels, 32, 1);
            ui_push_container(ui, .Horizontal);

            ui_push_width(ui, .Pixels, 256, 0);
            ui_label(ui, false, local_player.name);
            ui_pop_width(ui);
            
            ui_push_width(ui, .Pixels, 32, 1);
            input_device_widget(client, tprint("local_player_input_devices%", i), *local_player.input_binder.allowed_input_devices);
            ui_pop_width(ui);

            if local_player.input_binder.allowed_input_devices & .Gamepad && local_player.input_binder.gamepad_index >= client.window.connected_gamepads {
                ui_push_width(ui, .Label_Size, 5, 1);
                ui_label(ui, true, "!");
                ui_pop_width(ui);
            }
            
            ui_pop_container(ui);
            ui_pop_height(ui);
        }
        
        for i := 0; i < client.remote_players.count; ++i {
            player := array_get_pointer(*client.remote_players, i);
            ui_label(ui, false, player.name);
        }

        ui_divider(ui, true);
        
        {
            ui_label(ui, true, "Local Players");

            if client.local_player_count < MAX_LOCAL_PLAYERS {
                ui_push_container(ui, .Horizontal);
                ui_push_width(ui, .Percentage_Of_Parent, 0.5, 0.5);

                entered_name := ui_text_input_with_string(ui, "Name", *client.ui_state.local_player_name, *client.engine_allocator);

                if ui_button(ui, "Add!") || entered_name {
                    maybe_add_local_player(client);
                }

                ui_pop_width(ui);
                ui_pop_container(ui);
            }
            
            if client.local_player_count > 1 && ui_button(ui, "Remove Local Player!") {
                deallocate_string(*client.engine_allocator, *client.local_players[client.local_player_count - 1].name);
                msg := make_message(Remove_Local_Player_Message);
                msg.remove_local_player.client_pid = client.my_client_pid;
                msg.remove_local_player.local_player_index = client.local_player_count - 1;
                send_reliable_message(*client.connection, *msg);
                --client.local_player_count;
            }
        }

        ui_divider(ui, true);
        do_game_mode_selector(client);
        
        if ui_button(ui, "Start!") {
            maybe_add_local_player(client); // Add a new local player when somebody typed in the name but forgot to press "Add!"
            start_lobby(client);
        }
        
        ui_divider(ui, true);
        if ui_button(ui, "Disconnect!") then initiate_state_transition(client, .Main_Menu, 0);
        ui_pop_window(ui);
        ui_pop_width(ui);
    }

    // Handle test inputs. This can help in figuring out which player uses which gamepad in
    // local multiplayer.
    {
        register_test_input :: (client: *Client, local_player_index: s64, sprite_index: Sprite_Index) {
            input := array_push(*client.test_inputs);
            input.cpu_time = os_get_cpu_time();
            input.local_player_index = local_player_index;
            input.sprite_index = sprite_index;
        }

        now := os_get_cpu_time();
        for i := 0; i < client.test_inputs.count; {
            input := array_get_pointer(*client.test_inputs, i);
            if os_convert_cpu_time(now - input.cpu_time, .Seconds) > 2 {
                array_remove_index(*client.test_inputs, i);
            } else {
                ++i;
            }
        }
        
        for i := 0; i < client.local_player_count; ++i {
            local_player := *client.local_players[i];

            if bitfield_contains(*local_player.input_binder.allowed_input_devices, Input_Device.Keyboard) && !client.ui.active_text_input {
                if client.window.keys[.Space] & .Pressed then register_test_input(client, i, .Hud_Key_Space);
                if client.window.keys[.Shift] & .Pressed then register_test_input(client, i, .Hud_Key_Shift);
            }

            if bitfield_contains(*local_player.input_binder.allowed_input_devices, Input_Device.Gamepad) && local_player.input_binder.gamepad_index < client.window.connected_gamepads {
                gamepad := *client.window.gamepads[local_player.input_binder.gamepad_index];
                if gamepad.buttons[.XBox_A]    & .Pressed then register_test_input(client, i, .Hud_XBox_A);
                if gamepad.buttons[.XBox_X]    & .Pressed then register_test_input(client, i, .Hud_XBox_X);
                if gamepad.buttons[.PS_Cross]  & .Pressed then register_test_input(client, i, .Hud_PS_Cross);
                if gamepad.buttons[.PS_Square] & .Pressed then register_test_input(client, i, .Hud_PS_Square);
            }
        }
    }
}

do_game_over_screen :: (client: *Client) {
    ui :: *client.ui;
    ui_push_width(ui, .Pixels, 350, 1);
    ui_push_window(ui, "Game Over!", .Default, .{ .5, .5 });
    
    score_text := tprint("Final Score: %", client.game_score);
    
    if #complete client.previous_game_result == {
      case .Unfinished_Game; // Should never happen, this value is just used on the server side
          
      case .Completed_Tutorial;
        ui_label(ui, true, "You completed the tutorial!");

      case .All_Players_Died; 
        ui_label(ui, true, "All players have died!");
        ui_label(ui, true, score_text);
        
      case .Flag_Was_Destroyed;
        ui_label(ui, true, "The flag was destroyed!");
        ui_label(ui, true, score_text);

      case .Connection_Lost;
        ui_label(ui, true, "Connection died!");
    }
    
    ui_divider(ui, true);
    if ui_button(ui, "Back to Main Menu!") then initiate_state_transition(client, .Main_Menu, 0);

    ui_pop_window(ui);
    ui_pop_width(ui);
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

find_next_entity_to_spectate :: (client: *Client, current_pid: Pid, forwards: bool) -> Pid {
    build_list_of_candidates :: (client: *Client) -> [..]Pid {
        result: [..]Pid;
        result.allocator = *temp;

        for i := 0; i < client.guys.slot_count; ++i {
            guy, occupied := index_bucket_array(*client.guys, i);
            if occupied array_add(*result, guy.pid);
        }
        
        return result;
    }

    candidates := build_list_of_candidates(client);

    current_index, found_index := array_index_of(*candidates, current_pid);
    assert(found_index, "The currently spectated entity is not part of the candidates.");
    
    next_index := ifx forwards then current_index + 1 else current_index - 1;
    next_index = next_index % candidates.count;
    
    return array_get(*candidates, next_index);
}

maybe_do_pause_menu_panel :: (client: *Client) -> bool {
    if !client.pause_menu_open then return false;

    ui :: *client.ui;
    ui_push_window(ui, "Glassminers", .Default, .{ 0.5, 0.35 });
    ui_push_width(ui, .Pixels, 256, 1);
    ui_push_height(ui, .Pixels, 32, 1);

    ui_label(ui, true, "Seed: %", client.game_seed);
    ui_slider(ui, "Audio", *client.mixer.volumes[.Master], 0, 1);
    ui_slider(ui, "Gamma", *client.lightmap.gamma, 1, 4);
    ui_selector_box_with_enum_pointer(ui, "UI Scale", *client.desired_ui_scale);
    ui_check_box(ui, "Gamepad Vibration", *client.vibration_enabled);
    
    if client.game_mode == .Tutorial {
        ui_check_box(ui, "Tutorial Panels", *client.enable_tutorial_panels);
    }

    ui_toggle_button_with_pointer(ui, "Input Bindings", cast(*bool) *client.input_bindings_panel_state);

    ui_divider(ui, true);
    continue_game := ui_button(ui, "Continue!");
    ui_divider(ui, false);
    if ui_button(ui, "Back to Main Menu!") then initiate_state_transition(client, .Main_Menu, 0);

    ui_pop_height(ui);
    ui_pop_width(ui);
    ui_pop_window(ui);

    return continue_game;
}

maybe_do_input_bindings_panel :: (client: *Client) {
    if !client.pause_menu_open || client.input_bindings_panel_state == .Closed then return;

    ui := *client.ui;

    client.input_bindings_panel_state, client.input_bindings_panel_position = ui_push_window(ui, "Input Bindings", .Draggable | .Closeable, client.input_bindings_panel_position);

    if client.input_bindings_panel_state == .Open {
        for i: Input_Action = 0; i < Input_Action.Count; ++i {
            if !input_action_available(i) continue;

            ui_push_width(ui, .Pixels, 800, 1);
            ui_push_container(ui, .Horizontal);
            ui_set_width(ui, .Percentage_Of_Parent, 0.4, 1);
            ui_label(ui, false, "%", input_action_string(i));
            ui_set_width(ui, .Percentage_Of_Parent, 1.0, 0);
            ui_label(ui, false, input_bindings_string(client, i));
            ui_pop_container(ui);
            ui_pop_width(ui);
        }
    }

    ui_pop_window(ui);
}

#if DEVELOPER {
maybe_do_developer_panel :: (client: *Client) {
    if client.developer_panel_state == .Closed then return;

    ui :: *client.ui;
    
    ui_push_width(ui, .Pixels, 360, 0.8);
    client.developer_panel_state, client.developer_panel_position = ui_push_window(ui, "Developer", .Draggable | .Closeable | .Collapsable, client.developer_panel_position);

    if client.developer_panel_state == .Open {
        {
            ui_label(ui, true, "Timings (last frame)");
            ui_label(ui, false, "Window %ms", client.window.frame_time * 1000.0);
            ui_label(ui, false, "Update %ms", client.timing_update);
            ui_label(ui, false, "Draw   %ms", client.timing_draw);
            ui_label(ui, false, "Total (no sleep) %ms", client.timing_total_no_sleep);
            ui_divider(ui, true);
        }
            
        {
            ui_label(ui, true, "Misc.");
            ui_label(ui, false, "Round Trip Time: %", cast(s64) client.latest_rtt);
            ui_label(ui, false, "Draw Call Count: %", client.graphics.draw_call_count);
            ui_label(ui, false, "World Size: %x%", client.world_size.x, client.world_size.y);
            ui_label(ui, false, "Entities: %", client.all_entities.alive_count);
            ui_label(ui, false, "Particle Systems: %", client.particle_systems.alive_count);
            ui_divider(ui, true);
        }

        {
            allocator_string :: (allocator: *Allocator) -> string {
                size_in_units, units := convert_to_biggest_memory_unit(allocator.stats.working_set);
                return print_into_allocator(*temp, "% %", size_in_units, suffix_string_from_memory_unit(units));
            }

            ui_label(ui, true, "Allocators:");
            ui_label(ui, false, "Heap:   %", allocator_string(Default_Allocator));
            ui_label(ui, false, "Engine: %", allocator_string(*client.engine_allocator));
            ui_label(ui, false, "World:  %", allocator_string(*client.world_allocator));
            ui_label(ui, false, "UI:     %", allocator_string(*client.ui.allocator));
            ui_label(ui, false, "Tick:   %", allocator_string(*client.tick_allocator));
            ui_label(ui, false, "Temp:   %", allocator_string(*temp));
            ui_divider(ui, true);
        }
    
        {
            size_string :: (size_in_bytes: s64) -> string {
                size_in_units, units := convert_to_biggest_memory_unit(size_in_bytes);
                return print_into_allocator(*temp, "% %", size_in_units, suffix_string_from_memory_unit(units));
            }

            ui_label(ui, true, "Asset Data:");

            {
                sound_data_bytes := 0;
                for i := 0; i < client.sounds.Capacity; ++i    sound_data_bytes += client.sounds[i].bytes.count;
                ui_label(ui, false, "Sounds: %", size_string(sound_data_bytes));
            }

            ui_divider(ui, true);
        }

        {
            ui_label(ui, true, "Cheats");
            ui_check_box(ui, "Disable Lightmap", *client.lightmap.disabled);
            ui_check_box(ui, "Free Camera", *client.free_camera_enabled);
        }
    }
        
    ui_pop_window(ui);
    ui_pop_width(ui);
}

register_message_history :: (history: *Message_History, message: Message) {
    copy_memory(*history.entries[1], *history.entries[0], min(history.entries.Capacity - 1, history.active) * size_of(Message_History_Entry));
    history.active = min(history.entries.Capacity, history.active + 1);
    
    entry := *history.entries[0];
    entry.message = message;
    entry.timestamp = os_get_cpu_time();
}

maybe_do_message_history_panel :: (client: *Client) {
    WIDTH: f32 : 720;

    do_history :: (ui: *UI, history: *Message_History, name: string) {
        ui_push_growing_container(ui, .Vertical);
        ui_push_width(ui, .Pixels, WIDTH * 0.5, 0.9);

        ui_label(ui, true, name);
        ui_divider(ui, true);

        now := os_get_cpu_time();

        for i := 0; i < history.active; ++i {
            entry := *history.entries[i]; // Unfortunately, the dynamically allocated data on this message is no longer valid, as it lived on *temp. Therefore, we can't really print the content of this message safely, we can only print the kind of message...
            seconds_passed := os_convert_cpu_time(now - entry.timestamp, .Seconds);
            ui_label(ui, false, "% (%s)", type_info(entry.message.local_type_id).display_name, format_float(xx seconds_passed, 0, 2));
        }

        ui_pop_width(ui);
        ui_pop_container(ui);
    }

    cleanup_history :: (history: *Message_History) { // Delete old entries that no longer seem interesting...
        now := os_get_cpu_time();

        for i := history.active - 1; i >= 0; --i {
            entry := *history.entries[i];
            seconds_passed := os_convert_cpu_time(now - entry.timestamp, .Seconds);
            if seconds_passed >= 9.5 {
                --history.active;
            } else {
                break;
            }
        }
    }

    cleanup_history(*client.incoming_message_history);
    cleanup_history(*client.outgoing_message_history);

    if client.message_history_panel_state == .Closed then return;

    ui := *client.ui;

    ui_push_width(ui, .Pixels, WIDTH, 1);
    client.message_history_panel_state, client.message_history_panel_position = ui_push_window(ui, "Message History", .Draggable | .Collapsable | .Closeable, client.message_history_panel_position);

    if client.message_history_panel_state == .Open {
        ui_set_height(ui, .Sum_Of_Children, 0, 1);
        ui_push_container(ui, .Horizontal);
        do_history(ui, *client.incoming_message_history, "Incoming");
        ui_divider(ui, false);
        do_history(ui, *client.outgoing_message_history, "Outgoing");
        ui_pop_container(ui);        
    }

    ui_pop_window(ui);
    ui_pop_width(ui);
}
}

request_tutorial_panel :: (client: *Client, kind: Tutorial_Panel) {
    if client.game_mode != .Tutorial return;

    already_requested := false;
    
    for i := 0; i < client.requested_tutorial_panels.count; ++i {
        requested_kind := array_get(*client.requested_tutorial_panels, i);
        if requested_kind == kind {
            already_requested = true;
            break;
        }
    }
    
    if already_requested return;
    
    array_add(*client.requested_tutorial_panels, kind);
}

maybe_do_tutorial_panel :: (client: *Client) {
    if client.game_mode != .Tutorial || !client.enable_tutorial_panels || client.server_paused_game || client.current_tutorial_panel >= client.requested_tutorial_panels.count {
        // No more requested panel to show...
        return;    
    }

    ui := *client.ui;
    panel_kind := array_get(*client.requested_tutorial_panels, client.current_tutorial_panel);

    panel_name: string = ---;

    if #complete panel_kind == {
      case .About_Tutorial_Panels;      panel_name = "Tutorial - Introduction";
      case .Goal_Of_The_Game;           panel_name = "Tutorial - Goal of the Game";
      case .Using_The_Crafting_Menu;    panel_name = "Tutorial - Crafting Menu";
      case .Using_Mirrors_To_Kill;      panel_name = "Tutorial - Killing Monsters";
    }

    ui_push_width(ui, .Sum_Of_Children, 10, 1);
    ui_push_window(ui, panel_name, .Default, .{ .5, .5 });
    ui_push_width(ui, .Label_Size, 5, 1);

    if #complete panel_kind == {
      case .About_Tutorial_Panels;
        ui_label(ui, true,  "Welcome to the tutorial.");
        ui_label(ui, false, "We will try to guide you through the game with as little popups as possible.");
        ui_label(ui, false, "Unfortunately, there'a few things we need to tell you.");
        ui_label(ui, true,  "Press % to close these panels.", input_bindings_string(client, .Interact_Primary));

      case .Goal_Of_The_Game;
        ui_label(ui, true,  "The goal of the game is to get a high score.");
        ui_label(ui, false, "You increase the score by placing the flag further to the right.");
        ui_label(ui, false, "Unlock the next section of the world by activating the next emitter.");
        ui_label(ui, false, "An emitter is activated by interacting on it with the flag while it is powered.");
    
      case .Using_The_Crafting_Menu;
        ui_label(ui, true,  "Press % to open the crafting menu.", input_bindings_string(client, .Hud_Toggle));
        ui_label(ui, false, "There you can convert items that you are carrying into useful creations.");
        ui_label(ui, false, "Different options will appear depending on your surroundings.");
        ui_label(ui, false, "May we suggest you try crafting a mirror?");

      case .Using_Mirrors_To_Kill;
        ui_label(ui, true,  "You can use the light beam to kill monsters.");
        ui_label(ui, false, "Try reflecting the beam onto a monster using mirrors.");
        ui_label(ui, false, "Different monsters have different properties and must be approached differently.");
    }

    if input_action_fired_globally(client, .Interact_Primary, .Pressed) {
        if panel_kind == .About_Tutorial_Panels then request_tutorial_panel(client, .Goal_Of_The_Game);

        ++client.current_tutorial_panel;        
    }

    ui_pop_width(ui);    
    ui_pop_window(ui);
    ui_pop_width(ui);
}

do_game_tick :: (client: *Client) {
    read_incoming_packets(client);
    handle_server_timeout(client, .Game_Over, "");
    
    //
    // Update all local entities based on the information received by the server.
    // This also does some basic client-side prediction
    //
    if !client.server_paused_game {
        reset_allocator(*client.tick_allocator);
        
        for i := 0; i < client.emitters.slot_count; ++i {
            emitter, occupied := index_bucket_array(*client.emitters, i);
            if occupied && emitter.state != .Off then update_powered_emitter(client, emitter);
        }
        
        for i := 0; i < client.emitters.slot_count; ++i {
            emitter, occupied := index_bucket_array(*client.emitters, i);
            if occupied && emitter.state == .Off then update_off_emitter(client, emitter);
        }

        for i := 0; i < client.slabs.slot_count; ++i {
            slab, occupied := index_bucket_array(*client.slabs, i);
            if occupied then update_slab(client, slab);
        }

        for i := 0; i < client.guys.slot_count; ++i {
            guy, occupied := index_bucket_array(*client.guys, i);
            if occupied {
                update_guy(client, guy);
                if guy.state == .Carrying && guy.carrying_item == .Torch then fill_lightmap_tile(*client.lightmap, guy.physical_position, TORCH_BRIGHTNESS);
            }
        }
        
        for i := 0; i < client.frogs.slot_count; ++i {
            frog, occupied := index_bucket_array(*client.frogs, i);
            if occupied {
                update_frog(client, frog);
                if frog.state == .Attacking then fill_lightmap_with_beam(*client.lightmap, *frog.beam_data, 1);
            }
        }

        for i := 0; i < client.slimes.slot_count; ++i {
            slime, occupied := index_bucket_array(*client.slimes, i);
            if occupied then update_slime(client, slime);
        }

        for i := 0; i < client.goblins.slot_count; ++i {
            goblin, occupied := index_bucket_array(*client.goblins, i);
            if occupied then update_goblin(client, goblin);
        }

        for i := 0; i < client.torches.slot_count; ++i {
            torch, occupied := index_bucket_array(*client.torches, i);
            if occupied {
                update_torch(client, torch);
                fill_lightmap_tile(*client.lightmap, torch.physical_position, TORCH_BRIGHTNESS);
            }
        }
        
        for i := 0; i < client.all_entities.slot_count; ++i {
            entity, occupied := index_bucket_array(*client.all_entities, i);
            if occupied {
                interpolate_visuals_and_play_sounds(client, entity);

                if entity.entity_kind == .Torch {
                } else if entity.entity_kind == .Lava {
                    fill_lightmap_tile(*client.lightmap, entity.physical_position, LAVA_BRIGHTNESS);
                }
            }
        }

        for i := 0; i < client.particle_systems.slot_count; ++i {
            system, occupied := index_bucket_array(*client.particle_systems, i);
            if occupied then update_particle_system(system, client.tick_time);
        }

        update_lightmap(*client.lightmap, client.tick_time);
        play_random_sounds(client);

        client.game_epoch_time += client.tick_time;
    }

    //    
    // Developer UI
    //
#if DEVELOPER { 
    if input_action_fired_globally(client, .Developer_Panel_Toggle, .Pressed) {
        client.developer_panel_state = ifx client.developer_panel_state == .Closed then .Open else .Closed;
    }

    maybe_do_developer_panel(client);

    if input_action_fired_globally(client, .Message_History_Panel_Toggle, .Pressed) {
        client.message_history_panel_state = ifx client.message_history_panel_state == .Closed then .Open else .Closed;
    }

    maybe_do_message_history_panel(client);

    if input_action_fired_globally(client, .Sound_Hud_Toggle, .Pressed) {
        client.sound_hud_enabled = !client.sound_hud_enabled;
        enable_mixer_history(*client.mixer, 128, 2);
    }
}

    //
    // Tutorial UI
    //
    maybe_do_tutorial_panel(client);

    //
    // Forward any input for the guys to the server
    //
    if !(client.pause_menu_open || client.server_paused_game) {
        for i := 0; i < client.local_player_count; ++i {
            local_player := *client.local_players[i];
            
            guy_entity := get_entity(client, local_player.guy_pid);
            guy := down(guy_entity, Guy);

            // Determine if we are in free-camera mode.
            is_in_free_camera := false;
#if DEVELOPER {
    is_in_free_camera = i == 0 && client.free_camera_enabled;
}
            
            if !is_in_free_camera && guy.state != .Dead {
                //
                // Update the hud
                //
                update_hud(client, local_player);
            }

            if is_in_free_camera {
                //
                // Move the free camera
                //
                speed: f32 : 10.0;

                if input_action_fired_globally(client, .Move_West, .Held)  local_player.camera.world_center.x -= speed * client.tick_time;
                if input_action_fired_globally(client, .Move_East, .Held)  local_player.camera.world_center.x += speed * client.tick_time;
                if input_action_fired_globally(client, .Move_North, .Held) local_player.camera.world_center.y -= speed * client.tick_time;
                if input_action_fired_globally(client, .Move_South, .Held) local_player.camera.world_center.y += speed * client.tick_time;
            } else if guy.state == .Dead {
                //
                // If spectating, update the tracked entity
                //
                if input_action_fired_for_local_player(client, local_player, .Move_East, .Pressed) {
                    local_player.entity_tracked_by_camera = find_next_entity_to_spectate(client, local_player.entity_tracked_by_camera, true);
                } else if input_action_fired_for_local_player(client, local_player, .Move_West, .Pressed) {
                    local_player.entity_tracked_by_camera = find_next_entity_to_spectate(client, local_player.entity_tracked_by_camera, false);
                }

                if !entity_exists(client, local_player.entity_tracked_by_camera) {
                    // Fallback in case the tracked entity disappears for some reason
                    local_player.entity_tracked_by_camera = local_player.guy_pid;
                }
            } else {
                //
                // If alive, send some input to the server
                //
                input: Guy_Input_Message = ---;
                input.guy_pid          = local_player.guy_pid;
                input.position         = guy.physical_position;
                input.wants_to_move    = false;
                input.aim_direction    = guy.physical_rotation;
                input.interaction_kind = .Count;
                input.crafting_recipe  = local_player.hud.crafting_recipe_confirmed_this_frame;
                input.cheat            = local_player.hud.cheat_confirmed_this_frame;
                input.chest_item       = local_player.hud.chest_item_confirmed_this_frame;

                if !local_player.hud.was_open_this_frame {
                    if input_action_fired_for_local_player(client, local_player, .Move_North, .Pressed) {
                        if !input_action_fired_for_local_player(client, local_player, .Turn_Modifier, .Held) {
                            input.position.x = guy.physical_position.x;
                            input.position.y = guy.physical_position.y - 1;
                        }
                        input.aim_direction = .North;
                        input.wants_to_move = true;
                    }

                    if input_action_fired_for_local_player(client, local_player, .Move_West, .Pressed) {
                        if !input_action_fired_for_local_player(client, local_player, .Turn_Modifier, .Held) {
                            input.position.x = guy.physical_position.x - 1;
                            input.position.y = guy.physical_position.y;
                        }
                        input.aim_direction = .West;
                        input.wants_to_move = true;
                    }

                    if input_action_fired_for_local_player(client, local_player, .Move_South, .Pressed) {
                        if !input_action_fired_for_local_player(client, local_player, .Turn_Modifier, .Held) {
                            input.position.x = guy.physical_position.x;
                            input.position.y = guy.physical_position.y + 1;
                        }
                        input.aim_direction = .South;
                        input.wants_to_move = true;
                    }

                    if input_action_fired_for_local_player(client, local_player, .Move_East, .Pressed) {
                        if !input_action_fired_for_local_player(client, local_player, .Turn_Modifier, .Held) {
                            input.position.x = guy.physical_position.x + 1;
                            input.position.y = guy.physical_position.y;
                        }
                        input.aim_direction = .East;
                        input.wants_to_move = true;
                    }

                    if input_action_fired_for_local_player(client, local_player, .Look_North, .Pressed) { input.aim_direction = .North; input.wants_to_move = true; }
                    if input_action_fired_for_local_player(client, local_player, .Look_West, .Pressed)  { input.aim_direction = .West;  input.wants_to_move = true; }
                    if input_action_fired_for_local_player(client, local_player, .Look_South, .Pressed) { input.aim_direction = .South; input.wants_to_move = true; }
                    if input_action_fired_for_local_player(client, local_player, .Look_East, .Pressed)  { input.aim_direction = .East;  input.wants_to_move = true; }

                    if input_action_fired_for_local_player(client, local_player, .Interact_Primary, .Pressed)    { input.interaction_kind = .Primary_Start; }
                    if input_action_fired_for_local_player(client, local_player, .Interact_Primary, .Released)   { input.interaction_kind = .Primary_End; }
                    if input_action_fired_for_local_player(client, local_player, .Interact_Secondary, .Pressed)  { input.interaction_kind = .Secondary_Start; }
                    if input_action_fired_for_local_player(client, local_player, .Interact_Secondary, .Released) { input.interaction_kind = .Secondary_End; }
                }

                if (local_player.hud.was_confirmed_this_frame || input.wants_to_move || input.interaction_kind != .Count) {
                    // If nothing interesting happened, we can safe us the network traffic and just
                    // not send anything
                    msg := make_message_from(input);
                    array_add(*client.outgoing_messages, msg);
                }

                local_player.entity_tracked_by_camera = local_player.guy_pid; // If we're alive, we always want to track ourselves
            }
            
            {
                //
                // Update the camera
                //
                target_world_center: v2f = ---;
                interpolation_speed: f32 = ---;

                if is_in_free_camera {
                    target_world_center = local_player.camera.world_center;
                    interpolation_speed = 1; // Be snappy with the free camera
                } else {
                    target_entity := get_entity(client, local_player.entity_tracked_by_camera);
                    target_world_center = .{ xx target_entity.physical_position.x, xx target_entity.physical_position.y };
                    interpolation_speed = min(10 * client.tick_time, 1);
                }
                
                update_camera(client, *local_player.camera, target_world_center, local_player.viewport, interpolation_speed, !is_in_free_camera);
            }
        }
    }

    // Do the pause menu. The escape key can close the hud and open the pause menu, but we want to give
    // input priorization to the hud.
    {
        if input_action_fired_globally(client, .Toggle_Pause_Menu, .Pressed) {
            client.pause_menu_open = !client.pause_menu_open;

            msg := make_message(Game_Pause_Message);
            msg.game_pause.client_pid = client.my_client_pid;
            msg.game_pause.should_pause = client.pause_menu_open;
            array_add(*client.outgoing_messages, msg);
        }

        maybe_do_input_bindings_panel(client);

        if maybe_do_pause_menu_panel(client) {
            client.pause_menu_open = false;
            msg := make_message(Game_Pause_Message);
            msg.game_pause.client_pid = client.my_client_pid;
            msg.game_pause.should_pause = client.pause_menu_open;
            array_add(*client.outgoing_messages, msg);
        }
    }
    
    // Send all outgoing messages
    {
#if DEVELOPER {
        now := os_get_cpu_time();
}

        for i := 0; i < client.outgoing_messages.count; ++i {
            message := array_get_pointer(*client.outgoing_messages, i);
            send_reliable_message(*client.connection, message);

#if DEVELOPER   register_message_history(*client.outgoing_message_history, ~message);
        }

        array_clear(*client.outgoing_messages);
    }

    physically_remove_dead_particle_systems(client);
    physically_remove_dead_entities(client);
}

#if MEMORY_DEBUGGING {
    inside_allocator_callback := false;

    allocator_callback_procedure :: (client: *Client, allocator: *Allocator, operation: Allocator_Operation, pointer: *void, size_in_bytes: s64, old_pointer: *void, old_size_in_bytes: s64) {
        if inside_allocator_callback return;

        inside_allocator_callback = true;
        defer inside_allocator_callback = false;
        
        if allocator == Default_Allocator && operation == .Allocation {
            print_into_buffer(*client.memory_debug_printer, "%, %\n", pointer, size_in_bytes);

            trace := os_get_stack_trace(*temp, 3);
            for i := 0; i < trace.count; ++i {
                frame := *trace[i];
                print_into_buffer(*client.memory_debug_printer, "    - %:% - %\n", frame.source_file, frame.source_line, frame.description);
            }
            
            flush_file_printer(*client.memory_debug_printer);
        }
    }
}
    
main :: (args: []string) -> s32 {
    //
    // Start up the engine
    //
    set_working_directory_to_executable_path();
    os_enable_high_resolution_timer();
    create_temp_allocator(128 * Memory_Unit.Megabytes);

    logprint(.Info, "Starting the client...");
    
    client: Client;
    create_memory_pool(*client.engine_pool, 32 * Memory_Unit.Megabytes, 128 * Memory_Unit.Kilobytes);
    client.engine_allocator = allocator_from_memory_pool(*client.engine_pool);
    create_memory_pool(*client.world_pool, 32 * Memory_Unit.Megabytes, 128 * Memory_Unit.Kilobytes);
    client.world_allocator = allocator_from_memory_pool(*client.world_pool);
    create_memory_arena(*client.tick_arena, 32 * Memory_Unit.Megabytes, 128 * Memory_Unit.Kilobytes, false);
    client.tick_allocator = allocator_from_memory_arena(*client.tick_arena);
    
    client.ui_state.account_name = os_get_user_name(*client.engine_allocator);
    client.ui_state.network_port = 9876;

#if DEVELOPER {
    client.ui_state.network_host = copy_string(*client.engine_allocator, "localhost");
} #else {
    client.ui_state.network_host = copy_string(*client.engine_allocator, "tealfire.de");
}

#if MEMORY_DEBUGGING {
    create_file_printer(*client.memory_debug_printer, *temp, "memory.log");
    //create_stdio_printer(*client.memory_debug_printer, *temp);
    callback: Allocator_Callback = .{ ---, allocator_callback_procedure, *client };
    install_allocator_callback(*callback);
}
    
#if DEVELOPER {
    create_file_watcher(*client.pack_watchdog, *client.engine_allocator);
    add_file_to_watch(*client.pack_watchdog, "data/animation-pack.txt");
    add_file_to_watch(*client.pack_watchdog, "data/sprite-pack.txt");
}

    window_mode: Window_Style_Flags = ifx !DEVELOPER then (.Fullscreen | .Maximized) else .Default;
    window_width: s32 = ifx DEVELOPER then cast(s32) (720 * 1.8) else cast(s32) WINDOW_DONT_CARE;
    window_height: s32 = ifx DEVELOPER then 720 else cast(s32) WINDOW_DONT_CARE;

    create_window(*client.window, "Glassminers", WINDOW_DONT_CARE, WINDOW_DONT_CARE, window_width, window_height, window_mode);

#if OS == .Windows {
    set_window_icon_from_resource_name(*client.window, "IDI_ICON1");
}
    
    create_ui(*client.ui, 1024, draw_ui_callbacks(*client), UI_Dark_Theme, *client.window, *client.ui_font);
    create_mixer(*client.mixer, *client.engine_allocator, 16);
    register_all_input_bindings(*client);

    startup_success := create_draw_data(*client) && create_animation_data(*client) && create_sound_data(*client);
    if !startup_success return -1;
        
    client.remote_players.allocator = *client.engine_allocator;
    client.test_inputs.allocator    = *client.engine_allocator;
    client.requested_tutorial_panels.allocator = *client.engine_allocator;
    client.outgoing_messages.allocator = *temp;
    client.current_state = .Count;
    initiate_state_transition(*client, .Main_Menu, 0);
    maybe_transition_to_next_state(*client);

#if DEVELOPER {
    client.mixer.volumes[.Master] = 0.0;
    client.requested_game_mode = .Developer;
}
    
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
        reload_sprite_atlases_from_disk(*client);
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
            destroy_animation_data(*client);
            create_animation_data(*client);
        } else if filepath == "data/sprite-pack.txt" {
            reload_sprite_atlases_from_disk(*client);
        }
    }
}
        
        //
        // Handle transitions
        //
        client.tick_time = client.window.frame_time;
        maybe_transition_to_next_state(*client);
        maybe_update_ui_scale(*client);
        
        //
        // Do one frame
        //
        {
#if DEVELOPER {
           begin := os_get_cpu_time();
           defer client.timing_update = os_convert_cpu_time(os_get_cpu_time() - begin, .Milliseconds);
}
            
            update_window(*client.window);
            begin_ui_frame(*client.ui, .{ 128, 24 });
            recalculate_local_player_viewports(*client);
            reassign_gamepad_indices(*client);
            reset_input_binding_tracker(*client);

            if input_action_fired_globally(*client, .Toggle_Fullscreen, .Pressed) {
                if client.window.fullscreen {
                    set_window_style(*client.window, .Maximized);
                } else {
                    set_window_style(*client.window, .Fullscreen);                
                }
            }
            
            if #complete client.current_state == {
              case .Main_Menu;  do_main_menu(*client);
              case .Connecting; do_connecting_screen(*client);
              case .Lobby;      do_lobby_screen(*client);
              case .Ingame;     do_game_tick(*client);
              case .Game_Over;  do_game_over_screen(*client);
            }

            update_input_binders(*client);
        }
        
        //
        // Draw one frame
        //
        {
#if DEVELOPER {
           begin := os_get_cpu_time();
           defer client.timing_draw = os_convert_cpu_time(os_get_cpu_time() - begin, .Milliseconds);
}

            ge_clear_screen(*client.graphics, .{ 40, 40, 50, 255 });
            
            if #complete client.current_state == {
              case .Lobby #through;
                y: f32 = xx client.window.h - 34;
                x: f32 = xx client.window.w * 0.8;
                
                now := os_get_cpu_time();

                for i := client.test_inputs.count - 1; i >= 0; --i {
                    input := array_get_pointer(*client.test_inputs, i);
                    if input.local_player_index >= client.local_player_count continue;

                    time := os_convert_cpu_time(now - input.cpu_time, .Seconds);
                    alpha := 1 - smoothstep(time, 1, 2);
                    color := GE_Color.{ 200, 200, 200, cast(u8) (alpha * 255) };

                    text := tprint("%: ", client.local_players[input.local_player_index].name);
                    draw_text_screen_space(*client, *client.ui_font, text, .{ x, y }, .Right | .Median, color, .Default);
                    draw_sprite_screen_space(*client, input.sprite_index, .{ x + 16, y }, .{ 32, 32 }, 0, color, false);
                    
                    y -= 34;
                }

                if !client.test_inputs.count {
                    draw_text_screen_space(*client, *client.ui_font, "Press some buttons...", .{ x + 32, y }, .Right | .Median, GRAY_COLOR, .Default);
                }
                
              case .Main_Menu, .Connecting, .Game_Over;
                draw_text_screen_space(*client, *client.title_font, "GlassMiners", .{ xx client.window.w / 2, xx client.window.h / 4 }, .Center | .Median, WHITE_COLOR, .Default);
                if client.info_text_t >= 0 {
                    draw_text_screen_space(*client, *client.ui_font, client.info_text, .{ xx client.window.w / 2, xx (client.window.h / 4 + client.title_font.line_height) }, .Center | .Median, YELLOW_COLOR, .Default);
                    client.info_text_t -= client.tick_time;
                }
                
              case .Ingame;
                for i := 0; i < client.local_player_count; ++i {
                    draw_world(*client, *client.local_players[i]);
                    draw_hud(*client, *client.local_players[i]);
                }

                draw_viewport_information(*client);
                draw_global_hud(*client);

                if client.pause_menu_open || client.server_paused_game draw_rect_screen_space(*client, .{ 0, 0 }, .{ xx client.window.w, xx client.window.h }, .{ 0, 0, 0, 160 });

                if client.server_paused_game {
                    draw_text_screen_space(*client, *client.title_font, "Game Paused!", .{ xx client.window.w / 2, xx client.window.h * 0.25 }, .Center | .Median, ORANGE_COLOR, .Shadow);
                }

#if DEVELOPER {
                if client.sound_hud_enabled then draw_sound_hud(*client);
}
                
                ge_imm2d_flush(*client.graphics);
            }

            // Fade out a state transition if applicable
            if client.current_state != client.next_state {
                alpha := cast(u8) (clamp(1 - client.state_transition_t / client.state_transition_duration, 0, 1) * 255);

                FADE_COLOR: GE_Color : .{ 0, 0, 0, 255 };
                draw_rect_screen_space(*client, .{ 0, 0 }, .{ xx client.window.w, xx client.window.h }, .{ FADE_COLOR.r, FADE_COLOR.g, FADE_COLOR.b, alpha });
            }

            draw_ui_frame(*client.ui);

            draw_text_screen_space(*client, *client.ui_font, VERSION_STRING, .{ 10, xx client.window.h - 10 }, .Left | .Bottom, GRAY_COLOR, .Default);
            ge_imm2d_flush(*client.graphics);
            
            ge_swap_buffers(*client.graphics);
        }

        //
        // Output gamepad vibration if desired
        //
        if client.current_state == .Ingame {
            for i := 0; i < client.local_player_count; ++i {
                local_player := *client.local_players[i];
                if local_player.input_binder.active_input_device == .Gamepad {
                    entity := get_entity(*client, local_player.guy_pid);
                    guy := down(entity, Guy);
                    
                    digging_vibration: f32 = ifx guy.state == .Digging then 0.2 else 0;
                    desired_vibration := max(entity.health_bar_damage_animation_t, digging_vibration);
                    applied_vibration := ifx !client.server_paused_game && client.vibration_enabled then desired_vibration else 0;

                    health := (entity.health - HEALTH_PER_HEART) / (ENTITY_DEFAULT_HEALTH[entity.entity_kind] - HEALTH_PER_HEART); // We want to show the worst color when you've only got one heart left
                    color: GE_Color = ge_mix_colors(.{ 255, 55, 0, 255 }, .{ 95, 255, 0, 255 }, health);

                    set_gamepad_properties(*client.window, local_player.input_binder.gamepad_index, applied_vibration, applied_vibration, color.r, color.g, color.b);
                }
            }
        }
        
        //
        // Render one audio frame
        //
        {
            update_sound_players(*client);
            update_mixer(*client.mixer);

            client.sounds_played_this_frame = .[ false ];
        }
        
        release_temp_allocator(0);
        
        frame_end := os_get_cpu_time();
        #if DEVELOPER { client.timing_total_no_sleep = os_convert_cpu_time(frame_end - frame_start, .Milliseconds); }
        os_sleep_to_tick_rate(frame_start, frame_end, TARGET_FRAMES_PER_SECOND);
    }
    
    // Shut down all resources that might currently be in use
    initiate_state_transition(*client, .Count, 0);
    maybe_transition_to_next_state(*client);
    
    //
    // Destroy the engine
    //
    destroy_all_sounds(*client);
    destroy_mixer(*client.mixer);
    destroy_ui(*client.ui);
    destroy_draw_data(*client);
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
