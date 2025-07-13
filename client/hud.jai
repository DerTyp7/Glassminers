Hud :: struct {
    // Exposed intermediate state
    state: Hud_State;
    previously_opened_state: Hud_State;
    was_open_this_frame: bool;
    was_confirmed_this_frame: bool;
    
    crafting_recipe_confirmed_this_frame: Crafting_Recipe;
    cheat_confirmed_this_frame: Cheat;
    chest_item_confirmed_this_frame: Item_Kind;

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

update_hud :: (client: *Client, local_player: *Local_Player) {
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
        close_hud(client, hud);
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

        if find_entity_of_kind_at_position(client, .Chest, guy.target_position) {
            maybe_open_hud(client, local_player, guy, .Chest_Menu);
        } else {
            maybe_open_hud(client, local_player, guy, .Crafting_Menu);
        }

        hud_opened_this_frame = true;
    }

#if DEVELOPER {
    if input_action_fired_for_local_player(client, local_player, .Cheat_Menu_Toggle, .Pressed) {
        maybe_open_hud(client, local_player, guy, .Cheat_Menu);
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

            if crafting_recipe_looks_doable(client, guy, hud.crafting_recipe_confirmed_this_frame) {
                play_sound(client, .Hud_Success_0, .Default);
            } else {
                play_sound(client, .Hud_Failure_0, .Default);
            }

            close_hud(client, hud);

          case .Cheat_Menu;
            hud.cheat_confirmed_this_frame = hud.selected_option;
            play_sound(client, .Hud_Success_0, .Default);
            close_hud(client, hud);

          case .Chest_Menu;
            hud.chest_item_confirmed_this_frame = hud.chest_menu.item_kinds[hud.selected_option];
            play_sound(client, .Hud_Success_0, .Default);
            close_hud(client, hud);
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
        hud.outer_wheel_radius = local_player.camera.world_to_screen.y * 0.85;
        hud.inner_wheel_radius = local_player.camera.world_to_screen.y * 0.6;
        hud.icon_radius        = (hud.inner_wheel_radius + hud.outer_wheel_radius) * 0.5;

        hud.padding_per_option = ifx hud.available_options > 1 then 0.1 / cast(f32) hud.available_options else 0;
        hud.angle_per_option   = 1.0 / cast(f32) hud.available_options;
    }
}

draw_hud :: (client: *Client, local_player: *Local_Player) {
    hud := *local_player.hud;

    if hud.state != .Disabled {
        // Draw the circle background for each option
        for i := 0; i < hud.available_options; ++i {
            draw_circle_segment(client, hud, hud.animation_t[i], i);
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

                    for j := 0; j < CRAFTING_RECIPE_REQUIRED_ITEMS[recipe].count; ++j {
                        draw_icon(client, hud, get_sprite_index_for_item(CRAFTING_RECIPE_REQUIRED_ITEMS[recipe][j]), 1, i, xx j + 1);
                    }

                    draw_divider(client, hud, i);

                    draw_icon(client, hud, CRAFTING_RECIPE_ICONS[recipe], 1, i, -1);
                }

            case .Cheat_Menu;
                for i := 0; i < hud.available_options; ++i {
                    draw_icon(client, hud, CHEAT_ICONS[i], 1, i, 0);
                }

            case .Chest_Menu;
                for i := 0; i < hud.available_options; ++i {
                    sprite_index := get_sprite_index_for_item(hud.chest_menu.item_kinds[i]);

                    midpoint: f32 = xx hud.chest_menu.item_count[i] / 2;
                    for j := 0; j < hud.chest_menu.item_count[i]; ++j {
                        draw_icon(client, hud, sprite_index, 1, i, xx j + 0.5 - midpoint);
                    }
                }
        }

        // Draw the confirmation input binding hint
        confirm_sprite := get_sprite_index_for_input_action(client, local_player, .Hud_Confirm);
        draw_icon(client, hud, confirm_sprite, 0.6, hud.selected_option, 0);
    }
    
    
    // Spectating overlay
    guy_entity := get_entity(client, local_player.guy_pid);
    guy := down(guy_entity, Guy);
    is_spectating := guy.state == .Dead;
    if is_spectating {
        find_name_from_guy_pid :: (client: *Client, pid: Pid) -> string {
            for i := 0; i < client.remote_players.count; ++i {
                remote_player := array_get_pointer(*client.remote_players, i);
                if remote_player.guy_pid == pid { return remote_player.name; }
            }
            
            for i := 0; i < client.local_player_count; ++i {
                local_player := *client.local_players[i];
                if local_player.guy_pid == pid { return local_player.name; }
            }
            
            return "UNKNOWN";
        }
        
        color := GE_Color.{ 255, 255, 255, 100 };
        
        // Text Spectating
        text: string = "Spectating";
        position: v2f = .{ 
            (local_player.viewport[0] + local_player.viewport[2]) / 2, 
            (local_player.viewport[1] + local_player.viewport[3]) - 0.2*local_player.viewport[3]
        };
        draw_text_screen_space(client, *client.title_font, text, position, .Center | .Median, color);
        
        // Text Player
        {
            if local_player.guy_pid == local_player.entity_tracked_by_camera {
                text = "YOU";
            } else {
                text = find_name_from_guy_pid(client, local_player.entity_tracked_by_camera);
            }
            
            spectated_guy := down(get_entity(client, local_player.entity_tracked_by_camera), Guy);
            if spectated_guy.state == .Dead {
                text = concatenate_strings(*temp, text, " (DEAD)");
            }
        }
        position.y += 50;
        color.a = 255;
        draw_text_screen_space(client, *client.title_font, text, position, .Center | .Median, color);
        
        // Draw Arrows indicating that you can switch to other players
        {
            font := *client.title_font;
            text_width := get_string_width_in_pixels(font, text);
            
            sprite_index :: Sprite_Index.Hud_Arrow;
            center := position;
            size: GE_Vector2 = .{ 32, 32 };
            padding: f32 = 10;
            offset: f32 = xx text_width * 0.5 + padding + size.x;
            
            sprite_position: v2f;
            rotation: f32;
            
            // Right
            rotation = 0.25;
            sprite_position = .{ center.x + offset, center.y };
            draw_sprite_screen_space(client, sprite_index, sprite_position, size, rotation, .{ 255, 255, 255, 255 }, .None);
            
            // Left
            rotation = 0.75;
            sprite_position = .{ center.x - offset, center.y };
            draw_sprite_screen_space(client, sprite_index, sprite_position, size, rotation, .{ 255, 255, 255, 255 }, .None);
        }
   }
}

draw_debug_indicators :: (client: *Client, local_player: *Local_Player) {
    if client.free_cam_is_enabled {
        position: v2f = .{ 
            (local_player.viewport[0] + local_player.viewport[2] * 0.01),
            (local_player.viewport[1] + local_player.viewport[3] * 0.05)
        };
        draw_text_screen_space(client, *client.title_font, "Freecam", position, .Left | .Median, .{ 255, 255, 255, 255 });
    }
}



#file_scope

Hud_State :: enum {
    Disabled;
    Crafting_Menu;
    Cheat_Menu;
    Chest_Menu;
}

CRAFTING_RECIPE_ICONS: [Crafting_Recipe.Count]Sprite_Index : .[
    .Mirror,
    .Torch_0,
    .Chest_Closed,
    .Health_Potion,
    .Strength_Potion,
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
];

close_hud :: (client: *Client, hud: *Hud) {
    if #complete hud.state == {
      case .Disabled, .Cheat_Menu;
      case .Crafting_Menu;
        deallocate_array(*client.world_allocator, *hud.crafting_menu.recipes);
      case .Chest_Menu;
        deallocate_array(*client.world_allocator, *hud.chest_menu.item_kinds);
        deallocate_array(*client.world_allocator, *hud.chest_menu.item_count);
    }

    deallocate_array(*client.world_allocator, *hud.animation_t);
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
    hud.animation_t = allocate_array(*client.world_allocator, f32, options);
    clear_memory(hud.animation_t.data, hud.animation_t.count * size_of(f32));
    hud.previously_opened_state = state;
}

maybe_open_hud :: (client: *Client, local_player: *Local_Player, guy: *Guy, state: Hud_State) {
    hud := *local_player.hud;

    if hud.state == state {
        close_hud(client, hud);
        return;
    }
    
    if #complete state == {
      case .Disabled;

      case .Crafting_Menu;
        // Find the number of enabled recipes
        recipe_count := 0;

        for i := 0; i < Crafting_Recipe.Count; ++i {
            if crafting_recipe_is_enabled(client, guy, i) then ++recipe_count;
        }

        if recipe_count == 0 break;

        // Allocate the actual recipe options
        hud.crafting_menu.recipes = allocate_array(*client.world_allocator, Crafting_Recipe, recipe_count);

        recipe_index := 0;
        for i := 0; i < Crafting_Recipe.Count; ++i {
            if crafting_recipe_is_enabled(client, guy, i) {
                hud.crafting_menu.recipes[recipe_index] = i;
                ++recipe_index;
            }
        }

        switch_to_hud_state(client, hud, state, hud.crafting_menu.recipes.count);

      case .Cheat_Menu;
        switch_to_hud_state(client, hud, .Cheat_Menu, Cheat.Count);

      case .Chest_Menu;
        // Find the number of different items
        chest_entity := find_entity_of_kind_at_position(client, .Chest, guy.target_position);
        chest := down(chest_entity, Chest);
        
        base_item_array: [Item_Kind.Count]s64 = .[ 0 ];
        for i := 0; i < chest.item_count; ++i {
            base_item_array[chest.items[i]] += 1;
        }

        separate_item_count := 0;
        for i := 0; i < base_item_array.Capacity; ++i {
            if base_item_array[i] > 0 ++separate_item_count;
        }

        if separate_item_count == 0 break;
        
        // Allocate the actual item options
        hud.chest_menu.item_kinds = allocate_array(*client.world_allocator, Item_Kind, separate_item_count);
        hud.chest_menu.item_count = allocate_array(*client.world_allocator, s64, separate_item_count);

        index := 0;
        for i := 0; i < base_item_array.Capacity; ++i {
            if base_item_array[i] > 0 {
                hud.chest_menu.item_kinds[index] = i;
                hud.chest_menu.item_count[index] = base_item_array[i];
                ++index;
            }
        }
        
        switch_to_hud_state(client, hud, .Chest_Menu, separate_item_count);
    }

    if local_player.input_binder.active_input_device == .Keyboard {
        set_cursor_position(*client.window, xx hud.screen_center.x, xx hud.screen_center.y);
    }
}

crafting_recipe_looks_doable :: (client: *Client, guy: *Guy, recipe: Crafting_Recipe) -> bool {
    // Check that the recipe is even enabled
    if !crafting_recipe_is_enabled(client, guy, recipe) return false;
    
    // Check that the guy has the required resources available
    available_resources := get_available_resources_for_guy(client, guy);
    if !available_resources_fulfill(available_resources, CRAFTING_RECIPE_REQUIRED_ITEMS[recipe]) return false;

    return true;
}

crafting_recipe_is_enabled :: (client: *Client, guy: *Guy, recipe: Crafting_Recipe) -> bool {
    // Check that the target position is actually empty, if required
    if CRAFTING_RECIPE_REQUIRES_EMPTY_TARGET[recipe] && find_entity_with_flags_at_position(client, .Blocks_Crafting, guy.target_position) return false;

    if CRAFTING_RECIPE_ENABLER[recipe] != .Count {
        // Check that the required enabler is present
        if find_entity_of_kind_at_position(client, CRAFTING_RECIPE_ENABLER[recipe], guy.target_position) == null return false;
    } else {
        // Special case: The trader should only present recipes that are actually unique to the trader,
        // not general recipes that don't need a trader and can be done on-hand
        if find_entity_of_kind_at_position(client, .Trader, guy.target_position) != null return false;
    }
    
    return true;
}



/* ------------------------------------------- Drawing ------------------------------------------- */

get_icon_size_for_option :: (client: *Client, hud: *Hud, scale: f32, option_index: s64) -> v2f {
    icon_scale_factor := 0.9 + (sinf(client.game_epoch_time * 2 * FTAU) + 0.5) * 0.2 * hud.animation_t[option_index] * scale;
    base_size := hud.outer_wheel_radius - hud.inner_wheel_radius;
    return v2f.{ base_size * icon_scale_factor, base_size * icon_scale_factor };
}

draw_icon :: (client: *Client, hud: *Hud, sprite_index: Sprite_Index, inner_offset: f32, option_index: s64, index_in_option: f32) {
    icon_size := get_icon_size_for_option(client, hud, inner_offset, option_index);

    radians := ((cast(f32) option_index + 0.5) * hud.angle_per_option + index_in_option * hud.angle_per_icon) * FTAU;
    icon_center := v2f.{ hud.screen_center.x + sinf(radians) * hud.icon_radius * inner_offset,
                         hud.screen_center.y - cosf(radians) * hud.icon_radius * inner_offset };
    draw_sprite_screen_space(client, sprite_index, icon_center, icon_size, 0, .{ 255, 255, 255, 255 }, false);
}
    
draw_divider :: (client: *Client, hud: *Hud, option_index: s64) {
    base_size := (hud.outer_wheel_radius - hud.inner_wheel_radius) * 0.5;
    icon_size := v2f.{ base_size, base_size };

    theta := ((cast(f32) option_index + 0.5) * hud.angle_per_option);
    radians := theta * FTAU;
    icon_center := v2f.{ hud.screen_center.x + sinf(radians) * hud.icon_radius,
                         hud.screen_center.y - cosf(radians) * hud.icon_radius };
    draw_sprite_screen_space(client, .Hud_Arrow, icon_center, icon_size, theta - 0.25, .{ 255, 255, 255, 255 }, false);
}

draw_circle_segment :: (client: *Client, hud: *Hud, animation_t: f32, option_index: s64) {
    background_color := ge_mix_colors(.{ 40, 50, 60, 250 }, .{ 50, 89, 128, 230 }, animation_t);
    theta0 := cast(f32) option_index * hud.angle_per_option + hud.padding_per_option * 0.5;
    theta1 := cast(f32) (option_index + 1) * hud.angle_per_option - hud.padding_per_option * 0.5;

    draw_circle_segment_screen_space(client, hud.screen_center, hud.outer_wheel_radius, hud.inner_wheel_radius, theta0, theta1, background_color);

    if option_index == hud.selected_option {
        draw_outlined_circle_segment_screen_space(client, hud.screen_center, hud.outer_wheel_radius, hud.inner_wheel_radius, theta0, theta1, .{ 255, 255, 255, 180 }, 2);
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
