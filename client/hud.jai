Hud :: struct {
    state: Hud_State;
    crafting_recipe_input_this_frame: Crafting_Recipe;
    
    #using data: union {
        crafting_menu: struct {
            recipes: []Crafting_Recipe;
            animation_t: []f32;
            selected_recipe: s64;
        };
    };
}

create_hud :: (client: *Client) {
    client.hud.state = .Disabled;
    client.hud.crafting_recipe_input_this_frame = .Count;
    client.hud.crafting_menu.recipes = .[];
    client.hud.crafting_menu.animation_t = .[];
}

update_hud :: (client: *Client) {
    hud :: *client.hud;

    if client.pause_menu_open {
        hud.state = .Disabled;
        return;
    }
    
    //
    // Clear out persistent state
    //
    hud.crafting_recipe_input_this_frame = .Count;
    
    //
    // Toggle the active state
    //
    if client.window.keys[.C] & .Pressed {
        hud.state = .Crafting_Menu;
        hud.crafting_menu.selected_recipe = 0;
        set_available_crafting_recipes(client);
    } else if !client.window.keys[.C] & .Down && hud.state == .Crafting_Menu {
        hud.state = .Disabled;
    }

    //
    // Update the active state
    //
    if #complete hud.state == {
      case .Disabled;

      case .Crafting_Menu;
        if !hud.crafting_menu.recipes.count break;
        
        if client.window.keys[.A] & .Repeated || client.window.keys[.W] & .Repeated || client.window.keys[.Arrow_Left] & .Repeated || client.window.keys[.Arrow_Up] & .Repeated {
            hud.crafting_menu.selected_recipe = (hud.crafting_menu.selected_recipe - 1 + hud.crafting_menu.recipes.count) % hud.crafting_menu.recipes.count;
        }

        if client.window.keys[.D] & .Repeated || client.window.keys[.S] & .Repeated || client.window.keys[.Arrow_Right] & .Repeated || client.window.keys[.Arrow_Down] & .Repeated {
            hud.crafting_menu.selected_recipe = (hud.crafting_menu.selected_recipe + 1) % hud.crafting_menu.recipes.count;
        }

        if client.window.keys[.Enter] & .Pressed {
            hud.crafting_recipe_input_this_frame = hud.crafting_menu.recipes[hud.crafting_menu.selected_recipe];
            hud.state = .Disabled;

            if crafting_recipe_looks_doable(client, hud.crafting_recipe_input_this_frame) {
                play_sound(client, .Crafting_0, false);
            } else {
                play_sound(client, .Failure_0, false);
            }
        }
    }
}

draw_hud :: (client: *Client) {
    hud :: *client.hud;

    if #complete hud.state == {
      case .Disabled;

      case .Crafting_Menu;
        guy_entity := get_entity(client, client.my_entity_pid);
        screen_center := screen_from_world_position(client, guy_entity.visual_position);

        padding_per_recipe: f32 = ifx hud.crafting_menu.recipes.count > 1 then 0.1 / cast(f32) hud.crafting_menu.recipes.count else 0;
        theta_per_recipe := 1.0 / cast(f32) hud.crafting_menu.recipes.count;
        outer_radius := cast(f32) client.window.h * 0.22;
        inner_radius := cast(f32) client.window.h * 0.15;
        
        for i := 0; i < hud.crafting_menu.recipes.count; ++i {
            recipe := hud.crafting_menu.recipes[i];
            
            theta0 := cast(f32) i * theta_per_recipe + padding_per_recipe / 2;
            theta1 := cast(f32) (i + 1) * theta_per_recipe - padding_per_recipe / 2;
            theta  := (theta0 + theta1) * 0.5;

            // Draw the circle segment
            background_color := ge_mix_colors(.{ 40, 50, 60, 180 }, .{ 50, 89, 128, 180 }, client.hud.crafting_menu.animation_t[i]);
            draw_circle_segment_screen_space(client, screen_center, outer_radius, inner_radius, theta0, theta1, background_color);

            if hud.crafting_menu.selected_recipe == i {
                draw_outlined_circle_segment_screen_space(client, screen_center, outer_radius, inner_radius, theta0, theta1, .{ 255, 255, 255, 180 }, 2);
                client.hud.crafting_menu.animation_t[i] = clamp(client.hud.crafting_menu.animation_t[i] + 5 * client.tick_time, 0, 1);
            } else {
                client.hud.crafting_menu.animation_t[i] = clamp(client.hud.crafting_menu.animation_t[i] - 3 * client.tick_time, 0, 1);
            }

            // Draw the divider between input and output of the recipe
            draw_line_screen_space(client, .{ screen_center.x + sinf(theta * FTAU) * inner_radius * 1.1, screen_center.y - cosf(theta * FTAU) * inner_radius * 1.1 }, .{ screen_center.x + sinf(theta * FTAU) * outer_radius * 0.9, screen_center.y - cosf(theta * FTAU) * outer_radius * 0.9 }, .{ 255, 255, 255, 255 }, 1);
            
            // Draw the required + result icons
            icon_scale  := 0.9 + (sinf(client.epoch_time * 2 * FTAU) + 0.5) * 0.2 * client.hud.crafting_menu.animation_t[i];
            icon_size   := v2f.{ (outer_radius - inner_radius) * icon_scale, (outer_radius - inner_radius) * icon_scale };
            icon_theta  := cast(f32) 0.05;
            radius      := (inner_radius + outer_radius) * 0.5;

            for i := 0; i < CRAFTING_RECIPE_REQUIRED_ITEMS[recipe].count; ++i {
                icon_center := v2f.{ screen_center.x + sinf((theta + icon_theta * xx (i + 1)) * FTAU) * radius, screen_center.y - cosf((theta + icon_theta * xx (i + 1)) * FTAU) * radius };
                draw_sprite_screen_space(client, get_sprite_index_for_item(CRAFTING_RECIPE_REQUIRED_ITEMS[recipe][i]), icon_center, icon_size, 0, .{ 255, 255, 255, 255 }, false);
            }
            
            {
                icon_center := v2f.{ screen_center.x + sinf((theta - icon_theta * 1) * FTAU) * radius, screen_center.y - cosf((theta - icon_theta * 1) * FTAU) * radius };
                draw_sprite_screen_space(client, CRAFTING_RECIPE_ICONS[recipe], icon_center, icon_size, 0, .{ 255, 255, 255, 255 }, false);
            }
        }
    }
}

set_available_crafting_recipes :: (client: *Client) {
    deallocate_array(*client.world_allocator, *client.hud.crafting_menu.recipes);
    deallocate_array(*client.world_allocator, *client.hud.crafting_menu.animation_t);

    recipe_count := 0;

    for i := 0; i < Crafting_Recipe.Count; ++i {
        if crafting_recipe_is_enabled(client, i) then ++recipe_count;
    }

    if recipe_count == 0 return;
    
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



#file_scope

Hud_State :: enum {
    Disabled;
    Crafting_Menu;
}

CRAFTING_RECIPE_ICONS: [Crafting_Recipe.Count]Sprite_Index : .[
    .Mirror,
    .Health_Potion,
    .Strength_Potion,
];

crafting_recipe_looks_doable :: (client: *Client, recipe: Crafting_Recipe) -> bool {
    guy_entity := get_entity(client, client.my_entity_pid);
    guy := down(guy_entity, Guy);
    
    // Check that the target position is actually empty, if required
    if CRAFTING_RECIPE_REQUIRES_EMPTY_TARGET[recipe] {
        if find_any_entity_at_position(client, guy.target_position) return false;
    }

    // Check that the guy has the required resources available
    available_resources := get_available_resources_for_guy(client, guy);
    if !available_resources_fulfill(available_resources, CRAFTING_RECIPE_REQUIRED_ITEMS[recipe]) return false;

    return true;
}

crafting_recipe_is_enabled :: (client: *Client, recipe: Crafting_Recipe) -> bool {
    guy_entity := get_entity(client, client.my_entity_pid);
    guy := down(guy_entity, Guy);

    // Check that the target position is actually empty, if required
    if CRAFTING_RECIPE_REQUIRES_EMPTY_TARGET[recipe] && find_any_entity_at_position(client, guy.target_position) return false;

    // Check that the required enabler is present
    return CRAFTING_RECIPE_ENABLER[recipe] == .Count || find_entity_of_kind_at_position(client, CRAFTING_RECIPE_ENABLER[recipe], guy.target_position) != null;
}
