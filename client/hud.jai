Hud :: struct {
    state: Hud_State;
    crafting_recipe_input_this_frame: Crafting_Recipe;
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

create_hud :: (client: *Client) {
    client.hud.state = .Disabled;
    client.hud.crafting_recipe_input_this_frame = .Count;
    client.hud.was_open_this_frame = false;
}

update_hud :: (client: *Client) {
    hud :: *client.hud;

    hud.was_open_this_frame = hud.state != .Disabled;
    
    if client.pause_menu_open {
        close_hud(client);
        return;
    }
    
    //
    // Clear out persistent state
    //
    hud.crafting_recipe_input_this_frame = .Count;
    
    //
    // Toggle the active state
    //
    if input_action_fired(client, .Crafting_Menu_Toggle) {
        if hud.state != .Crafting_Menu {
            hud.crafting_menu.selected_recipe = 0;
            if set_available_crafting_recipes(client) then hud.state = .Crafting_Menu;
        } else {
            close_hud(client);
        }
    }

#if DEVELOPER {
    if input_action_fired(client, .Cheat_Menu_Toggle) {
        if hud.state != .Cheat_Menu {
            hud.state = .Cheat_Menu;
            hud.cheat_menu.selected_cheat = 0;
        } else {
            close_hud(client);
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
        
        if input_action_fired(client, .Crafting_Menu_Left) {
            hud.crafting_menu.selected_recipe = (hud.crafting_menu.selected_recipe - 1) % hud.crafting_menu.recipes.count;
        }

        if input_action_fired(client, .Crafting_Menu_Right) {
            hud.crafting_menu.selected_recipe = (hud.crafting_menu.selected_recipe + 1) % hud.crafting_menu.recipes.count;
        }

        if input_action_fired(client, .Crafting_Menu_Confirm) {
            hud.crafting_recipe_input_this_frame = hud.crafting_menu.recipes[hud.crafting_menu.selected_recipe];
            hud.state = .Disabled;

            if crafting_recipe_looks_doable(client, hud.crafting_recipe_input_this_frame) {
                play_sound(client, .Crafting_0, false);
            } else {
                play_sound(client, .Failure_0, false);
            }
        }

        for i := 0; i < hud.crafting_menu.recipes.count; ++i {
            if i == hud.crafting_menu.selected_recipe {
                client.hud.crafting_menu.animation_t[i] += client.tick_time * 5;
            } else {
                client.hud.crafting_menu.animation_t[i] -= client.tick_time * 3;
            }

            client.hud.crafting_menu.animation_t[i] = clamp(client.hud.crafting_menu.animation_t[i], 0, 1);
        }

      case .Cheat_Menu;
        if input_action_fired(client, .Crafting_Menu_Left) {
            hud.cheat_menu.selected_cheat = (hud.cheat_menu.selected_cheat - 1) % Cheat.Count;
        }

        if input_action_fired(client, .Crafting_Menu_Right) {
            hud.cheat_menu.selected_cheat = (hud.cheat_menu.selected_cheat + 1) % Cheat.Count;
        }

        if input_action_fired(client, .Crafting_Menu_Confirm) {
            // @Incomplete: Actually send the cheating message.
            play_sound(client, .Crafting_0, false);
            hud.state = .Disabled;
        }

        for i := 0; i < Cheat.Count; ++i {
            if i == hud.cheat_menu.selected_cheat {
                client.hud.cheat_menu.animation_t[i] += client.tick_time * 5;
            } else {
                client.hud.cheat_menu.animation_t[i] -= client.tick_time * 3;
            }

            client.hud.cheat_menu.animation_t[i] = clamp(client.hud.cheat_menu.animation_t[i], 0, 1);
        }
    }
}

draw_hud :: (client: *Client) {
    hud :: *client.hud;

    guy_entity := get_entity(client, client.my_entity_pid);
    screen_center := screen_from_world_position(client, guy_entity.visual_position);
    outer_radius := cast(f32) client.window.h * 0.15;
    inner_radius := cast(f32) client.window.h * 0.10;
    icon_radius  := (inner_radius + outer_radius) * 0.5;

    if #complete hud.state == {
      case .Disabled;

      case .Crafting_Menu;
        padding_per_recipe: f32 = ifx hud.crafting_menu.recipes.count > 1 then 0.1 / cast(f32) hud.crafting_menu.recipes.count else 0;
        angle_per_recipe:   f32 = 1.0 / cast(f32) hud.crafting_menu.recipes.count;
        
        for i := 0; i < hud.crafting_menu.recipes.count; ++i {
            recipe := hud.crafting_menu.recipes[i];
            theta  := (cast(f32) i + 0.5) * angle_per_recipe;
            
            icon_scale_factor := 0.9 + (sinf(client.epoch_time * 2 * FTAU) + 0.5) * 0.2 * client.hud.crafting_menu.animation_t[i];
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
                confirm_sprite := get_sprite_index_for_input_action(client, .Crafting_Menu_Confirm);
                draw_icon(client, confirm_sprite, screen_center, icon_radius * 0.6, .{ icon_size.x * 0.75, icon_size.y * 0.75 }, theta, 0);
            }
        }

      case .Cheat_Menu;
        padding_per_cheat: f32 = ifx Cheat.Count > 1 then 0.1 / cast(f32) Cheat.Count else 0;
        angle_per_cheat:   f32 = 1.0 / cast(f32) Cheat.Count;

        for i := 0; i < Cheat.Count; ++i {
            theta := (cast(f32) i + 0.5) * angle_per_cheat;

            icon_scale_factor := 0.9 + (sinf(client.epoch_time * 2 * FTAU) + 0.5) * 0.2 * client.hud.cheat_menu.animation_t[i];
            icon_size := v2f.{ (outer_radius - inner_radius) * icon_scale_factor, (outer_radius - inner_radius) * icon_scale_factor };

            // Draw the circle segment
            draw_circle_segment(client, screen_center, outer_radius, inner_radius, theta, angle_per_cheat, padding_per_cheat, hud.cheat_menu.animation_t[i], hud.cheat_menu.selected_cheat == i);

            // Draw the cheat icon
            draw_icon(client, CHEAT_ICONS[i], screen_center, icon_radius, icon_size, theta, 0);

            // Draw the input action hint
            if hud.crafting_menu.selected_recipe == i {
                confirm_sprite := get_sprite_index_for_input_action(client, .Crafting_Menu_Confirm);
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
];

set_available_crafting_recipes :: (client: *Client) -> s64 {
    recipe_count := 0;

    for i := 0; i < Crafting_Recipe.Count; ++i {
        if crafting_recipe_is_enabled(client, i) then ++recipe_count;
    }

    if recipe_count != 0 {
        client.hud.crafting_menu.recipes = allocate_array(*client.world_allocator, Crafting_Recipe, recipe_count);
        client.hud.crafting_menu.animation_t = allocate_array(*client.world_allocator, f32, recipe_count);

        recipe_index := 0;
        for i := 0; i < Crafting_Recipe.Count; ++i {
            if crafting_recipe_is_enabled(client, i) {
                client.hud.crafting_menu.recipes[recipe_index] = i;
                client.hud.crafting_menu.animation_t[recipe_index] = 0;
                ++recipe_index;
            }
        }
    }
        
    return recipe_count;
}

close_hud :: (client: *Client) {
    hud :: *client.hud;

    if #complete hud.state == {
      case .Disabled, .Cheat_Menu;
      case .Crafting_Menu;
        deallocate_array(*client.world_allocator, *client.hud.crafting_menu.recipes);
        deallocate_array(*client.world_allocator, *client.hud.crafting_menu.animation_t);
    }

    hud.state = .Disabled;
}

crafting_recipe_looks_doable :: (client: *Client, recipe: Crafting_Recipe) -> bool {
    guy_entity := get_entity(client, client.my_entity_pid);
    guy := down(guy_entity, Guy);
    
    // Check that the target position is actually empty, if required
    if CRAFTING_RECIPE_REQUIRES_EMPTY_TARGET[recipe] && find_entity_with_flags_at_position(client, .Blocks_Move, guy.target_position) return false;

    // Check that the guy has the required resources available
    available_resources := get_available_resources_for_guy(client, guy);
    if !available_resources_fulfill(available_resources, CRAFTING_RECIPE_REQUIRED_ITEMS[recipe]) return false;

    return true;
}

crafting_recipe_is_enabled :: (client: *Client, recipe: Crafting_Recipe) -> bool {
    guy_entity := get_entity(client, client.my_entity_pid);
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
