Hud :: struct {
    // Exposed intermediate state
    state: Hud_State;
    previously_opened_state: Hud_State;
    was_open_this_frame: bool;
    was_confirmed_this_frame: bool;

    crafting_recipe_confirmed_this_frame: Crafting_Recipe;
    cheat_confirmed_this_frame: Cheat;
    chest_item_confirmed_this_frame: Item_Kind;

    hud_providing_entity: Pid; // Can be a trader, a chest... If this is gone, we want to automatically close the hud...

    // Underlying data
    #using data: union {
        crafting_menu: struct {
            recipes: []Crafting_Recipe;
        };

        cheat_menu: struct {
        };

        chest_menu: struct {
            item_kinds: []Item_Kind;
            item_count: []s64;
        };
    };
    
    // Selection data
    available_options: s64;
    selected_option: s64;
    cursor_enabled: bool; // The cursor is activated when moving the mouse or when using the joystick for selection. Otherwise, we stick to regular left+right movements through button inputs
    cursor_theta: f32;
    animation_t: []f32;

    // Display data
    screen_center: v2f;
    inner_wheel_radius: f32;
    outer_wheel_radius: f32;
    icon_radius: f32;
    angle_per_option: f32;
    padding_per_option: f32;
    angle_per_icon: f32 : 0.05;
}

create_hud :: (client: *Client, local_player_index: s64) {
    hud := *client.local_players[local_player_index].hud;
    hud.state = .Disabled;
}

update_player_hud :: (client: *Client, local_player: *Local_Player) {
    hud := *local_player.hud;
    guy_entity := get_entity(client, local_player.guy_pid);
    guy := down(guy_entity, Guy);

    //
    // Clear out persistent state
    //
    hud.was_open_this_frame = hud.state != .Disabled;
    hud.was_confirmed_this_frame = false;
    
    hud.crafting_recipe_confirmed_this_frame = .Count;
    hud.cheat_confirmed_this_frame           = .Count;
    hud.chest_item_confirmed_this_frame      = .Count;

    if client.pause_menu_open {
        close_hud(client, local_player, guy);
        return;
    }
    
    //
    // Toggle the active state
    //

    hud_opened_this_frame := false;
    
    // This is a bit ugly, but rotating mirrors should have priority over opening the hud,
    // since they have the same keybindings. Since we're doing the hud update before the
    // general guy input though, we need to handle that here...
    if !find_entity_of_kind_at_position(client, .Mirror, guy.target_position) && input_action_fired_for_local_player(client, local_player, .Hud_Toggle, .Pressed) {
        guy_entity := get_entity(client, local_player.guy_pid);
        guy := down(guy_entity, Guy);

        chest_entity := find_entity_of_kind_at_position(client, .Chest, guy.target_position);
        trader_entity := find_entity_of_kind_at_position(client, .Trader, guy.target_position);

        if chest_entity {
            maybe_open_hud(client, local_player, guy, .Chest_Menu, chest_entity.pid);
        } else if trader_entity {
            maybe_open_hud(client, local_player, guy, .Crafting_Menu, trader_entity.pid); // Actually the shop menu...
        } else {
            maybe_open_hud(client, local_player, guy, .Crafting_Menu, INVALID_PID);
        }

        hud_opened_this_frame = true;
    }

    // Close the hud if the target entity was (re-) moved.
    if hud.hud_providing_entity != INVALID_PID && hud_providing_entity_is_gone(client, hud, guy) {
        close_hud(client, local_player, guy);
    }

    // Close the hud if the player exited it
    if hud.state != .Disabled && input_action_fired_for_local_player(client, local_player, .Hud_Close, .Pressed) {
        close_hud(client, local_player, guy);
    }

    // Close the hud if the player died
    if hud.state != .Disabled && guy.state == .Dead {
        close_hud(client, local_player, guy);
    }

#if DEVELOPER {
    if input_action_fired_for_local_player(client, local_player, .Cheat_Menu_Toggle, .Pressed) {
        maybe_open_hud(client, local_player, guy, .Cheat_Menu, INVALID_PID);
        hud_opened_this_frame = true;
    }
}

    //
    // Update the selected option
    //
    if hud.state != .Disabled {
        if input_action_fired_for_local_player(client, local_player, .Hud_Left, .Pressed) {
            hud.selected_option = (hud.selected_option - 1) % hud.available_options;
            hud.cursor_enabled = false;
        }

        if input_action_fired_for_local_player(client, local_player, .Hud_Right, .Pressed) {
            hud.selected_option = (hud.selected_option + 1) % hud.available_options;
            hud.cursor_enabled = false;
        }

        if local_player.input_binder.active_input_device == {
          case .Gamepad;
            position := v2f.{ client.window.gamepads[local_player.input_binder.gamepad_index].axes[.Left_Stick_X], client.window.gamepads[local_player.input_binder.gamepad_index].axes[.Left_Stick_Y] };
            magnitude := v2_magnitude(position);
            
            if magnitude > 0.5 {
                hud.cursor_enabled = true;
                hud.cursor_theta   = (atan2f(-position.x / magnitude, position.y / magnitude) + FPI) / FTAU;
            }

          case .Keyboard;
            if !hud_opened_this_frame && (client.window.mouse_delta_x != 0 || client.window.mouse_delta_y != 0) { // In the frame where the hud is opened the mouse is moved by us programatically...
                position := v2f.{ cast(f32) client.window.mouse_x - hud.screen_center.x, cast(f32) client.window.mouse_y - hud.screen_center.y };
                
                magnitude := v2_magnitude(position);
                hud.cursor_theta = (atan2f(-position.x / magnitude, position.y / magnitude) + FPI) / FTAU;
                hud.cursor_enabled = true;
            }
        }

        if hud.cursor_enabled {
            hud.selected_option = cast(s64) floor(hud.cursor_theta * cast(f32) hud.available_options) % hud.available_options;
        }
    }
    
    //
    // Confirm the selected option
    //
    if hud.state != .Disabled && input_action_fired_for_local_player(client, local_player, .Hud_Confirm, .Pressed) {
        hud.was_confirmed_this_frame = true;

        if #complete hud.state == {
          case .Disabled;

          case .Crafting_Menu;
            hud.crafting_recipe_confirmed_this_frame = hud.crafting_menu.recipes[hud.selected_option];

            if crafting_recipe_should_succeed(client, guy, hud.crafting_recipe_confirmed_this_frame) {
                play_sound(client, .Hud_Success_0, .Default);
                if hud.crafting_recipe_confirmed_this_frame == .Mirror then request_tutorial_panel(client, .Using_Mirrors_To_Kill);
            } else {
                play_sound(client, .Hud_Failure_0, .Default);
            }

            close_hud(client, local_player, guy);

          case .Cheat_Menu;
            hud.cheat_confirmed_this_frame = hud.selected_option;
            play_sound(client, .Hud_Success_0, .Default);
            close_hud(client, local_player, guy);

          case .Chest_Menu;
            hud.chest_item_confirmed_this_frame = hud.chest_menu.item_kinds[hud.selected_option];
            play_sound(client, .Hud_Success_0, .Default);
            close_hud(client, local_player, guy);
        }
    }
        
    //
    // Update the visual data
    //
    for i := 0; i < hud.available_options; ++i {
        if i == hud.selected_option {
            hud.animation_t[i] += client.tick_time * 5;
        } else {
            hud.animation_t[i] -= client.tick_time * 3;
        }

        hud.animation_t[i] = clamp(hud.animation_t[i], 0, 1);
    }

    {
        guy := get_entity(client, local_player.guy_pid);
        hud.screen_center = screen_from_world_position(*local_player.camera, guy.visual_position);
        hud.outer_wheel_radius = local_player.camera.world_to_screen_coordinates.y * 0.85;
        hud.inner_wheel_radius = local_player.camera.world_to_screen_coordinates.y * 0.6;
        hud.icon_radius        = (hud.inner_wheel_radius + hud.outer_wheel_radius) * 0.5;

        hud.padding_per_option = ifx hud.available_options > 1 then 0.1 / cast(f32) hud.available_options else 0;
        hud.angle_per_option   = 1.0 / cast(f32) hud.available_options;
    }
}

draw_player_hud :: (client: *Client, local_player: *Local_Player) {
    if local_player.guy_pid == INVALID_PID return;
    
    hud := *local_player.hud;

    if hud.state != .Disabled {
        // Draw the circle background for each option
        for i := 0; i < hud.available_options; ++i {
            success := hud_option_should_succeed(client, local_player, i);

            color0, color1: GE_Color = ---;

            if success {
                color0, color1 = .{ 40, 50, 60, 250 }, .{ 50, 89, 128, 230 };
            } else {
                color0, color1 = .{ 50, 40, 40, 250 }, .{ 90, 80, 80, 230 };
            }

            draw_circle_segment(client, hud, hud.animation_t[i], color0, color1, i);
        }

        // Draw the cursor if used
        if hud.cursor_enabled && hud.available_options > 1 {
            covered_angle := 0.9 / cast(f32) hud.available_options;
            theta0 := hud.cursor_theta - covered_angle / 2;
            theta1 := hud.cursor_theta + covered_angle / 2;
            draw_curve(client, hud, hud.inner_wheel_radius * 0.9, theta0, theta1);
        }

        // Draw the specific option, which depends on the open hud
        if #complete hud.state == {
          case .Disabled;

          case .Crafting_Menu;
            for i := 0; i < hud.available_options; ++i {
                recipe := hud.crafting_menu.recipes[i];
                should_succeed := hud_option_should_succeed(client, local_player, i);
                tint := ifx should_succeed then WHITE_COLOR else GRAY_COLOR;

                for j := 0; j < CRAFTING_RECIPE_REQUIRED_ITEMS[recipe].count; ++j {
                    draw_icon(client, hud, get_sprite_index_for_item(CRAFTING_RECIPE_REQUIRED_ITEMS[recipe][j]), 1, i, xx j + 1, tint);
                }

                draw_divider(client, hud, i, tint);
                draw_icon(client, hud, CRAFTING_RECIPE_ICONS[recipe], 1, i, -1, tint);
            }

          case .Cheat_Menu;
            for i := 0; i < hud.available_options; ++i {
                draw_icon(client, hud, CHEAT_ICONS[i], 1, i, 0, WHITE_COLOR);
            }

          case .Chest_Menu;
            for i := 0; i < hud.available_options; ++i {
                sprite_index := get_sprite_index_for_item(hud.chest_menu.item_kinds[i]);

                midpoint: f32 = xx hud.chest_menu.item_count[i] / 2;
                for j := 0; j < hud.chest_menu.item_count[i]; ++j {
                    draw_icon(client, hud, sprite_index, 1, i, xx j + 0.5 - midpoint, WHITE_COLOR);
                }
            }
        }

        // Draw the confirmation input binding hint
        confirm_sprite := get_sprite_index_for_input_action(client, local_player, .Hud_Confirm);
        draw_icon(client, hud, confirm_sprite, 0.6, hud.selected_option, 0, WHITE_COLOR);
    }


    // Spectating overlay
    guy_entity := get_entity(client, local_player.guy_pid);
    guy := down(guy_entity, Guy);

    if guy.state == .Dead {
        font :: *client.hud_font;
        position: v2f = .{ 
            round((local_player.viewport[0] + local_player.viewport[2]) * 0.5), 
            round((local_player.viewport[1] + local_player.viewport[3]) * 0.75)
        };

        // Draw the "spectating" hint
        draw_text_screen_space(client, font, "Spectating", position, .Center | .Median, GRAY_COLOR, .Default);
        position.y += cast(f32) font.line_height;

        player_name_text: string = find_player_name_from_guy_pid(client, local_player.entity_tracked_by_camera);

        // Draw the player name
        {
            spectated_guy := down(get_entity(client, local_player.entity_tracked_by_camera), Guy);
            if spectated_guy.state == .Dead {
                player_name_text = concatenate_strings(*temp, player_name_text, " (DEAD)");
            }

            draw_text_screen_space(client, font, player_name_text, position, .Center | .Median, WHITE_COLOR, .Default);
        }

        // Draw Arrows indicating that you can switch to other players
        {
            text_width: f32 = xx get_string_width_in_pixels(font, player_name_text);

            sprite_index :: Sprite_Index.Hud_Arrow;
            screen_size: GE_Vector2 : .{ 32, 32 };
            screen_padding: f32 = 10;
            screen_offset: f32 = round(text_width * 0.5) + screen_padding + screen_size.x;

            draw_sprite_screen_space(client, sprite_index, .{ position.x + screen_offset, position.y }, screen_size, 0.25, .{ 255, 255, 255, 255 }, .None);
            draw_sprite_screen_space(client, sprite_index, .{ position.x - screen_offset, position.y }, screen_size, -0.25, .{ 255, 255, 255, 255 }, .None);
        }
    }
}

draw_global_hud :: (client: *Client) {
    // Game Score
    {
        text := tprint("Score: %", client.game_score);
        position: v2f = .{ round(cast(f32) client.window.w * 0.95), round(cast(f32) client.window.h * 0.05) };
        draw_text_screen_space(client, *client.hud_font, text, position, .Right | .Top, ORANGE_COLOR, .Shadow);
    }

    // Forfeit Information
    if client.requested_game_forfeit {
        position: v2f = .{ round(cast(f32) client.window.w * 0.5), round(cast(f32) client.window.h * 0.9) };
        draw_text_screen_space(client, *client.hud_font, "Voted to Forfeit...", position, .Center | .Bottom, RED_COLOR, .Shadow);
    }
}

draw_sound_hud :: (client: *Client) {
    waveform_offset_top: f32 : 0.2;
    waveform_height:     f32 : 32;
    waveform_linegap:    f32 : waveform_height + 16;

    draw_history :: (client: *Client, history: []Sound_History_Sample, channel_index: s64, channel_name: string) {
        width: f32 = cast(f32) min(client.window.w / 2, history.count);

        top_left := GE_Vector2.{ (xx client.window.w - width) * 0.5, xx client.window.h * waveform_offset_top + xx channel_index * waveform_linegap };
        bottom_right := GE_Vector2.{ top_left.x + width, top_left.y + waveform_height };
        median := (top_left.y + bottom_right.y) * 0.5;

        BACKGROUND_COLOR: GE_Color : .{ 50, 50, 50, 230 };
        DEFAULT_SAMPLE_COLOR: GE_Color : .{ 100, 100, 255, 255 };
        WARNING_SAMPLE_COLOR: GE_Color : .{ 255, 100, 100, 255 };
        WARNING_THRESHOLD: f32 : 0.99;

        draw_text_screen_space(client, *client.ui_font, channel_name, .{ top_left.x - 5, median }, .Right | .Median, WHITE_COLOR, .Shadow);
        draw_rect_screen_space(client, top_left, bottom_right, BACKGROUND_COLOR);

        samples_to_draw := cast(s64) width;

        for x := 0; x < samples_to_draw; ++x {
            sample := history[x];

            if sample.high <= sample.low then continue;

            color := DEFAULT_SAMPLE_COLOR;
            if sample.low < -WARNING_THRESHOLD || sample.high > WARNING_THRESHOLD then color = WARNING_SAMPLE_COLOR;

            x0 := top_left.x + cast(f32) x;
            x1 := x0;
            y0 := ceil(median + sample.low * waveform_height * 0.5);
            y1 := floor(median + sample.high * waveform_height * 0.5);

            draw_rect_screen_space(client, .{ x0, y0 }, .{ x1, y1 }, color);
        }

    }

    //
    // Draw the waveform of all channels
    //
    for channel := 0; channel < client.mixer.history.Capacity; ++channel {
        history := client.mixer.history[channel];
        draw_history(client, history, channel, enum_names(Sound_Channel)[channel]);
    }

    //
    // Draw all active sound streams
    //
    {
        x_category:   f32 = 0;
        x_identifier: f32 = x_category + 200;
        x_volume:     f32 = x_identifier + 200;
        x_channels:   f32 = x_volume + 120;
        x_progress:   f32 = x_channels + 120;
        x_flags:      f32 = x_progress + 120;

        x: f32 = xx client.window.w * 0.5 - (x_flags + 200) * 0.5;

        y: f32 = xx client.window.h * waveform_offset_top + xx client.mixer.history.Capacity * waveform_linegap;

        for i := 0; i < client.mixer.streams.count; ++i {
            stream := *client.mixer.streams[i];
            if stream.state == .Stopped continue;

            draw_text_screen_space(client, *client.ui_font, enum_names(Sound_Category)[stream.category], .{ x + x_category, y }, .Left | .Top, WHITE_COLOR, .Default);

            draw_text_screen_space(client, *client.ui_font, stream.sound_data.debug_identifier, .{ x + x_identifier, y }, .Left | .Top, YELLOW_COLOR, .Default);

            volume_text := tprint("vol: %%", cast(s64) (stream.desired_gain * 100));
            draw_text_screen_space(client, *client.ui_font, volume_text, .{ x + x_volume, y }, .Left | .Top, WHITE_COLOR, .Default);

            channel_text := tprint("ch: %", cast(s64) stream.sound_data.channels);
            draw_text_screen_space(client, *client.ui_font, channel_text, .{ x + x_channels, y }, .Left | .Top, WHITE_COLOR, .Default);

            progress_text := tprint("t: %s", format_float(cast(f64) (stream.sound_data.available_frames - stream.offset_in_frames) / cast(f64) MIXER_SAMPLE_RATE, 0, 2));
            draw_text_screen_space(client, *client.ui_font, progress_text, .{ x + x_progress, y }, .Left | .Top, YELLOW_COLOR, .Default);

            flags_text: string = tprint("%", stream.flags);
            draw_text_screen_space(client, *client.ui_font, flags_text, .{ x + x_flags, y }, .Left | .Top, WHITE_COLOR, .Default);

            y += xx client.ui_font.line_height;
        }
    }
}

draw_shadow_hud :: (client: *Client, local_player: *Local_Player) {
    for x := 0; x < client.lightmap.size.x; ++x {
        for y := 0; y < client.lightmap.size.y; ++y {
            shadow := query_shadow(*client.lightmap, .{ x, y });
            if shadow != NO_SHADOW {
                BACKGROUND_HALF_WIDTH: f32 = 0.2 * cast(f32) ((shadow / 10) + 1);
                BACKGROUND_HALF_HEIGHT: f32 : 0.4;
                center: v2f = .{ xx x, xx y };

                text := tprint("%", cast(u64) shadow);

                draw_rect_world_space(client, local_player, 
                    .{ center.x - BACKGROUND_HALF_WIDTH, center.y - BACKGROUND_HALF_HEIGHT },
                    .{ center.x + BACKGROUND_HALF_WIDTH, center.y + BACKGROUND_HALF_HEIGHT },
                    .{ 100, 100, 100, 100 });
                
                draw_text_world_space(client, local_player, *client.title_font, text, .{ xx x, xx y }, .Center | .Median, WHITE_COLOR, .Shadow);
            }
        }
    }
}



/* ------------------------------------------------- Stat Hud ------------------------------------------------- */

Stat_Message :: struct {
    player_kind: Player_Stat_Kind;
    global_kind: Global_Stat_Kind;
    is_global: bool;
    text: string;
    time_left_in_seconds: f32;
    alive_time_in_seconds : f32; // We're resetting the time_left_in_seconds when replacing the message content, which would mess with our text_animation_t.
}

Stat_Hud :: struct {
    messages: [4]Stat_Message; // We only want to show one stat at a time. If however multiple stats are received at the same time, we want to remember those for later... We're just assuming we're never going to have more than 4 stats received at once, to avoid dynamic allocation here...
    active_message_count: s64;
    background_animation_t: f32;
}

reset_stat_hud :: (client: *Client) {
    client.stat_hud.active_message_count = 0;
}

add_player_stat_message :: (client: *Client, player_name: string, kind: Player_Stat_Kind, stat: Statistic) {
    hud := *client.stat_hud;
    text := format_player_stat(*client.world_allocator, player_name, kind, stat);

    found_existing := false;

    for i := 0; i < hud.active_message_count; ++i {
        if !hud.messages[i].is_global && hud.messages[i].player_kind == kind {
            replace_stat_message(client, hud, i, text);
            found_existing = true;
            break;
        }
    }

    if !found_existing {
        add_stat_message(client, text, kind, ---, false);
    }
}

add_global_stat_message :: (client: *Client, kind: Global_Stat_Kind, stat: Statistic) {
    hud := *client.stat_hud;
    text := format_global_stat(*client.world_allocator, kind, stat);

    found_existing := false;

    for i := 0; i < hud.active_message_count; ++i {
        if hud.messages[i].is_global && hud.messages[i].global_kind == kind {
            replace_stat_message(client, hud, i, text);
            found_existing = true;
            break;
        }
    }

    if !found_existing {
        add_stat_message(client, text, ---, kind, true);
    }
}

draw_stat_hud :: (client: *Client) {
    hud := *client.stat_hud;

    ANIMATION_TIME: f32 : 0.2;
    animation_speed: f32 = client.tick_time / ANIMATION_TIME;

    if hud.active_message_count > 0 && hud.messages[hud.active_message_count - 1].time_left_in_seconds >= ANIMATION_TIME {
        hud.background_animation_t = clamp(hud.background_animation_t + animation_speed, 0, 1);
    } else {
        hud.background_animation_t = clamp(hud.background_animation_t - animation_speed, 0, 1);
    }

    if hud.active_message_count == 0 return;

    message := *client.stat_hud.messages[0];

    if !client.server_paused_game {
        message.time_left_in_seconds  -= client.tick_time;
        message.alive_time_in_seconds += client.tick_time;
    }

    text_animation_t := min(smoothstep(message.alive_time_in_seconds, 0, ANIMATION_TIME), smoothstep(message.time_left_in_seconds, 0, ANIMATION_TIME));

    WIDTH:        f32 : 370;
    HEIGHT:       f32 : 64;
    TEXT_WIDTH:   f32 : WIDTH - 20;
    BANNER_WIDTH: f32 : 10;

    top_left            := v2f.{ xx client.window.w - WIDTH * hud.background_animation_t, xx client.window.h * 0.2 };
    banner_bottom_right := v2f.{ top_left.x + BANNER_WIDTH, top_left.y + HEIGHT };
    bottom_right        := v2f.{ top_left.x + WIDTH, top_left.y + HEIGHT };
    text_position       := v2f.{ xx client.window.w - TEXT_WIDTH * text_animation_t, (top_left.y + bottom_right.y) * 0.5 };

    draw_rect_screen_space(client, top_left, bottom_right, .{ DARK_GRAY_COLOR.r, DARK_GRAY_COLOR.g, DARK_GRAY_COLOR.b, 200 });
    draw_rect_screen_space(client, top_left, banner_bottom_right, ORANGE_COLOR);

    // Calculate the number of lines we'll have
    lines: [..]string;
    lines.allocator = *temp;

    {
        text_view := message.text;
        while text_view.count {
            line_end := find_line_wrapping_point_with_font(*client.ui_font, text_view, xx WIDTH - 20, true);
            line_view := substring_view(text_view, 0, line_end);
            array_add(*lines, line_view);
            text_view = substring_view(text_view, line_end, text_view.count);
        }
    }

    for i := 0; i < lines.count; ++i {
        vertical_offset: f32 = cast(f32) client.ui_font.line_height * cast(f32) (i * 2 - (lines.count - 1)) * 0.5;
        line_position := v2f.{ text_position.x, text_position.y + vertical_offset };
        draw_text_screen_space(client, *client.ui_font, array_get(*lines, i), line_position, .Left | .Median, WHITE_COLOR, .Default);
    }

    if message.time_left_in_seconds < 0 then remove_first_stat_message(client);
}



#file_scope

Hud_State :: enum {
    Disabled;
    Crafting_Menu;
    Cheat_Menu;
    Chest_Menu;
}

CRAFTING_RECIPE_ICONS: [Crafting_Recipe.Count]Sprite_Index : .[
    /* Crafting hud */
    .Mirror,
    .Torch_High_0,
    .Chest_Closed,

    /* Trader hud */
    .Health_Potion,
    .Strength_Potion,
    .Shard,
    .Coal_Item,
];

CHEAT_ICONS: [Cheat.Count]Sprite_Index : .[
    .Coin,                  // Give Coin
    .Coal_Item,             // Give Coal
    .Shard,                 // Give Shard
    .Stone,                 // Give Stone
    .Health_Potion,         // Give Health
    .Strength_Potion,       // Give Strength
    .Goblin_Idle_Front_0,   // Spawn Goblin
    .Frog_Idle_Front_0,     // Spawn Frog
    .Slime_Idle_Front_0,    // Spawn Slime
    .Trader_Idle_Front_0,   // Spawn Trader
    .Hud_Heart_Full,        // Toggle Invincibility
    .Ghost_Mode,            // Toggle Ghost Mode
    .Kill_Entity,           // Kill entity
    .Emitter,               // Complete Emitters
];

close_hud :: (client: *Client, local_player: *Local_Player, guy: *Guy) {
    hud := *local_player.hud;

    if #complete hud.state == {
      case .Disabled, .Cheat_Menu;
      case .Crafting_Menu;
        deallocate_slice(*client.world_allocator, *hud.crafting_menu.recipes);
      case .Chest_Menu;
        if entity_exists(client, hud.hud_providing_entity) {
            visually_close_chest(client, down(get_entity(client, hud.hud_providing_entity), Chest));  
        }

        deallocate_slice(*client.world_allocator, *hud.chest_menu.item_kinds);
        deallocate_slice(*client.world_allocator, *hud.chest_menu.item_count);
    }

    deallocate_slice(*client.world_allocator, *hud.animation_t);
    hud.available_options = 0;
    hud.state = .Disabled;
}

switch_to_hud_state :: (client: *Client, hud: *Hud, state: Hud_State, options: s64) {
    if hud.previously_opened_state == state {
        hud.selected_option = hud.selected_option % options;
    } else {
        hud.selected_option = 0;
    }

    hud.state = state;
    hud.available_options = options;
    hud.animation_t = allocate_slice(*client.world_allocator, f32, options);
    clear_memory(hud.animation_t.data, hud.animation_t.count * size_of(f32));
    hud.previously_opened_state = state;
}

maybe_open_hud :: (client: *Client, local_player: *Local_Player, guy: *Guy, state: Hud_State, providing_entity: Pid) {
    hud := *local_player.hud;

    if hud.state == state {
        close_hud(client, local_player, guy);
        return;
    }

    hud.hud_providing_entity = providing_entity;
    
    if #complete state == {
      case .Disabled;

      case .Crafting_Menu;
        // Find the number of enabled recipes
        recipe_count := 0;

        for i := 0; i < Crafting_Recipe.Count; ++i {
            if crafting_recipe_is_enabled(client, local_player, i) then ++recipe_count;
        }

        if recipe_count == 0 break;

        // Allocate the actual recipe options
        hud.crafting_menu.recipes = allocate_slice(*client.world_allocator, Crafting_Recipe, recipe_count);

        recipe_index := 0;
        for i := 0; i < Crafting_Recipe.Count; ++i {
            if crafting_recipe_is_enabled(client, local_player, i) {
                hud.crafting_menu.recipes[recipe_index] = i;
                ++recipe_index;
            }
        }

        switch_to_hud_state(client, hud, state, hud.crafting_menu.recipes.count);

      case .Cheat_Menu;
        switch_to_hud_state(client, hud, .Cheat_Menu, Cheat.Count);

      case .Chest_Menu;
        // Find the number of different items
        chest_entity := get_entity(client, hud.hud_providing_entity);
        chest := down(chest_entity, Chest);
        
        base_item_array: [Item_Kind.Count]s64 = .[ 0 ];
        for i := 0; i < chest.item_count; ++i {
            base_item_array[chest.item_kinds[i]] += 1;
        }

        separate_item_count := 0;
        for i := 0; i < base_item_array.Capacity; ++i {
            if base_item_array[i] > 0 ++separate_item_count;
        }

        if separate_item_count == 0 break;
        
        // Allocate the actual item options
        hud.chest_menu.item_kinds = allocate_slice(*client.world_allocator, Item_Kind, separate_item_count);
        hud.chest_menu.item_count = allocate_slice(*client.world_allocator, s64, separate_item_count);

        index := 0;
        for i := 0; i < base_item_array.Capacity; ++i {
            if base_item_array[i] > 0 {
                hud.chest_menu.item_kinds[index] = i;
                hud.chest_menu.item_count[index] = base_item_array[i];
                ++index;
            }
        }
        
        switch_to_hud_state(client, hud, .Chest_Menu, separate_item_count);
        visually_open_chest(client, chest);
    }

    if local_player.input_binder.active_input_device == .Keyboard {
        set_cursor_position(*client.window, xx hud.screen_center.x, xx hud.screen_center.y);
        hud.cursor_enabled = false;
    }
}

hud_option_should_succeed :: (client: *Client, local_player: *Local_Player, option: s64) -> bool {
    success := true;

    if local_player.hud.state == .Crafting_Menu {
        guy_entity := get_entity(client, local_player.guy_pid);
        success = crafting_recipe_should_succeed(client, down(guy_entity, Guy), local_player.hud.crafting_menu.recipes[option]);
    }

    return success;
}

crafting_recipe_is_enabled :: (client: *Client, local_player: *Local_Player, recipe: Crafting_Recipe) -> bool {
    hud := *local_player.hud;

    if CRAFTING_RECIPE_ENABLER[recipe] != .Count {
        // Only show specific crafting recipes if that specific hud is open
        return hud.hud_providing_entity != INVALID_PID && get_entity(client, hud.hud_providing_entity).entity_kind == CRAFTING_RECIPE_ENABLER[recipe];
    } else {
        // Only show generic crafting recipes without specific enabler if we have the generic crafting menu open
        return hud.hud_providing_entity == INVALID_PID;
    }
}

hud_providing_entity_is_gone :: (client: *Client, hud: *Hud, guy: *Guy) -> bool {
    if !entity_exists(client, hud.hud_providing_entity) return true;

    entity := get_entity(client, hud.hud_providing_entity);
    return entity.physical_position.x != guy.target_position.x || entity.physical_position.y != guy.target_position.y;
}



/* ------------------------------------------- Drawing ------------------------------------------- */

get_icon_size_for_option :: (client: *Client, hud: *Hud, scale: f32, option_index: s64) -> v2f {
    icon_scale_factor := 0.9 + (sinf(client.game_epoch_time * 2 * FTAU) + 0.5) * 0.2 * hud.animation_t[option_index] * scale;
    base_size := hud.outer_wheel_radius - hud.inner_wheel_radius;
    return v2f.{ base_size * icon_scale_factor, base_size * icon_scale_factor };
}

draw_icon :: (client: *Client, hud: *Hud, sprite_index: Sprite_Index, inner_offset: f32, option_index: s64, index_in_option: f32, tint: GE_Color) {
    icon_size := get_icon_size_for_option(client, hud, inner_offset, option_index);

    radians := ((cast(f32) option_index + 0.5) * hud.angle_per_option + index_in_option * hud.angle_per_icon) * FTAU;
    icon_center := v2f.{ round(hud.screen_center.x + sinf(radians) * hud.icon_radius * inner_offset),
                         round(hud.screen_center.y - cosf(radians) * hud.icon_radius * inner_offset) };
    draw_sprite_screen_space(client, sprite_index, icon_center, icon_size, 0, tint, false);
}
    
draw_divider :: (client: *Client, hud: *Hud, option_index: s64, tint: GE_Color) {
    base_size := (hud.outer_wheel_radius - hud.inner_wheel_radius) * 0.5;
    icon_size := v2f.{ base_size, base_size };

    theta := ((cast(f32) option_index + 0.5) * hud.angle_per_option);
    radians := theta * FTAU;
    icon_center := v2f.{ hud.screen_center.x + sinf(radians) * hud.icon_radius,
                         hud.screen_center.y - cosf(radians) * hud.icon_radius };
    draw_sprite_screen_space(client, .Hud_Arrow, icon_center, icon_size, theta - 0.25, tint, false);
}

draw_circle_segment :: (client: *Client, hud: *Hud, animation_t: f32, color0, color1: GE_Color, option_index: s64) {
    background_color := ge_mix_colors(color0, color1, animation_t);
    theta := (cast(f32) option_index + 0.5) * hud.angle_per_option;

    draw_circle_segment_screen_space(client, hud.screen_center, hud.outer_wheel_radius, hud.inner_wheel_radius, theta, hud.angle_per_option, hud.padding_per_option, background_color);

    if option_index == hud.selected_option {
        draw_outlined_circle_segment_screen_space(client, hud.screen_center, hud.outer_wheel_radius, hud.inner_wheel_radius, theta, hud.angle_per_option, hud.padding_per_option, .{ 255, 255, 255, 180 }, 2);
    }
}

draw_curve :: (client: *Client, hud: *Hud, radius: f32, theta0, theta1: f32) {
    SEGMENTS :: 8;

    angle := theta1 - theta0;
    
    for i := 0; i < SEGMENTS; ++i {
        seg_t0 := (theta0 + cast(f32) (i) / cast(f32) SEGMENTS * angle) * FTAU;
        seg_t1 := (theta0 + cast(f32) (i + 1) / cast(f32) SEGMENTS * angle) * FTAU;

        p0 := v2f.{ hud.screen_center.x + sinf(seg_t0) * radius, hud.screen_center.y - cosf(seg_t0) * radius };
        p1 := v2f.{ hud.screen_center.x + sinf(seg_t1) * radius, hud.screen_center.y - cosf(seg_t1) * radius };

        draw_line_screen_space(client, p0, p1, .{ 255, 255, 255, 180 }, 5);
    }
}


/* ------------------------------------------------- Stat Hud ------------------------------------------------- */

STAT_MESSAGE_DURATION: f32 : 5;

remove_first_stat_message :: (client: *Client) {
    deallocate_string(*client.world_allocator, *client.stat_hud.messages[0].text);
    copy_memory(*client.stat_hud.messages[0], *client.stat_hud.messages[1], (client.stat_hud.active_message_count - 1) * size_of(Stat_Message));
    --client.stat_hud.active_message_count;
}

replace_stat_message :: (client: *Client, hud: *Stat_Hud, index: s64, text: string) {
    deallocate_string(*client.world_allocator, *hud.messages[index].text);
    hud.messages[index].text = text;
    hud.messages[index].time_left_in_seconds = STAT_MESSAGE_DURATION;
}

add_stat_message :: (client: *Client, text: string, player_kind: Player_Stat_Kind, global_kind: Global_Stat_Kind, is_global: bool) {
    if client.stat_hud.active_message_count == client.stat_hud.messages.Capacity {
        remove_first_stat_message(client);
    }

    client.stat_hud.messages[client.stat_hud.active_message_count].player_kind = player_kind;
    client.stat_hud.messages[client.stat_hud.active_message_count].global_kind = global_kind;
    client.stat_hud.messages[client.stat_hud.active_message_count].is_global = is_global;
    client.stat_hud.messages[client.stat_hud.active_message_count].text = text;
    client.stat_hud.messages[client.stat_hud.active_message_count].time_left_in_seconds = STAT_MESSAGE_DURATION;
    client.stat_hud.messages[client.stat_hud.active_message_count].alive_time_in_seconds = 0;
    ++client.stat_hud.active_message_count;
}
