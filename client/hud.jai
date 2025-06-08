Hud :: struct {
    state: Hud_State;
    previously_opened_state: Hud_State;
    crafting_recipe_input_this_frame: Crafting_Recipe;
    cheat_input_this_frame: Cheat;
    was_open_this_frame: bool;
    
    #using data: union {
        crafting_menu: struct {
            recipes: []Crafting_Recipe;
            animation_t: []f32;
            selected_recipe: s64;
        };

        cheat_menu: struct {
            selected_cheat: s64;
            animation_t: [Cheat.Count]f32;
        };
    };
}

create_hud :: (client: *Client, local_player_index: s64) {
    hud := *client.local_players[local_player_index].hud;
    hud.state = .Disabled;
    hud.crafting_recipe_input_this_frame = .Count;
    hud.cheat_input_this_frame = .Count;
    hud.was_open_this_frame = false;
}

update_hud :: (client: *Client, local_player_index: s64) {
    local_player := *client.local_players[local_player_index];
    hud := *local_player.hud;

    hud.was_open_this_frame = hud.state != .Disabled;
    
    if client.pause_menu_open {
        close_hud(client, local_player_index);
        return;
    }
    
    //
    // Clear out persistent state
    //
    hud.crafting_recipe_input_this_frame = .Count;
    hud.cheat_input_this_frame = .Count;
    
    //
    // Toggle the active state
    //
    if input_action_fired_for_local_player(client, local_player, .Crafting_Menu_Toggle) {
        if hud.state != .Crafting_Menu {
            if hud.previously_opened_state != .Crafting_Menu {
                hud.crafting_menu.selected_recipe = 0;
            }

            if set_available_crafting_recipes(client, local_player_index) {
                hud.crafting_menu.selected_recipe = hud.crafting_menu.selected_recipe % hud.crafting_menu.recipes.count;
                hud.state = .Crafting_Menu;
                hud.previously_opened_state = .Crafting_Menu;
            }
        } else {
            close_hud(client, local_player_index);
        }
    }

#if DEVELOPER {
    if input_action_fired_for_local_player(client, local_player, .Cheat_Menu_Toggle) {
        if hud.state != .Cheat_Menu {
            if hud.previously_opened_state != .Cheat_Menu {
                hud.cheat_menu.selected_cheat = 0;
                hud.cheat_menu.animation_t = .[];
            }

            hud.cheat_menu.selected_cheat = hud.cheat_menu.selected_cheat % Cheat.Count;
            hud.state = .Cheat_Menu;
            hud.previously_opened_state = .Cheat_Menu;
        } else {
            close_hud(client, local_player_index);
        }
    }
}
    
    //
    // Update the active state
    //
    if #complete hud.state == {
      case .Disabled;

      case .Crafting_Menu;
        if !hud.crafting_menu.recipes.count break;
        
        if input_action_fired_for_local_player(client, local_player, .Crafting_Menu_Left) {
            hud.crafting_menu.selected_recipe = (hud.crafting_menu.selected_recipe - 1) % hud.crafting_menu.recipes.count;
        }

        if input_action_fired_for_local_player(client, local_player, .Crafting_Menu_Right) {
            hud.crafting_menu.selected_recipe = (hud.crafting_menu.selected_recipe + 1) % hud.crafting_menu.recipes.count;
        }

        if input_action_fired_for_local_player(client, local_player, .Crafting_Menu_Confirm) {
            hud.crafting_recipe_input_this_frame = hud.crafting_menu.recipes[hud.crafting_menu.selected_recipe];
            hud.state = .Disabled;

            if crafting_recipe_looks_doable(client, local_player_index, hud.crafting_recipe_input_this_frame) {
                play_sound(client, .Crafting_0, false);
            } else {
                play_sound(client, .Failure_0, false);
            }
        }

        for i := 0; i < hud.crafting_menu.recipes.count; ++i {
            if i == hud.crafting_menu.selected_recipe {
                hud.crafting_menu.animation_t[i] += client.tick_time * 5;
            } else {
                hud.crafting_menu.animation_t[i] -= client.tick_time * 3;
            }

            hud.crafting_menu.animation_t[i] = clamp(hud.crafting_menu.animation_t[i], 0, 1);
        }

      case .Cheat_Menu;
        if input_action_fired_for_local_player(client, local_player, .Crafting_Menu_Left) {
            hud.cheat_menu.selected_cheat = (hud.cheat_menu.selected_cheat - 1) % Cheat.Count;
        }

        if input_action_fired_for_local_player(client, local_player, .Crafting_Menu_Right) {
            hud.cheat_menu.selected_cheat = (hud.cheat_menu.selected_cheat + 1) % Cheat.Count;
        }

        if input_action_fired_for_local_player(client, local_player, .Crafting_Menu_Confirm) {
            hud.cheat_input_this_frame = hud.cheat_menu.selected_cheat;
            hud.state = .Disabled;
            play_sound(client, .Crafting_0, false);
        }

        for i := 0; i < Cheat.Count; ++i {
            if i == hud.cheat_menu.selected_cheat {
                hud.cheat_menu.animation_t[i] += client.tick_time * 5;
            } else {
                hud.cheat_menu.animation_t[i] -= client.tick_time * 3;
            }

            hud.cheat_menu.animation_t[i] = clamp(hud.cheat_menu.animation_t[i], 0, 1);
        }
    }
}

draw_hud :: (client: *Client, local_player: *Local_Player) {
    hud := *local_player.hud;
    
    guy_entity := get_entity(client, local_player.guy_pid);
    screen_center := screen_from_world_position(*local_player.camera, guy_entity.visual_position);
    outer_radius := (local_player.viewport[3] - local_player.viewport[1]) * 0.15;
    inner_radius := (local_player.viewport[3] - local_player.viewport[1]) * 0.10;
    icon_radius  := (inner_radius + outer_radius) * 0.5;

    if #complete hud.state == {
      case .Disabled;

      case .Crafting_Menu;
        padding_per_recipe: f32 = ifx hud.crafting_menu.recipes.count > 1 then 0.1 / cast(f32) hud.crafting_menu.recipes.count else 0;
        angle_per_recipe:   f32 = 1.0 / cast(f32) hud.crafting_menu.recipes.count;
        
        for i := 0; i < hud.crafting_menu.recipes.count; ++i {
            recipe := hud.crafting_menu.recipes[i];
            theta  := (cast(f32) i + 0.5) * angle_per_recipe;
            
            icon_scale_factor := 0.9 + (sinf(client.game_epoch_time * 2 * FTAU) + 0.5) * 0.2 * hud.crafting_menu.animation_t[i];
            icon_size := v2f.{ (outer_radius - inner_radius) * icon_scale_factor, (outer_radius - inner_radius) * icon_scale_factor };
            
            // Draw the circle segment
            draw_circle_segment(client, screen_center, outer_radius, inner_radius, theta, angle_per_recipe, padding_per_recipe, hud.crafting_menu.animation_t[i], hud.crafting_menu.selected_recipe == i);
                
            // Draw the required + result icons
            {
                for i := 0; i < CRAFTING_RECIPE_REQUIRED_ITEMS[recipe].count; ++i {
                    draw_icon(client, get_sprite_index_for_item(CRAFTING_RECIPE_REQUIRED_ITEMS[recipe][i]), screen_center, icon_radius, icon_size, theta, i + 1);
                }

                draw_divider(client, screen_center, outer_radius, inner_radius, theta);

                draw_icon(client, CRAFTING_RECIPE_ICONS[recipe], screen_center, icon_radius, icon_size, theta, -1);
            }

            // Draw the input action hint
            if hud.crafting_menu.selected_recipe == i {
                confirm_sprite := get_sprite_index_for_input_action(client, local_player, .Crafting_Menu_Confirm);
                draw_icon(client, confirm_sprite, screen_center, icon_radius * 0.6, .{ icon_size.x * 0.75, icon_size.y * 0.75 }, theta, 0);
            }
        }

      case .Cheat_Menu;
        padding_per_cheat: f32 = ifx Cheat.Count > 1 then 0.1 / cast(f32) Cheat.Count else 0;
        angle_per_cheat:   f32 = 1.0 / cast(f32) Cheat.Count;

        for i := 0; i < Cheat.Count; ++i {
            theta := (cast(f32) i + 0.5) * angle_per_cheat;

            icon_scale_factor := 0.9 + (sinf(client.game_epoch_time * 2 * FTAU) + 0.5) * 0.2 * hud.cheat_menu.animation_t[i];
            icon_size := v2f.{ (outer_radius - inner_radius) * icon_scale_factor, (outer_radius - inner_radius) * icon_scale_factor };

            // Draw the circle segment
            draw_circle_segment(client, screen_center, outer_radius, inner_radius, theta, angle_per_cheat, padding_per_cheat, hud.cheat_menu.animation_t[i], hud.cheat_menu.selected_cheat == i);

            // Draw the cheat icon
            draw_icon(client, CHEAT_ICONS[i], screen_center, icon_radius, icon_size, theta, 0);

            // Draw the input action hint
            if hud.cheat_menu.selected_cheat == i {
                confirm_sprite := get_sprite_index_for_input_action(client, local_player, .Crafting_Menu_Confirm);
                draw_icon(client, confirm_sprite, screen_center, icon_radius * 0.6, .{ icon_size.x * 0.75, icon_size.y * 0.75 }, theta, 0);
            }
        }
    }
}



#file_scope

Hud_State :: enum {
    Disabled;
    Crafting_Menu;
    Cheat_Menu;
}

CRAFTING_RECIPE_ICONS: [Crafting_Recipe.Count]Sprite_Index : .[
    .Mirror,
    .Health_Potion,
    .Strength_Potion,
];

CHEAT_ICONS: [Cheat.Count]Sprite_Index : .[
    .Coin,
    .Coal_Item,
    .Health_Potion,
    .Strength_Potion,
];

set_available_crafting_recipes :: (client: *Client, local_player_index: s64) -> s64 {
    hud := *client.local_players[local_player_index].hud;

    recipe_count := 0;

    for i := 0; i < Crafting_Recipe.Count; ++i {
        if crafting_recipe_is_enabled(client, local_player_index, i) then ++recipe_count;
    }

    if recipe_count != 0 {
        hud.crafting_menu.recipes = allocate_array(*client.world_allocator, Crafting_Recipe, recipe_count);
        hud.crafting_menu.animation_t = allocate_array(*client.world_allocator, f32, recipe_count);

        recipe_index := 0;
        for i := 0; i < Crafting_Recipe.Count; ++i {
            if crafting_recipe_is_enabled(client, local_player_index, i) {
                hud.crafting_menu.recipes[recipe_index] = i;
                hud.crafting_menu.animation_t[recipe_index] = 0;
                ++recipe_index;
            }
        }
    }
        
    return recipe_count;
}

close_hud :: (client: *Client, local_player_index: s64) {
    hud := *client.local_players[local_player_index].hud;

    if #complete hud.state == {
      case .Disabled, .Cheat_Menu;
      case .Crafting_Menu;
        deallocate_array(*client.world_allocator, *hud.crafting_menu.recipes);
        deallocate_array(*client.world_allocator, *hud.crafting_menu.animation_t);
    }

    hud.state = .Disabled;
}

crafting_recipe_looks_doable :: (client: *Client, local_player_index: s64, recipe: Crafting_Recipe) -> bool {
    guy_entity := get_entity(client, client.local_players[local_player_index].guy_pid);
    guy := down(guy_entity, Guy);
    
    // Check that the target position is actually empty, if required
    if CRAFTING_RECIPE_REQUIRES_EMPTY_TARGET[recipe] && find_entity_with_flags_at_position(client, .Blocks_Move, guy.target_position) return false;

    // Check that the guy has the required resources available
    available_resources := get_available_resources_for_guy(client, guy);
    if !available_resources_fulfill(available_resources, CRAFTING_RECIPE_REQUIRED_ITEMS[recipe]) return false;

    return true;
}

crafting_recipe_is_enabled :: (client: *Client, local_player_index: s64, recipe: Crafting_Recipe) -> bool {
    guy_entity := get_entity(client, client.local_players[local_player_index].guy_pid);
    guy := down(guy_entity, Guy);

    // Check that the target position is actually empty, if required
    if CRAFTING_RECIPE_REQUIRES_EMPTY_TARGET[recipe] && find_entity_with_flags_at_position(client, .Blocks_Move, guy.target_position) return false;

    // Check that the required enabler is present
    return CRAFTING_RECIPE_ENABLER[recipe] == .Count || find_entity_of_kind_at_position(client, CRAFTING_RECIPE_ENABLER[recipe], guy.target_position) != null;
}

draw_icon :: (client: *Client, sprite_index: Sprite_Index, screen_center: v2f, icon_radius: f32, icon_size: v2f, theta: f32, index: s64) {
    angle_per_icon :: cast(f32) 0.05;
    radians := (theta + xx index * angle_per_icon) * FTAU;
    icon_center := v2f.{ screen_center.x + sinf(radians) * icon_radius,
                         screen_center.y - cosf(radians) * icon_radius };
    draw_sprite_screen_space(client, sprite_index, icon_center, icon_size, 0, .{ 255, 255, 255, 255 }, false);
}

draw_divider :: (client: *Client, screen_center: v2f, outer_radius, inner_radius: f32, theta: f32) {
    radians := theta * FTAU;
    inner_point := v2f.{ screen_center.x + sinf(radians) * inner_radius * 1.1,
                         screen_center.y - cosf(radians) * inner_radius * 1.1 };
    outer_point := v2f.{ screen_center.x + sinf(radians) * outer_radius * 0.9,
                         screen_center.y - cosf(radians) * outer_radius * 0.9 };
    
    draw_line_screen_space(client, inner_point, outer_point, .{ 255, 255, 255, 255 }, 1);
}

draw_circle_segment :: (client: *Client, screen_center: v2f, outer_radius, inner_radius: f32, theta: f32, angle: f32, padding: f32, animation_t: f32, highlighted: bool) {
    background_color := ge_mix_colors(.{ 40, 50, 60, 180 }, .{ 50, 89, 128, 180 }, animation_t);
    theta0 := theta - angle / 2 + padding / 2;
    theta1 := theta + angle / 2 - padding / 2;

    draw_circle_segment_screen_space(client, screen_center, outer_radius, inner_radius, theta0, theta1, background_color);

    if highlighted {
        draw_outlined_circle_segment_screen_space(client, screen_center, outer_radius, inner_radius, theta0, theta1, .{ 255, 255, 255, 180 }, 2);
    }
}
