Hud :: struct {
    state: Hud_State;
    previously_opened_state: Hud_State;
    was_open_this_frame: bool;
    was_input_this_frame: bool;
    
    crafting_recipe_input_this_frame: Crafting_Recipe;
    cheat_input_this_frame: Cheat;
    chest_item_input_this_frame: Item_Kind;
    
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
    
    available_options: s64;
    selected_option: s64;
    animation_t: []f32;

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
    hud.crafting_recipe_input_this_frame = .Count;
    hud.cheat_input_this_frame = .Count;
    hud.was_open_this_frame = false;
}

update_hud :: (client: *Client, local_player: *Local_Player) {
    hud := *local_player.hud;

    //
    // Clear out persistent state
    //
    hud.was_open_this_frame = hud.state != .Disabled;
    hud.was_input_this_frame = false;
    
    hud.crafting_recipe_input_this_frame = .Count;
    hud.cheat_input_this_frame           = .Count;
    hud.chest_item_input_this_frame      = .Count;

    if client.pause_menu_open {
        close_hud(client, local_player);
        return;
    }
        
    //
    // Toggle the active state
    //
    if input_action_fired_for_local_player(client, local_player, .Hud_Toggle) {
        guy_entity := get_entity(client, local_player.guy_pid);
        guy := down(guy_entity, Guy);

        if find_entity_of_kind_at_position(client, .Chest, guy.target_position) {
            maybe_open_hud(client, local_player, .Chest_Menu);
        } else {
            maybe_open_hud(client, local_player, .Crafting_Menu);
        }
    }

#if DEVELOPER {
    if input_action_fired_for_local_player(client, local_player, .Cheat_Menu_Toggle) {
        maybe_open_hud(client, local_player, .Cheat_Menu);
    }
}

    //
    // Update the selected option
    //
    if hud.state != .Disabled {
        if input_action_fired_for_local_player(client, local_player, .Hud_Left) {
            hud.selected_option = (hud.selected_option - 1) % hud.available_options;
        }

        if input_action_fired_for_local_player(client, local_player, .Hud_Right) {
            hud.selected_option = (hud.selected_option + 1) % hud.available_options;
        }
    }
    
    //
    // Confirm the selected option
    //
    if input_action_fired_for_local_player(client, local_player, .Hud_Confirm) {
        hud.was_input_this_frame = true;

        if #complete hud.state == {
          case .Disabled;

          case .Crafting_Menu;
            hud.crafting_recipe_input_this_frame = hud.crafting_menu.recipes[hud.selected_option];

            if crafting_recipe_looks_doable(client, local_player, hud.crafting_recipe_input_this_frame) {
                play_sound(client, .Crafting_0, false);
            } else {
                play_sound(client, .Failure_0, false);
            }

            close_hud(client, local_player);

          case .Cheat_Menu;
            hud.cheat_input_this_frame = hud.selected_option;
            play_sound(client, .Crafting_0, false);
            close_hud(client, local_player);

          case .Chest_Menu;
            hud.chest_item_input_this_frame = hud.chest_menu.item_kinds[hud.selected_option];
            play_sound(client, .Crafting_0, false);
            close_hud(client, local_player);
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

    if hud.state == .Disabled return;

    // Draw the circle background for each option
    for i := 0; i < hud.available_options; ++i {
        draw_circle_segment(client, hud, hud.animation_t[i], i);
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
    .Coin,
    .Coal_Item,
    .Health_Potion,
    .Strength_Potion,
];

close_hud :: (client: *Client, local_player: *Local_Player) {
    hud := *local_player.hud;

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

switch_to_hud_state :: (client: *Client, local_player: *Local_Player, state: Hud_State, options: s64) {
    hud := *local_player.hud;

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

maybe_open_hud :: (client: *Client, local_player: *Local_Player, state: Hud_State) {
    hud := *local_player.hud;

    if hud.state == state {
        close_hud(client, local_player);
        return;
    }
    
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
        hud.crafting_menu.recipes = allocate_array(*client.world_allocator, Crafting_Recipe, recipe_count);

        recipe_index := 0;
        for i := 0; i < Crafting_Recipe.Count; ++i {
            if crafting_recipe_is_enabled(client, local_player, i) {
                hud.crafting_menu.recipes[recipe_index] = i;
                ++recipe_index;
            }
        }

        switch_to_hud_state(client, local_player, state, hud.crafting_menu.recipes.count);

      case .Cheat_Menu;
        switch_to_hud_state(client, local_player, .Cheat_Menu, Cheat.Count);

      case .Chest_Menu;
        // Find the number of different items
        guy_entity := get_entity(client, local_player.guy_pid);
        guy := down(guy_entity, Guy);

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
        
        switch_to_hud_state(client, local_player, .Chest_Menu, separate_item_count);
    }
}

crafting_recipe_looks_doable :: (client: *Client, local_player: *Local_Player, recipe: Crafting_Recipe) -> bool {
    guy_entity := get_entity(client, local_player.guy_pid);
    guy := down(guy_entity, Guy);
    
    // Check that the target position is actually empty, if required
    if CRAFTING_RECIPE_REQUIRES_EMPTY_TARGET[recipe] && find_entity_with_flags_at_position(client, .Blocks_Move, guy.target_position) return false;

    // Check that the guy has the required resources available
    available_resources := get_available_resources_for_guy(client, guy);
    if !available_resources_fulfill(available_resources, CRAFTING_RECIPE_REQUIRED_ITEMS[recipe]) return false;

    return true;
}

crafting_recipe_is_enabled :: (client: *Client, local_player: *Local_Player, recipe: Crafting_Recipe) -> bool {
    guy_entity := get_entity(client, local_player.guy_pid);
    guy := down(guy_entity, Guy);

    // Check that the target position is actually empty, if required
    if CRAFTING_RECIPE_REQUIRES_EMPTY_TARGET[recipe] && find_entity_with_flags_at_position(client, .Blocks_Move, guy.target_position) return false;

    // Check that the required enabler is present
    return CRAFTING_RECIPE_ENABLER[recipe] == .Count || find_entity_of_kind_at_position(client, CRAFTING_RECIPE_ENABLER[recipe], guy.target_position) != null;
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
