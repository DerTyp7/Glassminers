// Prometheus modules
#load "basic.jai";
#load "virtual_connection.jai";
#load "threads.jai";
#load "random.jai";

// Shared
#load "../shared/messages.jai";
#load "../shared/world.jai";
#load "../shared/shared.jai";

// Server
#load "world.jai";

TICK_RATE: f32 : 30;

Remote_Client :: struct {
    connection: Virtual_Connection;
    player_pid: Pid;
    entity_pid: Pid;
    name: string;
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
    perm_pool: Memory_Pool;
    perm: Allocator;
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
    game_seed: s64;
    world: World;
    tick_time: f32;
}

Log_Level :: enum {
    Debug;
    Warning;
    Error;
}

logprint :: (level: Log_Level, format: string, args: ..Any) {
    print("[%] ", enum_names(Log_Level)[level]);
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
        entity := get_entity(*server.world, client.entity_pid);
        entity.marked_for_removal = true;
    }
        
    msg := make_message(Player_Disconnect_Message);
    msg.player_disconnect.player_pid = client.player_pid;
    array_add(*server.outgoing_messages, msg);
    
    if client.name deallocate_string(*server.perm, *client.name);
    
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
      case .Player_Disconnect, .Game_Start, .Game_Over, .Create_Entity, .Destroy_Entity, .Entity_Health, .Player_State, .Emitter_State, .Receiver_State; // Ignore

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
        if target.name deallocate_string(*server.perm, *target.name);
        target.name = copy_string(*server.perm, msg.player_information.name);
        
        // Broadcast the message along
        array_add(*server.outgoing_messages, ~msg);
        
      case .Request_Game_Start;
        create_the_game(server);
        transition_to_state(server, .Ingame);

      case .Move_Entity;
        entity := get_entity(*server.world, msg.move_entity.entity_pid);
        
        move_delta := v2i.{ msg.move_entity.position.x - entity.physical_position.x, msg.move_entity.position.y - entity.physical_position.y };
        
        if can_move_to_position(*server.world, entity, msg.move_entity.position) {
            move_to_position(*server.world, entity, msg.move_entity.position);
        }
        
        
      case .Player_Move;
        entity := get_entity(*server.world, msg.player_move.entity_pid);
        player := down(entity, Player);

        if player.state == .Dead break;
        
        if can_move_to_position(*server.world, entity, msg.player_move.position) {
            move_to_position(*server.world, entity, msg.player_move.position);
        }

        player.aim_direction = msg.player_move.aim_direction;
        
        // Cancel the current action of the player when moving, if appropriate
        if #complete player.state == {
          case .Dead, .Idle, .Carrying;
          case .Digging;
            player.state = .Idle;
        }
        
      case .Player_Interact;
        entity := get_entity(*server.world, msg.player_interact.entity_pid);
        player := down(entity, Player);

        if player.state == .Dead break;

        target_entity := get_entity_at_position(*server.world, player.target_position);

        if #complete msg.player_interact.interaction_kind == {            
          case .Primary;
            if player.state != .Idle || !target_entity break;
            
            if target_entity.kind == {
              case .Bedrock, .Crystal, .Rock, .Mirror;
                player.state = .Digging;
              case .Shard, .Stone;
                player.state = .Carrying;
                player.carrying_item = target_entity.kind;
                target_entity.marked_for_removal = true;
            }
            
          case .Secondary;
            if target_entity == null {
                // Place a new entity
                if #complete player.state == {
                  case .Dead, .Digging;
                  case .Idle;
                    // @Temporary: Players can currently create mirrors out of thin air...
                    create_entity(*server.world, .Mirror, player.target_position, .North);
                  case .Carrying;
                    create_entity(*server.world, player.carrying_item, player.target_position, .North);
                    player.state = .Idle;
                    player.carrying_item = .Inanimate;
                }
            } else if target_entity.kind == .Mirror {
                target_entity.physical_rotation = (target_entity.physical_rotation + 1) % Direction.Count;
                target_entity.moved_this_frame  = true;                    
            }
        }
    }
}    

read_incoming_packets :: (server: *Server) {
    while read_packet(*server.connection) {
        if server.connection.incoming_packet.header.packet_type == {
          case Packet_Type.Connection_Request;
            if server.current_state != .Lobby break; // If we aren't in the lobby, don't accept new clients

            // Check if we already have a client connected at this remote, because the client will spam
            // this connection request a few times to combat potential packet loss.
            already_connected := false;
            
            for i := 0; i < server.clients.count; ++i {
                connected_client := array_get_pointer(*server.clients, i);
                if remote_sockets_equal(*server.connection.remote, *connected_client.connection.remote) {
                    already_connected = true;
                    break;
                }
            }

            if already_connected break;
            
            //
            // Create a new client on this server
            //    
            client := array_push(*server.clients);
            client.connection = create_udp_remote_client_connection(*server.connection);
            client.player_pid = server.client_pid_counter;
            client.entity_pid = INVALID_PID;
            client.connection.info.client_id = client.player_pid;
            
            send_connection_established_packet(*client.connection, 5);
            
            ++server.client_pid_counter;
            
            logprint(.Debug, "Connected to client '%'.", client.player_pid);
            
          case Packet_Type.Connection_Closed;
            client := find_client_by_pid(server, server.connection.incoming_packet.header.sender_client_id);
            if client then handle_client_disconnect(server, client);
          
          case Packet_Type.Ping;
            client := find_client_by_pid(server, server.connection.incoming_packet.header.sender_client_id);
            if client then update_virtual_connection_information_for_packet(*client.connection, *server.connection.incoming_packet.header);
            
          case Packet_Type.Message;
            client := find_client_by_pid(server, server.connection.incoming_packet.header.sender_client_id);
            if client {
                update_virtual_connection_information_for_packet(*client.connection, *server.connection.incoming_packet.header);
                
                msg: Message = ---;
                while read_message(*server.connection, *msg) {
                    handle_incoming_message(server, *msg);
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



transition_to_state :: (server: *Server, state: Game_State) {
    server.next_state = state;
}

switch_to_next_state :: (server: *Server) {
    if #complete server.current_state == {
      case .Lobby, .Game_Over; // Ignore
      case .Ingame; destroy_world(*server.world);
    }
    
    server.current_state = server.next_state;
    
    if #complete server.current_state == {
      case .Lobby, .Game_Over, .Ingame; // Ignore
    }
}

create_the_game :: (server: *Server) {
    server.game_seed = cast(s64) os_get_hardware_time();
    seed_random_generator(*server.random, server.game_seed, server.game_seed, server.game_seed, server.game_seed);

    create_world(*server.world, *server.perm, .{ 36, 5 });

    //
    // Notify the clients about the game seed
    //
    game_start := make_message(Game_Start_Message);
    game_start.game_start.seed = server.game_seed;
    game_start.game_start.size = server.world.size;
    array_add(*server.outgoing_messages, game_start);

    //
    // Generate the base world
    //
    {
        is_blocked_position :: (server: *Server, position: v2i) -> bool {
            return position.y >= 1 && position.y <= 3 &&
                position.x >= 2 && position.x <= 2 + server.clients.count + 1;
        }

        random_position :: (server: *Server) -> v2i {
            position := v2i.{ random_u64_in(*server.random, 0, server.world.size.x), random_u64_in(*server.random, 0, server.world.size.y) };

            while get_entity_at_position(*server.world, position) != null || is_blocked_position(server, position) {
                position = .{ random_u64_in(*server.random, 0, server.world.size.x), random_u64_in(*server.random, 0, server.world.size.y) };
            }
            
            return position;
        }

        generate_n_random_entities :: (server: *Server, kind: Entity_Kind, n: s64) {
            for i := 0; i < n; ++i {
                create_entity(*server.world, kind, random_position(server), .North);
            }
        }

        create_entity(*server.world, .Emitter, .{ 0, 2 }, .East);
        create_entity(*server.world, .Receiver, .{ server.world.size.x - 1, 2 }, .West);
        generate_n_random_entities(server, .Bedrock, server.world.size.x * 2);
        generate_n_random_entities(server, .Rock, server.world.size.x / 4);
        generate_n_random_entities(server, .Crystal, server.world.size.x / 4);
    }
    
    //
    // Generate one entity for each player and attach it to the player
    //
    for i := 0; i < server.clients.count; ++i {
        client := array_get_pointer(*server.clients, i);
        pid, entity := create_entity(*server.world, .Player, .{ 3 + i, 2 }, .North);

        client.entity_pid = pid;
        
        msg := make_message(Player_Information_Message);
        msg.player_information.player_pid = client.player_pid;
        msg.player_information.name       = client.name;
        msg.player_information.entity_pid = client.entity_pid;
        array_add(*server.outgoing_messages, msg);            
    }

    //
    // Notify the clients about all the created entities
    //
    for i := 0; i < server.world.entities.count; ++i {
        entity := array_get_pointer(*server.world.entities, i);
        entity.created_this_frame = false;
        
        msg := make_message(Create_Entity_Message);
        msg.create_entity.entity_pid = entity.pid;
        msg.create_entity.kind       = entity.kind;
        msg.create_entity.position   = entity.physical_position;
        msg.create_entity.rotation   = entity.physical_rotation;
        array_add(*server.outgoing_messages, msg);
    }
}

do_lobby_tick :: (server: *Server) {
    read_incoming_packets(server);
    handle_client_timeouts(server);
    send_all_outgoing_messages(server);
}

do_game_tick :: (server: *Server) {
    damage :: (server: *Server, entity: *Entity, immediate_damage: f32) {
        entity.health -= immediate_damage;

        msg := make_message(Entity_Health_Message);
        msg.entity_health.entity_pid = entity.pid;
        msg.entity_health.current_health = entity.health;
        array_add(*server.outgoing_messages, msg);
    }

    game_state: enum { Keep_Going; Won; Lost; } = .Keep_Going;

    read_incoming_packets(server);
    handle_client_timeouts(server);

    //
    // Update all emitters
    //
    for i := 0; i < server.world.entities.count; ++i {
        entity := array_get_pointer(*server.world.entities, i);
        if entity.kind == .Emitter {
            // @ReduceMessages: We do a simple client-side prediction on the time_left_in_seconds,
            // so we don't have to send the value every frame, we could only send it if the rate
            // of change changed or something...

            emitter := down(entity, Emitter);
            
            previous := emitter.time_left_in_seconds;
            
            if emitter.time_left_in_seconds > 0 {
                emitter.time_left_in_seconds -= server.tick_time;
            }

            recalculate_emitter(*server.world, entity, emitter);

            if previous != emitter.time_left_in_seconds {
                msg := make_message(Emitter_State_Message);
                msg.emitter_state.entity_pid = entity.pid;
                msg.emitter_state.time_left_in_seconds = emitter.time_left_in_seconds;
                array_add(*server.outgoing_messages, msg);
            }

            if emitter.time_left_in_seconds <= 0 {
                game_state = .Lost;
            }
        }
    }
    
    //
    // Update all receivers
    //
    for i := 0; i < server.world.entities.count; ++i {
        entity := array_get_pointer(*server.world.entities, i);
        if entity.kind == .Receiver {
            receiver := down(entity, Receiver);
            
            // @ReduceMessages: We do a simple client-side prediction on the progress_time_in_seconds,
            // so we don't have to send the value every frame, we could only send it if the rate
            // of change changed or something...
            previous := receiver.progress_time_in_seconds;
            
            if is_emitter_field_at(*server.world, entity.physical_position) {
                receiver.progress_time_in_seconds = clamp(receiver.progress_time_in_seconds + server.tick_time, 0, RECEIVER_TIME_TO_CHARGE);
            } else {
                receiver.progress_time_in_seconds = clamp(receiver.progress_time_in_seconds - server.tick_time, 0, RECEIVER_TIME_TO_CHARGE);
            }

            if receiver.progress_time_in_seconds != previous {
                msg := make_message(Receiver_State_Message);
                msg.receiver_state.entity_pid = entity.pid;
                msg.receiver_state.progress_time_in_seconds = receiver.progress_time_in_seconds;
                array_add(*server.outgoing_messages, msg);
            }

            if receiver.progress_time_in_seconds >= RECEIVER_TIME_TO_CHARGE {
                game_state = .Won;
            }
        }
    }

    //
    // Update each player
    //
    player_index := 0; // nocheckin
    number_of_dead_players := 0;
    
    for i := 0; i < server.world.entities.count; ++i {
        entity := array_get_pointer(*server.world.entities, i);
        if entity.kind == .Player {
            player := down(entity, Player);

            // nocheckin
            // if player_index == number_of_dead_players then damage(server, entity, server.tick_time);
            ++player_index;
            
            if entity.health > 0 {
                look_vector := vector_from_direction(player.aim_direction);
                player.target_position = .{ entity.physical_position.x + look_vector.x, entity.physical_position.y + look_vector.y };
                
                if player.state == {
                  case .Digging;
                    target_entity := get_entity_at_position(*server.world, player.target_position);
                    damage(server, target_entity, PLAYER_DPS * server.tick_time);
                    
                    if target_entity.health <= 0 {
                        target_entity.marked_for_removal = true;

                        // Generate the resource drop from the farmed entity
                        if target_entity.kind == {
                            case .Crystal; create_entity(*server.world, .Shard, target_entity.physical_position, .North);
                            case .Rock; create_entity(*server.world, .Stone, target_entity.physical_position, .North);
                        }

                        player.state = .Idle;
                    }
                }
            } else {
                player.state = .Dead;
                ++number_of_dead_players;
            }
            
            msg := make_message(Player_State_Message);
            msg.player_state.entity_pid = entity.pid;
            msg.player_state.state = player.state;
            msg.player_state.target_position = player.target_position;
            msg.player_state.carrying_item = player.carrying_item;
            array_add(*server.outgoing_messages, msg);
        }
    }

    if number_of_dead_players == server.clients.count {
        game_state = .Lost;
    }
    
    //
    // Figure out all updates this frame
    //
    for i := 0; i < server.world.entities.count; ++i {
        entity := array_get_pointer(*server.world.entities, i);
        if entity.created_this_frame && !entity.marked_for_removal {
            msg := make_message(Create_Entity_Message);
            msg.create_entity.entity_pid = entity.pid;
            msg.create_entity.kind       = entity.kind;
            msg.create_entity.position   = entity.physical_position;
            msg.create_entity.rotation   = entity.physical_rotation;
            array_add(*server.outgoing_messages, msg);
            entity.created_this_frame = false;
        } else if entity.moved_this_frame {
            msg := make_message(Move_Entity_Message);
            msg.move_entity.entity_pid = entity.pid;
            msg.move_entity.position   = entity.physical_position;
            msg.move_entity.rotation   = entity.physical_rotation;
            array_add(*server.outgoing_messages, msg);
            entity.moved_this_frame = false;
        } else if entity.marked_for_removal {
            msg := make_message(Destroy_Entity_Message);
            msg.destroy_entity.entity_pid = entity.pid;
            array_add(*server.outgoing_messages, msg);
        }
    }

    if game_state != .Keep_Going {
        msg := make_message(Game_Over_Message);
        msg.game_over.you_won = game_state == .Won;
        array_add(*server.outgoing_messages, msg);
        transition_to_state(server, .Game_Over);
        logprint(.Debug, "Game Over!");
    }

    //
    // Send all updates to clients.
    //
    send_all_outgoing_messages(server);
    
    //
    // Finally actually delete all marked entities
    //
    remove_all_marked_entities(*server.world);
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
    create_memory_pool(*server.perm_pool, 32 * Memory_Unit.Megabytes, 128 * Memory_Unit.Kilobytes);
    server.perm = allocator_from_memory_pool(*server.perm_pool);
    server.clients.allocator = *server.perm;
    server.outgoing_messages.allocator = *temp;

    if create_server_connection(*server.connection, .UDP, data.requested_port) == .Success {
        atomic_store(cast(*s64) *data.state, Server_State.Running);
    } else {
        atomic_store(cast(*s64) *data.state, Server_State.Closing);
    }
    
    server.current_state = .Count;
    server.next_state    = .Count;
    server.client_pid_counter = 1;
    
    logprint(.Debug, "Started the server.");
    
    transition_to_state(*server, .Lobby);
    switch_to_next_state(*server);
    
    while atomic_load(cast(*s64) *data.state) == Server_State.Running {
        tick_start := os_get_hardware_time();

        server.tick_time = 1 / TICK_RATE;
        
        //
        // Update the current state
        //
        if #complete server.current_state == {
          case .Lobby; do_lobby_tick(*server);
          case .Ingame; do_game_tick(*server);
          case .Game_Over;
        }

        if server.current_state != server.next_state switch_to_next_state(*server);

        release_temp_allocator(0);
        
        tick_end := os_get_hardware_time();
        os_sleep_to_tick_rate(tick_start, tick_end, TICK_RATE);
    }

    transition_to_state(*server, .Count); // Shut down all resources that might currently be in use
    
    atomic_store(cast(*s64) *data.state, Server_State.Closing);
    
    destroy_connection(*server.connection);
    array_clear(*server.clients);
    destroy_temp_allocator();

    logprint(.Debug, "Stopped the server.");
    
    atomic_store(cast(*s64) *data.state, Server_State.Closed);

    return 0;
}

main :: () -> u32 {
    data: Shared_Server_Data;
    data.requested_port = 9876;
    return server_entry_point(*data);
}
