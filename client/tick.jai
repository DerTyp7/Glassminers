/* --------------------------------------------- Message Handling --------------------------------------------- */

send_player_information_message :: (client: *Client, local_player_index: s64) {
    msg := make_message(Player_Information_Message);
    msg.player_information.local_player_index = local_player_index;
    msg.player_information.client_pid = client.my_client_pid;
    msg.player_information.name = client.local_players[local_player_index].name;
    array_add(*client.outgoing_messages, msg);
}



/* ------------------------------------------------ Menu Ticks ------------------------------------------------ */

do_main_menu :: (client: *Client) {
    ui :: *client.ui;
    
    DEFAULT_PORT: s64 : 9876;
    WINDOW_WIDTH: f32 : 256;
    APPROX_WINDOW_HEIGHT: f32 : 256;
    WINDOW_SPACING: f32 : 50;
    
    ui_push_width(ui, .Pixels, WINDOW_WIDTH, 1);

    window_position :: (client: *Client, index: s64) -> UI_Vector2 {
        scaled_window_width := WINDOW_WIDTH * client.ui.pixel_scaling;
        scaled_window_spacing := WINDOW_SPACING * client.ui.pixel_scaling;
        
        screen := UI_Vector2.{ (xx client.window.w / 2 + (xx index - 0.5) * scaled_window_width),
                               (xx client.window.h / 2 - APPROX_WINDOW_HEIGHT * 0.65) };
        screen.x += xx index * scaled_window_spacing;
        return .{ screen.x / (cast(f32) client.window.w - scaled_window_width), screen.y / (cast(f32) client.window.h - APPROX_WINDOW_HEIGHT) };
    }

    if client.server_data.state != .Closed && client.info_text_t <= 0 { // Don't override other error conditions...
        set_temp_info_text(client, "Your local server is still running...");
    }
    
    // Host Window
    {
        ui_push_window(ui, "Host", .Default, window_position(client, -1));
        ui_label(ui, false, "Name");
        ui_text_input_with_string_pointer(ui, "Enter your name", *client.config.account_name, true, *client.engine_allocator);
        ui_divider(ui, true);
        ui_label(ui, false, "Port");
        ui_text_input_with_int_pointer(ui, "Enter the port", *client.config.network_port, true);
        ui_divider(ui, true);
        
        if client.server_data.state == .Closed && ui_button(ui, "Host!") {
            if client.config.account_name && host_server(client, client.config.network_port) {
                join_server(client, client.config.account_name, "localhost", client.config.network_port);
                client.immediately_start_game = false;
            }
        }
        
        ui_pop_window(ui);
    }

    // Single Player Window
    {
        ui_push_window(ui, "Single Player", .Default, window_position(client, 0));

        do_game_mode_selector(client);
        ui_divider(ui, true);

        if client.server_data.state == .Closed && ui_button(ui, "Play!") && host_server(client, DEFAULT_PORT) {
            join_server(client, client.config.account_name, "localhost", DEFAULT_PORT);
            client.immediately_start_game = true;
        }
        
        ui_pop_window(ui);
    }
    
    // Join Window
    {
        ui_push_window(ui, "Join", .Default, window_position(client, +1));
        ui_label(ui, false, "Name");
        ui_text_input_with_string_pointer(ui, "Enter your name", *client.config.account_name, true, *client.engine_allocator);
        ui_divider(ui, true);
        ui_label(ui, false, "Host");
        ui_text_input_with_string_pointer(ui, "Enter the address", *client.config.network_host, true, *client.engine_allocator);
        ui_label(ui, false, "Port");
        ui_text_input_with_int_pointer(ui, "Enter the port", *client.config.network_port, true);
        ui_divider(ui, true);
        
        if client.server_data.state == .Closed && ui_button(ui, "Join!") {
            if client.config.account_name && client.config.network_host {
                join_server(client, client.config.account_name, client.config.network_host, client.config.network_port);
                client.immediately_start_game = false;
            }
        }
        
        ui_pop_window(ui);
    }

    // Quit Window
    {
        ui_push_window(ui, "Quit?", .Default, .{ 0.5, 0.8 });

        if ui_button(ui, "Quit to Desktop") client.window.should_close = true;
        
        ui_pop_window(ui);
    }
    
    ui_pop_width(ui);
}

do_game_over_screen :: (client: *Client) {
    display_game_stats :: () #macro {
        summary := client.previous_game_summary;

        if summary.player_stat_message.count {
            ui_divider(ui, true);
            ui_multiline_wrapped_label(ui, true, summary.player_stat_message, "", cast(s64) WIDTH, true);
        }

        if summary.global_stat_message.count {
            ui_divider(ui, true);
            ui_multiline_wrapped_label(ui, true, summary.global_stat_message, "", cast(s64) WIDTH, true);
        }
    }

    WIDTH: f32 : 350;

    ui :: *client.ui;
    ui_push_width(ui, .Pixels, WIDTH, 1);
    ui_push_window(ui, "Game Over!", .Default, .{ .5, .5 });
    
    score_text := tprint("Final Score: %", client.game_score);
    
    if #complete client.previous_game_summary.result == {
      case .Unfinished_Game; // Should never happen, this value is just used on the server side
          
      case .Completed_Tutorial;
        ui_label(ui, true, "You completed the tutorial!");

      case .All_Players_Died; 
        ui_label(ui, true, "All players have died!");
        ui_label(ui, true, score_text);
        display_game_stats();

      case .All_Players_Forfeited;
        ui_label(ui, true, "All players have forfeited!");
        ui_label(ui, true, score_text);
        display_game_stats();

      case .Flag_Was_Destroyed;
        ui_label(ui, true, "The flag was destroyed!");
        ui_label(ui, true, score_text);
        display_game_stats();

      case .Connection_Lost;
        ui_label(ui, true, "Connection died!");
    }
    
    ui_divider(ui, true);
    if ui_button(ui, "Back to Main Menu!") then initiate_state_transition(client, .Main_Menu, 0);

    ui_pop_window(ui);
    ui_pop_width(ui);
}

do_connecting_screen :: (client: *Client) {
    read_incoming_packets(client);
    handle_server_timeout(client, .Main_Menu, "The server could not be reached.");
    
    if !client.sent_connection_request && has_tcp_handshake_occurred(*client.connection) {
        send_connection_request_packet(*client.connection, 1, VERSION_STRING);
        client.sent_connection_request = true;
    }
    
    {
        ui :: *client.ui;
        ui_push_width(ui, .Pixels, 256, 1);
        ui_push_window(ui, "Connecting...", .Default, .{ .5, .5 });
        ui_label(ui, false, "...");
        ui_divider(ui, true);
        if ui_button(ui, "Cancel!") then initiate_state_transition(client, .Main_Menu, 0);
        ui_pop_window(ui);
        ui_pop_width(ui);
    }    

    send_outgoing_messages(client);
}

do_lobby_screen :: (client: *Client) {
    input_device_widget :: (client: *Client, label: string, allowed_devices: *Input_Device) {
        Custom_State :: struct {
            allowed_devices: *Input_Device;
        }

        draw_input_device_widget :: (client: *Client, element: *UI_Element, state: *Custom_State) {
            index: Sprite_Index = ---;

            if ~state.allowed_devices == .Keyboard {
                index = .Hud_Keyboard;
            } else if ~state.allowed_devices == .Gamepad {
                index = .Hud_Gamepad;
            } else if ~state.allowed_devices == .ALL {
                index = .Hud_Keyboard_Gamepad;
            }

            center: GE_Vector2 = .{ round(element.screen_position.x + element.screen_size.x * 0.5), round(element.screen_position.y + element.screen_size.y * 0.5) };
            size_animation_factor := sinf(element.size_t * 10) * 0.2 + 1;
            size: GE_Vector2 = .{ element.screen_size.x * size_animation_factor, element.screen_size.y * size_animation_factor };
            draw_sprite_screen_space(client, index, center, size, 0, .{ 255, 255, 255, 255 }, false);
        }

        update_input_device_widget :: (client: *Client, element: *UI_Element, state: *Custom_State) {
            if element.signals & .Clicked {
                if ~state.allowed_devices == .Keyboard {
                    ~state.allowed_devices = .Gamepad;
                } else if ~state.allowed_devices == .Gamepad {
                    ~state.allowed_devices = .ALL;
                } else if ~state.allowed_devices == .ALL {
                    ~state.allowed_devices = .Keyboard;
                }
            }
        }

        data := ui_custom_widget(*client.ui, label, .Animate_Size_On_Hover | .Animate_Size_On_Activation, update_input_device_widget, draw_input_device_widget, size_of(Sprite_Index));
        state := cast(*Custom_State) data.custom_state;
        state.allowed_devices = allowed_devices;
    }

    read_incoming_packets(client);
    handle_server_timeout(client, .Main_Menu, "The server died.");

    if client.immediately_start_game {
        send_game_start_request_message(client);
        client.immediately_start_game = false;
    }

    // Do the lobby UI
    {
        ui :: *client.ui;
        ui_push_width(ui, .Pixels, 256, 1);
        ui_push_window(ui, "Lobby!", .Default, .{ .5, .4 });
        
        for i := 0; i < client.local_player_count; ++i {
            local_player := *client.local_players[i];

            ui_push_height(ui, .Pixels, 32, 1);
            ui_push_container(ui, .Horizontal);

            ui_push_width(ui, .Pixels, 256, 0);
            ui_label(ui, false, local_player.name);
            ui_pop_width(ui);
            
            ui_push_width(ui, .Pixels, 32, 1);
            input_device_widget(client, tprint("local_player_input_devices%", i), *local_player.input_binder.allowed_input_devices);
            ui_pop_width(ui);

            if local_player.input_binder.allowed_input_devices & .Gamepad && local_player.input_binder.gamepad_index >= client.window.connected_gamepads {
                ui_push_width(ui, .Label_Size, 5, 1);
                ui_label(ui, true, "!");
                ui_pop_width(ui);
            }
            
            ui_pop_container(ui);
            ui_pop_height(ui);
        }
        
        for i := 0; i < client.remote_players.count; ++i {
            player := array_get_pointer(*client.remote_players, i);
            ui_label(ui, false, player.name);
        }

        ui_divider(ui, true);

        {
            ui_label(ui, true, "Local Players");

            if client.local_player_count < MAX_LOCAL_PLAYERS {
                ui_push_container(ui, .Horizontal);
                ui_push_width(ui, .Percentage_Of_Parent, 0.5, 0.5);

                confirmed := ui_text_input_with_string_pointer(ui, "Name", *client.new_local_player_name, true, *client.engine_allocator);

                if ui_button(ui, "Add!") || confirmed {
                    maybe_add_local_player(client);
                }

                ui_pop_width(ui);
                ui_pop_container(ui);
            }
            
            if client.local_player_count > 1 && ui_button(ui, "Remove Local Player!") {
                deallocate_string(*client.engine_allocator, *client.local_players[client.local_player_count - 1].name);
                msg := make_message(Remove_Local_Player_Message);
                msg.remove_local_player.client_pid = client.my_client_pid;
                msg.remove_local_player.local_player_index = client.local_player_count - 1;
                array_add(*client.outgoing_messages, msg);
                --client.local_player_count;
            }
        }

        ui_divider(ui, true);
        do_game_mode_selector(client);
        
        if ui_button(ui, "Start!") {
            maybe_add_local_player(client); // Add a new local player when somebody typed in the name but forgot to press "Add!"
            send_game_start_request_message(client);
        }
        
        ui_divider(ui, true);
        if ui_button(ui, "Disconnect!") then initiate_state_transition(client, .Main_Menu, 0);
        ui_pop_window(ui);
        ui_pop_width(ui);
    }

    // Handle test inputs. This can help in figuring out which player uses which gamepad in
    // local multiplayer.
    {
        register_test_input :: (client: *Client, local_player_index: s64, sprite_index: Sprite_Index) {
            input := array_push(*client.test_inputs);
            input.cpu_time = os_get_cpu_time();
            input.local_player_index = local_player_index;
            input.sprite_index = sprite_index;
        }

        now := os_get_cpu_time();
        for i := 0; i < client.test_inputs.count; {
            input := array_get_pointer(*client.test_inputs, i);
            if os_convert_cpu_time(now - input.cpu_time, .Seconds) > 2 {
                array_remove_index(*client.test_inputs, i);
            } else {
                ++i;
            }
        }
        
        for i := 0; i < client.local_player_count; ++i {
            local_player := *client.local_players[i];

            if bitfield_contains(*local_player.input_binder.allowed_input_devices, Input_Device.Keyboard) && !client.ui.active_text_input {
                if client.window.keys[.Space] & .Pressed then register_test_input(client, i, .Hud_Key_Space);
                if client.window.keys[.Shift] & .Pressed then register_test_input(client, i, .Hud_Key_Shift);
            }

            if bitfield_contains(*local_player.input_binder.allowed_input_devices, Input_Device.Gamepad) && local_player.input_binder.gamepad_index < client.window.connected_gamepads {
                gamepad := *client.window.gamepads[local_player.input_binder.gamepad_index];
                if gamepad.buttons[.XBox_A]    & .Pressed then register_test_input(client, i, .Hud_XBox_A);
                if gamepad.buttons[.XBox_X]    & .Pressed then register_test_input(client, i, .Hud_XBox_X);
                if gamepad.buttons[.PS_Cross]  & .Pressed then register_test_input(client, i, .Hud_PS_Cross);
                if gamepad.buttons[.PS_Square] & .Pressed then register_test_input(client, i, .Hud_PS_Square);
            }
        }
    }

    send_outgoing_messages(client);
}



/* -------------------------------------------------- Camera -------------------------------------------------- */

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



/* ------------------------------------------------- Game Tick ------------------------------------------------ */

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

    physically_remove_dead_particle_systems(client);
    physically_remove_dead_entities(client);
    send_outgoing_messages(client);
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

/* --------------------------------------------- Message Handling --------------------------------------------- */

handle_incoming_message :: (client: *Client, msg: *Message) {
    if #complete msg.msg_type == {
      case .Request_Game_Start, .Request_Game_Forfeit, .Guy_Input; // Ignore
    
      case .Client_Disconnect;
        for i := 0; i < client.remote_players.count; {
            remote_player := array_get_pointer(*client.remote_players, i);
            if remote_player.client_pid == msg.client_disconnect.client_pid {
                deallocate_string(*client.engine_allocator, *remote_player.name);
                array_remove_index(*client.remote_players, i);
            } else {
                ++i;
            }
        }

      case .Remove_Local_Player;
        if msg.remove_local_player.client_pid == client.my_client_pid break;
        
        for i := 0; i < client.remote_players.count; {
            remote_player := array_get_pointer(*client.remote_players, i);
            if remote_player.client_pid == msg.remove_local_player.client_pid && remote_player.local_player_index == msg.remove_local_player.local_player_index {
                deallocate_string(*client.engine_allocator, *remote_player.name);
                array_remove_index(*client.remote_players, i);
            } else {
                ++i;
            }
        }
        
      case .Player_Information;
        if msg.player_information.client_pid != client.my_client_pid {
            remote_player := find_remote_player_by_pid_and_local_index(client, msg.player_information.client_pid, msg.player_information.local_player_index);
            
            if remote_player == null {
                remote_player = array_push(*client.remote_players);
                remote_player.local_player_index = msg.player_information.local_player_index;
                remote_player.client_pid = msg.player_information.client_pid;
                remote_player.guy_pid    = msg.player_information.guy_pid;
                remote_player.name       = copy_string(*client.engine_allocator, msg.player_information.name);
            } else if msg.player_information.guy_pid != INVALID_PID {
                remote_player.guy_pid = msg.player_information.guy_pid;
            }
        } else if msg.player_information.guy_pid != INVALID_PID {
            local_player := *client.local_players[msg.player_information.local_player_index];
            local_player.guy_pid = msg.player_information.guy_pid;
            snap_camera_to_guy(client, local_player);
        }

      case .Game_Pause;
        client.server_paused_game = msg.game_pause.should_pause;
        toggle_all_game_sounds(client, client.server_paused_game);
        
      case .Game_Start;
        start_the_game(client, msg.game_start);

      case .Game_Over;
        client.pause_menu_open = false;
        client.game_score = msg.game_over.score;
        client.previous_game_summary.result = msg.game_over.result;
        client.previous_game_summary.score  = msg.game_over.score;

        if msg.game_over.player_stat_kind != .Count {
            player_name := find_player_name_from_guy_pid(client, msg.game_over.player_stat_guy_pid);
            client.previous_game_summary.player_stat_message = format_player_stat(*client.engine_allocator, player_name, msg.game_over.player_stat_kind, msg.game_over.player_stat);
        }
        
        if msg.game_over.global_stat_kind != .Count {
            client.previous_game_summary.global_stat_message = format_global_stat(*client.engine_allocator, msg.game_over.global_stat_kind, msg.game_over.global_stat);
        }

        initiate_state_transition(client, .Game_Over, 5);

        if msg.game_over.result == .Completed_Tutorial {
            client.config.tutorial_panels = false;   
        } else {
            play_sound(client, .Hud_Failure_0, .Default);
        }

      case .Game_Score;
        client.game_score = msg.game_score.score;

      case .Player_Stat;
        name := find_player_name_from_guy_pid(client, msg.player_stat.guy_pid);
        add_player_stat_message(client, name, msg.player_stat.kind, msg.player_stat.stat);
        play_sound(client, .Hud_Success_0, .Default);

      case .Global_Stat;
        add_global_stat_message(client, msg.global_stat.kind, msg.global_stat.stat);
        play_sound(client, .Hud_Success_0, .Default);

      case .World_Resize;
        client.world_size      = msg.world_resize.new_world_size;
        client.current_biome   = msg.world_resize.current_biome;
        client.current_section = msg.world_resize.current_section;
        resize_lightmap(*client.lightmap, client.world_size);

        {
            system := get_particle_system(client, client.global_particle_system);
            system.world_position = .{ xx (client.world_size.x / 2), xx (client.world_size.y / 2) };
            emitter := *system.emitters[0];
            emitter.box_half_size = .{ xx (client.world_size.x / 2) + 2, xx (client.world_size.y / 2) + 2 };
        }

      case .Create_Entity;
        entity := create_entity_with_pid(client, msg.create_entity.entity_pid, msg.create_entity.kind, msg.create_entity.position, msg.create_entity.rotation);
        maybe_add_blocker(*client.lightmap, entity);
        
      case .Destroy_Entity;
        entity := get_entity(client, msg.destroy_entity.entity_pid);
        entity.marked_for_removal = true;

        // Play death sounds
        if entity.entity_kind == {
          case .Frog;   play_sound_on_entity(client, .Frog_Death_0,   entity, .Once_Per_Frame);
          case .Goblin; play_sound_on_entity(client, .Goblin_Death_0, entity, .Once_Per_Frame);
          case .Slime;  play_sound_on_entity(client, .Slime_Death_0,  entity, .Once_Per_Frame);
          case .Trader; play_sound_on_entity(client, .Trader_Death_0, entity, .Once_Per_Frame);
        }

        maybe_remove_blocker(*client.lightmap, entity);
        
      case .Move_Entity;
        entity := get_entity(client, msg.move_entity.entity_pid);

        maybe_move_blocker(*client.lightmap, entity, msg.move_entity.position);

        entity.physical_position = msg.move_entity.position;
        entity.physical_rotation = msg.move_entity.rotation;

        // Play walking animations / rotate idle animations
        if entity.entity_kind == {
          case .Guy;
            maybe_play_animation_from_group_instead(client, entity, .Is_Idle | .Is_Walk, .Guy_Walk);
            down(entity, Guy).seconds_since_last_move = 0;
          case .Frog;
            maybe_play_animation_from_group_instead(client, entity, .Is_Idle, .Frog_Idle);
          case .Goblin;
            maybe_play_animation_from_group_instead(client, entity, .Is_Idle, .Goblin_Idle);
          case .Slime;
            maybe_play_animation_from_group_instead(client, entity, .Is_Idle | .Is_Walk, .Slime_Walk);
          case .Void_Eye;
            play_animation_from_group(client, entity, .Void_Eye);
          case .Trader;
            maybe_play_animation_from_group_instead(client, entity, .Is_Idle, .Trader_Idle);
        }
        
      case .Entity_Health;
        entity := get_entity(client, msg.entity_health.entity_pid);

        dropped_heart := floor(msg.entity_health.new_health / HEALTH_PER_HEART) < floor(entity.health / HEALTH_PER_HEART);
        gained_heart  := floor(msg.entity_health.new_health / HEALTH_PER_HEART) > floor(entity.health / HEALTH_PER_HEART);

        if msg.entity_health.new_health < entity.health {
            // Play a damaged sound
            if dropped_heart && msg.entity_health.new_health > 0 {
                sound_index: Sound_Index = .Count;
                if entity.entity_kind == {
                  case .Guy;    sound_index = .Guy_Damaged_0;
                  case .Frog;   sound_index = .Frog_Damaged_0;
                  case .Goblin; sound_index = .Goblin_Damaged_0;
                  case .Slime;  sound_index = .Slime_Damaged_0;
                  case .Trader; sound_index = .Trader_Damaged_0;
                }
        
                if sound_index != .Count {
                    play_sound_on_entity(client, sound_index, entity, .Once_Per_Frame);
                    get_sound_length_in_seconds(client, sound_index) * 2;
                }
            }
        
            // Play a damaged animation
            if entity.entity_kind == {
              case .Guy; maybe_play_animation_from_group_instead(client, entity, .Is_Idle | .Is_Walk, .Guy_Damaged);
              case .Goblin; maybe_play_animation_from_group_instead(client, entity, .Is_Idle, .Goblin_Damaged);
              case .Frog; maybe_play_animation_from_group_instead(client, entity, .Is_Idle, .Frog_Damaged);
              case .Slime; maybe_play_animation_from_group_instead(client, entity, .Is_Idle | .Is_Walk, .Slime_Damaged);
            }

            entity.time_since_last_damage = 0;
        }
            
        // Play damage particles & health bar animation
        if entity.entity_flags & .Living && dropped_heart {
            system := create_particle_system(client, 1.0, .{ xx entity.physical_position.x, xx entity.physical_position.y }, 1);
            emitter := create_particle_emitter(system, 0, 64);
            emitter.shape = .Box;
            emitter.box_half_size = .{ 0.15, 0.15 };
            emitter.drag     = 0.7;
            emitter.size     = .[ .{ 0.02, 0.02 }, .{ 0.05, 0.05 } ];
            emitter.speed    = .[ 3, 5 ];
            emitter.lifetime = .[ 0.6, 1.0 ];
            emitter.color    = .[ .{ 255, 0, 0, 255 }, .{ 184, 4, 70, 255 } ];
            emitter.particles_per_second = 1024;
            emitter.alive_t  = 0.6;
        }
        
        // Play heal particles
        if entity.entity_flags & .Living && gained_heart {
            system, emitter := create_halo_particles(client, entity, 1);
            emitter.alive_t  = 0.5;
            emitter.color    = .[ .{ 255, 0, 0, 255 }, .{ 184, 4, 70, 255 } ];
        }
            
        entity.health = msg.entity_health.new_health;
        
      case .Guy_State;
        entity := get_entity(client, msg.guy_state.entity_pid);
        guy := down(entity, Guy);

        // State Transitions
        if guy.state != msg.guy_state.state {
            stop_sound(client, *guy.sound);

            if #complete msg.guy_state.state == {
              case .Digging;      guy.sound = play_sound_on_entity(client, .Guy_Digging_0, entity, .Looping);
              case .Carrying;     guy.sound = play_sound_on_entity(client, .Hud_Pickup_0, entity, .Default);
              case .Resurrecting; 
                guy.sound = play_sound_on_entity(client, .Guy_Resurrecting_0, entity, .Default);
                guy.resurrection_t = 0;
              case .Dead;
                guy.sound = play_sound_on_entity(client, .Guy_Death_0, entity, .Default);
                play_animation_from_group(client, guy, .Guy_Dead);
              case .Idle; if guy.state == .Carrying guy.sound = play_sound_on_entity(client, .Hud_Placedown_0, entity, .Default);
            }

            if msg.guy_state.state != .Dead {
                // If the player just stopped being dead, we want to switch away from the Death animation.
                // We want this death animation to keep being played as long as we are dead, which is why
                // no other part of the code does this specific job (i.e. when a dead guy is taking damage,
                // we *don't* want to play the damage animation, because he's already dead...)
                play_animation_from_group(client, guy, .Guy_Idle);
            }
        }

        guy.state           = msg.guy_state.state;
        guy.target_position = msg.guy_state.target_position;
        guy.carrying_item   = msg.guy_state.carrying_item;
        guy.strength_t      = msg.guy_state.strength_t;
        
        if is_local_guy_pid(client, guy.pid) && guy.state == .Carrying && guy.carrying_item == .Shard {
            request_tutorial_panel(client, .Using_The_Crafting_Menu);
        }

      case .Emitter_State;
        entity := get_entity(client, msg.emitter_state.entity_pid);
        emitter := down(entity, Emitter);

        previous_state := emitter.state;

        emitter.state = msg.emitter_state.state;
        emitter.current_charge = msg.emitter_state.current_charge;

        if emitter.state == {
          case .Active; 
            if previous_state != .Active {
                stop_sound(client, *emitter.sound); // Stop the charging up sound
            }

          case .Off;
            should_play_sound := emitter.currently_charging_up && emitter.current_charge < EMITTER_MAX_BASE_CHARGE[client.game_mode]; // Avoid glitching at the end due to client side prediction
            if should_play_sound && !sound_active(client, emitter.sound) {
                emitter.sound = play_sound_on_entity(client, .Emitter_Charging, emitter, .Default);
                set_sound_playback_position(client, emitter.sound, emitter.current_charge / EMITTER_MAX_BASE_CHARGE[client.game_mode]);
            } else if !should_play_sound {
                stop_sound(client, *emitter.sound);
            }
        }

      case .Item_Stack_State;
        entity := get_entity(client, msg.item_stack_state.entity_pid);
        item_stack := down(entity, Item_Stack);
        item_stack.item_kind = msg.item_stack_state.item_kind;
        item_stack.count     = msg.item_stack_state.count;

      case .Torch_State;
        entity := get_entity(client, msg.torch_state.entity_pid);
        torch := down(entity, Torch);
        torch.time_left_in_seconds = msg.torch_state.time_left_in_seconds;

      case .Chest_State;
        entity := get_entity(client, msg.chest_state.entity_pid);
        chest := down(entity, Chest);
        chest.inventory = msg.chest_state.inventory;
        chest.visually_open = msg.chest_state.visually_open;

      case .Frog_State;
        entity := get_entity(client, msg.frog_state.entity_pid);
        frog := down(entity, Frog);

        if frog.state != msg.frog_state.state {
            frog.state_t = 0;

            if msg.frog_state.state == {
              case .Idle; play_animation_from_group(client, frog, .Frog_Idle);
              case .Recovering; play_animation_from_group(client, frog, .Frog_Recovering);
              case .Attacking;
                frog.sound = play_sound_on_entity(client, .Frog_Attack_0, entity, .Once_Per_Frame);
                play_animation_from_group(client, frog, .Frog_Attacking);

                particles := create_particle_system(client, FROG_ATTACK_TIME, frog.visual_position, 1);
                emitter := create_particle_emitter(particles, 0, 256);
                emitter.shape    = .Cone;
                emitter.emissive = true;
                emitter.drag     = .9;
                emitter.speed    = .[ 4, 6 ];
                emitter.lifetime = .[ 0.5, 0.8 ];
                emitter.color    = .[ .{ 255, 241, 99, 255 }, .{ 255, 111, 52, 255 } ];
                emitter.particles_per_second = 1024;
                emitter.alive_t  = 0.5;

                theta := visual_from_physical_rotation(frog.physical_rotation);
                emitter.cone_angles = .[ theta - 0.03, theta + 0.03 ];
            }
        }

        frog.state = msg.frog_state.state;

      case .Goblin_State;
        entity := get_entity(client, msg.goblin_state.entity_pid);
        goblin := down(entity, Goblin);

        if goblin.state != msg.goblin_state.state {
            goblin.state_t = 0;

            if msg.goblin_state.state == {
              case .Idle; play_animation_from_group(client, goblin, .Goblin_Idle);
              case .Recovering; play_animation_from_group(client, goblin, .Goblin_Recovering);
              case .Attacking;
                goblin.sound = play_sound_on_entity(client, .Goblin_Attack_0, entity, .Once_Per_Frame);
                play_animation_from_group(client, goblin, .Goblin_Attacking);
            }
        }

        goblin.state = msg.goblin_state.state;

      case .Slime_State;
        entity := get_entity(client, msg.slime_state.entity_pid);
        slime := down(entity, Slime);

        if slime.state != msg.slime_state.state {
            if msg.slime_state.state == .Fleeing {
                play_sound_on_entity(client, .Slime_Scared_0, entity, .Once_Per_Frame);
            }
        }
        
        if msg.slime_state.state == {
          case .Hiding; bitfield_add(*slime.entity_flags, Entity_Flags.Disabled_Temporarily);
          case; bitfield_remove(*slime.entity_flags, Entity_Flags.Disabled_Temporarily);
        }

        slime.state = msg.slime_state.state;
        
        for i := 0; i < client.all_entities.slot_count; ++i {
            entity, occupied := index_bucket_array(*client.all_entities, i);
            if occupied && entity.entity_kind == .Slime_Hole then update_slime_hole(client, entity);
        }

      case .Void_Eye_State;
        entity := get_entity(client, msg.void_eye_state.entity_pid);
        eye := down(entity, Void_Eye);
        eye.state = msg.void_eye_state.state;
    }
}

read_incoming_packets :: (client: *Client) {
    while read_packet(*client.connection) {
        packet :: *client.connection.incoming_packet;
        
        update_virtual_connection_information_for_packet(*client.connection, *packet.header);
        
        if packet.header.packet_type == {
          case Packet_Type.Connection_Established;
            if client.next_state == .Connecting {
                server_version: string = string.{ packet.body_size, packet.body };
                valid_connection: bool = server_version == VERSION_STRING;
                
                if !valid_connection {
                    set_info_text(client, DEFAULT_INFO_TEXT_TIMER, "The server is running a different version than you (% vs %)!", server_version, VERSION_STRING);
#if !DEVELOPER {
    client.next_state = .Main_Menu;
    break;
}
                }
                
                client.my_client_pid = packet.header.sender_client_id;
                client.connection.info.client_id = client.my_client_pid;
                client.next_state = .Lobby;

                for i := 0; i < client.local_player_count; ++i {
                    send_player_information_message(client, i);
                }
            }
          
          case Packet_Type.Connection_Closed;
            client.previous_game_summary.result = .Connection_Lost;
            initiate_state_transition(client, .Game_Over, 0);
            
          case Packet_Type.Ping;
            timestamp: CPU_Time = ~(cast(*CPU_Time) *packet.body[0]);
            client.latest_rtt = os_convert_cpu_time(os_get_cpu_time() - timestamp, .Milliseconds);

          case Packet_Type.Message;
            msg: Message = ---;
            while read_message(packet, *msg) {
#if DEVELOPER   register_message_history(client, *client.incoming_message_history, *msg);
                handle_incoming_message(client, *msg);
            }
        }
    }
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

send_outgoing_messages :: (client: *Client) {
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

handle_server_timeout :: (client: *Client, next_screen: Game_State, info_text: string) {
    if os_convert_cpu_time(os_get_cpu_time() - client.connection.time_of_last_received_packet, .Seconds) > NETWORK_TIMEOUT {
        client.previous_game_summary.result = .Connection_Lost;
        initiate_state_transition(client, next_screen, 0);
        set_info_text(client, DEFAULT_INFO_TEXT_TIMER, info_text);
    } else if os_convert_cpu_time(os_get_cpu_time() - client.connection.time_of_last_sent_packet, .Seconds) > NETWORK_PING_INTERVAL {
        timestamp := os_get_cpu_time();
        send_ping_packet(*client.connection, .{ size_of(timestamp), xx *timestamp });
    }
}

send_game_start_request_message :: (client: *Client) {
    msg := make_message(Request_Game_Start_Message);
    msg.request_game_start.game_mode = client.config.requested_game_mode;
    array_add(*client.outgoing_messages, msg);
}

start_the_game :: (client: *Client, game_info: Game_Start_Message) {
    client.pause_menu_open        = false;
    client.server_paused_game     = false;
    client.requested_game_forfeit = false;
    client.current_biome          = .Count;
    client.game_seed  = game_info.seed;
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
    camera.zoom += (desired_zoom - camera.zoom) * min(client.tick_time * 20, 1); // Also interpolate while in free-camera mode...
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



/* ----------------------------------------------- Logic Helpers ---------------------------------------------- */

get_colors_for_digging_particles :: (target_entity: *Entity) -> [2]GE_Color {
    colors: [2] GE_Color = ---;

    if target_entity.entity_kind == {
      case .Bedrock; colors = .[ .{ 102, 102, 102, 220 }, .{ 130, 130, 130, 220 } ];
      case .Crystal, .Mirror; colors = .[ .{ 70, 115, 206, 150 }, .{ 154, 172, 206, 150 } ];
      case .Coal; colors = .[ .{ 76, 49, 53, 255 }, .{ 62, 58, 58, 255 } ];
      case .Rock, .Chest; colors = .[ .{ 134, 134, 134, 255 }, .{ 192, 192, 192, 255 } ];
    }
    
    return colors;
}

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

is_furthest_active_emitter :: (client: *Client, emitter: *Emitter) -> bool {
    for i := 0; i < client.emitters.slot_count; ++i {
        other_emitter, occupied := index_bucket_array(*client.emitters, i);
        if !occupied || other_emitter == emitter || other_emitter.state == .Off || other_emitter.physical_position.x < emitter.physical_position.x continue;

        return false;
    }

    return true;
}

is_emitter_beam_at :: (client: *Client, position: v2i) -> bool, *Emitter, Direction {
    for i := 0; i < client.emitters.slot_count; ++i {
        emitter, occupied := index_bucket_array(*client.emitters, i);
        if !occupied || emitter.state == .Off continue;

        for j := 0; j < emitter.beam_data.fields.count; ++j {
            field := array_get(*emitter.beam_data.fields, j);
            if field.x == position.x && field.y == position.y return true, emitter, field.incoming_direction;
        }
    }
    
    return false, ---, ---;
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

clear_beam_data :: (client: *Client, data: *Beam_Data) {
    array_clear_without_deallocation(*data.fields);
    data.fields.allocator = *client.tick_allocator;
}

recalculate_beam :: (client: *Client, beam: *Beam_Data, position: v2i, direction: Direction, include_initial_position: bool, max_length: s64) {
    if include_initial_position then array_add(*beam.fields, Beam_Data.Field.{ position, direction });
    
    while beam.fields.count < max_length {
        vector := vector_from_direction(direction);
        position.x += vector.x;
        position.y += vector.y;
        if !position_in_bounds(client, position) break;
        
        blocking := find_entity_with_flags_at_position(client, .Blocks_Beam, position);
        
        if blocking == null {
            array_add(*beam.fields, Beam_Data.Field.{ position, direction });
        } else if blocking.entity_kind == .Mirror {
            reflected_direction, reflection_success := reflect_direction(direction, blocking.physical_rotation);
            if reflection_success {
                array_add(*beam.fields, Beam_Data.Field.{ position, direction });
                direction = reflected_direction;
            } else {
                break;
            }
        } else if blocking.entity_kind == .Emitter {
            if direction == blocking.physical_rotation {
                array_add(*beam.fields, Beam_Data.Field.{ position, direction });
            }
            break;
        } else {
            break;
        }
    }
}

update_local_player_input :: (client: *Client, local_player: *Local_Player) {
    if local_player.guy_pid == INVALID_PID return; // Could happen if the server didn't send us the Player_Information quick enough...
    
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


/* ----------------------------------------------- Entity Logic ----------------------------------------------- */

update_powered_emitter :: (client: *Client, emitter: *Emitter) {
    //
    // Update the emitter beam
    //
    clear_beam_data(client, *emitter.beam_data);

    previous_charge := emitter.current_charge;
    emitter.current_charge = max(emitter.current_charge - client.tick_time, 0);

    if emitter.current_charge > 0 {
        recalculate_beam(client, *emitter.beam_data, emitter.physical_position, emitter.physical_rotation, true, MAX_S64);

        if emitter.beam_data.fields.count {
            emitter.beam_ends_in_other_emitter = find_entity_of_kind_at_position(client, .Emitter, array_get(*emitter.beam_data.fields, emitter.beam_data.fields.count - 1).position) != null;
        } else {
            emitter.beam_ends_in_other_emitter = false;
        }

        x := 1 - emitter.current_charge / EMITTER_MAX_BASE_CHARGE[client.game_mode];
        t := cosf(powf(x * 2, 8)) * 0.5 + 0.5;
        emitter.beam_intensity = smoothstep(t, 0, powf(x, 4) / 3);

        /*    
        // :EmitterSound, currently don't have a good sound to use that isn't annoying...
        if !sound_active(client, emitter.sound) {
            emitter.sound = play_sound_on_entity(client, .Emitter_Humming, emitter, .Looping);
        }
        */
    } else if previous_charge > 0 && emitter.current_charge <= 0 && is_furthest_active_emitter(client, emitter) {
        stop_sound(client, *emitter.sound);
        emitter.sound = play_sound(client, .Emitter_Dying, .Default); // Don't spatialize this sound so that everyone can hear it
    }

    //
    // Update the emitter particle system
    //
    if emitter.current_charge > 0 {
        particles: *Particle_System = ---;

        // Create a new particle system if we don't have one yet
        if !particle_system_exists(client, emitter.particles) {
            particles = create_particle_system(client, MAX_F32, emitter.visual_position, 1);
            particle_emitter := create_particle_emitter(particles, 0, 256 * 5);
            particle_emitter.shape    = .Line_String;
            particle_emitter.lifetime = .[ MAX_F32, MAX_F32 ];
            particle_emitter.particles_per_second = 50;
            emitter.particles = particles.pid;
        } else {
            particles = get_particle_system(client, emitter.particles);
        }

        // Update the particle emitter
        particle_emitter := *particles.emitters[0];
        color_t := clamp((emitter.current_charge - EMITTER_MAX_BASE_CHARGE[client.game_mode]) / EMITTER_MAX_OVER_CHARGE, 0, 1);
        particle_emitter.color = .[ ge_mix_colors(.{ 183, 186, 59, 255 }, .{ 189, 89, 10, 255 }, color_t), ge_mix_colors(.{ 252, 252, 187, 255 }, .{ 245, 157, 87, 255 }, color_t) ];
        particles.global_alpha = emitter.beam_intensity;
        particles.world_position = emitter.visual_position;

        // Set the particle line string shape
        fields_with_particles_count := emitter.beam_data.fields.count - emitter.beam_ends_in_other_emitter;
        particle_emitter.line_strings = allocate_slice(*client.tick_allocator, Line_String, fields_with_particles_count);

        WIDTH: f32 : 0.9;
        
        for i := 1; i < fields_with_particles_count; ++i {
            field := array_get(*emitter.beam_data.fields, i);

            my_displacement := vector_from_direction(field.incoming_direction);

            previous_direction := array_get(*emitter.beam_data.fields, i - 1).incoming_direction;
            next_direction     := ifx i + 1 < fields_with_particles_count then array_get(*emitter.beam_data.fields, i + 1).incoming_direction else field.incoming_direction;

            start_angle := (visual_from_physical_rotation(previous_direction) - visual_from_physical_rotation(field.incoming_direction)) / 2 + 0.25;
            end_angle   := (visual_from_physical_rotation(next_direction) - visual_from_physical_rotation(field.incoming_direction)) / 2 + 0.25;
            
            start_field := v2f.{ xx field.position.x - xx my_displacement.x - emitter.visual_position.x,
                                    xx field.position.y - xx my_displacement.y - emitter.visual_position.y };
            end_field := v2f.{ xx field.position.x - emitter.visual_position.x,
                                xx field.position.y - emitter.visual_position.y };
            
            start_width := ifx i == 1 then 0 else WIDTH;
            end_width   := WIDTH;

            particle_emitter.line_strings[i - 1] = .{ .[ start_field, end_field ], .[ start_angle, end_angle ], .[ start_width, end_width ] };

            if i + 1 == fields_with_particles_count {
                final_field := v2f.{ xx field.position.x + xx my_displacement.x / 2 - emitter.visual_position.x,
                                        xx field.position.y + xx my_displacement.y / 2 - emitter.visual_position.y };
                particle_emitter.line_strings[i] = .{ .[ end_field, final_field ], .[ end_angle, end_angle ], .[ end_width, end_width] };
            }
        }
    } else if particle_system_exists(client, emitter.particles) {
        system := get_particle_system(client, emitter.particles);
        system.time_to_live = 0;
        system.emitters[0].line_strings = .[]; // The system will be updated one last time...
        emitter.particles = INVALID_PID;
    }
}

update_off_emitter :: (client: *Client, emitter: *Emitter) {
    clear_beam_data(client, *emitter.beam_data);

    is_beam, other_emitter, incoming_direction := is_emitter_beam_at(client, emitter.physical_position);
    is_lit := is_beam && incoming_direction == emitter.physical_rotation;

    if is_lit {
        emitter.current_charge = clamp(emitter.current_charge + client.tick_time * (EMITTER_MAX_BASE_CHARGE[client.game_mode] / EMITTER_TIME_TO_POWER_UP), 0, EMITTER_MAX_BASE_CHARGE[client.game_mode]);
    } else {
        emitter.current_charge = clamp(emitter.current_charge - client.tick_time * (EMITTER_MAX_BASE_CHARGE[client.game_mode] / EMITTER_TIME_TO_POWER_UP), 0, EMITTER_MAX_BASE_CHARGE[client.game_mode]);
    }

    emitter.currently_charging_up = is_lit && emitter.current_charge < EMITTER_MAX_BASE_CHARGE[client.game_mode];
}

update_torch :: (client: *Client, torch: *Torch) {
    system := get_particle_system(client, torch.particles);
    emitter := *system.emitters[0];
    system.time_to_live += client.tick_time;
    torch.time_left_in_seconds -= client.tick_time;

    desired_animation: Animation_Index = ---;

    if torch.time_left_in_seconds <= TORCH_TIME_TO_LIVE * TORCH_LOW_PERCENTAGE {
        desired_animation = .Torch_Low;
        emitter.particles_per_second = 7;
        emitter.lifetime = .[ 1, 2 ];
        emitter.speed = .[ 1.2, 1.4 ];
    } else if torch.time_left_in_seconds <= TORCH_TIME_TO_LIVE * TORCH_MEDIUM_PERCENTAGE {
        desired_animation = .Torch_Medium;
        emitter.particles_per_second = 5;
        emitter.lifetime = .[ 2, 4 ];
        emitter.speed = .[ 0.8, 1.2 ];
    } else {
        desired_animation = .Torch_High;
    }

    if torch.animation != desired_animation then play_animation(torch, desired_animation);
}

update_guy :: (client: *Client, guy: *Guy) {
    if guy.state == .Resurrecting {
        guy.resurrection_t += client.tick_time / RESURRECTION_TIME;
    }

    guy.seconds_since_last_move += client.tick_time;
    maybe_play_animation_from_group_after(client, guy, .Guy_Idle);

    //
    // Manage strength particles
    //
    if guy.strength_t > 0 && !particle_system_exists(client, guy.strength_particles) {
        system, emitter := create_halo_particles(client, guy, STRENGTH_POTION_TIME);
        emitter.color = .[ .{ 103, 34, 130, 170 }, .{ 164, 37, 214, 170 } ];
        guy.strength_particles = system.pid;
    } else if guy.strength_t <= 0 {
        guy.strength_particles = INVALID_PID;
    }

    if particle_system_exists(client, guy.strength_particles) {
        particles := get_particle_system(client, guy.strength_particles);
        particles.time_to_live = guy.strength_t;
        particles.world_position = .{ guy.visual_position.x, guy.visual_position.y - 0.35 };

        t := guy.strength_t / 10;
        if t <= 1 {
            particles.global_alpha = clamp(1 - powf(1 - t, 2), 0, 1);
        } else {
            particles.global_alpha = 1;
        }
    }
    
    //
    // Manage digging particles
    //
    if guy.state == .Digging && !particle_system_exists(client, guy.digging_particles) {
        target_entity := find_entity_with_flags_at_position(client, .Diggable, guy.target_position);
        if target_entity {
            estimated_digging_time: f32 = target_entity.health / GUY_DPS;
            particles := create_particle_system(client, estimated_digging_time, .{ xx guy.target_position.x, xx guy.target_position.y }, 1);
            emitter := create_particle_emitter(particles, 0, 32);
            emitter.shape = .Box;
            emitter.box_half_size = .{ 0.35, 0.35 };
            emitter.drag = 4;
            emitter.lifetime = .[ 0.4, 0.8 ];
            emitter.color = get_colors_for_digging_particles(target_entity);
            emitter.particles_per_second = xx emitter.particles.count / emitter.lifetime[1];
            guy.digging_particles = particles.pid;
        }
    } else if guy.state != .Digging {
        if particle_system_exists(client, guy.digging_particles) {
            particles := get_particle_system(client, guy.digging_particles);
            particles.emitters[0].particles_per_second = 0;
            particles.time_to_live = 0.5;
        }

        guy.digging_particles = INVALID_PID;
    }
}

update_frog :: (client: *Client, frog: *Frog) {
    clear_beam_data(client, *frog.beam_data);

    if frog.state == {
      case .Attacking;
        recalculate_beam(client, *frog.beam_data, frog.physical_position, frog.physical_rotation, false, FROG_BEAM_LENGTH);
    }

    frog.state_t += client.tick_time;
}

update_goblin :: (client: *Client, goblin: *Goblin) {
    maybe_play_animation_from_group_after(client, goblin, .Goblin_Idle);
}

update_slime :: (client: *Client, slime: *Slime) {
    maybe_play_animation_from_group_after(client, slime, .Slime_Idle);

    if #complete slime.state == {
      case .Idle, .Hiding;
        slime.particles = INVALID_PID;

      case .Fleeing;
        if !particle_system_exists(client, slime.particles) {
            system, emitter := create_halo_particles(client, slime, 0.5);
            emitter.color       = .[ .{ 0, 255, 253, 255 }, .{ 91, 166, 201, 255 } ];
            emitter.shape       = .Cone;
            emitter.cone_angles = .[ -0.1, 0.1 ];
            emitter.speed       = .[ 2, 3 ];
            emitter.drag        = 3;
            emitter.gravity     = .{ 0, 1 };
            emitter.lifetime    = .[ 0.3, 0.7 ];
            emitter.particles_per_second = 32;
            slime.particles     = system.pid;
        }

        system := get_particle_system(client, slime.particles);
        system.world_position = slime.visual_position;
        system.time_to_live = 0.5;
        system.emitters[0].alive_t = 0.5;
    }
}

update_void_eye :: (client: *Client, eye: *Void_Eye) {
    if eye.state == .Attacking && !sound_active(client, eye.sound) {
        eye.sound = play_sound_on_entity(client, .Void_Eye_Attack_0, eye, .Once_Per_Frame);
    }
}

update_slime_hole :: (client: *Client, hole: *Entity) {
    found_any_slime := false;

    for i := 0; i < client.slimes.slot_count; ++i {
        slime, occupied := index_bucket_array(*client.slimes, i);
        if occupied && !slime.marked_for_removal && slime.state == .Hiding && slime.physical_position.x == hole.physical_position.x && slime.physical_position.y == hole.physical_position.y {
            found_any_slime = true;
            break;
        }
    }
    
    if found_any_slime {
        play_animation(hole, .Slime_Hole_Filled);
    } else {
        disable_animation(hole);
    }
}



/* ------------------------------------------------- UI Panels ------------------------------------------------ */

do_game_mode_selector :: (client: *Client) {
    ui :: *client.ui;

    if ui_push_dropdown(ui, "Campaign", .Vertical, true, enum_names(Game_Mode)[client.config.requested_game_mode]) {
        for i := 0; i < Game_Mode.Count; ++i {
            if !DEVELOPER && i == Game_Mode.Developer continue;

            if ui_button(ui, enum_names(Game_Mode)[i]) {
                client.config.requested_game_mode = i;
            }
        }
    }
    ui_pop_dropdown(ui);
}

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
