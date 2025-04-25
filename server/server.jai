// Prometheus modules
#load "basic.jai";
#load "virtual_connection.jai";

// Shared
#load "../shared/messages.jai";
#load "../shared/world.jai";
#load "../shared/shared.jai";

// Server
#load "world.jai";

TICK_RATE: f32 : 60;

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

    //
    // Networking
    //
    connection: Virtual_Connection;
    clients: [..]Remote_Client;
    incoming_messages: [..]Message;
    outgoing_messages: [..]Message;
    client_pid_counter: Pid;

    //
    // Game Data
    //
    game_seed: s64;
    world: World;
    frame_time: f32;
}

logprint :: (format: string, args: ..Any) {
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

handle_connection_request :: (server: *Server) {
    if server.current_state != .Lobby return; // If we aren't in the lobby, don't accept new clients

    // Check if we already have a client connected at this remote, because the client will spam
    // this connection request a few times to combat potential packet loss.
    for i := 0; i < server.clients.count; ++i {
        connected_client := array_get_pointer(*server.clients, i);
        if remote_sockets_equal(*server.connection.remote, *connected_client.connection.remote) {
            return;
        }
    }

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
    
    logprint("Connected to client '%'.", client.player_pid);
}

handle_connection_closed :: (server: *Server) {
    for i := 0; i < server.clients.count; ++i {
        client := array_get_pointer(*server.clients, i);
        if client.player_pid == server.connection.incoming_packet.header.sender_client_id {
            logprint("Disconnected from client '%'.", client.player_pid);

            // @Cleanup: We should probably also remove the entity here...
            
            msg := make_message(Player_Disconnect_Message);
            msg.player_disconnect.player_pid = client.player_pid;
            array_add(*server.outgoing_messages, msg);
            
            if client.name deallocate_string(*server.perm, *client.name);
            
            array_remove_index(*server.clients, i);
            break;
        }
    }
}

send_all_outgoing_messages :: (server: *Server) {
    for j := 0; j < server.clients.count; ++j {
        client := array_get_pointer(*server.clients, j);
        for i := 0; i < server.outgoing_messages.count; ++i {
            send_reliable_message(*client.connection, array_get_pointer(*server.outgoing_messages, i));
        }
    }
    
    array_clear_without_deallocation(*server.outgoing_messages);    
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
    generate_world(*server.world, server.game_seed);

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
    //
    // Handle all incoming messages on player information and game info
    //
    for i := 0; i < server.incoming_messages.count; ++i {
        msg := array_get_pointer(*server.incoming_messages, i);

        if msg.type == {
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
        }    
    }

    //
    // Send all updates to clients.
    //
    send_all_outgoing_messages(server);
}

do_game_tick :: (server: *Server) {
    game_state: enum { Keep_Going; Won; Lost; } = .Keep_Going;

    //
    // Handle all incoming messages on player input
    //
    for i := 0; i < server.incoming_messages.count; ++i {
        msg := array_get_pointer(*server.incoming_messages, i);
        
        if msg.type == {
          case .Move_Entity;
            entity := get_entity(*server.world, msg.move_entity.entity_pid);
            
            move_delta := v2i.{ msg.move_entity.position.x - entity.physical_position.x, msg.move_entity.position.y - entity.physical_position.y };
            
            if can_move_to_position(*server.world, entity, msg.move_entity.position) {
                move_to_position(*server.world, entity, msg.move_entity.position);
            }
            
            if entity.kind == .Player {
                player := down(entity, Player);
                player.aim_direction = direction_from_vector(move_delta);

                // Cancel the current action of the player when moving, if appropriate
                if #complete player.state == {
                  case .Idle, .Carrying;
                  case .Digging;
                    player.state = .Idle;
                    player.progress_time_in_seconds = 0;
                }
            }
            
          case .Player_Interact;
            entity := get_entity(*server.world, msg.player_interact.entity_pid);
            player := down(entity, Player);
            target_entity := get_entity_at_position(*server.world, player.target_position);

            if #complete msg.player_interact.interaction_kind == {            
              case .Primary;
                if player.state != .Idle || !target_entity break;
                
                if target_entity.kind == {
                    // @Incomplete: Allow desruction of built mirrors
                  case .Bedrock, .Crystal, .Rock;
                    player.state = .Digging;
                    player.progress_time_in_seconds = 0;
                  case .Shard, .Stone;
                    player.state = .Carrying;
                    player.carrying_item = target_entity.kind;
                    target_entity.marked_for_removal = true;
                }
                
              case .Secondary;
                if target_entity == null {
                    // Place a new entity
                    if #complete player.state == {
                      case .Digging;
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

    //
    // Recalculate all emitters
    //
    recalculate_emitters(*server.world);

    //
    // Update all receivers
    //
    for i := 0; i < server.world.entities.count; ++i {
        entity := array_get_pointer(*server.world.entities, i);
        if entity.kind == .Receiver {
            receiver := down(entity, Receiver);
            
            previous := receiver.progress_time_in_seconds;
            
            if is_emitter_field_at(*server.world, entity.physical_position) {
                receiver.progress_time_in_seconds = clamp(receiver.progress_time_in_seconds + server.frame_time, 0, RECEIVER_TIME);
            } else {
                receiver.progress_time_in_seconds = clamp(receiver.progress_time_in_seconds - server.frame_time, 0, RECEIVER_TIME);
            }

            if receiver.progress_time_in_seconds != previous {
                msg := make_message(Receiver_State_Message);
                msg.receiver_state.entity_pid = entity.pid;
                msg.receiver_state.progress_time_in_seconds = receiver.progress_time_in_seconds;
                array_add(*server.outgoing_messages, msg);
            }

            if receiver.progress_time_in_seconds >= RECEIVER_TIME {
                game_state = .Won;
            }
        }
    }

    //
    // Update each player's target position
    //
    for i := 0; i < server.world.entities.count; ++i {
        entity := array_get_pointer(*server.world.entities, i);
        if entity.kind == .Player {
            player := down(entity, Player);
            
            look_vector := vector_from_direction(player.aim_direction);
            player.target_position = .{ entity.physical_position.x + look_vector.x, entity.physical_position.y + look_vector.y };
            
            if player.state == {
              case .Digging;
                target_entity := get_entity_at_position(*server.world, player.target_position);
                player.progress_time_in_seconds += server.frame_time;
                if player.progress_time_in_seconds >= DIGGING_TIMES[target_entity.kind] {
                    target_entity.marked_for_removal = true;

                    // Generate the resource drop from the farmed entity
                    if target_entity.kind == {
                      case .Crystal; create_entity(*server.world, .Shard, target_entity.physical_position, .North);
                      case .Rock; create_entity(*server.world, .Stone, target_entity.physical_position, .North);
                    }

                    player.state = .Idle;
                    player.progress_time_in_seconds = 0;
                }
            }
            
            msg := make_message(Player_State_Message);
            msg.player_state.entity_pid = entity.pid;
            msg.player_state.state = player.state;
            msg.player_state.target_position = player.target_position;
            msg.player_state.progress_time_in_seconds = player.progress_time_in_seconds;
            msg.player_state.carrying_item = player.carrying_item;
            array_add(*server.outgoing_messages, msg);
        }
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
    server.incoming_messages.allocator = *temp;
    server.outgoing_messages.allocator = *temp;

    if create_server_connection(*server.connection, .UDP, data.requested_port) == .Success {
        data.state = .Running;
    } else {
        data.state = .Closing;
    }
    
    server.current_state = .Count;
    server.next_state    = .Count;
    server.client_pid_counter = 1;
    
    logprint("Started the server.");
    
    transition_to_state(*server, .Lobby);
    switch_to_next_state(*server);
    
    while data.state == .Running {
        tick_start := os_get_hardware_time();

        server.frame_time = 1 / TICK_RATE;

        //
        // Handle connection packets and read all messages from clients.
        //
        {
            array_clear_without_deallocation(*server.incoming_messages);
            
            while read_packet(*server.connection) {
                if server.connection.incoming_packet.header.packet_type == {
                  case Packet_Type.Connection_Request;
                    handle_connection_request(*server);
                    
                  case Packet_Type.Connection_Closed;
                    handle_connection_closed(*server);
                    
                  case Packet_Type.Ping;
                    client := find_client_by_pid(*server, server.connection.incoming_packet.header.sender_client_id);
                    if client send_ping_packet(*client.connection);
                    
                  case Packet_Type.Message;
                    message := array_push(*server.incoming_messages);
                    read_message(*server.connection, message);
                }
            }
        }
        
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
    
    data.state = .Closing;
    
    destroy_connection(*server.connection);
    array_clear(*server.clients);
    destroy_temp_allocator();

    logprint("Stopped the server.");
    
    data.state = .Closed;

    return 0;
}

main :: () -> u32 {
    data: Shared_Server_Data;
    data.requested_port = 9876;
    return server_entry_point(*data);
}
