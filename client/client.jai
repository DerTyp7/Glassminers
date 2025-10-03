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
#load "game_tick.jai";
#load "input_bindings.jai";
#load "entity.jai";
#load "particles.jai";
#load "sprite_packer.jai";
#load "sounds.jai";
#load "animation.jai";
#load "hud.jai";
#load "draw.jai";

GE_ACTIVE_BACKEND :: GE_Backend.GL_Modern;

DEVELOPER :: #run compiler_is_user_option_present("Developer");
MEMORY_DEBUGGING :: false;
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
    requested_game_forfeit := false;

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
      case .Request_Game_Start, .Request_Game_Forfeit, .Guy_Input; // Ignore
    
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
            snap_camera_to_guy(client, local_player);
        }

      case .Game_Pause;
        client.server_paused_game = msg.game_pause.should_pause;
        toggle_all_game_sounds(client, client.server_paused_game);
        
      case .Game_Start;
        start_the_game(client, msg.game_start);

      case .Game_Over;
        client.pause_menu_open = false;
        client.game_score = msg.game_over.score;
        client.previous_game_summary.result = msg.game_over.result;
        client.previous_game_summary.score  = msg.game_over.score;

        if msg.game_over.player_stat_kind != .Count {
            player_name := find_player_name_from_guy_pid(client, msg.game_over.player_stat_guy_pid);
            client.previous_game_summary.player_stat_message = format_player_stat(*client.engine_allocator, player_name, msg.game_over.player_stat_kind, msg.game_over.player_stat);
        }
        
        if msg.game_over.global_stat_kind != .Count {
            client.previous_game_summary.global_stat_message = format_global_stat(*client.engine_allocator, msg.game_over.global_stat_kind, msg.game_over.global_stat);
        }

        initiate_state_transition(client, .Game_Over, 5);

        if msg.game_over.result != .Completed_Tutorial then play_sound(client, .Hud_Failure_0, .Default);

      case .Game_Score;
        client.game_score = msg.game_score.score;

      case .Player_Stat;
        name := find_player_name_from_guy_pid(client, msg.player_stat.guy_pid);
        add_player_stat_message(client, name, msg.player_stat.kind, msg.player_stat.stat);
        play_sound(client, .Hud_Success_0, .Default);

      case .Global_Stat;
        add_global_stat_message(client, msg.global_stat.kind, msg.global_stat.stat);
        play_sound(client, .Hud_Success_0, .Default);

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
          case .Trader; play_sound_on_entity(client, .Trader_Death_0, entity, .Once_Per_Frame);
        }

        maybe_remove_blocker(*client.lightmap, entity);
        
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
          case .Void_Eye;
            play_animation_from_group(client, entity, .Void_Eye);
          case .Trader;
            maybe_play_animation_from_group_instead(client, entity, .Is_Idle, .Trader_Idle);
        }
        
      case .Entity_Health;
        entity := get_entity(client, msg.entity_health.entity_pid);

        dropped_heart := floor(msg.entity_health.new_health / HEALTH_PER_HEART) < floor(entity.health / HEALTH_PER_HEART);
        gained_heart  := floor(msg.entity_health.new_health / HEALTH_PER_HEART) > floor(entity.health / HEALTH_PER_HEART);

        if msg.entity_health.new_health < entity.health {
            // Play a damaged sound
            if dropped_heart && msg.entity_health.new_health > 0 {
                sound_index: Sound_Index = .Count;
                if entity.entity_kind == {
                  case .Guy;    sound_index = .Guy_Damaged_0;
                  case .Frog;   sound_index = .Frog_Damaged_0;
                  case .Goblin; sound_index = .Goblin_Damaged_0;
                  case .Slime;  sound_index = .Slime_Damaged_0;
                  case .Trader; sound_index = .Trader_Damaged_0;
                }
        
                if sound_index != .Count {
                    play_sound_on_entity(client, sound_index, entity, .Once_Per_Frame);
                    get_sound_length_in_seconds(client, sound_index) * 2;
                }
            }
        
            // Play a damaged animation
            if entity.entity_kind == {
              case .Guy; maybe_play_animation_from_group_instead(client, entity, .Is_Idle | .Is_Walk, .Guy_Damaged);
              case .Goblin; maybe_play_animation_from_group_instead(client, entity, .Is_Idle, .Goblin_Damaged);
              case .Frog; maybe_play_animation_from_group_instead(client, entity, .Is_Idle, .Frog_Damaged);
              case .Slime; maybe_play_animation_from_group_instead(client, entity, .Is_Idle | .Is_Walk, .Slime_Damaged);
            }

            entity.time_since_last_damage = 0;
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

      case .Torch_State;
        entity := get_entity(client, msg.torch_state.entity_pid);
        torch := down(entity, Torch);
        torch.time_left_in_seconds = msg.torch_state.time_left_in_seconds;

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

      case .Void_Eye_State;
        entity := get_entity(client, msg.void_eye_state.entity_pid);
        eye := down(entity, Void_Eye);
        eye.state = msg.void_eye_state.state;
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
            client.previous_game_summary.result = .Connection_Lost;
            initiate_state_transition(client, .Game_Over, 0);
            
          case Packet_Type.Ping;
            timestamp: CPU_Time = ~(cast(*CPU_Time) *packet.body[0]);
            client.latest_rtt = os_convert_cpu_time(os_get_cpu_time() - timestamp, .Milliseconds);

          case Packet_Type.Message;
            msg: Message = ---;
            while read_message(packet, *msg) {
#if DEVELOPER   register_message_history(client, *client.incoming_message_history, *msg);
                handle_incoming_message(client, *msg);
            }
        }
    }
}

handle_server_timeout :: (client: *Client, next_screen: Game_State, info_text: string) {
    if os_convert_cpu_time(os_get_cpu_time() - client.connection.time_of_last_received_packet, .Seconds) > NETWORK_TIMEOUT {
        client.previous_game_summary.result = .Connection_Lost;
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
    WINDOW_SPACING: f32 : 50;
    
    ui_push_width(ui, .Pixels, WINDOW_WIDTH, 1);

    window_position :: (client: *Client, index: s64) -> UI_Vector2 {
        scaled_window_width := WINDOW_WIDTH * client.ui.pixel_scaling;
        scaled_window_spacing := WINDOW_SPACING * client.ui.pixel_scaling;
        
        screen := UI_Vector2.{ (xx client.window.w / 2 + (xx index - 0.5) * scaled_window_width),
                               (xx client.window.h / 2 - APPROX_WINDOW_HEIGHT * 0.65) };
        screen.x += xx index * scaled_window_spacing;
        return .{ screen.x / (cast(f32) client.window.w - scaled_window_width), screen.y / (cast(f32) client.window.h - APPROX_WINDOW_HEIGHT) };
    }

    if client.server_data.state != .Closed && client.info_text_t <= 0 { // Don't override other error conditions...
        set_temp_info_text(client, "Your local server is still running...");
    }
    
    // Host Window
    {
        ui_push_window(ui, "Host", .Default, window_position(client, -1));
        ui_label(ui, false, "Name");
        ui_text_input_with_string_pointer(ui, "Enter your name", *client.config.account_name, true, *client.engine_allocator);
        ui_divider(ui, true);
        ui_label(ui, false, "Port");
        ui_text_input_with_int_pointer(ui, "Enter the port", *client.config.network_port, true);
        ui_divider(ui, true);
        
        if client.server_data.state == .Closed && ui_button(ui, "Host!") {
            if client.config.account_name && host_server(client, client.config.network_port) {
                join_server(client, client.config.account_name, "localhost", client.config.network_port);
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
            join_server(client, client.config.account_name, "localhost", DEFAULT_PORT);
            client.immediately_start_game = true;
        }
        
        ui_pop_window(ui);
    }
    
    // Join Window
    {
        ui_push_window(ui, "Join", .Default, window_position(client, +1));
        ui_label(ui, false, "Name");
        ui_text_input_with_string_pointer(ui, "Enter your name", *client.config.account_name, true, *client.engine_allocator);
        ui_divider(ui, true);
        ui_label(ui, false, "Host");
        ui_text_input_with_string_pointer(ui, "Enter the address", *client.config.network_host, true, *client.engine_allocator);
        ui_label(ui, false, "Port");
        ui_text_input_with_int_pointer(ui, "Enter the port", *client.config.network_port, true);
        ui_divider(ui, true);
        
        if client.server_data.state == .Closed && ui_button(ui, "Join!") {
            if client.config.account_name && client.config.network_host {
                join_server(client, client.config.account_name, client.config.network_host, client.config.network_port);
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

maybe_add_local_player :: (client: *Client, local_player_name: string) {
    if client.local_player_count >= MAX_LOCAL_PLAYERS || local_player_name.count == 0 return;

    client.local_players[client.local_player_count].name = copy_string(*client.engine_allocator, local_player_name);
    client.local_players[client.local_player_count].input_binder.allowed_input_devices = .Gamepad;
    ++client.local_player_count;

    if client.local_players[0].input_binder.allowed_input_devices == .ALL then client.local_players[0].input_binder.allowed_input_devices = .Keyboard;

    send_player_information_message(client, client.local_player_count - 1);
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

        local_player_name_data: UI_Text_Input_Data;

        {
            ui_label(ui, true, "Local Players");

            if client.local_player_count < MAX_LOCAL_PLAYERS {
                ui_push_container(ui, .Horizontal);
                ui_push_width(ui, .Percentage_Of_Parent, 0.5, 0.5);

                local_player_name_data = ui_text_input(ui, "Name", .Everything);

                if ui_button(ui, "Add!") || local_player_name_data.confirmed {
                    maybe_add_local_player(client, local_player_name_data._string);
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
            if local_player_name_data.valid maybe_add_local_player(client, local_player_name_data._string); // Add a new local player when somebody typed in the name but forgot to press "Add!"
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
    display_game_stats :: () #macro {
        summary := client.previous_game_summary;

        if summary.player_stat_message.count {
            ui_divider(ui, true);
            ui_multiline_wrapped_label(ui, true, summary.player_stat_message, "", cast(s64) WIDTH, true);
        }

        if summary.global_stat_message.count {
            ui_divider(ui, true);
            ui_multiline_wrapped_label(ui, true, summary.global_stat_message, "", cast(s64) WIDTH, true);
        }
    }

    WIDTH: f32 : 350;

    ui :: *client.ui;
    ui_push_width(ui, .Pixels, WIDTH, 1);
    ui_push_window(ui, "Game Over!", .Default, .{ .5, .5 });
    
    score_text := tprint("Final Score: %", client.game_score);
    
    if #complete client.previous_game_summary.result == {
      case .Unfinished_Game; // Should never happen, this value is just used on the server side
          
      case .Completed_Tutorial;
        ui_label(ui, true, "You completed the tutorial!");

      case .All_Players_Died; 
        ui_label(ui, true, "All players have died!");
        ui_label(ui, true, score_text);
        display_game_stats();

      case .All_Players_Forfeited;
        ui_label(ui, true, "All players have forfeited!");
        ui_label(ui, true, score_text);
        display_game_stats();

      case .Flag_Was_Destroyed;
        ui_label(ui, true, "The flag was destroyed!");
        ui_label(ui, true, score_text);
        display_game_stats();

      case .Connection_Lost;
        ui_label(ui, true, "Connection died!");
    }
    
    ui_divider(ui, true);
    if ui_button(ui, "Back to Main Menu!") then initiate_state_transition(client, .Main_Menu, 0);

    ui_pop_window(ui);
    ui_pop_width(ui);
}

main :: (args: []string) -> s32 {
    //
    // Start up the engine
    //
    set_working_directory(cut_file_name_from_path(args[0]));
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

    create_config(*client.config, *client.engine_allocator);

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

        maybe_reload_config(*client.config);
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
}
            
            update_window(*client.window);
            begin_ui_frame(*client.ui, .{ 128, 24 });
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
                    draw_text_screen_space(*client, *client.ui_font, text, .{ x, y }, .Right | .Median, color, .Default);
                    draw_sprite_screen_space(*client, input.sprite_index, .{ x + 16, y }, .{ 32, 32 }, 0, color, false);
                    
                    y -= 34;
                }

                if !client.test_inputs.count {
                    text := tprint("Try pressing %...", input_bindings_string(*client, .Interact_Primary));
                    draw_text_screen_space(*client, *client.ui_font, text, .{ x + 32, y }, .Right | .Median, GRAY_COLOR, .Default);

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
                    draw_player_hud(*client, *client.local_players[i]);
                }

                draw_viewport_information(*client);
                draw_stat_hud(*client);
                draw_global_hud(*client);

                if client.pause_menu_open || client.server_paused_game draw_rect_screen_space(*client, .{ 0, 0 }, .{ xx client.window.w, xx client.window.h }, .{ 0, 0, 0, 160 });

                if client.server_paused_game {
                    draw_text_screen_space(*client, *client.title_font, "Game Paused!", .{ xx client.window.w / 2, xx client.window.h * 0.25 }, .Center | .Median, ORANGE_COLOR, .Shadow);
                }

                #if DEVELOPER {
                    if client.shadow_hud_enabled {
                        for i := 0; i < client.local_player_count; ++i {
                            draw_shadow_hud(*client, *client.local_players[i]);
                        }
                    }

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

            draw_text_screen_space(*client, *client.ui_font, VERSION_STRING, .{ 10, xx client.window.h - 10 }, .Left | .Bottom, GRAY_COLOR, .Default);

            #if DEVELOPER {
                ff :: (time: f32) -> Print_Format { return format_float(xx time, 0, 2); }

                timings := tprint("Update: % | Draw: % | Frame: %", ff(client.total_update_time), ff(client.total_draw_time), ff(client.window.frame_time * 1000));
                draw_text_screen_space(*client, *client.ui_font, timings, .{ xx client.window.w - 10, xx 10 }, .Right | .Top, GRAY_COLOR, .Default);
                
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
                if local_player.input_binder.active_input_device == .Gamepad {
                    entity := get_entity(*client, local_player.guy_pid);
                    guy := down(entity, Guy);
                    
                    digging_vibration: f32 = ifx guy.state == .Digging then 0.2 else 0;
                    damage_vibration:  f32 = clamp(1 - guy.time_since_last_damage * 2, 0, 1); // When taking damage once, vibrate of 0.5 seconds
                    
                    applied_vibration := ifx !client.server_paused_game && client.vibration_enabled then max(damage_vibration, digging_vibration) else 0;

                    health := (entity.health - HEALTH_PER_HEART) / (DEFAULT_ENTITY_HEALTH[entity.entity_kind] - HEALTH_PER_HEART); // We want to show the worst color when you've only got one heart left
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
        #if DEVELOPER { 
            client.total_frame_time_without_sleep = os_convert_cpu_time(frame_end - frame_start, .Milliseconds);
        }
        os_sleep_to_tick_rate(frame_start, frame_end, TARGET_FRAMES_PER_SECOND);
    }
    
    // Shut down all resources that might currently be in use
    initiate_state_transition(*client, .Count, 0);
    save_config(*client.config);
    maybe_transition_to_next_state(*client);

    //
    // Destroy the engine
    //
    destroy_config(*client.config);
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
