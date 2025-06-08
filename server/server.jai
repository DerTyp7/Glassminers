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

TICK_RATE: f32 : 60;
DEVELOPER   :: #run compiler_is_user_option_present("Developer");
BAKE_ASSETS :: !DEVELOPER;

#if BAKE_ASSETS {
    bake_file :: (filepath: string) -> string {
        file_content, success := read_entire_file(Default_Allocator, filepath);
        if !success compiler_report_error(print_into_allocator(Default_Allocator, "Failed to bake the file '%': The file does not exist.", filepath));
        return file_content;
    }

    CAMPAIGN_WORLD_STRINGS :: [Campaign.Count]string.[
        #run bake_file("run_tree/data/developer-world.txt"),
        #run bake_file("run_tree/data/tutorial-world.txt"),
        "", // Easy
        "", // Medium
        "" // Hard
    ];
} #else {
    CAMPAIGN_WORLD_FILE_PATHS :: [Campaign.Count]string.[
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
    campaign: Campaign = .Tutorial;
    world_pool: Memory_Pool;
    world_allocator: Allocator;
    game_seed: s64;
    tick_time: f32;
    game_paused := false;
    world_size: v2i;
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
      case .Client_Disconnect, .Game_Start, .Game_Over, .Create_Entity, .Destroy_Entity, .Move_Entity, .Entity_Health, .Guy_State, .Emitter_State, .Receiver_State, .Item_Stack_State, .Frog_State, .Goblin_State; // Ignore

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
        server.campaign = msg.request_game_start.campaign;
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
                if client then update_virtual_connection_information_for_packet(*client.connection, *packet.header);
                
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
    now := os_get_hardware_time();

    for i := 0; i < server.clients.count; {
        client := array_get_pointer(*server.clients, i);

        if os_convert_hardware_time(now - client.connection.time_of_last_received_packet, .Seconds) > NETWORK_TIMEOUT {
            handle_client_disconnect(server, client);
        } else if os_convert_hardware_time(now - client.connection.time_of_last_sent_packet, .Seconds) > NETWORK_PING_INTERVAL {
            send_ping_packet(*client.connection);
            ++i;
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

fill_world_randomly :: (server: *Server) {
    is_blocked_position :: (server: *Server, position: v2i) -> bool {
        if position.y >= 1 && position.y <= 3 &&
            position.x >= 2 && position.x <= 2 + server.clients.count + 1 return true;

        if find_any_entity_at_position(server, position) != null return true;

        return false;
    }

    random_position :: (server: *Server) -> v2i, bool {
        position := v2i.{ random_u64_in(*server.random, 0, server.world_size.x), random_u64_in(*server.random, 0, server.world_size.y) };

        success := true;
        
        iteration := 0;
        while is_blocked_position(server, position) {
            position = .{ random_u64_in(*server.random, 0, server.world_size.x), random_u64_in(*server.random, 0, server.world_size.y) };

            if iteration > 10 {
                logprint(.Warning, "Failed to find a suitable spawn position while generating the world...");
                success = false;
                break;
            }

            ++iteration;
        }
        
        return position, success;
    }

    generate_n_random_entities :: (server: *Server, kind: Entity_Kind, n: s64) {
        for i := 0; i < n; ++i {
            position, success := random_position(server);
            if success create_entity(server, kind, position, ENTITY_DEFAULT_DIRECTION[kind]);
        }
    }

    create_entity(server, .Emitter, .{ 0, 2 }, .East);
    create_entity(server, .Receiver, .{ server.world_size.x - 1, random_u64_in(*server.random, 0, server.world_size.y) }, .West);
    generate_n_random_entities(server, .Lava,    server.world_size.x / 2);
    generate_n_random_entities(server, .Bedrock, server.world_size.x);
    generate_n_random_entities(server, .Rock,    server.world_size.x / 4);
    generate_n_random_entities(server, .Crystal, server.world_size.x / 4);
    generate_n_random_entities(server, .Coal,    server.world_size.x / 4);
    generate_n_random_entities(server, .Frog,  server.world_size.x / 9);
    generate_n_random_entities(server, .Goblin,  server.world_size.x / 9);
    generate_n_random_entities(server, .Trader,  min(1, server.world_size.x / 36));
}

load_predefined_world_data :: (server: *Server, campaign: Campaign) -> [..]string, bool {
#if !BAKE_ASSETS {
    data, success := read_entire_file(*temp, CAMPAIGN_WORLD_FILE_PATHS[campaign]);
    if !success {
        logprint(.Error, "Failed to load the predefined world file '%' from disk.", CAMPAIGN_WORLD_FILE_PATHS[campaign]);
        return ---, false;
    }
} #else {
    data := CAMPAIGN_WORLD_STRINGS[campaign];
}

    lines := string_split(data, #char "\n", false, *temp);

    for i := 0; i < lines.count; ++i {
        line := array_get(*lines, i);
        if line.count && line[line.count - 1] == #char "\r" {
            array_put(*lines, i, substring_view(line, 0, line.count - 1));
        }
    }
    
    return lines, true;
}

get_predefined_world_size :: (server: *Server, campaign: Campaign) -> v2i {
    lines, success := load_predefined_world_data(server, campaign);
    if !success return .{};
    
    width: s32 = 0;

    for i := 0; i < lines.count; ++i {
        width = max(width, array_get(*lines, i).count);
    }

    return .{ width, lines.count };
}

fill_predefined_world :: (server: *Server, campaign: Campaign) -> bool {
    ENTITY_TO_CHAR: [Entity_Kind.Count]char : .[
        // Beams
        #char "e", // Emitter
        #char "r", // Receiver
        #char "m", // Mirror

        // Environment
        #char "l", // Lava
        #char "b", // Bedrock
        #char "s", // Rock
        #char "c", // Coal
        #char "@", // Crystal

        // Creations
        #char "i", // Item Stack
        #char "_", // Slab
        #char "T", // Torch
        
        // Beings
        #char "!", // Guy
        #char "f", // Frog
        #char "g", // Goblin
        #char "t", // Trader
    ];

    lines, success := load_predefined_world_data(server, campaign);
    if !success return false;

    //
    // Create entities for all characters in the world string
    //
    for y := 0; y < lines.count; ++y {
        line := array_get(*lines, y);
        for x := 0; x < line.count; ++x {
            if line[x] == #char " " continue;

            direction: Direction = ---;
            
            kind := Entity_Kind.Count;
            for i := 0; i < ENTITY_TO_CHAR.Capacity; ++i {
                if ENTITY_TO_CHAR[i] == line[x] {
                    kind = i;
                    direction = ENTITY_DEFAULT_DIRECTION[kind];
                    break;
                }
            }

            if kind != .Count {
                create_entity(server, kind, .{ x, y }, direction);
            } else {
                logprint(.Error, "Failed to parse the world string for '%' in line %: The character '%' is not a known entity.", campaign, y + 1, line[x]);
                success = false;
            }
        }
    }
    
    return true;
}

create_the_game :: (server: *Server) {
    reset_allocator(*server.world_allocator);
    create_entity_manager(server);

    server.game_seed = cast(s64) os_get_hardware_time();
    seed_random_generator(*server.random, server.game_seed, server.game_seed, server.game_seed, server.game_seed);

    if #complete server.campaign == {
      case .Tutorial, .Developer; server.world_size = get_predefined_world_size(server, server.campaign);
      case .Easy;      server.world_size = .{ 20, 5 };
      case .Medium;    server.world_size = .{ 36, 5 };
      case .Hard;      server.world_size = .{ 72, 5 };
    }
    
    //
    // Notify the clients about the game seed
    //
    game_start := make_message(Game_Start_Message);
    game_start.game_start.seed = server.game_seed;
    game_start.game_start.size = server.world_size;
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

    if server.campaign == .Tutorial || server.campaign == .Developer {
        fill_predefined_world(server, server.campaign);
    } else {
        fill_world_randomly(server);
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
    if CRAFTING_RECIPE_REQUIRES_EMPTY_TARGET[recipe] && find_entity_with_flags_at_position(server, .Blocks_Move, guy.target_position) return false;
    
    // Check the guy has enough resources
    available_resources := get_available_resources_for_guy(server, guy);
    if !available_resources_fulfill(available_resources, CRAFTING_RECIPE_REQUIRED_ITEMS[recipe]) return false;
    
    // Actually commit to crafting.
    consume_resources_from_guy(server, guy, CRAFTING_RECIPE_REQUIRED_ITEMS[recipe]);
    return true;
}

handle_guy_input :: (server: *Server, guy: *Guy) {
    //
    // Handle movement
    //
    if guy.received_input.wants_to_move {
        cancel_current_action := guy.physical_rotation != guy.received_input.aim_direction || guy.physical_position.x != guy.received_input.position.x || guy.physical_position.y != guy.received_input.position.y;

        if cancel_current_action {
            if #complete guy.state == {
              case .Dead, .Idle, .Carrying;
              case .Digging, .Resurrecting;
                guy.state = .Idle;
            }
        }

        distance_to_move := abs(guy.received_input.position.x - guy.physical_position.x) + abs(guy.received_input.position.y - guy.physical_position.y); // This can be violated if the guy got moved during this tick...
        
        if distance_to_move == 1 && can_move_to_position(server, guy, guy.received_input.position, GUY_PUSH_STRENGTH) {
            move_to_position(server, guy, guy.received_input.position);
        }
        
        update_physical_location(server, guy, guy.physical_position, guy.physical_rotation);
    }

    update_physical_location(server, guy, guy.physical_position, guy.received_input.aim_direction);
    
    //
    // Handle interaction
    //
    if #complete guy.received_input.interaction_kind == {            
      case .Primary;
        target_entity := find_any_entity_at_position(server, guy.target_position);

        if #complete guy.state == {
          case .Dead, .Digging, .Resurrecting;
            
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
                guy.state = .Carrying;
                guy.carrying_item = take_item_from_stack(server, down(target_entity, Item_Stack));

              case;
                if target_entity.entity_flags & .Diggable {
                    guy.state = .Digging;
                }
            }
            
          case .Carrying;
            if target_entity && target_entity.entity_kind == .Emitter && guy.carrying_item == .Coal {
                emitter := down(target_entity, Emitter);
                set_emitter_time_left(server, emitter, emitter.time_left_in_seconds + COAL_EMITTER_CHARGE_TIME);
                guy.state = .Idle;
                guy.carrying_item = 0;
            } else if target_entity && target_entity.entity_kind == .Lava && guy.carrying_item == .Stone {
                remove_entity(server, target_entity);
                create_entity(server, .Slab, target_entity.physical_position, .North);
                guy.state = .Idle;
                guy.carrying_item = 0;
            } else if try_to_put_item(server, guy.target_position, guy.carrying_item, null) {
                guy.state = .Idle;
                guy.carrying_item = 0;
            }
        }

      case .Secondary;
        target_entity := find_any_entity_at_position(server, guy.target_position);
        if target_entity && target_entity.entity_kind == .Mirror {
            update_physical_location(server, target_entity, target_entity.physical_position, (target_entity.physical_rotation + 1) % Direction.Count);
        }
    }
    
    //
    // Handle crafting
    //
    if guy.received_input.crafting_recipe != .Count {
        if try_to_fulfill_recipe(server, guy, guy.received_input.crafting_recipe) {
            if #complete guy.received_input.crafting_recipe == {
              case .Mirror; create_entity(server, .Mirror, guy.target_position, .North);
              case .Health_Potion; set_entity_health(server, guy, guy.health + HEALTH_PER_HEART);
              case .Strength_Potion; guy.strength_t = STRENGTH_POTION_TIME;
            }
        }
    }
    
    //
    // Handle cheating
    //
#if DEVELOPER {
    if #complete guy.received_input.cheat == {
      case .Give_Coin; try_to_give_item(server, guy, .Coin);
      case .Give_Coal; try_to_give_item(server, guy, .Coal);
      case .Give_Health; set_entity_health(server, guy, ENTITY_DEFAULT_HEALTH[.Guy]);
      case .Give_Strength; guy.strength_t = STRENGTH_POTION_TIME;
    }
}
}

do_game_tick :: (server: *Server) {
    game_state: enum { Keep_Going; Won; Lost; } = .Keep_Going;

    read_incoming_packets(server);
    handle_client_timeouts(server);

    if !server.game_paused {
        //
        // Update all emitters
        //
        for i := 0; i < server.emitters.slot_count; ++i {
            emitter, occupied := index_bucket_array(*server.emitters, i);
            if !occupied continue;

            update_emitter(server, emitter);

            if emitter.time_left_in_seconds <= 0 {
                game_state = .Lost;
            }
        }
        
        //
        // Update all receivers
        //
        for i := 0; i < server.receivers.slot_count; ++i {
            receiver, occupied := index_bucket_array(*server.receivers, i);
            if !occupied continue;

            update_receiver(server, receiver);

            if receiver.progress_time_in_seconds >= RECEIVER_TIME_TO_CHARGE {
                game_state = .Won;
            }
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
                case .Rock, .Coal, .Crystal, .Mirror, .Item_Stack; damage_and_maybe_kill_if_in_lava(server, entity);
            }
        }
        
        if number_of_dead_guys == server.clients.count {
            game_state = .Lost;
        }

        if game_state != .Keep_Going {
            msg := make_message(Game_Over_Message);
            msg.game_over.you_won = game_state == .Won;
            array_add(*server.outgoing_messages, msg);
            server.next_state = .Game_Over;
        }
    }
        
    //
    // Send all updates to clients.
    //
    send_all_outgoing_messages(server);
    
    //
    // Finally actually delete all marked entities
    //
    physically_remove_all_marked_entities(server);
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
        tick_start := os_get_hardware_time();

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
        
        tick_end := os_get_hardware_time();
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
