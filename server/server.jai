// Jai modules
#load "compiler.jai";
#load "basic.jai";
#load "virtual_connection.jai";
#load "threads.jai";
#load "random.jai";
#load "noise.jai";
#load "hash_table.jai";

// Shared
#load "../shared/messages.jai";
#load "../shared/shared.jai";
#load "../shared/bucket_array.jai";
#load "../shared/lightmap.jai";
#load "../shared/VERSION_STRING.jai";

// Server
#load "world_generator.jai";
#load "tick.jai";
#load "entity.jai";
#load "pathfinder.jai";
#load "stats.jai";

TICK_RATE: f32 : 60;
DEVELOPER   :: #run compiler_is_user_option_present("Developer");
BAKE_ASSETS :: !DEVELOPER;

Log_Level :: enum {
    Debug;
    Info;
    Warning;
    Error;
}

Local_Player :: struct {
    guy_pid: Pid = INVALID_PID;
    name := "";
    stats: [Player_Stat_Kind.Count]Statistic;
}

Remote_Client :: struct {
    connection: Virtual_Connection;
    client_pid: Pid = INVALID_PID;
    currently_requesting_pause := false;
    requested_game_forfeit := false;
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
    current_section_index: u64;
    current_biome: Biome_Type = .Count;
    global_stats: [Global_Stat_Kind.Count]Statistic;
    flag_pid: Pid;
    latest_emitter: Pid = INVALID_PID;
    lightmap: Lightmap;
    void_eyes_spawn_accumulator: f32 = 0;
    void_eyes_spawn_cooldown:    f32 = 0; // After unlocking a new section, the lightmap needs a bit of time to propagate the initial beam. Otherwise, we'll be spawning new void eyes in places were they'll be killed immediately after again
    #using em: Entity_Manager;
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

count_total_players :: (server: *Server) -> s64 {
    count := 0;
    
    for i := 0; i < server.clients.count; ++i {
        count += array_get_pointer(*server.clients, i).local_player_count;
    }

    return count;
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

        send_all_outgoing_messages(*server);
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
