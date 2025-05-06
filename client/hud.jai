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

update_hud :: (client: *Client) {
    hud :: *client.hud;

    if client.pause_menu_open {
        hud.state = .Disabled;
        return;
    }
    
    //
    // Clear out persistent state
    //
    hud.crafting_recipe_input_this_frame = .None;
    
    //
    // Toggle the active state
    //
    if client.window.keys[.C] & .Pressed {
        hud.state = .Crafting_Menu;
        set_available_crafting_recipes(client, RECIPES);
    } else if !client.window.keys[.C] & .Down && hud.state == .Crafting_Menu {
        hud.state = .Disabled;
    }

    //
    // Update the active state
    //
    if #complete hud.state == {
      case .Disabled;

      case .Crafting_Menu;
        if client.window.keys[.A] & .Repeated || client.window.keys[.W] & .Repeated || client.window.keys[.Arrow_Left] & .Repeated || client.window.keys[.Arrow_Up] & .Repeated {
            hud.crafting_menu.selected_recipe = (hud.crafting_menu.selected_recipe - 1 + hud.crafting_menu.recipes.count) % hud.crafting_menu.recipes.count;
        }

        if client.window.keys[.D] & .Repeated || client.window.keys[.S] & .Repeated || client.window.keys[.Arrow_Right] & .Repeated || client.window.keys[.Arrow_Down] & .Repeated {
            hud.crafting_menu.selected_recipe = (hud.crafting_menu.selected_recipe + 1) % hud.crafting_menu.recipes.count;
        }

        if client.window.keys[.Enter] & .Pressed {
            hud.crafting_recipe_input_this_frame = hud.crafting_menu.recipes[hud.crafting_menu.selected_recipe];
            hud.state = .Disabled;
        }
    }
}

draw_hud :: (client: *Client) {
    hud :: *client.hud;

    if #complete hud.state == {
      case .Disabled;

      case .Crafting_Menu;
        player_entity := get_entity(client, client.my_entity_pid);
        screen_center := screen_from_world_position(client, player_entity.visual_position);

        padding_per_recipe: f32 = ifx hud.crafting_menu.recipes.count > 1 then 0.1 / cast(f32) hud.crafting_menu.recipes.count else 0;
        theta_per_recipe := 1.0 / cast(f32) hud.crafting_menu.recipes.count;
        outer_radius := cast(f32) client.window.h * 0.22;
        inner_radius := cast(f32) client.window.h * 0.15;
        
        for i := 0; i < hud.crafting_menu.recipes.count; ++i {
            recipe := hud.crafting_menu.recipes[i];
            
            theta0 := cast(f32) i * theta_per_recipe + padding_per_recipe / 2;
            theta1 := cast(f32) (i + 1) * theta_per_recipe - padding_per_recipe / 2;

            background_color := ge_mix_colors(.{ 40, 50, 60, 180 }, .{ 50, 89, 128, 180 }, client.hud.crafting_menu.animation_t[i]);
            draw_circle_segment_screen_space(client, screen_center, outer_radius, inner_radius, theta0, theta1, background_color);

            if hud.crafting_menu.selected_recipe == i {
                draw_outlined_circle_segment_screen_space(client, screen_center, outer_radius, inner_radius, theta0, theta1, .{ 255, 255, 255, 180 }, 2);
                client.hud.crafting_menu.animation_t[i] = clamp(client.hud.crafting_menu.animation_t[i] + 5 * client.tick_time, 0, 1);
            } else {
                client.hud.crafting_menu.animation_t[i] = clamp(client.hud.crafting_menu.animation_t[i] - 3 * client.tick_time, 0, 1);
            }

            sprite_index: Sprite_Index = ---;
            
            if #complete recipe == {
              case .None;
              case .Mirror;  sprite_index = .Mirror;
              case .Dragon;  sprite_index = .Dragon_Idle_0;
              case .Crystal; sprite_index = .Crystal;
            }

            theta       := (theta0 + theta1) * 0.5 * FTAU;
            radius      := (inner_radius + outer_radius) * 0.5;
            item_scale  := 0.9 + (sinf(client.epoch_time * 2 * FTAU) + 0.5) * 0.2 * client.hud.crafting_menu.animation_t[i];
            item_size   := v2f.{ (outer_radius - inner_radius) * item_scale, (outer_radius - inner_radius) * item_scale };
            item_center := v2f.{ screen_center.x + sinf(theta) * radius, screen_center.y - cosf(theta) * radius };
            draw_sprite_screen_space(client, sprite_index, item_center, item_size, 0, .{ 255, 255, 255, 255 }, false);

        }
    }
}

set_available_crafting_recipes :: (client: *Client, recipes: []Crafting_Recipe) {
    deallocate_array(*client.world_allocator, *client.hud.crafting_menu.recipes);
    deallocate_array(*client.world_allocator, *client.hud.crafting_menu.animation_t);
    client.hud.crafting_menu.recipes = allocate_array(*client.world_allocator, Crafting_Recipe, recipes.count);
    client.hud.crafting_menu.animation_t = allocate_array(*client.world_allocator, f32, recipes.count);
    copy_memory(client.hud.crafting_menu.recipes.data, recipes.data, recipes.count * size_of(Crafting_Recipe));
    clear_memory(client.hud.crafting_menu.animation_t.data, recipes.count * size_of(f32));
}



#file_scope

Hud_State :: enum {
    Disabled;
    Crafting_Menu;
}

RECIPES := []Crafting_Recipe.[ .Mirror, .Dragon, .Crystal ];
