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

// Server
#load "entity.jai";

TICK_RATE: f32 : 30;
DEVELOPER :: #run compiler_is_user_option_present("Developer");

Remote_Client :: struct {
    connection: Virtual_Connection;
    player_pid: Pid = INVALID_PID;
    entity_pid: Pid = INVALID_PID;
    name: string = "";
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
    world_size: v2i;
    #using em: Entity_Manager;
}

Log_Level :: enum {
    Debug;
    Warning;
    Error;
}

logprint :: (level: Log_Level, format: string, args: ..Any) {
    print("[SERVER][%] ", enum_names(Log_Level)[level]);
    print(format, ..args);
    print("\n");
}

find_client_by_pid :: (server: *Server, pid: Pid) -> *Remote_Client {
    for i := 0; i < server.clients.count; ++i {
        client := array_get_pointer(*server.clients, i);
        if client.player_pid == pid return client;
    }
    
    return null;
}

handle_client_disconnect :: (server: *Server, client: *Remote_Client) {
    logprint(.Debug, "Disconnected from client '%'.", client.player_pid);

    if server.current_state == .Ingame {
        entity := get_entity(server, client.entity_pid);
        remove_entity(server, entity);
    }
        
    msg := make_message(Player_Disconnect_Message);
    msg.player_disconnect.player_pid = client.player_pid;
    array_add(*server.outgoing_messages, msg);
    
    if client.name deallocate_string(*server.world_allocator, *client.name);
    
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
      case .Player_Disconnect, .Game_Start, .Game_Over, .Create_Entity, .Destroy_Entity, .Move_Entity, .Entity_Health, .Player_State, .Emitter_State, .Receiver_State, .Item_Stack_State, .Dragon_State, .Goblin_State; // Ignore

      case .Player_Information;
        // Respond to this specific player by sending all other already-connected clients
        target := find_client_by_pid(server, msg.player_information.player_pid);
        for i := 0; i < server.clients.count; ++i {
            source := array_get_pointer(*server.clients, i);
            target_msg := make_message(Player_Information_Message);
            target_msg.player_information.player_pid = source.player_pid;
            target_msg.player_information.name       = source.name;
            target_msg.player_information.entity_pid = source.entity_pid;
            send_reliable_message(*target.connection, *target_msg);
        }
        
        // Store the information locally
        if target.name deallocate_string(*server.world_allocator, *target.name);
        target.name = copy_string(*server.world_allocator, msg.player_information.name);
        
        // Broadcast the message along
        broadcasted_msg := make_message(Player_Information_Message);
        broadcasted_msg.player_information.player_pid = target.player_pid;
        broadcasted_msg.player_information.name       = target.name;
        broadcasted_msg.player_information.entity_pid = target.entity_pid;
        array_add(*server.outgoing_messages, broadcasted_msg);
        
      case .Request_Game_Start;
        server.campaign = msg.request_game_start.campaign;
        server.next_state = .Ingame;
        
      case .Player_Input;
        entity := get_entity(server, msg.player_input.entity_pid);
        player := down(entity, Player);

        // We want to ensure a deterministic order in which entities are updated on the server.
        // Players are just normal entities that are updated at a specific time during the tick,
        // so just remember the player input for later.
        player.received_input = msg.player_input;
        player.received_input_this_tick = true;
    }
}    

read_incoming_packets :: (server: *Server) {
    if server.current_state == .Lobby {
        found_client, client_connection := accept_tcp_remote_client_connection(*server.connection);
        while found_client {
            client := array_push(*server.clients);
            client.connection = client_connection;
            client.player_pid = server.client_pid_counter;
            client.entity_pid = INVALID_PID;
            client.connection.info.client_id = client.player_pid;
            ++server.client_pid_counter;
            
            logprint(.Debug, "Connected to client '%'.", client.player_pid);

            found_client, client_connection = accept_tcp_remote_client_connection(*server.connection);
        }
    }
    
    for i := 0; i < server.clients.count; ++i {
        client := array_get_pointer(*server.clients, i);

        while read_packet(*client.connection) {
            packet :: *client.connection.incoming_packet;
            
            if packet.header.packet_type == {
              case Packet_Type.Connection_Request;
                send_connection_established_packet(*client.connection, 5);
                
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
    logprint(.Debug, "Switching from '%' to '%'...", server.current_state, server.next_state);

    if #complete server.current_state == {
      case .Lobby; // Ignore
      case .Ingame;
        destroy_entity_manager(server);
        reset_allocator(*server.world_allocator);

      case .Game_Over;
        // Give the clients time to cleanly disconnect from the server, see:
        // https://stackoverflow.com/questions/3757289/when-is-tcp-option-so-linger-0-required
        for i := 0; i < server.clients.count; ++i {
            client := array_get(*server.clients, i);
            destroy_connection(*client.connection);
        }
        array_clear(*server.clients);
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
    server.game_seed = cast(s64) os_get_hardware_time();
    seed_random_generator(*server.random, server.game_seed, server.game_seed, server.game_seed, server.game_seed);

    if #complete server.campaign == {
      case .Tutorial; server.world_size = .{ 9, 5 };
      case .Easy;     server.world_size = .{ 18, 5 };
      case .Medium;   server.world_size = .{ 36, 5 };
      case .Hard;     server.world_size = .{ 72, 5 };
    }

    create_entity_manager(server);
    
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
    for i := 0; i < server.clients.count; ++i {
        client := array_get_pointer(*server.clients, i);
        entity := create_entity(server, .Player, .{ 3 + i, 2 }, .North);
        client.entity_pid = entity.pid;
        
        msg := make_message(Player_Information_Message);
        msg.player_information.player_pid = client.player_pid;
        msg.player_information.name       = client.name;
        msg.player_information.entity_pid = client.entity_pid;
        array_add(*server.outgoing_messages, msg);            
    }

    //
    // Generate the base world
    //
    {
        is_blocked_position :: (server: *Server, position: v2i) -> bool {
            return position.y >= 1 && position.y <= 3 &&
                position.x >= 2 && position.x <= 2 + server.clients.count + 1;
        }

        random_position :: (server: *Server) -> v2i {
            position := v2i.{ random_u64_in(*server.random, 0, server.world_size.x), random_u64_in(*server.random, 0, server.world_size.y) };

            while get_entity_at_position(server, position) != null || is_blocked_position(server, position) {
                position = .{ random_u64_in(*server.random, 0, server.world_size.x), random_u64_in(*server.random, 0, server.world_size.y) };
            }
            
            return position;
        }

        generate_n_random_entities :: (server: *Server, kind: Entity_Kind, n: s64) {
            for i := 0; i < n; ++i {
                create_entity(server, kind, random_position(server), .North);
            }
        }

        create_entity(server, .Emitter, .{ 0, 2 }, .East);
        create_entity(server, .Receiver, .{ server.world_size.x - 1, 2 }, .West);
        generate_n_random_entities(server, .Bedrock, server.world_size.x * 2);
        generate_n_random_entities(server, .Rock,    server.world_size.x / 4);
        generate_n_random_entities(server, .Crystal, server.world_size.x / 4);
        generate_n_random_entities(server, .Coal,    server.world_size.x / 4);
        generate_n_random_entities(server, .Dragon,  server.world_size.x / 9);
        generate_n_random_entities(server, .Goblin,  server.world_size.x / 9);
    }
}

do_lobby_tick :: (server: *Server) {
    read_incoming_packets(server);
    handle_client_timeouts(server);
    send_all_outgoing_messages(server);
}

get_available_resources_for_player :: (server: *Server, player: *Player) -> [..]Item_Kind {
    result: [..]Item_Kind;
    result.allocator = *temp;

    if player.state == .Carrying && player.carrying_item != .Count {
        array_add(*result, player.carrying_item);
    }

    standing_on := get_entity_of_kind_at_position(server, .Item_Stack, player.physical_position);
    if standing_on {
        item_stack := down(standing_on, Item_Stack);

        for i := 0; i < item_stack.count; ++i {
            array_add(*result, item_stack.item_kind);
        }
    }
    
    return result;
}

consume_resources_from_player :: (server: *Server, player: *Player, resources: []Item_Kind) {
    standing_on := get_entity_of_kind_at_position(server, .Item_Stack, player.physical_position);
    item_stack: *Item_Stack = null;

    if standing_on {
        item_stack = down(standing_on, Item_Stack);
    }
        
    for i := 0; i < resources.count; ++i {
        resource := resources[i];

        if player.state == .Carrying && player.carrying_item == resource {
            player.carrying_item = .Count;
            player.state = .Idle;
        } else if item_stack && item_stack.item_kind == resource && item_stack.count {
            take_item_from_stack(server, item_stack);            
        } else {
            panic("Tried to consume resources from the player that they don't have.");
        }
    }
}

available_resources_fulfill :: (available: [..]Item_Kind, required: []Item_Kind) -> bool {
    copy := array_copy(*available, *temp);

    all_requirements_met := true;

    for i := 0; i < required.count; ++i {
        item_found := false;

        for j := 0; j < copy.count; ++j {
            if array_get(*copy, j) == required[i] {
                item_found = true;
                array_remove_index(*copy, j);
                break;
            }
        }

        all_requirements_met &= item_found;
    }
    
    return all_requirements_met;
}

maybe_craft_recipe :: (server: *Server, player: *Player, result_entity: Entity_Kind, required_resources: []Item_Kind) -> bool {
    // First check that the player has the necessary resources available
    available_resources := get_available_resources_for_player(server, player);
    if !available_resources_fulfill(available_resources, required_resources) return false;
    
    // Then check the target position is actually empty
    target_entity := get_entity_at_position(server, player.target_position);
    if target_entity return false;

    // Actually commit to crafting.
    consume_resources_from_player(server, player, required_resources);
    create_entity(server, result_entity, player.target_position, .North);
    return true;
}

handle_player_input :: (server: *Server, player: *Player) {
    //
    // Handle movement
    //
    {
        cancel_current_action := player.physical_rotation != player.received_input.aim_direction || player.physical_position.x != player.received_input.position.x || player.physical_position.y != player.received_input.position.y;

        if cancel_current_action {
            if #complete player.state == {
              case .Dead, .Idle, .Carrying;
              case .Digging, .Resurrecting;
                player.state = .Idle;
            }
        }

        if can_move_to_position(server, player, player.received_input.position) {
            move_to_position(server, player, player.received_input.position);
        }
        
        update_physical_location(server, player, player.physical_position, player.received_input.aim_direction);
    }
        
    //
    // Handle interaction
    //
    if #complete player.received_input.interaction_kind == {            
      case .None;

      case .Primary;
        target_entity := get_entity_at_position(server, player.target_position);

        if player.state != .Idle || !target_entity break;
        
        if target_entity.entity_kind == {
          case .Bedrock, .Crystal, .Rock, .Mirror, .Coal;
            player.state = .Digging;
          case .Item_Stack;
            player.state = .Carrying;
            player.carrying_item = take_item_from_stack(server, down(target_entity, Item_Stack));
        }
        
      case .Secondary;
        target_entity := get_entity_at_position(server, player.target_position);

        if #complete player.state == {
          case .Dead, .Digging, .Resurrecting;
          case .Idle;
            if target_entity == null {
            } else if target_entity.entity_kind == .Mirror {
                update_physical_location(server, target_entity, target_entity.physical_position, (target_entity.physical_rotation + 1) % Direction.Count);
            } else if target_entity.entity_kind == .Player {
                other_player := down(target_entity, Player);
                if other_player.state == .Dead {
                    player.state = .Resurrecting;
                    player.resurrection_pid = other_player.pid;
                    player.resurrection_t = 0;
                }
            }
            
          case .Carrying;
            if target_entity && target_entity.entity_kind == .Emitter {
                emitter := down(target_entity, Emitter);
                emitter.time_left_in_seconds = clamp(emitter.time_left_in_seconds + COAL_EMITTER_CHARGE_TIME, 0, EMITTER_MAX_TIME);
                player.state = .Idle;
                player.carrying_item = 0;
            } else  if try_to_put_item(server, player.target_position, player.carrying_item) {
                player.state = .Idle;
                player.carrying_item = 0;
            }
        }
    }
    
    //
    // Handle crafting
    //
    if #complete player.received_input.crafting_recipe == {
      case .None; // Ignore
      case .Mirror; maybe_craft_recipe(server, player, .Mirror, .[ .Shard ]);
      case .Dragon; maybe_craft_recipe(server, player, .Dragon, .[ .Stone, .Coal ]);
      case .Crystal; maybe_craft_recipe(server, player, .Crystal, .[ .Shard, .Shard ]);
    }
}

do_game_tick :: (server: *Server) {
    game_state: enum { Keep_Going; Won; Lost; } = .Keep_Going;

    read_incoming_packets(server);
    handle_client_timeouts(server);

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
        
        // @NetworkTraffic: Simple client-side predicition
        
        previous := receiver.progress_time_in_seconds;

        lit_up, incoming_direction := is_emitter_field_at(server, receiver.physical_position);
        if lit_up && incoming_direction == opposite_direction(receiver.physical_rotation) {
            receiver.progress_time_in_seconds = clamp(receiver.progress_time_in_seconds + server.tick_time, 0, RECEIVER_TIME_TO_CHARGE);
        } else {
            receiver.progress_time_in_seconds = clamp(receiver.progress_time_in_seconds - server.tick_time, 0, RECEIVER_TIME_TO_CHARGE);
        }

        if receiver.progress_time_in_seconds != previous {
            msg := make_message(Receiver_State_Message);
            msg.receiver_state.entity_pid = receiver.pid;
            msg.receiver_state.progress_time_in_seconds = receiver.progress_time_in_seconds;
            array_add(*server.outgoing_messages, msg);
        }

        if receiver.progress_time_in_seconds >= RECEIVER_TIME_TO_CHARGE {
            game_state = .Won;
        }
    }

    //
    // Update all dragons
    //
    for i := 0; i < server.dragons.slot_count; ++i {
        dragon, occupied := index_bucket_array(*server.dragons, i);
        if occupied update_dragon(server, dragon);
    }

    //
    // Update all goblins
    //
    for i := 0; i < server.goblins.slot_count; ++i {
        goblin, occupied := index_bucket_array(*server.goblins, i);
        if occupied update_goblin(server, goblin);
    }
    
    //
    // Update all players
    //
    number_of_dead_players := 0;
    
    for i := 0; i < server.players.slot_count; ++i {
        player, occupied := index_bucket_array(*server.players, i);
        if !occupied continue;

        if player.received_input_this_tick && player.state != .Dead then handle_player_input(server, player);
        player.received_input_this_tick = false;

        update_player(server, player);

        if player.state == .Dead ++number_of_dead_players;
    }

    if number_of_dead_players == server.clients.count {
        game_state = .Lost;
    }

    if game_state != .Keep_Going {
        msg := make_message(Game_Over_Message);
        msg.game_over.you_won = game_state == .Won;
        array_add(*server.outgoing_messages, msg);
        server.next_state = .Game_Over;
        logprint(.Debug, "Game Over!");
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
        atomic_store(*data.state, Server_State.Closing);
    }
    
    server.current_state = .Count;
    server.next_state    = .Count;
    server.client_pid_counter = 1;
    
    logprint(.Debug, "Started the server.");
    
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
          case .Game_Over; atomic_store(*data.state, Server_State.Closed);
        }

        release_temp_allocator(0);
        
        tick_end := os_get_hardware_time();
        os_sleep_to_tick_rate(tick_start, tick_end, TICK_RATE);
    }

    server.next_state = .Count; // Shut down all resources that might currently be in use
    switch_to_next_state(*server);
    
    atomic_store(*data.state, Server_State.Closing);
    
    destroy_connection(*server.connection);
    destroy_memory_pool(*server.world_pool);
    destroy_memory_pool(*server.engine_pool);
    destroy_temp_allocator();

    logprint(.Debug, "Stopped the server.");
    
    atomic_store(*data.state, Server_State.Closed);

    return 0;
}

main :: () -> u32 {
    data: Shared_Server_Data;
    data.requested_port = 9876;
    data.state          = .Starting;
    return server_entry_point(*data);
}
