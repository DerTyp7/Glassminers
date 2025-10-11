/* --------------------------------------------- Message Handling --------------------------------------------- */

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

send_all_outgoing_messages :: (server: *Server) {
    for j := 0; j < server.clients.count; ++j {
        client := array_get_pointer(*server.clients, j);
        send_reliable_messages(*client.connection, *server.outgoing_messages);
    }
    
    array_clear_without_deallocation(*server.outgoing_messages);    
}

handle_incoming_message :: (server: *Server, msg: *Message) {
    if #complete msg.msg_type == {
      case .Client_Disconnect, .Game_Start, .Game_Over, .Game_Score, .Player_Stat, .Global_Stat, .World_Resize, .Create_Entity, .Destroy_Entity, .Move_Entity, .Entity_Health, .Guy_State, .Emitter_State, .Item_Stack_State, .Torch_State, .Frog_State, .Goblin_State, .Slime_State, .Void_Eye_State; // Ignore

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

      case .Request_Game_Forfeit;
        client := find_client_by_pid(server, msg.request_game_forfeit.client_pid);
        client.requested_game_forfeit = true;

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



/* ------------------------------------------------ Lobby Tick ------------------------------------------------ */

do_lobby_tick :: (server: *Server) {
    read_incoming_packets(server);
    handle_client_timeouts(server);
}



/* ------------------------------------------------- Game Tick ------------------------------------------------ */

create_the_game :: (server: *Server) {
    reset_allocator(*server.world_allocator);
    create_entity_manager(server);
    reset_all_statistics(server);
    increment_global_statistic(server, .Sections_Reached);

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

setup_initial_chest_inventory :: (server: *Server) -> Item_Inventory {
    inventory: Item_Inventory = ---;

    if server.game_mode == {
      case .Easy;   inventory = .{ 6, .[ .Coin, .Coin, .Shard, .Shard, .Coal, .Coal, ---, --- ] };
      case .Medium; inventory = .{ 3, .[ .Coin, .Shard, .Coal, ---, ---, ---, ---, --- ] };
      case .Hard;   inventory = .{ 1, .[ random_one_of(*server.entity_random, .[ Item_Kind.Shard, Item_Kind.Coal, Item_Kind.Coin ]), ---, ---, ---, ---, ---, ---, --- ] };
      case; inventory = .{ };
    }

    return inventory;
}

position_in_bounds :: (server: *Server, position: v2i) -> bool {
    return position.x >= 0 && position.x < server.world_size.x && position.y >= 0 && position.y < server.world_size.y;
}

is_emitter_beam_at :: (server: *Server, position: v2i) -> bool, *Emitter, Direction {
    for i := 0; i < server.emitters.slot_count; ++i {
        emitter, occupied := index_bucket_array(*server.emitters, i);
        if !occupied || emitter.state == .Off continue;

        for j := 0; j < emitter.beam_data.fields.count; ++j {
            field := array_get(*emitter.beam_data.fields, j);
            if field.x == position.x && field.y == position.y return true, emitter, field.incoming_direction;
        }
    }
    
    return false, ---, ---;
}

// This will first try to put the item on the ground, and if that doesn't work it'll try to
// place the item inside the guy's hand. The target_guy might be standing away from the target
// position. This could be interesting for cases where they destruct a mirror, and under the
// mirror is already a coin item
try_to_place_item :: (server: *Server, target_position: v2i, kind: Item_Kind, source_guy: *Guy, target_guy: *Guy) -> bool {
    if !position_in_bounds(server, target_position) return false;

    place_stack_on_ground :: () #macro {
        stack_entity := create_entity(server, .Item_Stack, target_position, .North);
        stack := down(stack_entity, Item_Stack);
        stack.item_kind = kind;
        stack.count = 1;

        msg := make_message(Item_Stack_State_Message);
        msg.item_stack_state.entity_pid = stack.pid;
        msg.item_stack_state.item_kind  = stack.item_kind;
        msg.item_stack_state.count      = stack.count;
        array_add(*server.outgoing_messages, msg);
    }

    place_flag_on_ground :: () #macro {
        flag_entity := create_entity(server, .Flag, target_position, .North);
        server.flag_pid = flag_entity.pid;

        new_score := target_position.x + 1;

        if new_score > server.game_score {
            server.game_score = new_score;
            msg := make_message(Game_Score_Message);
            msg.game_score.score = server.game_score;
            array_add(*server.outgoing_messages, msg);
        }
    }

    place_chest_on_ground :: () #macro {
        chest_entity := create_entity(server, .Chest, target_position, .North);
        
        if source_guy && source_guy.state == .Carrying && source_guy.carrying_item == .Chest {
            chest := down(chest_entity, Chest);
            chest.inventory = source_guy.carrying_item_data.chest_inventory;
            broadcast_chest_inventory(server, chest);
        }
    }

    place_torch_on_ground :: () #macro {
        torch_entity := create_entity(server, .Torch, target_position, .North);
        if source_guy {
            torch := down(torch_entity, Torch);
            set_torch_time_left_in_seconds(server, torch, source_guy.carrying_item_data.torch_time_left_in_seconds);
        }
    }

    internal_placing_logic :: (server: *Server, target_position: v2i, kind: Item_Kind, source_guy: *Guy) -> bool {
        //
        // Turns out the placement logic for items is actually pretty complex (or to be fair I wanted it to be this
        // complex). Here's a little diagram of the logic:
        //
        // vv ON GROUND || IN HAND >>	Resource	                Torch	                Flag	                Chest
        // Stack                    	If Same (Not On Ground)	    No	                    Yes	                    Yes
        // Chest	                    Inside (Not On Ground)	    No                      No	                    No
        // Guy	                        In Hand (Not On Ground)	    In Hand (On Ground)	    In Hand (On Ground)	    In Hand (Not On Ground)
        // Hole	                        No	                        No	                    Yes	                    Yes
        // Torch	                    No	                        No	                    Yes	                    Yes
        // Flag	                        Yes	                        Yes	                    No	                    No
        // Blocking (Non Guy / Chest)	No	                        No	                    No	                    No
        // Empty	                    Yes	                        Yes	                    Yes	                    Yes
        //
        // As it is so "arbitrary", we unfortunately need this monster of a function.
        //
     
        stack_entity := find_entity_of_kind_at_position(server, .Item_Stack, target_position);
        chest_entity := find_entity_of_kind_at_position(server, .Chest, target_position);
        guy_entity   := find_entity_of_kind_at_position(server, .Guy, target_position);
        hole_entity  := find_entity_of_kind_at_position(server, .Slime_Hole, target_position);
        torch_entity := find_entity_of_kind_at_position(server, .Torch, target_position);
        flag_entity  := find_entity_of_kind_at_position(server, .Flag, target_position);
        move_blocking_entity := find_entity_with_flags_at_position(server, .Blocks_Movement, target_position);
        
        if move_blocking_entity && (move_blocking_entity.entity_kind == .Guy || move_blocking_entity.entity_kind == .Chest) {
            // These kinds of move-blocking entities are handled as a special case here, so ignore them.
            // We only care about move blocking entities that should block *items* from being put on them,
            // which is kind-of a different thing, but I don't want to create *another* entity flag just for
            // that...
            move_blocking_entity = null;
        }

        if move_blocking_entity {
            // Any move blocking entity for which there's no special handling completely blocks placing
            // down an item.    
            return false;
        }
        
        if guy_entity {
            guy := down(guy_entity, Guy);
            if guy.state == .Idle {
                put_item_in_hand(server, guy, kind);
                if source_guy {
                    guy.carrying_item_data.chest_inventory = source_guy.carrying_item_data.chest_inventory;
                } else {
                    guy.carrying_item_data.chest_inventory.item_count = 0;
                }
                return true;
            }
        }
        
        if chest_entity {
            chest := down(chest_entity, Chest);
            if kind != .Flag && kind != .Chest && kind != .Torch && chest.item_count < chest.item_kinds.Capacity {
                chest.item_kinds[chest.item_count] = kind;
                ++chest.item_count;
                broadcast_chest_inventory(server, chest);
                return true;
            }
        }

        if stack_entity {
            stack := down(stack_entity, Item_Stack);
            if stack.item_kind == kind && stack.count < PHYSICAL_ITEM_STACK_CAPACITY {
                ++stack.count;

                msg := make_message(Item_Stack_State_Message);
                msg.item_stack_state.entity_pid = stack.pid;
                msg.item_stack_state.item_kind  = stack.item_kind;
                msg.item_stack_state.count      = stack.count;
                array_add(*server.outgoing_messages, msg);
                return true;
            }
        }

        if kind == {
          case .Torch;
            if !stack_entity && !chest_entity && !hole_entity && !torch_entity {
                place_torch_on_ground();
                return true;
            }

          case .Flag;
            if !chest_entity && !flag_entity {
                place_flag_on_ground();
                return true;
            }
        
          case .Chest;
            if !chest_entity && !guy_entity && !flag_entity {
                place_chest_on_ground();
                return true;
            }

          case;
            if !stack_entity && !chest_entity && !guy_entity && !hole_entity && !torch_entity {
                place_stack_on_ground();
                return true;
            }
        }

        return false;
    }

    success := internal_placing_logic(server, target_position, kind, source_guy);

    if !success && target_guy && target_guy.state == .Idle {
        //
        // If we couldn't place the item onto the target position, try putting it directly
        // into the target guy's hand (if there is a target guy...)
        // This can for example happen when mining a mirror, but there's already an item stack on
        // that tile.
        //
        put_item_in_hand(server, target_guy, kind);
        success = true;
    }
    
    return success;
}

do_game_tick :: (server: *Server) {
    read_incoming_packets(server);
    handle_client_timeouts(server);

    game_result: Game_Result = .Unfinished_Game;

    if !server.game_paused {
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

        for i := 0; i < server.torches.slot_count; ++i {
            torch, occupied := index_bucket_array(*server.torches, i);
            if occupied update_torch(server, torch);
        }
        
        //
        // Update all frogs, as their beams will be used for the lightmap calculation as well.
        //
        for i := 0; i < server.frogs.slot_count; ++i {
            frog, occupied := index_bucket_array(*server.frogs, i);
            if occupied update_frog(server, frog);
        }
        
        update_lightmap(*server.lightmap, *server.em, server.tick_time);
        calculate_shadows(*server.lightmap, *temp);

        for i := 0; i < server.slabs.slot_count; ++i {
            slab, occupied := index_bucket_array(*server.slabs, i);
            if occupied update_slab(server, slab);
        }

        for i := 0; i < server.goblins.slot_count; ++i {
            goblin, occupied := index_bucket_array(*server.goblins, i);
            if occupied update_goblin(server, goblin);
        }

        for i := 0; i < server.slimes.slot_count; ++i {
            slime, occupied := index_bucket_array(*server.slimes, i);
            if occupied update_slime(server, slime);
        }

        manage_void_eye_lifetimes(server);
        
        for i := 0; i < server.void_eyes.slot_count; ++i {
            eye, occupied := index_bucket_array(*server.void_eyes, i);
            if occupied update_void_eye(server, eye);
        }
        
        all_guys_dead := true;

        for i := 0; i < server.guys.slot_count; ++i {
            guy, occupied := index_bucket_array(*server.guys, i);
            if !occupied continue;

            if guy.state != .Dead {
                for input_index := 0; input_index < guy.received_inputs_count; ++input_index {
                    handle_guy_input(server, guy, *guy.received_inputs[input_index]);
                }
            }
            guy.received_inputs_count = 0;

            update_guy(server, guy);

            all_guys_dead &= guy.state == .Dead;
        }

        for i := 0; i < server.all_entities.slot_count; ++i {
            entity, occupied := index_bucket_array(*server.all_entities, i);
            if !occupied continue;

            if entity.entity_kind == {
              case .Trader; update_trader(server, entity);
              case .Rock, .Coal, .Crystal, .Mirror, .Item_Stack, .Chest, .Flag; remove_if_in_lava(server, entity);
            }

            if entity.entity_flags & .Auto_Heal && !entity.damaged_this_frame {
                set_entity_health(server, entity, entity.health + HEALTH_PER_HEART * server.tick_time);
            }
            
            entity.damaged_this_frame = false;
        }

        //
        // Check for game over scenarios
        //
        if all_guys_dead {
            game_result = .All_Players_Died;
        }

        if !entity_exists(server, server.flag_pid) && !is_any_guy_carrying_the_flag(server) {
            // This means that the flag is not currently carried by any player, but it no longer
            // physically exists, which can only mean it got killed (e.g. by lava or whatever).
            game_result = .Flag_Was_Destroyed;
        }

        if server.game_mode == .Tutorial && generate_next_section && server.current_section_index + 1 >= count_sections_in_predefined_world(server.game_mode) {
            game_result = .Completed_Tutorial;
        }

        if server.game_mode == .Developer && generate_next_section && server.current_section_index + 1 >= count_sections_in_predefined_world(server.game_mode) {
            generate_next_section = false;
        }

        //
        // Progress through the world
        //
        if generate_next_section {
            increment_global_statistic(server, .Sections_Reached);
            generate_next_world_section(server);
        }
    } 
    
    //
    // Check if all players disconnected or forfeited
    //
    {
        all_clients_forfeited := true;

        for i := 0; i < server.clients.count; ++i {
            client := array_get(*server.clients, i);
            all_clients_forfeited &= client.requested_game_forfeit;
        }

        if all_clients_forfeited then game_result = .All_Players_Forfeited;
    }

    //
    // If the game is over, transition the state
    //
    if game_result != .Unfinished_Game {
        msg := make_message(Game_Over_Message);
        msg.game_over.score  = server.game_score;
        msg.game_over.result = game_result;
        msg.game_over.player_stat_kind, msg.game_over.player_stat_guy_pid, msg.game_over.player_stat = find_game_over_player_stat(server);
        msg.game_over.global_stat_kind, msg.game_over.global_stat = find_game_over_global_stat(server);

        array_add(*server.outgoing_messages, msg);
        server.next_state = .Game_Over;
    }
    
    //
    // Finally actually delete all marked entities
    //
    physically_remove_dead_entities(server);
}



#file_scope

is_any_guy_carrying_the_flag :: (server: *Server) -> bool {
    found_the_flag := false;

    for i := 0; i < server.guys.slot_count; ++i {
        guy, occupied := index_bucket_array(*server.guys, i);
        if occupied && guy.state == .Carrying && guy.carrying_item == .Flag {
            found_the_flag = true;
            break;
        }
    }

    return found_the_flag;
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
            take_item_from_hand(server, guy);
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

handle_guy_movement :: (server: *Server, guy: *Guy, input: *Guy_Input_Message) {
    if !input.wants_to_move return;

    distance_to_move := abs(input.position.x - guy.physical_position.x) + abs(input.position.y - guy.physical_position.y); // This can be violated if the guy got moved by something else during this tick...
    if distance_to_move != 1 {
        update_physical_location(server, guy, guy.physical_position, input.aim_direction);
        return;
    }

    is_in_ghost_mode := false;
    #if DEVELOPER { 
        is_in_ghost_mode = guy.ghost_mode;
    }

    if is_in_ghost_mode {
        // Bypass checks and recursive move routine
        if position_in_bounds(server, input.position) {
            update_physical_location(server, guy, input.position, input.aim_direction);
        }
    } else if can_move_to_position(server, guy, input.position, GUY_PUSH_STRENGTH) {
        // Rotate and move to the target position by recursively pushing things
        guy.physical_rotation = input.aim_direction;
        move_to_position(server, guy, input.position);
        increment_player_statistic(server, guy.pid, .Moves);
    } else {
        // If we can't move to the position then at least update the rotation
        update_physical_location(server, guy, guy.physical_position, input.aim_direction);
    }
}

handle_guy_input :: (server: *Server, guy: *Guy, input: *Guy_Input_Message) {
    handle_guy_movement(server, guy, input);
    
    //
    // Handle interaction
    //
    if #complete input.interaction_kind == {
      case .Primary_Start;
        target_entity := find_any_entity_at_position(server, guy.target_position);

        if #complete guy.state == {
          case .Dead, .Resurrecting, .Digging;
            
          case .Idle;
            if !target_entity break;

            if target_entity.entity_kind == {
              case .Guy;
                other_guy := down(target_entity, Guy);
                if other_guy.state == .Dead {
                    guy.resurrection_pid = other_guy.pid;
                    guy.resurrection_t = 0;
                    switch_guy_state(server, guy, .Resurrecting);
                }

              case .Item_Stack;                
                put_item_in_hand(server, guy, take_item_from_stack(server, down(target_entity, Item_Stack)));

              case .Torch;
                torch := down(target_entity, Torch);
                guy.carrying_item_data.torch_time_left_in_seconds = torch.time_left_in_seconds;
                put_item_in_hand(server, guy, .Torch);
                remove_entity(server, target_entity);

              case .Flag;
                put_item_in_hand(server, guy, .Flag);
                remove_entity(server, target_entity);
                server.flag_pid = INVALID_PID;

              case .Chest;
                chest := down(target_entity, Chest);
                guy.carrying_item_data.chest_inventory = chest.inventory;
                put_item_in_hand(server, guy, .Chest);
                remove_entity(server, target_entity);

              case;
                if target_entity.entity_flags & .Diggable {
                    switch_guy_state(server, guy, .Digging);
                }
            }
            
          case .Carrying;
            if target_entity && target_entity.entity_kind == .Emitter && guy.carrying_item == .Coal {
                // Edge-Case: Charge the emitter using the coal
                emitter := down(target_entity, Emitter);
                if emitter.state == .Active {
                    set_emitter_state(server, emitter, .Active, emitter.current_charge + COAL_EMITTER_CHARGE);
                    take_item_from_hand(server, guy);
                    increment_player_statistic(server, guy.pid, .Emitter_Charges);
                }
            } else if target_entity && target_entity.entity_kind == .Emitter && guy.carrying_item == .Flag {
                // Edge-Case: Activate the emitter using the flag
                target_emitter := down(target_entity, Emitter);
                if target_emitter.state == .Off && target_emitter.current_charge >= EMITTER_MAX_CHARGE[server.game_mode] {
                    set_emitter_state(server, target_emitter, .Active, target_emitter.current_charge);
                }
            } else if target_entity && target_entity.entity_kind == .Lava && guy.carrying_item == .Stone {
                // Edge-Case: Create a slab on lava
                remove_entity(server, target_entity);
                create_entity(server, .Slab, guy.target_position, .North);
                take_item_from_hand(server, guy);
            } else if try_to_place_item(server, guy.target_position, guy.carrying_item, guy, null) {
                // Try to place down the item that is currently being held.
                take_item_from_hand(server, guy);
            }
        }

      case .Primary_End;
        if guy.state == .Digging || guy.state == .Resurrecting {
            switch_guy_state(server, guy, .Idle);
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
    if input.crafting_recipe != .Count {
        if try_to_fulfill_recipe(server, guy, input.crafting_recipe) {
            // @Cleanup: We're currently manually tracking the stats for the coins here when interacting with
            // the trader. I would like to read that out from the crafting recipe basically to make it
            // more robust.

            if #complete input.crafting_recipe == {
              /* Crafting Hud */
              case .Mirror;
                create_entity(server, .Mirror, guy.target_position, .North);
                increment_player_statistic(server, guy.pid, .Mirrors_Constructed);
              case .Torch;
                put_item_in_hand(server, guy, .Torch);
                guy.carrying_item_data.torch_time_left_in_seconds = TORCH_TIME_TO_LIVE;
              case .Chest;  create_entity(server, .Chest, guy.target_position, .North);
              
              /* Trader Hud */              
              case .Health_Potion;
                set_entity_health(server, guy, guy.health + HEALTH_PER_HEART);
                increment_player_statistic(server, guy.pid, .Coins_Spent_Total);
                increment_player_statistic(server, guy.pid, .Coins_Spent_Healing);
              case .Strength_Potion;
                start_strength_effect(server, guy);
                increment_player_statistic(server, guy.pid, .Coins_Spent_Total);
              case .Shard;
                put_item_in_hand(server, guy, .Shard);
                increment_player_statistic(server, guy.pid, .Coins_Spent_Total);
              case .Coal;
                put_item_in_hand(server, guy, .Coal);
                increment_player_statistic(server, guy.pid, .Coins_Spent_Total);
            }
        }
    }

    //
    // Handle taking items from a chest
    //
    if input.chest_item != .Count && guy.state == .Idle {
        target_entity := find_entity_of_kind_at_position(server, .Chest, guy.target_position);
        if target_entity {
            chest := down(target_entity, Chest);
            if try_to_take_item_from_chest(server, chest, input.chest_item) {
                put_item_in_hand(server, guy, input.chest_item);
            }
        }
    }
    
    //
    // Handle cheating
    //
#if DEVELOPER {
    spawn_creature_with_cheat :: (server: *Server, guy: *Guy, kind: Entity_Kind) {
        if !find_any_entity_at_position(server, guy.target_position) {
            create_entity(server, kind, guy.target_position, DEFAULT_ENTITY_ROTATION[kind]);
        }
    }
    
    if #complete input.cheat == {
      case .Give_Coin; try_to_give_item(server, guy, .Coin);
      case .Give_Coal; try_to_give_item(server, guy, .Coal);
      case .Give_Shard; try_to_give_item(server, guy, .Shard);
      case .Give_Stone; try_to_give_item(server, guy, .Stone);
      case .Give_Health; set_entity_health(server, guy, DEFAULT_ENTITY_HEALTH[.Guy]);
      case .Give_Strength; start_strength_effect(server, guy);
      case .Spawn_Goblin; spawn_creature_with_cheat(server, guy, .Goblin);
      case .Spawn_Frog; spawn_creature_with_cheat(server, guy, .Frog);
      case .Spawn_Slime; spawn_creature_with_cheat(server, guy, .Slime);
      case .Spawn_Trader; spawn_creature_with_cheat(server, guy, .Trader);
      case .Toggle_Invincibility; guy.invincible = !guy.invincible;
	  case .Toggle_GhostMode; guy.ghost_mode = !guy.ghost_mode;
	  case .Remove_Entity; 
        for i := 0; i < server.all_entities.slot_count; ++i {
            entity, occupied := index_bucket_array(*server.all_entities, i);
            if occupied && entity.physical_position.x == guy.target_position.x && entity.physical_position.y == guy.target_position.y then remove_entity(server, entity);
        }
        
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

manage_void_eye_lifetimes :: (server: *Server) {
    //
    // Remove all void eyes that are outside a shadow, and count how many void eyes are in each shadow
    //
    void_eyes_per_shadow := allocate_slice(*temp, s64, server.lightmap.shadow_sizes.count);
    clear_slice(void_eyes_per_shadow); // @Cleanup: Apparently the temp allocator isn't guaranteed to zero-initialize?

    for i := 0; i < server.void_eyes.slot_count; ++i {
        eye, occupied := index_bucket_array(*server.void_eyes, i);
        if !occupied then continue;

        shadow := query_shadow(*server.lightmap, eye.physical_position);
        if shadow != NO_SHADOW {
            set_entity_health(server, eye, eye.health + VOID_EYE_HPS_IN_DARKNESS * server.tick_time);
            void_eyes_per_shadow[shadow] += 1;
        } else {
            damage_and_maybe_kill_entity(server, eye, VOID_EYE_DPS_IN_BRIGHTNESS * server.tick_time);
        }
    }

    //
    // Spawn a new void eye in each shadow that doesn't have one yet
    //
    if server.void_eyes_spawn_cooldown <= 0 {
        server.void_eyes_spawn_accumulator += server.tick_time * VOID_EYE_SPAWN_RATE * cast(f32) server.world_size.x;
        void_eyes_to_spawn_this_tick       := cast(s64) floor(server.void_eyes_spawn_accumulator);
        server.void_eyes_spawn_accumulator -= xx void_eyes_to_spawn_this_tick;

        for i := 0; void_eyes_to_spawn_this_tick > 0 && i < void_eyes_per_shadow.count; ++i {
            shadow_size := array_get(*server.lightmap.shadow_sizes, i);

            if (void_eyes_per_shadow[i] == 0 && shadow_size >= MIN_SHADOW_SIZE_FOR_VOID_EYE) ||
               void_eyes_per_shadow[i] < shadow_size / SHADOW_SIZE_PER_VOID_EYE {
                position := get_random_position_in_shadow(*server.lightmap, i);
                create_entity(server, .Void_Eye, position, DEFAULT_ENTITY_ROTATION[.Void_Eye]);
                --void_eyes_to_spawn_this_tick;
            }
        }
    } else {
        server.void_eyes_spawn_cooldown -= server.tick_time;
    }
}

// This will first try to put the item inside the guy's hand, and if that doesn't work it'll try to
// place the item on the ground
try_to_give_item :: (server: *Server, guy: *Guy, kind: Item_Kind) {
    if guy.state == .Idle {
        put_item_in_hand(server, guy, kind);
    } else {
        try_to_place_item(server, guy.physical_position, kind, guy, null);
    }
}

try_to_take_item_from_chest :: (server: *Server, chest: *Chest, kind: Item_Kind) -> bool {
    for i := 0; i < chest.item_count; ++i {
        if chest.item_kinds[i] == kind {
            if i + 1 < chest.item_count copy_memory(*chest.item_kinds[i], *chest.item_kinds[i + 1], (chest.item_count - i - 1) * size_of(Item_Kind));
            --chest.item_count;
            broadcast_chest_inventory(server, chest);            
            return true;
        }
    }

    return false;
}
