// Jai modules
#load "compiler.jai";
#load "basic.jai";
#load "virtual_connection.jai";
#load "threads.jai";
#load "random.jai";
#load "hash_table.jai";

// Shared
#load "../shared/messages.jai";
#load "../shared/shared.jai";
#load "../shared/bucket_array.jai";
#load "../shared/lightmap.jai";
#load "../shared/VERSION_STRING.jai";

// Server
#load "world_generator.jai";
#load "game_tick.jai";
#load "entity.jai";
#load "pathfinder.jai";
#load "stats.jai";

TICK_RATE: f32 : 60;
DEVELOPER   :: #run compiler_is_user_option_present("Developer");
BAKE_ASSETS :: !DEVELOPER;

Local_Player :: struct {
    guy_pid: Pid = INVALID_PID;
    name := "";
    stats: [Player_Stat_Kind.Count]Statistic;
}

Remote_Client :: struct {
    connection: Virtual_Connection;
    client_pid: Pid = INVALID_PID;
    currently_requesting_pause := false;
    local_players: [MAX_LOCAL_PLAYERS]Local_Player;
    local_player_count: s64;
}

Game_State :: enum {
    Lobby;
    Ingame;
    Game_Over;
}

Server :: struct {
    //
    // Engine structure
    //
    engine_pool: Memory_Pool;
    engine_allocator: Allocator;
    current_state: Game_State;
    next_state: Game_State;
    world_random: Random_Generator; // To ensure the world generation is completely deterministic for a game seed, we need to ensure only the world generation is using this random generator...
    entity_random: Random_Generator;

    //
    // Networking
    //
    connection: Virtual_Connection;
    clients: [..]Remote_Client;
    outgoing_messages: [..]Message;
    client_pid_counter: Pid;

    //
    // Game Data
    //
    game_mode: Game_Mode = .Tutorial;
    world_pool: Memory_Pool;
    world_allocator: Allocator;
    game_seed: s64;
    game_score: u64;
    game_paused := false;
    tick_time: f32;
    world_size: v2i;
    current_section_index: u64; // keeps track of how often the world was expanded & next section generation
    global_stats: [Global_Stat_Kind.Count]Statistic;
    flag_pid: Pid;
    latest_emitter: Pid = INVALID_PID;
    lightmap: Lightmap;
    void_eyes_spawn_accumulator: f32 = 0;
    void_eyes_spawn_cooldown:    f32 = 0; // After unlocking a new section, the lightmap needs a bit of time to propagate the initial beam. Otherwise, we'll be spawning new void eyes in places were they'll be killed immediately after again
    #using em: Entity_Manager;
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
    print_into_buffer(*buffer, "[SERVER][%] ", enum_names(Log_Level)[level]);
    print_into_buffer(*buffer, format, ..args);
    print_into_buffer(*buffer, "\n");
    flush_print_buffer(*buffer);
}

find_local_player_by_guy_pid :: (server: *Server, guy_pid: Pid) -> *Local_Player {
    for i := 0; i < server.clients.count; ++i {
        client := array_get_pointer(*server.clients, i);
        for j := 0; j < client.local_player_count; ++j {
            if client.local_players[j].guy_pid == guy_pid then return *client.local_players[j];
        }
    }

    return null;
}

find_client_by_pid :: (server: *Server, pid: Pid) -> *Remote_Client {
    for i := 0; i < server.clients.count; ++i {
        client := array_get_pointer(*server.clients, i);
        if client.client_pid == pid return client;
    }
    
    return null;
}

handle_client_disconnect :: (server: *Server, client: *Remote_Client) {
    logprint(.Debug, "Disconnected from client '%'.", client.client_pid);

    if server.current_state == .Ingame {
        for i := 0; i < client.local_player_count; ++i {
            entity := get_entity(server, client.local_players[i].guy_pid);
            
            // Drop items carried by player
            guy := down(entity, Guy);
            if guy.carrying_item != .Count {
                try_to_place_item(server, guy.physical_position, guy.carrying_item, guy, null);
            }
            
            remove_entity(server, entity);
        }
    }
        
    msg := make_message(Client_Disconnect_Message);
    msg.client_disconnect.client_pid = client.client_pid;
    array_add(*server.outgoing_messages, msg);
    
    for i := 0; i < client.local_player_count; ++i {
        if client.local_players[i].name deallocate_string(*server.engine_allocator, *client.local_players[i].name);
    }
    
    array_remove_value_pointer(*server.clients, client);
}

send_all_outgoing_messages :: (server: *Server) {
    for j := 0; j < server.clients.count; ++j {
        client := array_get_pointer(*server.clients, j);
        send_reliable_messages(*client.connection, *server.outgoing_messages);
    }
    
    array_clear_without_deallocation(*server.outgoing_messages);    
}

handle_incoming_message :: (server: *Server, msg: *Message) {
    if #complete msg.msg_type == {
      case .Client_Disconnect, .Game_Start, .Game_Over, .Game_Score, .Player_Stat, .Global_Stat, .World_Resize, .Create_Entity, .Destroy_Entity, .Move_Entity, .Entity_Health, .Guy_State, .Emitter_State, .Item_Stack_State, .Frog_State, .Goblin_State, .Slime_State, .Void_Eye_State; // Ignore

      case .Player_Information;
        // Respond to this specific player by sending all other already-connected clients
        local_client := find_client_by_pid(server, msg.player_information.client_pid);
        for i := 0; i < server.clients.count; ++i {
            other_client := array_get_pointer(*server.clients, i);

            for j := 0; j < other_client.local_player_count; ++j {
                other_player := *other_client.local_players[j];
                
                target_msg := make_message(Player_Information_Message);
                target_msg.player_information.local_player_index = j;
                target_msg.player_information.client_pid = other_client.client_pid;
                target_msg.player_information.name       = other_player.name;
                target_msg.player_information.guy_pid    = other_player.guy_pid;
                send_reliable_message(*local_client.connection, *target_msg);
            }
        }
        
        // Store the information locally
        local_client.local_player_count = max(local_client.local_player_count, msg.player_information.local_player_index + 1);
        local_player := *local_client.local_players[msg.player_information.local_player_index];
        if local_player.name deallocate_string(*server.engine_allocator, *local_player.name);
        local_player.name = copy_string(*server.engine_allocator, msg.player_information.name);
        
        logprint(.Debug, "Client '%' set their '%'th name to '%'.", local_client.client_pid, msg.player_information.local_player_index, local_player.name);
        
        // Broadcast the message along
        broadcasted_msg := make_message(Player_Information_Message);
        broadcasted_msg.player_information.local_player_index = msg.player_information.local_player_index;
        broadcasted_msg.player_information.client_pid = local_client.client_pid;
        broadcasted_msg.player_information.guy_pid    = local_player.guy_pid;
        broadcasted_msg.player_information.name       = local_player.name;
        array_add(*server.outgoing_messages, broadcasted_msg);

      case .Remove_Local_Player;
        local_client := find_client_by_pid(server, msg.remove_local_player.client_pid);
        if msg.remove_local_player.local_player_index + 1 < local_client.local_player_count {
            copy_memory(*local_client.local_players[msg.remove_local_player.local_player_index], *local_client.local_players[msg.remove_local_player.local_player_index + 1], (local_client.local_player_count - msg.remove_local_player.local_player_index - 1) * size_of(Local_Player));
        }
        --local_client.local_player_count;

        // Broadcast the message along
        broadcasted_msg := make_message(Remove_Local_Player_Message);
        broadcasted_msg.remove_local_player.local_player_index = msg.remove_local_player.local_player_index;
        broadcasted_msg.remove_local_player.client_pid = local_client.client_pid;
        array_add(*server.outgoing_messages, broadcasted_msg);
        
      case .Request_Game_Start;
        server.game_mode = msg.request_game_start.game_mode;
        server.next_state = .Ingame;

      case .Game_Pause;
        target := find_client_by_pid(server, msg.game_pause.client_pid);
        target.currently_requesting_pause = msg.game_pause.should_pause;

        paused_before := server.game_paused;
        server.game_paused = false;

        for i := 0; i < server.clients.count; ++i {
            if array_get_pointer(*server.clients, i).currently_requesting_pause {
                server.game_paused = true;
            }
        }

        if paused_before != server.game_paused {
            msg := make_message(Game_Pause_Message);
            msg.game_pause.client_pid = INVALID_PID;
            msg.game_pause.should_pause = server.game_paused;
            array_add(*server.outgoing_messages, msg);
        }
        
      case .Guy_Input;
        entity := get_entity(server, msg.guy_input.guy_pid);
        guy := down(entity, Guy);

        // We want to ensure a deterministic order in which entities are updated on the server.
        // Guys are just normal entities that are updated at a specific time during the tick,
        // so just remember the player input for later.
        if guy.received_inputs_count < guy.received_inputs.Capacity {
            guy.received_inputs[guy.received_inputs_count] = msg.guy_input;
            guy.received_inputs_count += 1;
        } else {
            logprint(.Warning, "Too many inputs for guy this tick, dropping input!");
        }

      case .Chest_State;
        entity := get_entity(server, msg.chest_state.entity_pid);
        chest := down(entity, Chest);
        update_visual_chest_state(server, chest, msg.chest_state.visually_open);
    }
}    

read_incoming_packets :: (server: *Server) {
    if server.current_state == .Lobby {
        client_connection, valid_connection := accept_tcp_remote_client_connection(*server.connection);

        while valid_connection {
            client := array_push(*server.clients);
            client.connection   = client_connection;
            client.client_pid   = server.client_pid_counter;
            client.local_player_count = 0;
            client.connection.info.client_id = client.client_pid;
            ++server.client_pid_counter;
            
            logprint(.Debug, "Connected to client '%'.", client.client_pid);

            client_connection, valid_connection = accept_tcp_remote_client_connection(*server.connection);
        }
    }
    
    for i := 0; i < server.clients.count; ++i {
        client := array_get_pointer(*server.clients, i);

        while read_packet(*client.connection) {
            packet :: *client.connection.incoming_packet;
            
            if packet.header.packet_type == {
              case Packet_Type.Connection_Request;
                send_connection_established_packet(*client.connection, 1, VERSION_STRING);
                
              case Packet_Type.Connection_Closed;
                client := find_client_by_pid(server, packet.header.sender_client_id);
                if client then handle_client_disconnect(server, client);
                
              case Packet_Type.Ping;
                client := find_client_by_pid(server, packet.header.sender_client_id);
                if client {
                    update_virtual_connection_information_for_packet(*client.connection, *packet.header);
                    send_ping_packet(*client.connection, .{ packet.body_size, packet.body });
                }
                
              case Packet_Type.Message;
                client := find_client_by_pid(server, packet.header.sender_client_id);
                if client {
                    update_virtual_connection_information_for_packet(*client.connection, *packet.header);
                    
                    msg: Message = ---;
                    while read_message(packet, *msg) {
                        handle_incoming_message(server, *msg);
                    }
                }
            }
        }    
    }
}
    
handle_client_timeouts :: (server: *Server) {
    now := os_get_cpu_time();

    for i := 0; i < server.clients.count; {
        client := array_get_pointer(*server.clients, i);

        if os_convert_cpu_time(now - client.connection.time_of_last_received_packet, .Seconds) > NETWORK_TIMEOUT {
            handle_client_disconnect(server, client);
        } else {
            ++i;
        }
    }
}

switch_to_next_state :: (server: *Server) {
    // logprint(.Debug, "Switching from '%' to '%'...", server.current_state, server.next_state);

    if #complete server.current_state == {
      case .Lobby, .Game_Over; // Ignore
      case .Ingame;
        destroy_entity_manager(server);
        destroy_lightmap(*server.lightmap);
        reset_allocator(*server.world_allocator);
    }
    
    server.current_state = server.next_state;
    
    if #complete server.current_state == {
      case .Lobby, .Game_Over; // Ignore
        
      case .Ingame;
        create_the_game(server);
    }
}

create_the_game :: (server: *Server) {
    reset_allocator(*server.world_allocator);
    create_entity_manager(server);
    reset_all_statistics(server);

    server.current_section_index    = 0;
    server.void_eyes_spawn_cooldown = 5;    
    server.flag_pid   = INVALID_PID;
    server.world_size = get_initial_world_size(server);
    server.game_seed  = os_get_cpu_time();
    seed_random_generator(*server.world_random, server.game_seed, server.game_seed, server.game_seed, server.game_seed);
    seed_random_generator(*server.entity_random, server.game_seed, server.game_seed, server.game_seed, server.game_seed);

    create_lightmap(*server.lightmap, *server.world_allocator, server.world_size);
    
    //
    // Notify the clients about the game seed
    //
    game_start := make_message(Game_Start_Message);
    game_start.game_start.seed = server.game_seed;
    game_start.game_start.size = server.world_size;
    game_start.game_start.game_mode = server.game_mode;
    array_add(*server.outgoing_messages, game_start);

    //
    // Generate one entity for each player and attach it to the player
    //
    total_index := 0;
    for i := 0; i < server.clients.count; ++i {
        client := array_get_pointer(*server.clients, i);

        for j := 0; j < client.local_player_count; ++j {
            player := *client.local_players[j];

            entity := create_entity(server, .Guy, .{ 2 + total_index, 2 }, .North);
            player.guy_pid = entity.pid;
            
            msg := make_message(Player_Information_Message);
            msg.player_information.local_player_index = j;
            msg.player_information.client_pid = client.client_pid;
            msg.player_information.guy_pid    = player.guy_pid;
            msg.player_information.name       = player.name;
            array_add(*server.outgoing_messages, msg);

            ++total_index;
        }
    }

    //
    // Generate the first section
    //
    generate_initial_world_section(server);
}

do_lobby_tick :: (server: *Server) {
    read_incoming_packets(server);
    handle_client_timeouts(server);
    send_all_outgoing_messages(server);
}

server_entry_point :: (data: *Shared_Server_Data) -> u32 #export {
    //
    // Start up the server
    //
    data.state = .Starting;

    set_working_directory_to_executable_path();
    os_enable_high_resolution_timer();
    create_temp_allocator(128 * Memory_Unit.Megabytes);

    logprint(.Info, "Starting the server...");

    server: Server;
    create_memory_pool(*server.engine_pool, 32 * Memory_Unit.Megabytes, 128 * Memory_Unit.Kilobytes);
    server.engine_allocator = allocator_from_memory_pool(*server.engine_pool);
    create_memory_pool(*server.world_pool, 32 * Memory_Unit.Megabytes, 128 * Memory_Unit.Kilobytes);
    server.world_allocator = allocator_from_memory_pool(*server.world_pool);
    server.clients.allocator = *server.engine_allocator;
    server.outgoing_messages.allocator = *temp;
    
    result := create_server_connection(*server.connection, NETWORK_PROTOCOL, data.requested_port);
    if result == .Success {
        atomic_store(*data.state, Server_State.Running);
    } else {
        logprint(.Error, "Failed to open the server connection: '%'. Shutting down!", result);
        atomic_store(*data.startup_error, result);
        atomic_store(*data.state, Server_State.Closing);
    }
    
    server.current_state = .Count;
    server.next_state    = .Count;
    server.client_pid_counter = 1;
    
    server.next_state = .Lobby;
    switch_to_next_state(*server);
    
    while atomic_load(*data.state) == Server_State.Running {
        tick_start := os_get_cpu_time();

        server.tick_time = 1 / TICK_RATE;

        if server.current_state != server.next_state switch_to_next_state(*server);
        
        //
        // Update the current state
        //
        if #complete server.current_state == {
          case .Lobby; do_lobby_tick(*server);
          case .Ingame; do_game_tick(*server);
          case .Game_Over;
            atomic_store(*data.state, Server_State.Closing);
            server.next_state = .Count;
        }

        release_temp_allocator(0);
        
        tick_end := os_get_cpu_time();
        os_sleep_to_tick_rate(tick_start, tick_end, TICK_RATE);
    }
    
    logprint(.Info, "Game over, shutting down...");
    atomic_store(*data.state, Server_State.Closing);
    
    // Give the TCP connection time to ensure the Game_Over message has reached all clients...
    // https://stackoverflow.com/questions/3757289/when-is-tcp-option-so-linger-0-required
    os_sleep(NETWORK_DIE_TIME);

    for i := 0; i < server.clients.count; ++i {
        client := array_get(*server.clients, i);
        destroy_connection(*client.connection);
    }
    array_clear(*server.clients);
    
    destroy_connection(*server.connection);
    destroy_memory_pool(*server.world_pool);
    destroy_memory_pool(*server.engine_pool);
    destroy_temp_allocator();

    logprint(.Info, "Stopped the server.");
    
    atomic_store(*data.state, Server_State.Closed);

    return 0;
}

main :: () -> u32 {
    data: Shared_Server_Data;
    data.requested_port = 9876;
    data.state          = .Starting;
    return server_entry_point(*data);
}
