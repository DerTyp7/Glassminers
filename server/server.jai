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
#load "../shared/VERSION_STRING.jai";

// Server
#load "entity.jai";
#load "pathfinder.jai";

TICK_RATE: f32 : 60;
DEVELOPER   :: #run compiler_is_user_option_present("Developer");
BAKE_ASSETS :: !DEVELOPER;
DEVELOPER_WORLD_SECTION_SEPARATOR :: #char "|";

#if BAKE_ASSETS {
    bake_file :: (filepath: string) -> string {
        file_content, success := read_entire_file(Default_Allocator, filepath);
        if !success || file_content.count == 0 compiler_report_error(print_into_allocator(Default_Allocator, "Failed to bake the file '%': The file does not exist.", filepath));
        return file_content;
    }

    // @Cleanup: In release builds, this is actually put into the data section, not the read-only section
    // of the executable? Also, it seems like the strings land in there twice?
    GAME_MODE_WORLD_STRINGS :: [Game_Mode.Count]string.[
        #run bake_file(ASSET_FILE_PATH("run_tree/data/developer-world.txt")),
        #run bake_file(ASSET_FILE_PATH("run_tree/data/tutorial-world.txt")),
        "", // Easy
        "", // Medium
        "" // Hard
    ];
} #else {
    GAME_MODE_WORLD_FILE_PATHS :: [Game_Mode.Count]string.[
        "data/developer-world.txt",
        "data/tutorial-world.txt",
        "", // Easy
        "", // Medium
        "", // Hard
    ];
}

Local_Player :: struct {
    guy_pid: Pid = INVALID_PID;
    name := "";
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
    random: Random_Generator;
    
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
    flag_pid: Pid;
    latest_emitter: Pid;
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
            if guy.carrying_item == .Flag {
                place_flag(server, guy.physical_position);
            } else if guy.carrying_item != .Count {
                try_to_place_item(server, guy.physical_position, guy.carrying_item, null);
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
      case .Client_Disconnect, .Game_Start, .Game_Over, .Game_Score, .World_Resize, .Create_Entity, .Destroy_Entity, .Move_Entity, .Entity_Health, .Guy_State, .Emitter_State, .Item_Stack_State, .Chest_State, .Frog_State, .Goblin_State, .Slime_State; // Ignore

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
        guy.received_input = msg.guy_input;
        guy.received_input_this_tick = true;
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
        reset_allocator(*server.world_allocator);
    }
    
    server.current_state = server.next_state;
    
    if #complete server.current_state == {
      case .Lobby, .Game_Over; // Ignore
        
      case .Ingame;
        create_the_game(server);
    }
}

use_random_world_generation :: (server: *Server) -> bool {
    return !(server.game_mode == .Tutorial || server.game_mode == .Developer);
}



SPAWN_PROBABILITY_TABLE :: #run setup_probabilities_table(); // This table contains the chance ([0-1]) that an entity of this category will spawn on one tile.

setup_probabilities_table :: () -> [Game_Mode.Count][Entity_Kind.Count]f32 {
    desired_per_section :: (x: f32) -> f32 { // On average I expect X entities in one section
        return cast(f32) x / cast(f32) (SECTION_WIDTH * SECTION_HEIGHT);
    }

    desired_coverage :: (p: f32) -> f32 { // On average I expect p % of the tiles to be this entity
        return p;
    }

    modify_default :: (target: Game_Mode, kind: Entity_Kind, modifier: f32) #macro {
        result[target][kind] = result[.Medium][kind] * modifier;
    }

    result: [Game_Mode.Count][Entity_Kind.Count]f32;

    // Set up the default difficulty
    {
        result[.Medium][.Slime_Hole] = desired_per_section(1);
        result[.Medium][.Trader]     = desired_per_section(0.75);
        result[.Medium][.Lava]       = desired_coverage(0.085);
        result[.Medium][.Bedrock]    = desired_coverage(0.17);
        result[.Medium][.Coal]       = desired_per_section(4);
        result[.Medium][.Rock]       = desired_per_section(4);
        result[.Medium][.Crystal]    = desired_per_section(3);
        result[.Medium][.Frog]       = desired_per_section(3);
        result[.Medium][.Goblin]     = desired_per_section(4);
    }

    // Set up the easy difficulty
    {
        modify_default(.Easy, .Slime_Hole, 0.75);
        modify_default(.Easy, .Trader,      2.0);
        modify_default(.Easy, .Lava,        1.0);
        modify_default(.Easy, .Bedrock,     1.0);
        modify_default(.Easy, .Coal,        1.1);
        modify_default(.Easy, .Rock,        1.1);
        modify_default(.Easy, .Crystal,     1.1);
        modify_default(.Easy, .Frog,       0.75);
        modify_default(.Easy, .Goblin,     0.75);
    }    

    // Set up the hard difficulty
    {
        modify_default(.Hard, .Slime_Hole, 1.2);
        modify_default(.Hard, .Trader,     1.1);
        modify_default(.Hard, .Lava,       1.2);
        modify_default(.Hard, .Bedrock,    1.0);
        modify_default(.Hard, .Coal,       0.75);
        modify_default(.Hard, .Rock,       0.75);
        modify_default(.Hard, .Crystal,    0.75);
        modify_default(.Hard, .Frog,       1.2);
        modify_default(.Hard, .Goblin,     1.2);
    }

    return result;
}

fill_world_section_randomly :: (server: *Server, section: [2]s32) {
    is_reserved_position :: (server: *Server, position: v2i) -> bool {
        // We want to free up space around the spawn positions of the player (so that players don't spawn on
        // top of monsters, etc).
        // However, we *don't* want this to mess with our probability distributions - so if an entity would've
        // been spawned here, we don't want to move it somewhere else in the section, we just want to drop it.
        // Otherwise, we make the right side of the first section really dense...
        return (position.y >= 1 && position.y <= 3 && position.x >= 0 && position.x <= 2 + server.clients.count + 1);
    }

    random_position :: (server: *Server, section: [2]s32) -> v2i, bool {
        position := v2i.{ random_u64_in(*server.random, section[0], section[1] + 1),
                          random_u64_in(*server.random, 0, SECTION_HEIGHT) };

        success := true;
        
        iteration := 0;
        while find_any_entity_at_position(server, position) {
            position = v2i.{ random_u64_in(*server.random, section[0], section[1] + 1),
                             random_u64_in(*server.random, 0, SECTION_HEIGHT) };

            if iteration > 10 {
                logprint(.Warning, "Failed to find a suitable spawn position while generating the world...");
                success = false;
                break;
            }

            ++iteration;
        }

        if success {
            success = !is_reserved_position(server, position);
        }

        assert(!success || position_in_bounds(server, position), "Somehow generated a position out-of-bounds...");
        
        return position, success;
    }

    generate_random_count :: (server: *Server, section: [2]s32, kind: Entity_Kind) -> s32 {
        t := SPAWN_PROBABILITY_TABLE[server.game_mode][kind];
        area := (section[1] - section[0] + 1) * SECTION_HEIGHT;
        mean := t * cast(f32) area;
        stddev: f32 : 0.25;
        return cast(s32) round(random_f32_normal_distribution(*server.random, mean, stddev * mean));
    }

    generate_randomly :: (server: *Server, section: [2]s32, kind: Entity_Kind) -> [..]*Entity {
        result: [..]*Entity;
        result.allocator = *temp;
        
        count := generate_random_count(server, section, kind);

        for i := 0; i < count; ++i {
            position, success := random_position(server, section);
            if success {
                entity := create_entity(server, kind, position, ENTITY_DEFAULT_DIRECTION[kind]);
                array_add(*result, entity);
            }
        }

        return result;
    }

    {
        latest_emitter := create_entity(server, .Emitter, .{ section[1], random_u64_in(*server.random, 0, SECTION_HEIGHT) }, .East);
        server.latest_emitter = latest_emitter.pid;
    }
    
    generate_randomly(server, section, .Lava);
    generate_randomly(server, section, .Bedrock);
    generate_randomly(server, section, .Rock);
    generate_randomly(server, section, .Crystal);
    generate_randomly(server, section, .Coal);
    generate_randomly(server, section, .Frog);
    generate_randomly(server, section, .Goblin);
    generate_randomly(server, section, .Trader);
    holes := generate_randomly(server, section, .Slime_Hole);
    
    for i := 0; i < holes.count; ++i {
        hole := array_get(*holes, i);
        create_entity(server, .Slime, hole.physical_position, ENTITY_DEFAULT_DIRECTION[.Slime]);
    }
}

count_sections_in_predefined_world :: (game_mode: Game_Mode) -> u32 {
    lines, success := load_predefined_world_data(game_mode);
    if !success return 0;

    max_section_count := 1;
    for y := 0; y < lines.count; ++y {
        line := array_get(*lines, y);
        line_section_count := 1;

        for x := 0; x < line.count; ++x {
            if line[x] == DEVELOPER_WORLD_SECTION_SEPARATOR then ++line_section_count;
        }

        max_section_count = max(max_section_count, line_section_count);
    }

    return max_section_count;
}

load_predefined_world_data :: (game_mode: Game_Mode) -> [..]string, bool {
#if !BAKE_ASSETS {
    data, success := read_entire_file(*temp, GAME_MODE_WORLD_FILE_PATHS[game_mode]);
    if !success {
        logprint(.Error, "Failed to load the predefined world file '%' from disk.", GAME_MODE_WORLD_FILE_PATHS[game_mode]);
        return ---, false;
    }
} #else {
    data := GAME_MODE_WORLD_STRINGS[game_mode];
}

    lines := string_split(data, #char "\n", false, *temp);

    for i := 0; i < lines.count; {
        line := array_get(*lines, i);
        if line.count && line[0] == #char "#" {
            array_remove_index(*lines, i);
        } else if line.count && line[line.count - 1] == #char "\r" {
            array_put(*lines, i, substring_view(line, 0, line.count - 1));
            ++i;
        } else {
            ++i;
        }
    }
    
    return lines, true;
}

get_predefined_world_size :: (game_mode: Game_Mode, current_section_index: s64) -> v2i {
    lines, success := load_predefined_world_data(game_mode);
    if !success return .{};
    
    max_width: s64 = 0;

    for y := 0; y < lines.count; ++y {
        line := array_get(*lines, y);
        line_width: s64 = 0;
        line_section_index := 0;

        for x := 0; x < line.count && line_section_index <= current_section_index; ++x {
            if line[x] == DEVELOPER_WORLD_SECTION_SEPARATOR then ++line_section_index;

            line_width += 1;
        }
        
        max_width = max(max_width, line_width - line_section_index); // The separator characters don't actually represent entities and therefore don't count here
    }

    return .{ max_width, lines.count };
}

fill_predefined_world_section :: (server: *Server, game_mode: Game_Mode, section_index_to_fill: u32) -> bool {
    ENTITY_TO_CHAR: [Entity_Kind.Count]char : .[
        // Beams
        #char "e", // Emitter
        #char "m", // Mirror

        // Environment
        #char "l", // Lava
        #char "b", // Bedrock
        #char "s", // Rock
        #char "c", // Coal
        #char "g", // Crystal
        #char "h", // Slime Hole

        // Creations
        #char " ", // Item Stack
        #char " ", // Slab
        #char " ", // Torch
        #char " ", // Chest

        // Beings
        #char ".", // Guy
        #char "F", // Frog
        #char "G", // Goblin
        #char "S", // Slime
        #char "T", // Trader

        // Misc
        #char "f", // Flag
    ];

    lines, success := load_predefined_world_data(game_mode);
    if !success return false;

    //
    // Create entities for all characters in the world string
    //
    for y := 0; y < lines.count; ++y {
        line := array_get(*lines, y);
        current_section_index := 0;
        for x := 0; x < line.count && current_section_index <= section_index_to_fill; ++x {
            if line[x] == #char " " continue;
            
            if line[x] == DEVELOPER_WORLD_SECTION_SEPARATOR {
                current_section_index += 1;
                continue;
            }
            if current_section_index < section_index_to_fill continue;

            direction: Direction = ---;
            xPos := x - current_section_index;
            
            kind := Entity_Kind.Count;
            for i := 0; i < ENTITY_TO_CHAR.Capacity; ++i {
                if ENTITY_TO_CHAR[i] == line[x] {
                    kind = i;
                    direction = ENTITY_DEFAULT_DIRECTION[kind];
                    break;
                }
            }

            if kind != .Count {
                entity := create_entity(server, kind, .{ xPos, y }, direction);

                if kind == .Emitter {
                    emitter := down(entity, Emitter);
                    server.latest_emitter = emitter.pid;
                    
                    // Cannot use section_index for this, because the first
                    // section index consists of two emitters.
                    // (Every following section index should contain 
                    //  exactly one emitter)
                    is_first_emitter := (x == 0);
                    
                    if is_first_emitter {
                        set_emitter_state(server, emitter, .Active, EMITTER_MAX_CHARGE[server.game_mode]);
                    }
                } else if kind == .Slime_Hole {
                    slime := create_entity(server, .Slime, .{ xPos, y }, direction);
                }
            } else {
                logprint(.Error, "Failed to parse the world string for '%' in line %: The character '%' is not a known entity.", game_mode, y + 1, line[x]);
                success = false;
            }
        }
    }
    
    return true;
}

create_the_game :: (server: *Server) {
    reset_allocator(*server.world_allocator);
    create_entity_manager(server);

    server.world_size = .{ 0, 0 };
    server.current_section_index = 0;
    server.game_seed = os_get_cpu_time();
    seed_random_generator(*server.random, server.game_seed, server.game_seed, server.game_seed, server.game_seed);

    if use_random_world_generation(server) {
        server.world_size = .{ SECTION_WIDTH, SECTION_HEIGHT };
    } else {
        server.world_size = get_predefined_world_size(server.game_mode, server.current_section_index);
    }
    
    //
    // Notify the clients about the game seed
    //
    game_start := make_message(Game_Start_Message);
    game_start.game_start.seed = server.game_seed;
    game_start.game_start.size = server.world_size;
    game_start.game_start.game_mode = server.game_mode;
    array_add(*server.outgoing_messages, game_start);

    //
    // Generate the required entities
    //
    place_flag(server, .{ 1, 2 });

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
    if use_random_world_generation(server) {
        emitter_entity := create_entity(server, .Emitter, .{ 0, 2 }, .East);
        emitter := down(emitter_entity, Emitter);
        set_emitter_state(server, emitter, .Active, EMITTER_MAX_CHARGE[server.game_mode]);
        
        fill_world_section_randomly(server, .[ 0, server.world_size.x - 1]);
    } else {
        fill_predefined_world_section(server, server.game_mode, server.current_section_index);
    }
}

generate_next_world_section :: (server: *Server) {
    ++server.current_section_index;

    if use_random_world_generation(server) {
        previous_width := server.world_size.x;
        server.world_size.x += SECTION_WIDTH;

        msg := make_message(World_Resize_Message);
        msg.world_resize.new_world_size = server.world_size;
        array_add(*server.outgoing_messages, msg);

        fill_world_section_randomly(server, .[ previous_width, server.world_size.x - 1 ]);
    } else {
        server.world_size = get_predefined_world_size(server.game_mode, server.current_section_index);

        msg := make_message(World_Resize_Message);
        msg.world_resize.new_world_size = server.world_size;
        array_add(*server.outgoing_messages, msg);

        fill_predefined_world_section(server, server.game_mode, server.current_section_index);
    }
}

do_lobby_tick :: (server: *Server) {
    read_incoming_packets(server);
    handle_client_timeouts(server);
    send_all_outgoing_messages(server);
}

get_available_resources_for_guy :: (server: *Server, guy: *Guy) -> [..]Item_Kind {
    result: [..]Item_Kind;
    result.allocator = *temp;

    if guy.state == .Carrying && guy.carrying_item != .Count {
        array_add(*result, guy.carrying_item);
    }

    standing_on := find_entity_of_kind_at_position(server, .Item_Stack, guy.physical_position);
    if standing_on {
        item_stack := down(standing_on, Item_Stack);

        for i := 0; i < item_stack.count; ++i {
            array_add(*result, item_stack.item_kind);
        }
    }
    
    return result;
}

consume_resources_from_guy :: (server: *Server, guy: *Guy, resources: []Item_Kind) {
    standing_on := find_entity_of_kind_at_position(server, .Item_Stack, guy.physical_position);
    item_stack: *Item_Stack = null;

    if standing_on {
        item_stack = down(standing_on, Item_Stack);
    }
        
    for i := 0; i < resources.count; ++i {
        resource := resources[i];

        if guy.state == .Carrying && guy.carrying_item == resource {
            guy.carrying_item = .Count;
            guy.state = .Idle;
        } else if item_stack && item_stack.item_kind == resource && item_stack.count {
            take_item_from_stack(server, item_stack);            
        } else {
            panic("Tried to consume resources from the guy that they don't have.");
        }
    }
}

try_to_fulfill_recipe :: (server: *Server, guy: *Guy, recipe: Crafting_Recipe) -> bool {
    // Check the guy is facing the required enabler
    if CRAFTING_RECIPE_ENABLER[recipe] != .Count && !find_entity_of_kind_at_position(server, CRAFTING_RECIPE_ENABLER[recipe], guy.target_position) return false;

    // Check the target position is empty when required
    if CRAFTING_RECIPE_REQUIRES_EMPTY_TARGET[recipe] && find_entity_with_flags_at_position(server, .Blocks_Crafting, guy.target_position) return false;
    
    // Check the guy has enough resources
    available_resources := get_available_resources_for_guy(server, guy);
    if !available_resources_fulfill(available_resources, CRAFTING_RECIPE_REQUIRED_ITEMS[recipe]) return false;
    
    // Actually commit to crafting.
    consume_resources_from_guy(server, guy, CRAFTING_RECIPE_REQUIRED_ITEMS[recipe]);
    return true;
}

handle_guy_movement :: (server: *Server, guy: *Guy) {
    if !guy.received_input.wants_to_move return; 

    distance_to_move := abs(guy.received_input.position.x - guy.physical_position.x) + abs(guy.received_input.position.y - guy.physical_position.y); // This can be violated if the guy got moved by something else during this tick...
    if distance_to_move != 1 {
        update_physical_location(server, guy, guy.physical_position, guy.received_input.aim_direction);
        return;
    }

    is_in_ghost_mode := false;
    #if DEVELOPER { 
        is_in_ghost_mode = guy.ghost_mode;
    }

    if is_in_ghost_mode {
        // Bypass checks and recursive move routine
        if position_in_bounds(server, guy.received_input.position) {
            update_physical_location(server, guy, guy.received_input.position, guy.received_input.aim_direction);
        }
    } else if can_move_to_position(server, guy, guy.received_input.position, GUY_PUSH_STRENGTH) {
        // Rotate and move to the target position by recursively pushing things
        guy.physical_rotation = guy.received_input.aim_direction;
        move_to_position(server, guy, guy.received_input.position);
    } else {
        // If we can't move to the position then at least update the rotation
        update_physical_location(server, guy, guy.physical_position, guy.received_input.aim_direction);
    }
}

handle_guy_input :: (server: *Server, guy: *Guy) {
    handle_guy_movement(server, guy);
    
    //
    // Handle interaction
    //
    if #complete guy.received_input.interaction_kind == {            
      case .Primary_Start;
        target_entity := find_any_entity_at_position(server, guy.target_position);

        if #complete guy.state == {
          case .Dead, .Resurrecting;

          case .Digging;
            guy.state = .Idle; // Pressing primary again should stop the current again, in case that was a mistake
            
          case .Idle;
            if !target_entity break;

            if target_entity.entity_kind == {
              case .Guy;
                other_guy := down(target_entity, Guy);
                if other_guy.state == .Dead {
                    guy.state = .Resurrecting;
                    guy.resurrection_pid = other_guy.pid;
                    guy.resurrection_t = 0;
                }

              case .Item_Stack;                
                put_item_in_hand(guy, take_item_from_stack(server, down(target_entity, Item_Stack)));

              case .Torch;
                put_item_in_hand(guy, .Torch);
                remove_entity(server, target_entity);

              case .Flag;
                put_item_in_hand(guy, .Flag);
                remove_entity(server, target_entity);
                server.flag_pid = INVALID_PID;
                
              case;
                if target_entity.entity_flags & .Diggable {
                    guy.state = .Digging;
                }
            }
            
          case .Carrying;
            if target_entity && target_entity.entity_kind == .Emitter && guy.carrying_item == .Coal {
                emitter := down(target_entity, Emitter);
                if emitter.state == .Active {
                    set_emitter_state(server, emitter, .Active, emitter.current_charge + COAL_EMITTER_CHARGE);
                    guy.state = .Idle;
                }
            } else if target_entity && target_entity.entity_kind == .Lava && guy.carrying_item == .Stone {
                remove_entity(server, target_entity);
                create_entity(server, .Slab, guy.target_position, .North);
                guy.state = .Idle;
            } else if !target_entity && guy.carrying_item == .Torch {
                if position_in_bounds(server, guy.target_position) {
                    guy.state = .Idle;
                    create_entity(server, .Torch, guy.target_position, .North);
                }
            } else if guy.carrying_item == .Flag {
                if try_to_place_flag(server, guy.target_position) {
                    guy.state = .Idle;
                }
            } else if try_to_place_item(server, guy.target_position, guy.carrying_item, null) {
                guy.state = .Idle;
            }
        }

      case .Primary_End;
        if guy.state == .Digging {
            guy.state = .Idle;
        }
        
      case .Secondary_Start;
        target_entity := find_any_entity_at_position(server, guy.target_position);
        if target_entity && target_entity.entity_kind == .Mirror {
            update_physical_location(server, target_entity, target_entity.physical_position, (target_entity.physical_rotation + 1) % Direction.Count);
        }

      case .Secondary_End;
    }
    
    //
    // Handle crafting
    //
    if guy.received_input.crafting_recipe != .Count {
        if try_to_fulfill_recipe(server, guy, guy.received_input.crafting_recipe) {
            if #complete guy.received_input.crafting_recipe == {
              /* Crafting Hud */
              case .Mirror; create_entity(server, .Mirror, guy.target_position, .North);
              case .Torch;  put_item_in_hand(guy, .Torch);
              case .Chest;  create_entity(server, .Chest, guy.target_position, .North);
              
              /* Trader Hud */              
              case .Health_Potion;   set_entity_health(server, guy, guy.health + HEALTH_PER_HEART);
              case .Strength_Potion; guy.strength_t = STRENGTH_POTION_TIME;
              case .Shard;           put_item_in_hand(guy, .Shard);
              case .Coal;            put_item_in_hand(guy, .Coal);
            }
        }
    }

    //
    // Handle taking items from a chest
    //
    if guy.received_input.chest_item != .Count && guy.state == .Idle {
        target_entity := find_entity_of_kind_at_position(server, .Chest, guy.target_position);
        if target_entity {
            chest := down(target_entity, Chest);
            if try_to_take_item_from_chest(server, chest, guy.received_input.chest_item) {
                put_item_in_hand(guy, guy.received_input.chest_item);
            }
        }
    }
    
    //
    // Handle cheating
    //
#if DEVELOPER {
    spawn_creature_with_cheat :: (server: *Server, guy: *Guy, kind: Entity_Kind) {
        if !find_any_entity_at_position(server, guy.target_position) {
            create_entity(server, kind, guy.target_position, ENTITY_DEFAULT_DIRECTION[kind]);
        }
    }

    if #complete guy.received_input.cheat == {
      case .Give_Coin; try_to_give_item(server, guy, .Coin);
      case .Give_Coal; try_to_give_item(server, guy, .Coal);
      case .Give_Shard; try_to_give_item(server, guy, .Shard);
      case .Give_Stone; try_to_give_item(server, guy, .Stone);
      case .Give_Health; set_entity_health(server, guy, ENTITY_DEFAULT_HEALTH[.Guy]);
      case .Give_Strength; guy.strength_t = STRENGTH_POTION_TIME;
      case .Spawn_Goblin; spawn_creature_with_cheat(server, guy, .Goblin);
      case .Spawn_Frog; spawn_creature_with_cheat(server, guy, .Frog);
      case .Spawn_Slime; spawn_creature_with_cheat(server, guy, .Slime);
      case .Spawn_Trader; spawn_creature_with_cheat(server, guy, .Trader);
      case .Toggle_Invincibility; guy.invincible = !guy.invincible;
	  case .Toggle_GhostMode; guy.ghost_mode = !guy.ghost_mode;
      case .Complete_Emitters;
        for i := 0; i < server.emitters.slot_count; ++i {
            emitter, occupied := index_bucket_array(*server.emitters, i);
            if occupied && emitter.state == .Off {
                set_emitter_state(server, emitter, .Active, EMITTER_MAX_CHARGE[server.game_mode]);
            }
        }
    }
}
}

do_game_tick :: (server: *Server) {
    read_incoming_packets(server);
    handle_client_timeouts(server);

    if !server.game_paused {
        game_result: Game_Result = .Unfinished_Game;
        
        generate_next_section: bool = false;

        //
        // Update all emitters. The emitters that are off need to access the beams of the emitters
        // that have power, so we need to update the powered emitters first to build up the beams.
        // Otherwise we'd attempt to access the beams of the previous frames, which would cause
        // segfaults.
        //
        for i := 0; i < server.emitters.slot_count; ++i {
            emitter, occupied := index_bucket_array(*server.emitters, i);
            if !occupied continue;

            update_powered_emitter(server, emitter);

            if emitter.pid == server.latest_emitter && emitter.state == .Active then generate_next_section = true;
        }

        for i := 0; i < server.emitters.slot_count; ++i {
            emitter, occupied := index_bucket_array(*server.emitters, i);
            if !occupied continue;

            update_off_emitter(server, emitter);
        }
        
        //
        // Update all slab
        //
        for i := 0; i < server.slabs.slot_count; ++i {
            slab, occupied := index_bucket_array(*server.slabs, i);
            if occupied update_slab(server, slab);
        }
        
        //
        // Update all frogs
        //
        for i := 0; i < server.frogs.slot_count; ++i {
            frog, occupied := index_bucket_array(*server.frogs, i);
            if occupied update_frog(server, frog);
        }

        //
        // Update all goblins
        //
        for i := 0; i < server.goblins.slot_count; ++i {
            goblin, occupied := index_bucket_array(*server.goblins, i);
            if occupied update_goblin(server, goblin);
        }

        //
        // Update all slimes
        //
        for i := 0; i < server.slimes.slot_count; ++i {
            slime, occupied := index_bucket_array(*server.slimes, i);
            if occupied update_slime(server, slime);
        }
        
        //
        // Update all guys
        //
        number_of_dead_guys := 0;
        
        for i := 0; i < server.guys.slot_count; ++i {
            guy, occupied := index_bucket_array(*server.guys, i);
            if !occupied continue;

            if guy.received_input_this_tick && guy.state != .Dead then handle_guy_input(server, guy);
            guy.received_input_this_tick = false;

            update_guy(server, guy);
            
            if guy.state == .Dead ++number_of_dead_guys;
        }
        
        //
        // Update all other kinds entities
        //
        for i := 0; i < server.all_entities.slot_count; ++i {
            entity, occupied := index_bucket_array(*server.all_entities, i);
            if !occupied continue;

            if entity.entity_kind == {
              case .Trader; update_trader(server, entity);
              case .Rock, .Coal, .Crystal, .Mirror, .Item_Stack, .Flag; damage_and_maybe_kill_if_in_lava(server, entity);
            }

            if entity.entity_flags & .Auto_Heal && !entity.damaged_this_frame {
                set_entity_health(server, entity, entity.health + HEALTH_PER_HEART * server.tick_time);
            }
            
            entity.damaged_this_frame = false;
        }

        //
        // Check for game over scenarios
        //
        {
            number_of_players := 0;
            for i := 0; i < server.clients.count; ++i {
                number_of_players += array_get(*server.clients, i).local_player_count;
            }
            
            if number_of_dead_guys == number_of_players {
                game_result = .All_Players_Died;
            }
        }
            
        if server.flag_pid != INVALID_PID && !entity_exists(server, server.flag_pid) {
            // This means that the flag is not currently carried by any player, but it no longer
            // physically exists, which can only mean it got killed (e.g. by lava or whatever).
            game_result = .Flag_Was_Destroyed;
        }

        if server.game_mode == .Tutorial && server.current_section_index + 1 >= count_sections_in_predefined_world(server.game_mode) && server.game_score == server.world_size.x {
            game_result = .Completed_Tutorial;
        }

        //
        // Progress through the game state
        //
        if game_result != .Unfinished_Game {
            msg := make_message(Game_Over_Message);
            msg.game_over.score  = server.game_score;
            msg.game_over.result = game_result;
            
            array_add(*server.outgoing_messages, msg);
            server.next_state = .Game_Over;
        } else if generate_next_section {
            generate_next_world_section(server);
        }
    } else if server.clients.count == 0 {
        server.next_state = .Game_Over;
    }
        
    //
    // Send all updates to clients.
    //
    send_all_outgoing_messages(server);
    
    //
    // Finally actually delete all marked entities
    //
    physically_remove_dead_entities(server);
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
