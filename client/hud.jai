Hud :: struct {
    state: Hud_State;

    #using data: union {
        crafting_menu: struct {
            recipes: []Crafting_Recipe;
            selected_recipe: s64;
        };
    };
}

update_hud :: (client: *Client) {
    hud :: *client.hud;

    //
    // Toggle the active state
    //
    if client.window.keys[.C] & .Pressed {
        hud.state = .Crafting_Menu;
        hud.crafting_menu.recipes = RECIPES;
    } else if !client.window.keys[.C] & .Down && hud.state == .Crafting_Menu {
        hud.state = .Disabled;
    }

    //
    // Update the active state
    //
    if #complete hud.state == {
      case .Disabled;

      case .Crafting_Menu;
        if client.window.keys[.W] & .Repeated || client.window.keys[.Arrow_Left] & .Repeated {
            hud.crafting_menu.selected_recipe = (hud.crafting_menu.selected_recipe - 1 + hud.crafting_menu.recipes.count) % hud.crafting_menu.recipes.count;
        }

        if client.window.keys[.D] & .Repeated || client.window.keys[.Arrow_Right] & .Repeated {
            hud.crafting_menu.selected_recipe = (hud.crafting_menu.selected_recipe + 1) % hud.crafting_menu.recipes.count;
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

            draw_circle_segment_screen_space(client, screen_center, outer_radius, inner_radius, theta0, theta1, .{ 40, 50, 60, 180 });

            sprite_index: Sprite_Index = ---;
            
            if #complete recipe == {
                case .None;
                case .Mirror; sprite_index = .Mirror;
                case .Dragon; sprite_index = .Dragon_Idle_0;
                case .Crystal; sprite_index = .Crystal;
            }

            theta     := (theta0 + theta1) * 0.5 * FTAU;
            radius    := (inner_radius + outer_radius) * 0.5;
            item_size := v2f.{ (outer_radius - inner_radius) * 0.9, (outer_radius - inner_radius) * 0.9 };
            item_center := v2f.{ screen_center.x + sinf(theta) * radius, screen_center.y - cosf(theta) * radius };
            draw_sprite_screen_space(client, sprite_index, item_center, item_size, 0, .{ 255, 255, 255, 255 }, false);
            
            if hud.crafting_menu.selected_recipe == i {
                draw_outlined_circle_segment_screen_space(client, screen_center, outer_radius, inner_radius, theta0, theta1, .{ 255, 255, 255, 180 }, 2);
            }
        }
    }
}



#file_scope

Hud_State :: enum {
    Disabled;
    Crafting_Menu;
}

RECIPES := []Crafting_Recipe.[ .Mirror, .Dragon, .Crystal ];
