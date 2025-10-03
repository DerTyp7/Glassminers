Camera :: struct {
    // To avoid visual artifacts when rendering pixel art, we should ensure that the textures are rendering
    // with an integer scaling onto the back buffer. Otherwise, we might get small offsets in the UVs on
    // the same row of pixels and similar things.
    // Therefore, we ensure that the tile size on screen is a multiple of 16.
    FORCE_INTEGER_TILE_SCALING :: true;

    DESIRED_MIN_VISIBLE_TILES: f32 : 6.0;

    window_aspect_ratio: f32;
    world_to_screen_coordinates: v2f;
    covered_world_area: v2f; // Always unzoomed
    zoomed_covered_world_area: v2f; // Can include zoom in developer builds
    center_in_world: v2f;
    viewport: [4]f32;

#if DEVELOPER {
    zoom: f32 = 1;
    zoom_step: f32 = 0;
}
}

screen_from_world_position :: (camera: *Camera, world: v2f) -> v2f {
    return .{ round((world.x - camera.center_in_world.x) * camera.world_to_screen_coordinates.x + (camera.viewport[2] - camera.viewport[0]) * 0.5 + camera.viewport[0]),
              round((world.y - camera.center_in_world.y) * camera.world_to_screen_coordinates.y + (camera.viewport[3] - camera.viewport[1]) * 0.5 + camera.viewport[1]) };
}

screen_from_world_size :: (camera: *Camera, world: v2f) -> v2f {
    return .{ round(world.x * camera.world_to_screen_coordinates.x), round(world.y * camera.world_to_screen_coordinates.y) };
}

screen_from_world_height :: (camera: *Camera, height: f32) -> f32 {
    return round(height * camera.world_to_screen_coordinates.y);
}

snap_camera_to_guy :: (client: *Client, local_player: *Local_Player) {
    entity := get_entity(client, local_player.guy_pid);
    update_camera(client, local_player, .{ xx entity.physical_position.x, xx entity.physical_position.y }, 1, true);
}

position_in_bounds :: (client: *Client, position: v2i) -> bool {
    return position.x >= 0 && position.x < client.world_size.x && position.y >= 0 && position.y < client.world_size.y;
}



#if DEVELOPER {
clear_message_histories :: (client: *Client) {
    client.incoming_message_history.active = 0;
    client.outgoing_message_history.active = 0;
    client.incoming_message_history.total_bytes_received = 0;
    client.outgoing_message_history.total_bytes_received = 0;
}

register_message_history :: (client: *Client, history: *Message_History, message: *Message) {
    size_in_bytes := message_size_in_bytes(message);
    history.total_bytes_received += size_in_bytes;

    if !client.message_history_paused {
        copy_memory(*history.entries[1], *history.entries[0], min(history.entries.Capacity - 1, history.active) * size_of(Message_History_Entry));
        history.active = min(history.entries.Capacity, history.active + 1);
        
        entry := *history.entries[0];
        entry.message       = ~message;
        entry.age           = 0;
        entry.size_in_bytes = size_in_bytes;
    }
}
}

request_tutorial_panel :: (client: *Client, kind: Tutorial_Panel) {
    if client.game_mode != .Tutorial return;

    already_requested := false;
    
    for i := 0; i < client.requested_tutorial_panels.count; ++i {
        requested_kind := array_get(*client.requested_tutorial_panels, i);
        if requested_kind == kind {
            already_requested = true;
            break;
        }
    }
    
    if already_requested return;
    
    array_add(*client.requested_tutorial_panels, kind);
}

crafting_recipe_should_succeed :: (client: *Client, guy: *Guy, recipe: Crafting_Recipe) -> bool { // The server is in charge here, but we'll do a heuristic for player feedback
    // Check that the target position is free if required
    if CRAFTING_RECIPE_REQUIRES_EMPTY_TARGET[recipe] && find_entity_with_flags_at_position(client, .Blocks_Crafting, guy.target_position) return false;

    // Check that the guy has the required resources available
    available_resources := get_available_resources_for_guy(client, guy);
    if !available_resources_fulfill(available_resources, CRAFTING_RECIPE_REQUIRED_ITEMS[recipe]) return false;

    return true;
}

start_the_game :: (client: *Client, game_info: Game_Start_Message) {
    client.pause_menu_open    = false;
    client.server_paused_game = false;
    client.requested_game_forfeit = false;
    client.game_seed  = game_info.seed;
    client.world_size = game_info.size;
    client.game_mode  = game_info.game_mode;
    initiate_state_transition(client, .Ingame, 0);

#if DEVELOPER  clear_message_histories(client);

    reset_stat_hud(client);

    seed_random_generator(*client.random, client.game_seed, client.game_seed, client.game_seed, client.game_seed);
    initialize_random_sounds(client);
    create_entity_manager(client);
    create_particle_manager(client);
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

    request_tutorial_panel(client, .About_Tutorial_Panels);
    recalculate_local_player_viewports(client);

    // Reset debug settings
    #if DEVELOPER {
        client.developer_panel_state = .Closed;
        client.free_camera_enabled = false;
    }
}

do_game_tick :: (client: *Client) {
    read_incoming_packets(client);
    handle_server_timeout(client, .Game_Over, "");

    if client.window.resized_this_frame recalculate_local_player_viewports(client);
    reassign_gamepad_indices(client);

    //    
    // Developer UI
    //
#if DEVELOPER { 
    if input_action_fired_globally(client, .Developer_Panel_Toggle, .Pressed) {
        client.developer_panel_state = ifx client.developer_panel_state == .Closed then .Open else .Closed;
    }

    maybe_do_developer_panel(client);

    if input_action_fired_globally(client, .Message_History_Panel_Toggle, .Pressed) {
        client.message_history_panel_state = ifx client.message_history_panel_state == .Closed then .Open else .Closed;
    }

    maybe_do_message_history_panel(client);

    if input_action_fired_globally(client, .Sound_Hud_Toggle, .Pressed) {
        client.sound_hud_enabled = !client.sound_hud_enabled;
        enable_mixer_history(*client.mixer, 128, 2);
    }

    if input_action_fired_globally(client, .Shadow_Hud_Toggle, .Pressed) then client.shadow_hud_enabled = !client.shadow_hud_enabled;

    if input_action_fired_globally(client, .Checkerboard_Texture_Toggle, .Pressed) then client.draw_entities_with_checkerboard_texture = !client.draw_entities_with_checkerboard_texture;
}
    
    //
    // Update all local entities based on the information received by the server.
    // This also does some basic client-side prediction
    //
    if !client.server_paused_game {
        reset_allocator(*client.tick_allocator);

        //
        // Update all entities that have an impact on the lightmap
        //

        for i := 0; i < client.emitters.slot_count; ++i {
            emitter, occupied := index_bucket_array(*client.emitters, i);
            if occupied && emitter.state != .Off then update_powered_emitter(client, emitter);
        }
        
        for i := 0; i < client.emitters.slot_count; ++i {
            emitter, occupied := index_bucket_array(*client.emitters, i);
            if occupied && emitter.state == .Off then update_off_emitter(client, emitter);
        }

        for i := 0; i < client.torches.slot_count; ++i {
            torch, occupied := index_bucket_array(*client.torches, i);
            if occupied {
                update_torch(client, torch);
            }
        }
        
        for i := 0; i < client.frogs.slot_count; ++i {
            frog, occupied := index_bucket_array(*client.frogs, i);
            if occupied {
                update_frog(client, frog);
            }
        }

        update_lightmap(*client.lightmap, *client.em, client.tick_time);

#if DEVELOPER {
        if client.shadow_hud_enabled calculate_shadows(*client.lightmap, *client.tick_allocator);
}


        for i := 0; i < client.slabs.slot_count; ++i {
            slab, occupied := index_bucket_array(*client.slabs, i);
            if occupied then update_slab(client, slab);
        }

        for i := 0; i < client.guys.slot_count; ++i {
            guy, occupied := index_bucket_array(*client.guys, i);
            if occupied {
                update_guy(client, guy);
            }
        }

        for i := 0; i < client.goblins.slot_count; ++i {
            goblin, occupied := index_bucket_array(*client.goblins, i);
            if occupied then update_goblin(client, goblin);
        }

        for i := 0; i < client.slimes.slot_count; ++i {
            slime, occupied := index_bucket_array(*client.slimes, i);
            if occupied then update_slime(client, slime);
        }

        for i := 0; i < client.void_eyes.slot_count; ++i {
            eye, occupied := index_bucket_array(*client.void_eyes, i);
            if occupied then update_void_eye(client, eye);
        }

        for i := 0; i < client.all_entities.slot_count; ++i {
            entity, occupied := index_bucket_array(*client.all_entities, i);
            if occupied interpolate_visuals_and_play_sounds(client, entity);
        }

        for i := 0; i < client.particle_systems.slot_count; ++i {
            system, occupied := index_bucket_array(*client.particle_systems, i);
            if occupied then update_particle_system(system, client.tick_time);
        }

        play_random_sounds(client);

        client.game_epoch_time += client.tick_time;
    }

    //
    // Tutorial UI
    //
    maybe_do_tutorial_panel(client);

    //
    // Update the input for all local players
    //
    if !(client.pause_menu_open || client.server_paused_game) {
        for i := 0; i < client.local_player_count; ++i {
            local_player := *client.local_players[i];
            update_local_player_input(client, local_player);
        }
    }

    // Do the pause menu. The escape key can close the hud and open the pause menu, but we want to give
    // input priorization to the hud.
    {
        if input_action_fired_globally(client, .Toggle_Pause_Menu, .Pressed) {
            client.pause_menu_open = !client.pause_menu_open;

            msg := make_message(Game_Pause_Message);
            msg.game_pause.client_pid = client.my_client_pid;
            msg.game_pause.should_pause = client.pause_menu_open;
            array_add(*client.outgoing_messages, msg);
        }

        maybe_do_input_bindings_panel(client);

        if maybe_do_pause_menu_panel(client) {
            client.pause_menu_open = false;
            msg := make_message(Game_Pause_Message);
            msg.game_pause.client_pid = client.my_client_pid;
            msg.game_pause.should_pause = client.pause_menu_open;
            array_add(*client.outgoing_messages, msg);
        }
    }
    
    // Send all outgoing messages
    {
#if DEVELOPER {
        now := os_get_cpu_time();
}

        for i := 0; i < client.outgoing_messages.count; ++i {
            message := array_get_pointer(*client.outgoing_messages, i);
            send_reliable_message(*client.connection, message);

#if DEVELOPER   register_message_history(client, *client.outgoing_message_history, message);
        }

        array_clear(*client.outgoing_messages);
    }

    physically_remove_dead_particle_systems(client);
    physically_remove_dead_entities(client);
}

#if MEMORY_DEBUGGING {
    inside_allocator_callback := false;

    allocator_callback_procedure :: (client: *Client, allocator: *Allocator, operation: Allocator_Operation, pointer: *void, size_in_bytes: s64, old_pointer: *void, old_size_in_bytes: s64) {
        if inside_allocator_callback return;

        inside_allocator_callback = true;
        defer inside_allocator_callback = false;
        
        if allocator == Default_Allocator && operation == .Allocation {
            print_into_buffer(*client.memory_debug_printer, "%, %\n", pointer, size_in_bytes);

            trace := os_get_stack_trace(*temp, 3);
            for i := 0; i < trace.count; ++i {
                frame := *trace[i];
                print_into_buffer(*client.memory_debug_printer, "    - %:% - %\n", frame.source_file, frame.source_line, frame.description);
            }
            
            flush_file_printer(*client.memory_debug_printer);
        }
    }
}



#file_scope

/* ------------------------------------------- Local Player Handling ------------------------------------------ */

snap_position_to_rooms :: (client: *Client, camera: *Camera, target_center_position: v2f) -> v2f {
    custom_clamp :: (value, low, high: $T) -> T {
        if low < high {
            return clamp(value, low, high);
        } else {
            return (low + high) * 0.5;
        }
    }

    // We allow looking over the world edge for a bit, so that the crafting menu isn't cut off when standing
    // on the edge...
    min_distance_to_world_edge := v2f.{ camera.covered_world_area.x / 2 - 1, camera.covered_world_area.y / 2 - 1 };

    room_position := v2f.{ floor(xx target_center_position.x / CAMERA_AREA_WIDTH) * CAMERA_AREA_WIDTH + CAMERA_AREA_OFFSET, min_distance_to_world_edge.y };

    target_position := v2f.{
        custom_clamp(room_position.x, min_distance_to_world_edge.x, cast(f32) client.world_size.x - 1 - min_distance_to_world_edge.x),
        custom_clamp(room_position.y, min_distance_to_world_edge.y, cast(f32) client.world_size.y - 1 - min_distance_to_world_edge.y) };
    
    return target_position;
}

update_camera :: (client: *Client, local_player: *Local_Player, target_center_in_world: v2f, interpolation: f32, snap_to_room_center: bool) {
    camera := *local_player.camera;
 
    camera.viewport = local_player.viewport;

    viewport_width := camera.viewport[2] - camera.viewport[0];
    viewport_height := camera.viewport[3] - camera.viewport[1];

    camera.window_aspect_ratio = viewport_width / viewport_height;

#if Camera.FORCE_INTEGER_TILE_SCALING {
    driving_viewport_dimension := ifx camera.window_aspect_ratio >= 1 then viewport_height else viewport_width;
    NOMINATOR: f32 : cast(f32) SPRITE_HEIGHT;
    tile_size_in_pixels_on_screen := floor((driving_viewport_dimension / NOMINATOR) / Camera.DESIRED_MIN_VISIBLE_TILES) * NOMINATOR;
    visible_tiles: f32 = driving_viewport_dimension / tile_size_in_pixels_on_screen;
} #else {
    visible_tiles := Camera.DESIRED_MIN_VISIBLE_TILES;
}

#if DEVELOPER {
    desired_zoom := powf(camera.zoom_step, 1.5) + 1;
    camera.zoom += (desired_zoom - camera.zoom) * interpolation;
    zoomed_visible_tiles: f32 = visible_tiles * camera.zoom;
} #else {
    zoomed_visible_tiles: f32 = visible_tiles;
}

    if camera.window_aspect_ratio >= 1 {
        camera.world_to_screen_coordinates.y = viewport_height / zoomed_visible_tiles;
        camera.world_to_screen_coordinates.x = camera.world_to_screen_coordinates.y;
        camera.covered_world_area.x = visible_tiles * camera.window_aspect_ratio;
        camera.covered_world_area.y = visible_tiles;
    } else {
        camera.world_to_screen_coordinates.x = viewport_width / zoomed_visible_tiles;
        camera.world_to_screen_coordinates.y = camera.world_to_screen_coordinates.x;
        camera.covered_world_area.x = visible_tiles;
        camera.covered_world_area.y = visible_tiles / camera.window_aspect_ratio;
    }

#if DEVELOPER {
    camera.zoomed_covered_world_area.x = camera.covered_world_area.x * camera.zoom;
    camera.zoomed_covered_world_area.y = camera.covered_world_area.y * camera.zoom;
} #else {
    camera.zoomed_covered_world_area.x = camera.covered_world_area.x;
    camera.zoomed_covered_world_area.y = camera.covered_world_area.y;
}

    if snap_to_room_center {
        target_center_in_world = snap_position_to_rooms(client, camera, target_center_in_world);
    }
        
    camera.center_in_world.x = lerp_with_snap(camera.center_in_world.x, target_center_in_world.x, interpolation);
    camera.center_in_world.y = lerp_with_snap(camera.center_in_world.y, target_center_in_world.y, interpolation);
}

recalculate_local_player_viewports :: (client: *Client) {
    #assert(MAX_LOCAL_PLAYERS == 4);

    if client.local_player_count == {
      case 1;
        client.local_players[0].viewport = .[ 0, 0, xx client.window.w, xx client.window.h ];
      case 2;
        center_x: f32 = floor(cast(f32) client.window.w * 0.5);
        client.local_players[0].viewport = .[ 0, 0, center_x, xx client.window.h ];
        client.local_players[1].viewport = .[ center_x, 0, xx client.window.w, xx client.window.h ];
      case 3;
        center_x: f32 = floor(cast(f32) client.window.w * 0.5);
        center_y: f32 = floor(cast(f32) client.window.h * 0.5);
        client.local_players[0].viewport = .[ 0, 0, center_x, center_y ];
        client.local_players[1].viewport = .[ center_x, 0, xx client.window.w, center_y ];
        client.local_players[2].viewport = .[ 0, center_y, center_x, xx client.window.h ];
      case 4;
        center_x: f32 = floor(cast(f32) client.window.w * 0.5);
        center_y: f32 = floor(cast(f32) client.window.h * 0.5);
        client.local_players[0].viewport = .[ 0, 0, center_x, center_y ];
        client.local_players[1].viewport = .[ center_x, 0, xx client.window.w, center_y ];
        client.local_players[2].viewport = .[ 0, center_y, center_x, xx client.window.h ];
        client.local_players[3].viewport = .[ center_x, center_y, xx client.window.w, xx client.window.h ];
    }

    for i := 0; i < client.local_player_count; ++i {
        local_player := *client.local_players[i];
        if entity_exists(client, local_player.guy_pid) {
            entity := get_entity(client, local_player.guy_pid);
            update_camera(client, local_player, .{ xx entity.physical_position.x, xx entity.physical_position.y }, 1, true);
        }
    }
}

reassign_gamepad_indices :: (client: *Client) {
    index := 0;

    for i := 0; i < client.local_player_count; ++i {
        client.local_players[i].input_binder.gamepad_index = index;
        if client.local_players[i].input_binder.allowed_input_devices & .Gamepad ++index;
    }
}



/* ---------------------------------------------- Gameplay Logic ---------------------------------------------- */

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

find_next_entity_to_spectate :: (client: *Client, current_pid: Pid, forwards: bool) -> Pid {
    build_list_of_candidates :: (client: *Client) -> [..]Pid {
        result: [..]Pid;
        result.allocator = *temp;

        for i := 0; i < client.guys.slot_count; ++i {
            guy, occupied := index_bucket_array(*client.guys, i);
            if occupied array_add(*result, guy.pid);
        }
        
        return result;
    }

    candidates := build_list_of_candidates(client);

    current_index, found_index := array_index_of(*candidates, current_pid);
    assert(found_index, "The currently spectated entity is not part of the candidates.");
    
    next_index := ifx forwards then current_index + 1 else current_index - 1;
    next_index = next_index % candidates.count;
    
    return array_get(*candidates, next_index);
}

update_local_player_input :: (client: *Client, local_player: *Local_Player) {
    guy_entity := get_entity(client, local_player.guy_pid);
    guy := down(guy_entity, Guy);

    #if DEVELOPER {
        //
        // Move the camera around freely
        //
        local_player.camera.zoom_step = clamp(local_player.camera.zoom_step - client.window.mouse_wheel_turns, 0, 32);

        if client.free_camera_enabled {
            speed := local_player.camera.zoom * 10;

            target_center: v2f = local_player.camera.center_in_world;

            if input_action_fired_globally(client, .Move_West, .Held)  target_center.x -= speed * client.tick_time;
            if input_action_fired_globally(client, .Move_East, .Held)  target_center.x += speed * client.tick_time;
            if input_action_fired_globally(client, .Move_North, .Held) target_center.y -= speed * client.tick_time;
            if input_action_fired_globally(client, .Move_South, .Held) target_center.y += speed * client.tick_time;
        
            update_camera(client, local_player, target_center, 1, false);

            return;
        }
    }

    if guy.state != .Dead {
        //
        // If the guy is alive, update the hud and send some input to the server.
        //
        update_player_hud(client, local_player);

        input: Guy_Input_Message = ---;
        input.guy_pid          = local_player.guy_pid;
        input.position         = guy.physical_position;
        input.wants_to_move    = false;
        input.aim_direction    = guy.physical_rotation;
        input.interaction_kind = .Count;
        input.crafting_recipe  = local_player.hud.crafting_recipe_confirmed_this_frame;
        input.cheat            = local_player.hud.cheat_confirmed_this_frame;
        input.chest_item       = local_player.hud.chest_item_confirmed_this_frame;

        if !local_player.hud.was_open_this_frame {
            // The turn modifier check must only be done once.
            // Otherwise when pressing >=2 movement keys at the same time,
            // "input_action_fired_for_local_player" will return true on the second call, 
            // causing the player to move.
            turn_modifier_fired := input_action_fired_for_local_player(client, local_player, .Turn_Modifier, .Held);

            if input_action_fired_for_local_player(client, local_player, .Move_North, .Pressed) {
                if !turn_modifier_fired {
                    input.position.x = guy.physical_position.x;
                    input.position.y = guy.physical_position.y - 1;
                }
                input.aim_direction = .North;
                input.wants_to_move = true;
            }

            if input_action_fired_for_local_player(client, local_player, .Move_West, .Pressed) {
                if !turn_modifier_fired {
                    input.position.x = guy.physical_position.x - 1;
                    input.position.y = guy.physical_position.y;
                }
                input.aim_direction = .West;
                input.wants_to_move = true;
            }

            if input_action_fired_for_local_player(client, local_player, .Move_South, .Pressed) {
                if !turn_modifier_fired {
                    input.position.x = guy.physical_position.x;
                    input.position.y = guy.physical_position.y + 1;
                }
                input.aim_direction = .South;
                input.wants_to_move = true;
            }

            if input_action_fired_for_local_player(client, local_player, .Move_East, .Pressed) {
                if !turn_modifier_fired {
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
            // If nothing interesting happened, we can safe us the network traffic and just
            // not send anything
            msg := make_message_from(input);
            array_add(*client.outgoing_messages, msg);
        }

        local_player.entity_tracked_by_camera = local_player.guy_pid; // If we're alive, we always want to track ourselves
    } else {
        //
        // If spectating, update the tracked entity
        //
        if input_action_fired_for_local_player(client, local_player, .Move_East, .Pressed) {
            local_player.entity_tracked_by_camera = find_next_entity_to_spectate(client, local_player.entity_tracked_by_camera, true);
        } else if input_action_fired_for_local_player(client, local_player, .Move_West, .Pressed) {
            local_player.entity_tracked_by_camera = find_next_entity_to_spectate(client, local_player.entity_tracked_by_camera, false);
        }

        if !entity_exists(client, local_player.entity_tracked_by_camera) {
            // Fallback in case the tracked entity disappears for some reason
            local_player.entity_tracked_by_camera = local_player.guy_pid;
        }
    }

    //
    // Update the camera
    //
    {
        target_entity := get_entity(client, local_player.entity_tracked_by_camera);
        target_center := v2f.{ xx target_entity.physical_position.x, xx target_entity.physical_position.y };
        interpolation_speed := min(10 * client.tick_time, 1);
        update_camera(client, local_player, target_center, interpolation_speed, true);
    }
}



/* ------------------------------------------------- UI Panels ------------------------------------------------ */

maybe_do_pause_menu_panel :: (client: *Client) -> bool {
    if !client.pause_menu_open then return false;

    ui :: *client.ui;
    ui_push_window(ui, "Glassminers", .Default, .{ 0.5, 0.35 });
    ui_push_width(ui, .Pixels, 256, 1);
    ui_push_height(ui, .Pixels, 32, 1);

    ui_label(ui, true, "Seed: %", client.game_seed);
    ui_slider(ui, "Audio", *client.mixer.volumes[.Master], 0, 1);
    ui_slider(ui, "Gamma", *client.lightmap.gamma, 1, 4);
    ui_selector_box_with_enum_pointer(ui, "UI Scale", *client.config.ui_scale);
    ui_check_box(ui, "Gamepad Vibration", *client.config.gamepad_vibration);
    
    if client.game_mode == .Tutorial {
        ui_check_box(ui, "Tutorial Panels", *client.config.tutorial_panels);
    }

    ui_toggle_button_with_pointer(ui, "Input Bindings", cast(*bool) *client.input_bindings_panel_state);

    ui_divider(ui, true);
    continue_game := ui_button(ui, "Continue!");

    ui_divider(ui, false);

    if client.requested_game_forfeit {
        ui_deactivated_button(ui, "Forfeit!");
    } else if ui_button(ui, "Forfeit!") {
        msg := make_message(Request_Game_Forfeit_Message);
        msg.request_game_forfeit.client_pid = client.my_client_pid;
        array_add(*client.outgoing_messages, msg);
        client.requested_game_forfeit = true;
    }

    ui_divider(ui, false);
    if ui_button(ui, "Back to Main Menu!") then initiate_state_transition(client, .Main_Menu, 0);

    ui_pop_height(ui);
    ui_pop_width(ui);
    ui_pop_window(ui);

    return continue_game;
}

maybe_do_input_bindings_panel :: (client: *Client) {
    if !client.pause_menu_open || client.input_bindings_panel_state == .Closed then return;

    ui := *client.ui;

    client.input_bindings_panel_state, client.input_bindings_panel_position = ui_push_window(ui, "Input Bindings", .Draggable | .Closeable, client.input_bindings_panel_position);

    if client.input_bindings_panel_state == .Open {
        for i: Input_Action = 0; i < Input_Action.Count; ++i {
            if !input_action_available(i) continue;

            ui_push_width(ui, .Pixels, 800, 1);
            ui_push_container(ui, .Horizontal);
            ui_set_width(ui, .Percentage_Of_Parent, 0.4, 1);
            ui_label(ui, false, "%", input_action_string(i));
            ui_set_width(ui, .Percentage_Of_Parent, 1.0, 0);
            ui_label(ui, false, input_bindings_string(client, i));
            ui_pop_container(ui);
            ui_pop_width(ui);
        }
    }

    ui_pop_window(ui);
}

maybe_do_tutorial_panel :: (client: *Client) {
    if client.game_mode != .Tutorial || !client.config.tutorial_panels || client.server_paused_game || client.current_tutorial_panel >= client.requested_tutorial_panels.count {
        // No more requested panel to show...
        return;    
    }

    ui := *client.ui;
    panel_kind := array_get(*client.requested_tutorial_panels, client.current_tutorial_panel);

    panel_name: string = ---;

    if #complete panel_kind == {
      case .About_Tutorial_Panels;      panel_name = "Tutorial - Introduction";
      case .Goal_Of_The_Game;           panel_name = "Tutorial - Goal of the Game";
      case .Using_The_Crafting_Menu;    panel_name = "Tutorial - Crafting Menu";
      case .Using_Mirrors_To_Kill;      panel_name = "Tutorial - Killing Monsters";
    }

    ui_push_width(ui, .Sum_Of_Children, 10, 1);
    ui_push_window(ui, panel_name, .Default, .{ .5, .5 });
    ui_push_width(ui, .Label_Size, 5, 1);

    if #complete panel_kind == {
      case .About_Tutorial_Panels;
        ui_label(ui, true,  "Welcome to the tutorial.");
        ui_label(ui, false, "We will try to guide you through the game with as little popups as possible.");
        ui_label(ui, false, "Unfortunately, there'a few things we need to tell you.");
        ui_label(ui, true,  "Press % to close these panels.", input_bindings_string(client, .Interact_Primary));

      case .Goal_Of_The_Game;
        ui_label(ui, true,  "The goal of the game is to get a high score.");
        ui_label(ui, false, "You increase the score by placing the flag further to the right.");
        ui_label(ui, false, "Unlock the next section of the world by activating the next emitter.");
        ui_label(ui, false, "An emitter is activated by interacting on it with the flag while it is powered.");
    
      case .Using_The_Crafting_Menu;
        ui_label(ui, true,  "Press % to open the crafting menu.", input_bindings_string(client, .Hud_Toggle));
        ui_label(ui, false, "There you can convert items that you are carrying into useful creations.");
        ui_label(ui, false, "Different options will appear depending on your surroundings.");
        ui_label(ui, false, "May we suggest you try crafting a mirror?");

      case .Using_Mirrors_To_Kill;
        ui_label(ui, true,  "You can use the light beam to kill monsters.");
        ui_label(ui, false, "Try reflecting the beam onto a monster using mirrors.");
        ui_label(ui, false, "Different monsters have different properties and must be approached differently.");
    }

    if input_action_fired_globally(client, .Interact_Primary, .Pressed) {
        if panel_kind == .About_Tutorial_Panels then request_tutorial_panel(client, .Goal_Of_The_Game);

        ++client.current_tutorial_panel;        
    }

    ui_pop_width(ui);    
    ui_pop_window(ui);
    ui_pop_width(ui);
}

#if DEVELOPER {
maybe_do_developer_panel :: (client: *Client) {
    if client.developer_panel_state == .Closed then return;

    ui :: *client.ui;
    
    ui_push_width(ui, .Pixels, 360, 0.8);
    client.developer_panel_state, client.developer_panel_position = ui_push_window(ui, "Developer", .Draggable | .Closeable | .Collapsable, client.developer_panel_position);

    if client.developer_panel_state == .Open {
        {
            ui_multiline_wrapped_label(ui, false, client.graphics.backend_version, "", 360, true);
            ui_divider(ui, true);
        }

        {
            ui_label(ui, true, "Timings (previous frame)");
            ui_label(ui, false, "Frame             %ms", client.window.frame_time * 1000.0);
            ui_label(ui, false, "Frame (w/o sleep) %ms", client.total_frame_time_without_sleep);
            ui_label(ui, false, "Update            %ms", client.total_update_time);
            ui_label(ui, false, "Draw              %ms", client.total_draw_time);
            ui_label(ui, false, "Draw (w/o UI)     %ms", client.draw_time_before_ui);
            ui_divider(ui, true);
        }
            
        {
            ui_label(ui, true, "Misc.");
            ui_label(ui, false, "Round Trip Time: %", cast(s64) client.latest_rtt);
            ui_label(ui, false, "Draw Call Count: %", client.draw_call_count_before_ui);
            ui_label(ui, false, "    With UI:     %", client.graphics.draw_call_count);
            ui_label(ui, false, "World Size: %x%", client.world_size.x, client.world_size.y);
            ui_label(ui, false, "Entities: %", client.all_entities.alive_count);
            ui_label(ui, false, "Particle Systems: %", client.particle_systems.alive_count);
            ui_divider(ui, true);
        }

        #if ALLOCATOR_STATISTICS {
            allocator_string :: (allocator: *Allocator) -> string {
                size_in_units, units := convert_to_biggest_memory_unit(allocator.stats.working_set);
                return print_into_allocator(*temp, "% %", size_in_units, suffix_string_from_memory_unit(units));
            }

            ui_label(ui, true, "Allocators:");
            ui_label(ui, false, "Heap:   %", allocator_string(Default_Allocator));
            ui_label(ui, false, "Engine: %", allocator_string(*client.engine_allocator));
            ui_label(ui, false, "World:  %", allocator_string(*client.world_allocator));
            ui_label(ui, false, "UI:     %", allocator_string(*client.ui.allocator));
            ui_label(ui, false, "Tick:   %", allocator_string(*client.tick_allocator));
            ui_label(ui, false, "Temp:   %", allocator_string(*temp));
            ui_divider(ui, true);
        }
    
        {
            size_string :: (size_in_bytes: s64) -> string {
                size_in_units, units := convert_to_biggest_memory_unit(size_in_bytes);
                return print_into_allocator(*temp, "% %", size_in_units, suffix_string_from_memory_unit(units));
            }

            ui_label(ui, true, "Asset Data:");

            {
                sound_data_bytes := 0;
                for i := 0; i < client.sounds.Capacity; ++i    sound_data_bytes += client.sounds[i].bytes.count;
                ui_label(ui, false, "Sounds: %", size_string(sound_data_bytes));
            }

            ui_divider(ui, true);
        }

        {
            ui_label(ui, true, "Cheats");
            ui_check_box(ui, "Disable Lightmap", *client.lightmap.disabled);
            ui_check_box(ui, "Free Camera", *client.free_camera_enabled);
        }
    }
        
    ui_pop_window(ui);
    ui_pop_width(ui);
}

maybe_do_message_history_panel :: (client: *Client) {
    WIDTH: f32 : 960;

    calculate_bandwidth :: (history: *Message_History) -> f32 {
        if history.active == 0 return 0;

        bytes: s64;
        timespan: f32 = history.entries[history.active - 1].age;

        for i := 0; i < history.active; ++i   bytes += history.entries[i].size_in_bytes;

        return cast(f32) bytes / timespan;
    }

    do_history :: (ui: *UI, history: *Message_History, name: string) {
        ui_push_growing_container(ui, .Vertical);
        ui_push_width(ui, .Pixels, WIDTH * 0.5, 0.9);

        unit_value, unit := convert_to_biggest_memory_unit(history.total_bytes_received);
        ui_label(ui, true, "% - % kb/s - %% total", name, 
                 format_float(xx calculate_bandwidth(history) / 1000, 0, 2),
                 format_float(unit_value, 0, 2),
                 suffix_string_from_memory_unit(unit)
                 );
        ui_divider(ui, true);

        now := os_get_cpu_time();

        for i := 0; i < history.active; ++i {
            entry := *history.entries[i]; // Unfortunately, the dynamically allocated data on this message is no longer valid, as it lived on *temp. Therefore, we can't really print the content of this message safely, we can only print the kind of message...
            ui_label(ui, false, "% (%b) (%s)", type_info(entry.message.local_type_id).display_name, entry.size_in_bytes, entry.age);
        }

        ui_pop_width(ui);
        ui_pop_container(ui);
    }

    update_history :: (client: *Client, history: *Message_History) { // Delete old entries that no longer seem interesting...
        now := os_get_cpu_time();

        for i := 0; i < history.active; ++i {
            entry := *history.entries[i];
            if entry.age >= 9.5 {
                --history.active;
            } else {
                entry.age += client.tick_time;
            }
        }
    }

    if !client.message_history_paused {
        update_history(client, *client.incoming_message_history);
        update_history(client, *client.outgoing_message_history);
    }

    if client.message_history_panel_state == .Closed then return;

    ui := *client.ui;

    ui_push_width(ui, .Pixels, WIDTH, 1);
    client.message_history_panel_state, client.message_history_panel_position = ui_push_window(ui, "Message History", .Draggable | .Collapsable | .Closeable, client.message_history_panel_position);

    if client.message_history_panel_state == .Open {
        ui_set_height(ui, .Sum_Of_Children, 0, 1);
        ui_push_container(ui, .Horizontal);
        do_history(ui, *client.incoming_message_history, "Incoming");
        ui_divider(ui, false);
        do_history(ui, *client.outgoing_message_history, "Outgoing");
        ui_pop_container(ui);        
    }

    ui_divider(ui, true);
    ui_check_box(ui, "Pause", *client.message_history_paused);

    ui_pop_window(ui);
    ui_pop_width(ui);
}
}
