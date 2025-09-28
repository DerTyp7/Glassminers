
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

were_all_emitters_activated :: (server: *Server) -> bool {
    all_active := true;

    for i := 0; i < server.emitters.slot_count; ++i {
        emitter, occupied := index_bucket_array(*server.emitters, i);
        if occupied then all_active &= emitter.state == .Active;
    }

    return all_active;
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
            switch_guy_state(server, guy, .Idle);
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
                put_item_in_hand(server, guy, .Torch);
                remove_entity(server, target_entity);

              case .Flag;
                put_item_in_hand(server, guy, .Flag);
                remove_entity(server, target_entity);
                server.flag_pid = INVALID_PID;

              case .Chest;
                chest := down(target_entity, Chest);
                guy.carrying_chest_inventory = chest.inventory;
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
                    switch_guy_state(server, guy, .Idle);
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
                switch_guy_state(server, guy, .Idle);
            } else if try_to_place_item(server, guy.target_position, guy.carrying_item, guy, null) {
                // Try to place down the item that is currently being held.
                switch_guy_state(server, guy, .Idle);
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
            if #complete input.crafting_recipe == {
              /* Crafting Hud */
              case .Mirror; create_entity(server, .Mirror, guy.target_position, .North);
              case .Torch;  put_item_in_hand(server, guy, .Torch);
              case .Chest;  create_entity(server, .Chest, guy.target_position, .North);
              
              /* Trader Hud */              
              case .Health_Potion;   set_entity_health(server, guy, guy.health + HEALTH_PER_HEART);
              case .Strength_Potion; guy.strength_t = STRENGTH_POTION_TIME;
              case .Shard;           put_item_in_hand(server, guy, .Shard);
              case .Coal;            put_item_in_hand(server, guy, .Coal);
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
      case .Give_Strength; guy.strength_t = STRENGTH_POTION_TIME;
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
        
        number_of_dead_guys := 0;
        
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

            if guy.state == .Dead ++number_of_dead_guys;
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
        {
            number_of_players := 0;
            for i := 0; i < server.clients.count; ++i {
                number_of_players += array_get(*server.clients, i).local_player_count;
            }
            
            if number_of_dead_guys == number_of_players {
                game_result = .All_Players_Died;
            }
        }
        
        if !entity_exists(server, server.flag_pid) && !is_any_guy_carrying_the_flag(server) {
            // This means that the flag is not currently carried by any player, but it no longer
            // physically exists, which can only mean it got killed (e.g. by lava or whatever).
            game_result = .Flag_Was_Destroyed;
        }

        if server.game_mode == .Tutorial && server.current_section_index + 1 >= count_sections_in_predefined_world(server.game_mode) && were_all_emitters_activated(server) {
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
