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
    hwtime: Hardware_Time;
    local_player_index: s64;
    sprite_index: Sprite_Index;
}

UI_State :: struct {
    account_name: string;
    local_player_name: string = ""; // So that we can clear the text input when a player was added
    network_host: string;
    network_port := 9876;
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

    ui_state: UI_State;
    
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
    global_input_binder: Input_Binder;
    
    //
    // Networking
    //
    server_data: Shared_Server_Data;
    server_thread: Thread;
    connection: Virtual_Connection;
    sent_connection_request: bool;
    remote_players: [..]Remote_Player;
    my_client_pid: Pid;
    
    //
    // Lobby Screen
    //
    requested_campaign: Campaign = .Tutorial; // Lobby screen
    immediately_start_game: bool = false; // Lobby screen, after pressing "single player" in the main menu
    test_inputs: [..]Test_Input;
    
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
    world_size: v2i;

    tick_time: f32;
    game_epoch_time: f32;

    local_players: [MAX_LOCAL_PLAYERS]Local_Player;
    local_player_count := 1;

    #using em: Entity_Manager;
    lightmap: Lightmap;
    global_particle_system: Pid;
    
    //
    // debug/developer UI
    // 
    #if DEVELOPER {
        developer_panel_open: bool;
        free_cam_is_enabled: bool;
        
        timing_update: f32;
        timing_draw: f32;
        timing_total_no_sleep: f32;
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
        client.next_state = .Main_Menu;
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
        client.next_state = .Connecting;
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
    msg.request_game_start.campaign = client.requested_campaign;
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
            update_camera(client, *local_player.camera, guy.physical_position, local_player.viewport, 1);
        }

      case .Game_Pause;
        client.server_paused_game = msg.game_pause.should_pause;
        toggle_all_game_sounds(client, client.server_paused_game);
        
      case .Game_Start;
        client.pause_menu_open = false;
        client.server_paused_game = false;
        client.game_seed  = msg.game_start.seed;
        client.world_size = msg.game_start.size;
        client.next_state = .Ingame;

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
        
        // Reset debug settings
        #if DEVELOPER {
            client.developer_panel_open = false;
            client.free_cam_is_enabled = false;
        }
        
      case .Game_Over;
        if msg.game_over.you_won {
            client.previous_game_result = .We_Won;
        } else {
            client.previous_game_result = .We_Lost;
        }
        client.next_state = .Game_Over;

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
        
      case .Emitter_State;
        entity := get_entity(client, msg.emitter_state.entity_pid);
        emitter := down(entity, Emitter);
        emitter.state = msg.emitter_state.state;
        emitter.current_charge = msg.emitter_state.current_charge;
        
      case .Item_Stack_State;
        entity := get_entity(client, msg.item_stack_state.entity_pid);
        item_stack := down(entity, Item_Stack);
        item_stack.item_kind = msg.item_stack_state.item_kind;
        item_stack.count     = msg.item_stack_state.count;

      case .Chest_State;
        entity := get_entity(client, msg.chest_state.entity_pid);
        chest := down(entity, Chest);
        chest.items      = msg.chest_state.items;
        chest.item_count = msg.chest_state.item_count;
        
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
            client.next_state = .Game_Over;
            
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

        // Stop any active rumbling effect
        for i := 0; i < client.local_player_count; ++i {
            local_player := *client.local_players[i];
            set_window_gamepad_properties(*client.window, local_player.input_binder.gamepad_index, 0, 0, 255, 255, 255);
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

        do_campaign_selector(client);
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
        if ui_button(ui, "Cancel!") {
            client.next_state = .Main_Menu;
        }
        ui_pop_window(ui);
        ui_pop_width(ui);
    }    
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

                ui_text_input_with_string(ui, "Name", *client.ui_state.local_player_name, *client.engine_allocator);

                if ui_button(ui, "Add!") && client.ui_state.local_player_name {
                    client.local_players[client.local_player_count].name = copy_string(*client.engine_allocator, client.ui_state.local_player_name);
                    client.local_players[client.local_player_count].input_binder.allowed_input_devices = .Gamepad;
                    ++client.local_player_count;

                    if client.local_players[0].input_binder.allowed_input_devices == .ALL then client.local_players[0].input_binder.allowed_input_devices = .Keyboard;

                    send_player_information_message(client, client.local_player_count - 1);

                    deallocate_string(*client.engine_allocator, *client.ui_state.local_player_name);
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

    // Handle test inputs. This can help in figuring out which player uses which gamepad in
    // local multiplayer.
    {
        register_test_input :: (client: *Client, local_player_index: s64, sprite_index: Sprite_Index) {
            input := array_push(*client.test_inputs);
            input.hwtime = os_get_hardware_time();
            input.local_player_index = local_player_index;
            input.sprite_index = sprite_index;
        }

        now := os_get_hardware_time();
        for i := 0; i < client.test_inputs.count; {
            input := array_get_pointer(*client.test_inputs, i);
            if os_convert_hardware_time(now - input.hwtime, .Seconds) > 2 {
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

find_next_spectate_pid :: (client: *Client, current_pid: Pid) -> Pid {
    first_pid := INVALID_PID;
    next_pid := INVALID_PID;
    {
        found_current_pid: bool = false;
        for i := 0; i < client.guys.slot_count; ++i {
            guy, occupied := index_bucket_array(*client.guys, i);
            if occupied {
                if first_pid == INVALID_PID { first_pid = guy.pid; }
                if next_pid == INVALID_PID && found_current_pid { next_pid = guy.pid; }
                if !found_current_pid && guy.pid == current_pid { found_current_pid = true; }
            }
        }
    }
    
    result_pid := ifx next_pid != INVALID_PID then next_pid else first_pid;
    return result_pid;
}

find_previous_spectate_pid :: (client: *Client, current_pid: Pid) -> Pid {
    last_pid := INVALID_PID;
    previous_pid := INVALID_PID;
    {
        found_current_pid: bool = false;
        for i := 0; i < client.guys.slot_count; ++i {
            guy, occupied := index_bucket_array(*client.guys, i);
            if occupied {
                if !found_current_pid && guy.pid == current_pid { found_current_pid = true; }
                if !found_current_pid { previous_pid = guy.pid; }
                last_pid = guy.pid;
            }
        }
    }
    
    result_pid := ifx previous_pid != INVALID_PID then previous_pid else last_pid;
    return result_pid;
}

#if DEVELOPER {
do_debug_panel :: (client: *Client) {
    ui :: *client.ui;

    window_flags : UI_Window_Flags : .Draggable;
    ui_push_width(ui, .Pixels, 350, 0.8);
    ui_push_window(ui, "Developer Window", window_flags, .{ 0.5, 0.5 });

    ui_label(ui, true, "Timings (last frame)");
    ui_label(ui, false, "Window %ms", client.window.frame_time * 1000.0);
    ui_label(ui, false, "Update %ms", client.timing_update);
    ui_label(ui, false, "Draw   %ms", client.timing_draw);
    ui_label(ui, false, "Total (no sleep) %ms", client.timing_total_no_sleep);
    ui_divider(ui, true);

    ui_label(ui, true, "Misc.");
    {
        ui_label(ui, false, "Draw Call Count: %", client.graphics.draw_call_count);
        ui_label(ui, false, "World Size: %", client.world_size);
        ui_label(ui, false, "Entity Count: %", client.all_entities.alive_count);

        system := get_particle_system(client, client.global_particle_system);
        particle_count := 0;
        for emitter_index := 0; emitter_index < system.emitters.count; ++emitter_index {
            particle_count += system.emitters[emitter_index].particles.count;
        }
        ui_label(ui, false, "Particle Count: %", particle_count);
    }
    ui_divider(ui, true);

    ui_label(ui, true, "Allocators: working_set");
    {
        string_from_bytes :: (size_in_bytes: u64) -> string {
            size_in_units, units := convert_to_biggest_memory_unit(size_in_bytes);
            text := print_into_allocator(*temp, "% %", size_in_units, suffix_string_from_memory_unit(units));
            return text;
        }

        ui_label(ui, false, "Default: %", string_from_bytes(Default_Allocator.stats.working_set));
        ui_label(ui, false, "Engine:  %", string_from_bytes(client.engine_allocator.stats.working_set));
        ui_label(ui, false, "World:   %", string_from_bytes(client.world_allocator.stats.working_set));
        ui_label(ui, false, "Temp:    %", string_from_bytes(temp.stats.working_set));
    }
    ui_divider(ui, true);

    ui_label(ui, true, "Player Positions");
    for local_player_index := 0; local_player_index < client.local_player_count; ++local_player_index {
        entity := get_entity(client, client.local_players[local_player_index].guy_pid);
        ui_label(ui, false, "Local Player %: %", local_player_index, entity.physical_position); // TODO(Felix)
    }
    for remote_player_index := 0; remote_player_index < client.remote_players.count; ++remote_player_index {
        entity := get_entity(client, array_get(*client.remote_players, remote_player_index).guy_pid);
        ui_label(ui, false, "Remote Player %: %", remote_player_index, entity.physical_position); // TODO(Felix)
    }
    ui_divider(ui, true);

    ui_label(ui, true, "Options");
    {
        // Extra temp variable so we don't have to "enable disable light"
        lightmap := !client.lightmap.disabled;
        ui_check_box(ui, "Lightmap", *lightmap);
        client.lightmap.disabled = !lightmap;

        ui_check_box(ui, "Free Cam", *client.free_cam_is_enabled);
    }

    // Debug camera is only for first player
    {
        player := *client.local_players[0];
        guy := get_entity(client, player.guy_pid);

        if client.free_cam_is_enabled {
            speed : f32 : 20.0;
            movement: v2f;

            if input_action_fired_globally(client, .Move_West, .Held) { 
                movement.x -= speed * client.tick_time;
            }
            if input_action_fired_globally(client, .Move_East, .Held) { 
                movement.x += speed * client.tick_time;
            }
            if input_action_fired_globally(client, .Move_North, .Held) { 
                movement.y -= speed * client.tick_time;
            }
            if input_action_fired_globally(client, .Move_South, .Held) { 
                movement.y += speed * client.tick_time;
            }

            player.camera.world_center.x += movement.x;
            player.camera.world_center.y += movement.y;
        }
    }

    ui_pop_window(ui);
    ui_pop_width(ui);
}
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

        client.game_epoch_time += client.tick_time;
    }
   
    outgoing_messages: [..]Message;
    outgoing_messages.allocator = *temp;
    
    
    // Developer UI
#if DEVELOPER { 
    if input_action_fired_globally(client, .Cheat_Debug_Window_Toggle, .Pressed) {
        client.developer_panel_open = ! client.developer_panel_open;
    }
    
    if client.developer_panel_open { 
        do_debug_panel(client);
    }
}


    // Do the pause menu
    {
        if input_action_fired_globally(client, .Toggle_Pause_Menu, .Pressed) {
            client.pause_menu_open = !client.pause_menu_open;

            msg := make_message(Game_Pause_Message);
            msg.game_pause.client_pid = client.my_client_pid;
            msg.game_pause.should_pause = client.pause_menu_open;
            array_add(*outgoing_messages, msg);
        }

        if client.pause_menu_open {
            ui :: *client.ui;
            ui_push_window(ui, "Glassminers", .Default, .{ 0.5, 0.5 });
            ui_push_width(ui, .Pixels, 256, 1);
            ui_push_height(ui, .Pixels, 32, 1);

            ui_label(ui, true, "Seed: %", client.game_seed);
            ui_slider(ui, "Audio", *client.mixer.volumes[.Master], 0, 1);

            ui_divider(ui, true);
            if ui_button(ui, "Continue!") {
                client.pause_menu_open = false;
                msg := make_message(Game_Pause_Message);
                msg.game_pause.client_pid = client.my_client_pid;
                msg.game_pause.should_pause = client.pause_menu_open;
                array_add(*outgoing_messages, msg);
            }
            
            ui_divider(ui, false);
            if ui_button(ui, "Back to Main Menu!") then client.next_state = .Main_Menu;

            ui_pop_height(ui);
            ui_pop_width(ui);
            ui_pop_window(ui);
        }
    }

    for i := 0; i < client.local_player_count; ++i {
        local_player := *client.local_players[i];
        
        guy_entity := get_entity(client, local_player.guy_pid);
        guy := down(guy_entity, Guy);
        is_spectating := guy.state == .Dead;
        
        is_in_freecam: bool = false;
        #if DEVELOPER { is_in_freecam = i == 0 && client.free_cam_is_enabled; }
        

        // Update camera
        if !is_in_freecam {
            is_invalid_pid := local_player.entity_tracked_by_camera == INVALID_PID;
            if !is_spectating || is_invalid_pid { 
                local_player.entity_tracked_by_camera = local_player.guy_pid;
            }

            focus_guy := get_entity(client, local_player.entity_tracked_by_camera);
            update_camera(client, *local_player.camera, focus_guy.physical_position, local_player.viewport, min(10 * client.tick_time, 1));
        }

        update_hud(client, local_player);

        // Input handling outside of hud
        if client.pause_menu_open || client.server_paused_game {
            // Do nothing
        } else if is_spectating {
            if input_action_fired_for_local_player(client, local_player, .Move_East, .Pressed) {
                local_player.entity_tracked_by_camera = find_next_spectate_pid(client, local_player.entity_tracked_by_camera); 
            } else if input_action_fired_for_local_player(client, local_player, .Move_West, .Pressed) {
                local_player.entity_tracked_by_camera = find_previous_spectate_pid(client, local_player.entity_tracked_by_camera); 
            }
            // (Spectate info doesn't need to be sent to the server)
        } else {
            // Input which requires info sent to server
            input: Guy_Input_Message = ---;
            input.guy_pid          = local_player.guy_pid;
            input.position         = guy.physical_position;
            input.wants_to_move    = false;
            input.aim_direction    = guy.physical_rotation;
            input.interaction_kind = .Count;
            input.crafting_recipe  = local_player.hud.crafting_recipe_confirmed_this_frame;
            input.cheat            = local_player.hud.cheat_confirmed_this_frame;
            input.chest_item       = local_player.hud.chest_item_confirmed_this_frame;

            if !local_player.hud.was_open_this_frame && !is_in_freecam {
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
                msg := make_message_from(input);
                array_add(*outgoing_messages, msg);
            }
        }
    }
    
    // Send all outgoing messages
    {
        for i := 0; i < outgoing_messages.count; ++i {
            send_reliable_message(*client.connection, array_get_pointer(*outgoing_messages, i));
        }
    }

    physically_remove_dead_particle_systems(client);
    physically_remove_dead_entities(client);
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
        reload_sprite_atlases_from_disk(*client);
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
        if client.current_state != client.next_state switch_to_next_state(*client);
        client.tick_time = client.window.frame_time;
        
        //
        // Do one frame
        //
        {
#if DEVELOPER {
           begin := os_get_hardware_time();
           defer { 
               end := os_get_hardware_time();
               client.timing_update = os_convert_hardware_time(end - begin, .Milliseconds);
           }
}
            
            update_window(*client.window);
            begin_ui_frame(*client.ui, .{ 128, 24 });
            recalculate_local_player_viewports(*client);
            reassign_gamepad_indices(*client);
            prepare_input_binders(*client);

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
           begin := os_get_hardware_time();
           defer { 
               end := os_get_hardware_time();
               client.timing_draw = os_convert_hardware_time(end - begin, .Milliseconds);
           }
}

            ge_clear_screen(*client.graphics, .{ 40, 40, 50, 255 });
            
            if #complete client.current_state == {
              case .Lobby #through;
                y: f32 = xx client.window.h - 34;
                x: f32 = xx client.window.w * 0.8;
                
                now := os_get_hardware_time();

                for i := client.test_inputs.count - 1; i >= 0; --i {
                    input := array_get_pointer(*client.test_inputs, i);
                    if input.local_player_index >= client.local_player_count continue;

                    time := os_convert_hardware_time(now - input.hwtime, .Seconds);
                    alpha := 1 - smoothstep(time, 1, 2);
                    color := GE_Color.{ 200, 200, 200, cast(u8) (alpha * 255) };

                    text := tprint("%: ", client.local_players[input.local_player_index].name);
                    draw_text_screen_space(*client, *client.ui_font, text, .{ x, y }, .Right | .Median, color);
                    draw_sprite_screen_space(*client, input.sprite_index, .{ x + 16, y }, .{ 32, 32 }, 0, color, false);
                    
                    y -= 34;
                }

                if !client.test_inputs.count {
                    draw_text_screen_space(*client, *client.ui_font, "Press some buttons...", .{ x + 32, y }, .Right | .Median, .{ 200, 200, 200, 255 });
                }
                
              case .Main_Menu, .Connecting, .Game_Over;
                draw_text_screen_space(*client, *client.title_font, "GlassMiners", .{ xx client.window.w / 2, xx client.window.h / 4 }, .Center | .Median, .{ 255, 255, 255, 255 });
                if client.info_text_t >= 0 {
                    draw_text_screen_space(*client, *client.ui_font, client.info_text, .{ xx client.window.w / 2, xx (client.window.h / 4 + client.title_font.line_height) }, .Center | .Median, .{ 252, 238, 28, 255 });
                    client.info_text_t -= client.tick_time;
                }
                
              case .Ingame;
                for i := 0; i < client.local_player_count; ++i {
                    draw_world(*client, *client.local_players[i]);
                    draw_hud(*client, *client.local_players[i]);
                    
                }
                
                #if DEVELOPER {
                    draw_debug_indicators(*client, *client.local_players[0]); 
                }

                draw_viewports(*client);
                
                if client.pause_menu_open || client.server_paused_game draw_rect_screen_space(*client, .{ 0, 0 }, .{ xx client.window.w, xx client.window.h }, .{ 0, 0, 0, 160 });

                if client.server_paused_game {
                    draw_text_screen_space(*client, *client.title_font, "Game Paused!", .{ xx client.window.w / 2 + 2, xx client.window.h * 0.33 + 2 }, .Center | .Median, .{ 100, 100, 100, 255 });
                    draw_text_screen_space(*client, *client.title_font, "Game Paused!", .{ xx client.window.w / 2, xx client.window.h * 0.33 }, .Center | .Median, .{ 255, 166, 0, 255 });
                }
                
                ge_imm2d_flush(*client.graphics);
            }

            draw_ui_frame(*client.ui);

            draw_text_screen_space(*client, *client.ui_font, VERSION_STRING, .{ 10, xx client.window.h - 10 }, .Left | .Bottom, .{ 255, 255, 255, 150 });
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
                    vibration := max(entity.health_bar_damage_animation_t, digging_vibration);

                    health := (entity.health - HEALTH_PER_HEART) / (ENTITY_DEFAULT_HEALTH[entity.entity_kind] - HEALTH_PER_HEART); // We want to show the worst color when you've only got one heart left
                    color: GE_Color = ge_mix_colors(.{ 255, 55, 0, 255 }, .{ 95, 255, 0, 255 }, health);

                    set_window_gamepad_properties(*client.window, local_player.input_binder.gamepad_index, vibration, vibration, color.r, color.g, color.b);
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
        
        frame_end := os_get_hardware_time();
        #if DEVELOPER { client.timing_total_no_sleep = os_convert_hardware_time(frame_end - frame_start, .Milliseconds); }
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
    destroy_memory_arena(*client.tick_arena);
    destroy_memory_pool(*client.world_pool);
    destroy_memory_pool(*client.engine_pool);

    logprint(.Info, "Stopped the client.");

    destroy_temp_allocator();
    return 0;
}
