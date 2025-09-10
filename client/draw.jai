WHITE_COLOR  :: GE_Color.{ 255, 255, 255, 255 };
GRAY_COLOR   :: GE_Color.{ 100, 100, 100, 255 };
ORANGE_COLOR :: GE_Color.{ 255, 166, 0, 255 };
YELLOW_COLOR :: GE_Color.{ 252, 238, 28, 255 };

Sprite_Index :: enum {
    // HUD
    Hud_Heart_Full;
    Hud_Heart_Damaged_0;
    Hud_Heart_Damaged_1;

    Hud_Keyboard;
    Hud_Gamepad;
    Hud_Keyboard_Gamepad;
    Hud_PS_Circle;
    Hud_PS_Cross;
    Hud_PS_Triangle;
    Hud_PS_Square;
    Hud_XBox_A;
    Hud_XBox_B;
    Hud_XBox_X;
    Hud_XBox_Y;
    Hud_Key_C;
    Hud_Key_E;
    Hud_Key_Space;
    Hud_Key_Shift;
    Hud_Arrow;
    
    // Items
    Coal_Item;
    Shard;
    Stone;
    Coin;
    Health_Potion;
    Strength_Potion;
    
    // Inanimates
    Background;
    World_Edge;
    Bedrock;
    Crystal;
    Rock;
    Coal_Block;
    Emitter;
    Mirror;
    Chest_Closed;
    
    // Animates
    Lava_0;
    Lava_1;
    Lava_2;
    Lava_3;
    Lava_4;
    Slab_0;
    Slab_1;
    Slab_2;
    Slab_3;
    Slab_4;
    Torch_0;
    Torch_1;
    Torch_2;
    Torch_3;
    Flag_0;
    Flag_1;
    Flag_2;
    Flag_3;
    Flag_4;
    Slime_Hole_Empty;
    Slime_Hole_Filled_0;
    Slime_Hole_Filled_1;
    
    // Guy
    Guy_Idle_Back_0;
    Guy_Idle_Back_1;
    Guy_Idle_Front_0;
    Guy_Idle_Front_1;
    Guy_Idle_Side_0;
    Guy_Idle_Side_1;

    Guy_Walk_Back_0;
    Guy_Walk_Back_1;
    Guy_Walk_Back_2;
    Guy_Walk_Front_0;
    Guy_Walk_Front_1;
    Guy_Walk_Front_2;
    Guy_Walk_Side_0;
    Guy_Walk_Side_1;
    Guy_Walk_Side_2;

    Guy_Damaged_Back_0;
    Guy_Damaged_Back_1;
    Guy_Damaged_Back_2;
    Guy_Damaged_Front_0;
    Guy_Damaged_Front_1;
    Guy_Damaged_Front_2;
    Guy_Damaged_Side_0;
    Guy_Damaged_Side_1;
    Guy_Damaged_Side_2;
    
    Guy_Dead_Back;
    Guy_Dead_Front;
    Guy_Dead_Side;
    
    // Frog
    Frog_Idle_Back_0;
    Frog_Idle_Back_1;
    Frog_Idle_Back_2;
    Frog_Idle_Back_3;
    Frog_Idle_Front_0;
    Frog_Idle_Front_1;
    Frog_Idle_Front_2;
    Frog_Idle_Front_3;
    Frog_Idle_Side_0;
    Frog_Idle_Side_1;
    Frog_Idle_Side_2;
    Frog_Idle_Side_3;

    Frog_Attacking_Back_0;
    Frog_Attacking_Back_1;
    Frog_Attacking_Back_2;
    Frog_Attacking_Front_0;
    Frog_Attacking_Front_1;
    Frog_Attacking_Front_2;
    Frog_Attacking_Side_0;
    Frog_Attacking_Side_1;
    Frog_Attacking_Side_2;

    Frog_Recovering_Back_0;
    Frog_Recovering_Back_1;
    Frog_Recovering_Front_0;
    Frog_Recovering_Front_1;
    Frog_Recovering_Side_0;
    Frog_Recovering_Side_1;

    Frog_Damaged_Back_0;
    Frog_Damaged_Back_1;
    Frog_Damaged_Back_2;
    Frog_Damaged_Front_0;
    Frog_Damaged_Front_1;
    Frog_Damaged_Front_2;
    Frog_Damaged_Side_0;
    Frog_Damaged_Side_1;
    Frog_Damaged_Side_2;
    
    // Goblin
    Goblin_Idle_Back_0;
    Goblin_Idle_Back_1;
    Goblin_Idle_Front_0;
    Goblin_Idle_Front_1;
    Goblin_Idle_Side_0;
    Goblin_Idle_Side_1;
    
    Goblin_Attacking_Back;
    Goblin_Attacking_Front;
    Goblin_Attacking_Side;

    Goblin_Recovering_Back_0;
    Goblin_Recovering_Back_1;
    Goblin_Recovering_Front_0;
    Goblin_Recovering_Front_1;
    Goblin_Recovering_Side_0;
    Goblin_Recovering_Side_1;

    Goblin_Damaged_Back_0;
    Goblin_Damaged_Back_1;
    Goblin_Damaged_Back_2;
    Goblin_Damaged_Front_0;
    Goblin_Damaged_Front_1;
    Goblin_Damaged_Front_2;
    Goblin_Damaged_Side_0;
    Goblin_Damaged_Side_1;
    Goblin_Damaged_Side_2;
    
    // Slime
    Slime_Idle_Back_0;
    Slime_Idle_Back_1;
    Slime_Idle_Front_0;
    Slime_Idle_Front_1;
    Slime_Idle_Side_0;
    Slime_Idle_Side_1;

    Slime_Walk_Back_0;
    Slime_Walk_Back_1;
    Slime_Walk_Back_2;
    Slime_Walk_Front_0;
    Slime_Walk_Front_1;
    Slime_Walk_Front_2;
    Slime_Walk_Side_0;
    Slime_Walk_Side_1;
    Slime_Walk_Side_2;

    Slime_Damaged_Back_0;
    Slime_Damaged_Back_1;
    Slime_Damaged_Back_2;
    Slime_Damaged_Front_0;
    Slime_Damaged_Front_1;
    Slime_Damaged_Front_2;
    Slime_Damaged_Side_0;
    Slime_Damaged_Side_1;
    Slime_Damaged_Side_2;
    
    // Trader
    Trader_Idle_Back_0;
    Trader_Idle_Back_1;
    Trader_Idle_Front_0;
    Trader_Idle_Front_1;
    Trader_Idle_Side_0;
    Trader_Idle_Side_1;
    
    // Debug/Cheat only
    Ghost_Mode;
}

find_sprite_index_from_name :: (name: string) -> s64, bool {
    enum_info := cast(*Type_Info_Enum) type_info(Sprite_Index);

    for i := 0; i < enum_info.members.count; ++i {
        member := *enum_info.members[i];

        if member.display_name == name {
            return member.integral_value, true;
        }
    }

    return 0, false;
}


//
// Draw Context
//

create_draw_data :: (client: *Client) -> bool {
    ge_create(*client.graphics, *client.window, *client.engine_allocator);
    client.ui_pipeline = ge_create_pipeline(*client.graphics, .{ .Default, .Disabled, .Disabled, true });
    client.entity_pipeline = ge_create_pipeline(*client.graphics, .{ .Default, .Disabled, .Disabled, true });
    create_ui_scaled_draw_data(client);

#if BAKE_ASSETS {
    ge_create_font_from_buffer(*client.graphics, *client.title_font, BAKED_FONT, TITLE_FONT_SIZE, .Ascii);
    ge_create_font_from_buffer(*client.graphics, *client.hud_font, BAKED_FONT, HUD_FONT_SIZE, .Ascii);

    for i := 0; i < SPRITE_ATLAS_COUNT; ++i {
        client.sprite_atlases[i] = ge_create_texture_from_raw_buffer(*client.graphics, BAKED_SPRITE_ATLASES[i].width, BAKED_SPRITE_ATLASES[i].height, BAKED_SPRITE_ATLASES[i].channels, BAKED_SPRITE_ATLASES[i].pixels.data, .Filter_Nearest | .Wrap_Clamp_To_Edge);
    }
    return true;
} #else {
    ge_create_font_from_file(*client.graphics, *client.title_font, "data/font.ttf", TITLE_FONT_SIZE, .Ascii);
    ge_create_font_from_file(*client.graphics, *client.hud_font, "data/font.ttf", HUD_FONT_SIZE, .Ascii);
    return reload_sprite_atlases_from_disk(client);
}
}

create_ui_scaled_draw_data :: (client: *Client) {
    ge_destroy_font(*client.graphics, *client.ui_font);
    desired_scale: s16 = cast(s16) ceil(cast(f32) UI_FONT_SIZE * UI_SCALING_VALUES[client.current_ui_scale]);

#if BAKE_ASSETS {
    ge_create_font_from_buffer(*client.graphics, *client.ui_font, BAKED_FONT, desired_scale, .Ascii);
} #else {
    ge_create_font_from_file(*client.graphics, *client.ui_font, "data/font.ttf", desired_scale, .Ascii);
}
}

destroy_draw_data :: (client: *Client) {
    for i := 0; i < SPRITE_ATLAS_COUNT; ++i {
        ge_destroy_texture(*client.graphics, client.sprite_atlases[i]);
    }

    ge_destroy_font(*client.graphics, *client.ui_font);
    ge_destroy_font(*client.graphics, *client.title_font);
    ge_destroy_font(*client.graphics, *client.hud_font);
    ge_destroy_pipeline(*client.graphics, client.ui_pipeline);
    ge_destroy_pipeline(*client.graphics, client.entity_pipeline);
    ge_destroy(*client.graphics);
}

#if DEVELOPER {
reload_sprite_atlases_from_disk :: (client: *Client) -> bool {
    result := pack_sprite_atlases_with_watchdog(client, "data");
    if result == .Complete_Failure return false;

    for i := 0; i < SPRITE_ATLAS_COUNT; ++i {
        file_path := tprint("data/sprite_atlas_%.png", i);
        if client.sprite_atlases[i] ge_destroy_texture(*client.graphics, client.sprite_atlases[i]);
        client.sprite_atlases[i] = ge_create_texture_from_file(*client.graphics, file_path, .Filter_Nearest | .Wrap_Clamp_To_Edge);
    }

    return true;
}
}

draw_ui_callbacks :: (client: *Client) -> UI_Callbacks {
    return .{ client, draw_ui_text, draw_ui_rect, set_ui_scissors, clear_ui_scissors };
}
    
get_sprite_index_for_item :: (item: Item_Kind) -> Sprite_Index {
    index: Sprite_Index = ---;

    if #complete item == {
      case .Shard; index = .Shard;
      case .Stone; index = .Stone;
      case .Coal;  index = .Coal_Item;
      case .Coin;  index = .Coin;
      case .Torch; index = .Torch_0;
      case .Flag;  index = .Flag_0;
    }
    
    return index;
}

get_sprite_index_for_input_action :: (client: *Client, local_player: *Local_Player, action: Input_Action) -> Sprite_Index {
    is_vendor_appropriate_gamepad_binding :: (gamepad: *Gamepad, button: Gamepad_Button_Code) -> bool {
        result: bool = ---;

        if button == {
          case .XBox_A, .XBox_B, .XBox_X, .XBox_Y, .XBox_Menu, .XBox_XBoxButton, .XBox_View, .XBox_Share;
            result = gamepad.product == .XBox_360 || gamepad.product == .XBox_One;
          case .PS_Cross, .PS_Circle, .PS_Square, .PS_Triangle, .PS_Options, .PS_Share, .PS_PSButton, .PS_TouchPad;
            result = gamepad.product == .DualShock_4 || gamepad.product == .DualShock_5;
          case;
            result = true;
        }
        
        return result;
    }
    
    for i := 0; i < client.input_bindings[action].count; ++i {
        binding := *client.input_bindings[action][i];

        if #complete binding.kind == {
          case .Keyboard;
            if local_player.input_binder.active_input_device == .Keyboard {
                return get_sprite_index_for_key_code(binding.keycode);
            }
          case .Gamepad_Button;
            if local_player.input_binder.active_input_device == .Gamepad && is_vendor_appropriate_gamepad_binding(*client.window.gamepads[0], binding.gamepad_button) {
                return get_sprite_index_for_gamepad_button(binding.gamepad_button);
            }
          case .Gamepad_Gesture;
            if local_player.input_binder.active_input_device == .Gamepad {
                return get_sprite_index_for_gamepad_gesture(binding.gamepad_gesture);
            }
        }
    }

    return .Count;
}



//
// Screen Space Drawing
//

draw_rect_screen_space :: (client: *Client, c0, c1: v2f, color: GE_Color) {
    ge_imm2d_colored_rect(*client.graphics, c0.x, c0.y, c1.x, c1.y, color);
}

draw_line_screen_space :: (client: *Client, c0, c1: v2f, color: GE_Color, thickness: f32) {
    ge_imm2d_line(*client.graphics, c0.x, c0.y, c1.x, c1.y, thickness, color);
}

draw_outlined_rect_screen_space :: (client: *Client, c0, c1: v2f, thickness: f32, color: GE_Color) {
    ge_imm2d_colored_rect_outline(*client.graphics, c0.x, c0.y, c1.x, c1.y, thickness, color);
}

Draw_Text_Flags :: enum bitfield {
    Default;
    Shadow;
    Background;
}

draw_text_screen_space :: (client: *Client, font: *Font, text: string, position: v2f, alignment: Text_Alignment, foreground: GE_Color, flags: Draw_Text_Flags) {
    if bitfield_contains(*flags, Draw_Text_Flags.Background) {
        width: f32 = xx get_string_width_in_pixels(font, text);
        height: f32 = xx font.average_character_height;
        padding: f32 = cast(f32) font.average_character_height * 0.2;
        x0, y0, x1, y1: f32 = ---;

        if alignment & .Center {
            x0 = position.x - width * 0.5;
        } else if alignment & .Right {
            x0 = position.x - width;
        } else {
            x0 = position.x;
        }

        if alignment & .Median {
            y0 = position.y - height * 0.5;
        } else if alignment & .Bottom {
            y0 = position.y - height;
        } else {
            y0 = position.y;
        }

        x1 = x0 + width;
        y1 = y0 + height;
        
        x0 = round(x0) - padding;
        y0 = round(y0) - padding;
        x1 = round(x1) + padding;
        y1 = round(y1) + padding;

        BACKGROUND_COLOR :: GE_Color.{ 100, 100, 100, 100 };
        
        ge_imm2d_colored_rect(*client.graphics, x0, y0, x1, y1, BACKGROUND_COLOR);
    }

    if bitfield_contains(*flags, Draw_Text_Flags.Shadow) {
        ge_draw_text(*client.graphics, font, text, position.x + 2, position.y + 2, alignment, GRAY_COLOR);
    }

    ge_draw_text(*client.graphics, font, text, position.x, position.y, alignment, foreground);
}

draw_filling_boxes_screen_space :: (client: *Client, center: v2f, box_count: s64, box_size: f32, percentage: f32, foreground: GE_Color) {
    background :: GE_Color.{ 100, 100, 100, 200 };

    gap_size := ceil(cast(f32) box_size * 0.1);
    
    for i := 0; i < box_count; ++i {
        theta := cast(f32) i / cast(f32) box_count;
        
        c0 := v2f.{ center.x + (theta - 0.5) * xx box_count * (box_size + gap_size), center.y - box_size / 2};
        c1 := v2f.{ c0.x + box_size, center.y + box_size / 2 };
        
        alpha: f32 = ---;
        if theta + (cast(f32) 1 / cast(f32) box_count) <= percentage then
            alpha = 1;
        else
            alpha = clamp((percentage - theta) / (cast(f32) 1 / cast(f32) box_count), 0, 1);

        color := GE_Color.{ foreground.r, foreground.g, foreground.b, xx (xx foreground.a * alpha) };

        draw_rect_screen_space(client, c0, c1, background);
        draw_rect_screen_space(client, c0, c1, color);
    }
}

draw_circle_segment_screen_space :: (client: *Client, center: v2f, outer_radius, inner_radius: f32, theta0, theta1: f32, color: GE_Color) {
    subsegments :: 24;
    
    for i := 0; i < subsegments; ++i {
        range  := theta1 - theta0;
        seg_t0 := (cast(f32) i / cast(f32) subsegments * range + theta0) * FTAU;
        seg_t1 := (cast(f32) (i + 1 % subsegments) / cast(f32) subsegments * range + theta0) * FTAU;
        
        p0 := v2f.{ center.x + sinf(seg_t0) * outer_radius, center.y - cosf(seg_t0) * outer_radius };
        p1 := v2f.{ center.x + sinf(seg_t1) * outer_radius, center.y - cosf(seg_t1) * outer_radius };
        p2 := v2f.{ center.x + sinf(seg_t0) * inner_radius, center.y - cosf(seg_t0) * inner_radius };
        p3 := v2f.{ center.x + sinf(seg_t1) * inner_radius, center.y - cosf(seg_t1) * inner_radius };
        
        ge_imm2d_colored_vertex(*client.graphics, p0.x, p0.y, color);
        ge_imm2d_colored_vertex(*client.graphics, p1.x, p1.y, color);
        ge_imm2d_colored_vertex(*client.graphics, p2.x, p2.y, color);

        ge_imm2d_colored_vertex(*client.graphics, p2.x, p2.y, color);
        ge_imm2d_colored_vertex(*client.graphics, p1.x, p1.y, color);
        ge_imm2d_colored_vertex(*client.graphics, p3.x, p3.y, color);
    }
}

draw_outlined_circle_segment_screen_space :: (client: *Client, center: v2f, outer_radius, inner_radius: f32, theta0, theta1: f32, color: GE_Color, thickness: f32) {
    subsegments :: 24;

    draw_endpoint_sides := abs(theta0 - theta1) > 0.01 && (theta0 > 0.01 || theta1 < 0.99);
    
    for i := 0; i < subsegments; ++i {
        range  := theta1 - theta0;
        seg_t0 := (cast(f32) i / cast(f32) subsegments * range + theta0) * FTAU;
        seg_t1 := (cast(f32) (i + 1 % subsegments) / cast(f32) subsegments * range + theta0) * FTAU;
        
        p0 := v2f.{ center.x + sinf(seg_t0) * outer_radius, center.y - cosf(seg_t0) * outer_radius };
        p1 := v2f.{ center.x + sinf(seg_t1) * outer_radius, center.y - cosf(seg_t1) * outer_radius };
        p2 := v2f.{ center.x + sinf(seg_t0) * inner_radius, center.y - cosf(seg_t0) * inner_radius };
        p3 := v2f.{ center.x + sinf(seg_t1) * inner_radius, center.y - cosf(seg_t1) * inner_radius };

        draw_line_screen_space(client, p0, p1, color, thickness);
        draw_line_screen_space(client, p2, p3, color, thickness);

        if draw_endpoint_sides {
            if i == 0 then draw_line_screen_space(client, p0, p2, color, thickness);
            if i == subsegments - 1 then draw_line_screen_space(client, p1, p3, color, thickness);
        }
    }
}

draw_filling_circle_screen_space :: (client: *Client, center: v2f, outer_radius: f32, percentage: f32) {
    segments :: 6;
    background :: GE_Color.{ 100, 100, 100, 200 };
    foreground :: GE_Color.{ 100, 240, 150, 200 };
    gap_size :: cast(f32) 0.03; // Percentage of the entire circle
    inner_radius: f32 = outer_radius * 0.35;
    
    //
    // Draw the circle segments
    //
    for i := 0; i < segments; ++i {
        theta0 := (cast(f32) i / cast(f32) segments);
        theta1 := (cast(f32) (i + 1 % segments) / cast(f32) segments);
        
        alpha: f32 = ---;
        if theta1 <= percentage then
            alpha = 1;
        else
            alpha = clamp((percentage - theta0) / (theta1 - theta0), 0, 1);
            
        color := GE_Color.{ foreground.r, foreground.g, foreground.b, xx (xx foreground.a * alpha) };

        draw_circle_segment_screen_space(client, center, outer_radius, inner_radius, theta0 + gap_size / 2, theta1 - gap_size / 2, background);
        draw_circle_segment_screen_space(client, center, outer_radius, inner_radius, theta0 + gap_size / 2, theta1 - gap_size / 2, color);
    }
}

draw_circle_screen_space :: (client: *Client, center: v2f, inner_radius, outer_radius: f32, color: GE_Color) {
    draw_circle_segment_screen_space(client, center, inner_radius, outer_radius, 0, 1, color);
}

draw_progress_bar_screen_space :: (client: *Client, center: v2f, box_size: f32, percentage: f32) {
    box_count :: 6;
    foreground :: GE_Color.{ 100, 240, 150, 200 };
    draw_filling_boxes_screen_space(client, center, box_count, box_size, percentage, foreground);
}


draw_sprite_screen_space :: (client: *Client, sprite_index: Sprite_Index, screen_center: v2f, screen_size: v2f, rotation: f32, tint: GE_Color, flags: Draw_Sprite_Flags) {
    if sprite_index == .Count return; // This makes it more convenient when drawing input action hints, because we might not have sprites for every input binding...

    atlas_index    := sprite_index / SPRITES_PER_ATLAS;
    index_in_atlas := sprite_index % SPRITES_PER_ATLAS;
    
    vertices: [4]v2f =.[
        v2_rotate(v2f.{ -screen_size.x / 2, -screen_size.y / 2 }, rotation),
        v2_rotate(v2f.{ +screen_size.x / 2, -screen_size.y / 2 }, rotation),
        v2_rotate(v2f.{ +screen_size.x / 2, +screen_size.y / 2 }, rotation),
        v2_rotate(v2f.{ -screen_size.x / 2, +screen_size.y / 2 }, rotation) ];

    vertices[0].x = round(vertices[0].x);
    vertices[0].y = round(vertices[0].y);
    vertices[1].x = round(vertices[1].x);
    vertices[1].y = round(vertices[1].y);
    vertices[2].x = round(vertices[2].x);
    vertices[2].y = round(vertices[2].y);
    vertices[3].x = round(vertices[3].x);
    vertices[3].y = round(vertices[3].y);
    
    uvs:      [4]v2f = calculate_uv_box_for_index_in_atlas(index_in_atlas, flags);
    indices:  [6]s32 = .[ 0, 1, 2, 0, 2, 3 ];
    texture := client.sprite_atlases[atlas_index];

    for i := 0; i < indices.Capacity; ++i {
        ge_imm2d_textured_vertex(*client.graphics, screen_center.x + vertices[indices[i]].x, screen_center.y + vertices[indices[i]].y, uvs[indices[i]].x, uvs[indices[i]].y, texture, tint);
    }
}



//
// World Space Drawing
//

draw_rect_world_space :: (client: *Client, local_player: *Local_Player, world_c0, world_c1: v2f, color: GE_Color) {
    screen_c0 := screen_from_world_position(*local_player.camera, world_c0);
    screen_c1 := screen_from_world_position(*local_player.camera, world_c1);
    draw_rect_screen_space(client, screen_c0, screen_c1, color);
}

draw_outlined_rect_world_space :: (client: *Client, local_player: *Local_Player, world_c0, world_c1: v2f, screen_thickness: f32, color: GE_Color) {
    screen_c0 := screen_from_world_position(*local_player.camera, world_c0);
    screen_c1 := screen_from_world_position(*local_player.camera, world_c1);
    draw_outlined_rect_screen_space(client, screen_c0, screen_c1, screen_thickness, color);
}

draw_circle_world_space :: (client: *Client, local_player: *Local_Player, world_center: v2f, inner_world_radius, outer_world_radius: f32, color: GE_Color) {
    screen_center := screen_from_world_position(*local_player.camera, world_center);
    inner_screen_radius := screen_from_world_height(*local_player.camera, inner_world_radius);
    outer_screen_radius := screen_from_world_height(*local_player.camera, outer_world_radius);
    draw_circle_screen_space(client, screen_center, inner_screen_radius, outer_screen_radius, color);
}

draw_progress_bar_world_space :: (client: *Client, local_player: *Local_Player, world_center: v2f, world_size: f32, percentage: f32) {
    screen_center := screen_from_world_position(*local_player.camera, world_center);
    screen_size   := screen_from_world_height(*local_player.camera, world_size);
    draw_progress_bar_screen_space(client, screen_center, screen_size, percentage);
}

draw_health_bar_world_space :: (client: *Client, local_player: *Local_Player, entity: *Entity, world_size: f32) {
    screen_center := screen_from_world_position(*local_player.camera, .{ entity.visual_position.x, entity.visual_position.y + 0.35 });
    screen_size   := screen_from_world_height(*local_player.camera, world_size);

    heart_count: s64 = cast(s64) ceil(ENTITY_DEFAULT_HEALTH[entity.entity_kind] / HEALTH_PER_HEART);

    gap_size := round(cast(f32) screen_size * 0.1);
    leftmost_center := screen_center.x - xx (heart_count - 1) * cast(f32) 0.5 * (screen_size + gap_size);

    brightness := query_lightmap(*client.lightmap, entity.physical_position);
    
    for i := 0; i < heart_count; ++i {
        heart_0 := (cast(f32) i) * ENTITY_DEFAULT_HEALTH[entity.entity_kind] / cast(f32) heart_count;
        heart_1 := (cast(f32) i + 1) * ENTITY_DEFAULT_HEALTH[entity.entity_kind] / cast(f32) heart_count;
        sprite_center := v2f.{ leftmost_center + xx i * (screen_size + gap_size), screen_center.y };

        sprite_index: Sprite_Index = ---;
        tint: GE_Color = ---;

        if heart_1 > entity.health && heart_0 < entity.health_bar_damage_animation_base {
            t := (entity.health - heart_0) / (heart_1 - heart_0);

            if entity.health_bar_damage_animation_t > 0.5 {
                sprite_index = .Hud_Heart_Damaged_1;
            } else if entity.health_bar_damage_animation_t > 0.0 {
                sprite_index = .Hud_Heart_Damaged_0;
            } else {
                sprite_index = .Hud_Heart_Full;
            }

            tint = ge_mix_colors(.{ 100, 100, 100, 255 }, .{ 255, 255, 255, 255 }, t) ;
        } else if heart_1 <= entity.health {
            sprite_index = .Hud_Heart_Full;
            tint = .{ 255, 255, 255, 255 };
        } else if heart_0 >= entity.health_bar_damage_animation_base {
            sprite_index = .Hud_Heart_Full;
            tint = .{ 100, 100, 100, 255 };
        }

        tint = darken_color(tint, brightness);
            
        draw_sprite_screen_space(client, sprite_index, sprite_center, .{ screen_size, screen_size }, 0, tint, .None);
    }
}

draw_sprite_world_space :: (client: *Client, local_player: *Local_Player, sprite_index: Sprite_Index, world_center: v2f, world_size: v2f, rotation: f32, tint: GE_Color, flags: Draw_Sprite_Flags) {
    if sprite_index == .Count return;

    atlas_index    := sprite_index / SPRITES_PER_ATLAS;
    index_in_atlas := sprite_index % SPRITES_PER_ATLAS;

    world_vertices: [4]v2f =.[
        v2_rotate(v2f.{ -world_size.x / 2, -world_size.y / 2 }, rotation),
        v2_rotate(v2f.{ +world_size.x / 2, -world_size.y / 2 }, rotation),
        v2_rotate(v2f.{ +world_size.x / 2, +world_size.y / 2 }, rotation),
        v2_rotate(v2f.{ -world_size.x / 2, +world_size.y / 2 }, rotation) ];
    
    uvs:      [4]v2f = calculate_uv_box_for_index_in_atlas(index_in_atlas, flags & .Flipped);
    indices:  [6]s32 = .[ 0, 1, 2, 0, 2, 3 ];
    texture := client.sprite_atlases[atlas_index];

    if flags & .Lit {
        brightness := query_lightmap_at_fractional(*client.lightmap, world_center);
        tint = darken_color(tint, brightness);
    }
    
    for i := 0; i < indices.Capacity; ++i {
        screen_position := screen_from_world_position(*local_player.camera, v2f.{ world_center.x + world_vertices[indices[i]].x, world_center.y + world_vertices[indices[i]].y });
        ge_imm2d_textured_vertex(*client.graphics, screen_position.x, screen_position.y, uvs[indices[i]].x, uvs[indices[i]].y, texture, tint);
    }
}



//
// World Drawing
//

draw_world :: (client: *Client, local_player: *Local_Player) {
    draw_beam :: (client: *Client, local_player: *Local_Player, beam: *Beam_Data, color: GE_Color, intensity: f32, flags: Draw_Beam_Flags) {
        intense_color := GE_Color.{ color.r, color.g, color.b, cast(u8) (cast(f32) color.a * intensity) };

        vertices: []v2f = build_mesh_for_beam(beam, flags);

        for i := 0; i < vertices.count; ++i {
            world_space := vertices[i];
            screen_space := screen_from_world_position(*local_player.camera, world_space);
            ge_imm2d_colored_vertex(*client.graphics, screen_space.x, screen_space.y, intense_color);
        }
    }
    
    draw_label :: (client: *Client, local_player: *Local_Player, label: string, entity_pid: Pid) {
        entity := get_entity(client, entity_pid);
        if entity {
            screen_center := screen_from_world_position(*local_player.camera, v2f.{ entity.visual_position.x, entity.visual_position.y - 0.55 });
            draw_text_screen_space(client, *client.ui_font, label, screen_center, .Center | .Median, WHITE_COLOR, .Background);
        }
    }

    PROGRESS_BAR_WORLD_SIZE: f32 : 0.9 * 0.13333;

    ge_set_scissors(*client.graphics, local_player.viewport);
    ge_set_pipeline(*client.graphics, client.entity_pipeline);
    
    //
    // Draw implicit background inanimates
    //
    for x := 0; x < client.world_size.x; ++x {
        if visibility_check_tile(local_player, .{ x, -1 }) {
            draw_sprite_world_space(client, local_player, .World_Edge, .{ xx x, -1 }, .{ 1, 1 }, 0.5, .{ 255, 255, 255, 255 }, .Lit);
        }
        
        if visibility_check_tile(local_player, .{ x, client.world_size.y }) {
            draw_sprite_world_space(client, local_player, .World_Edge, .{ xx x, xx client.world_size.y }, .{ 1, 1 }, 0, .{ 255, 255, 255, 255 }, .Lit);
        }

        // @Speed: We're also drawing background inanimates under other entities such as bedrock, where we know
        // this isn't going to be visible...
        for y := 0; y < client.world_size.y; ++y {
            if visibility_check_tile(local_player, .{ x, y }) {
                draw_sprite_world_space(client, local_player, .Background, .{ xx x, xx y }, .{ 1, 1 }, 0, .{ 255, 255, 255, 255 }, .Lit);
            }
        }
    }
    
    //
    // Draw all entities, sorted by their kind's depth. We also do some simple
    // visibility checks on these entities
    //
    {
        compare_entities_by_depth :: (lhs, rhs: **Entity) -> Sort_Comparison_Result {
            return ENTITY_VISUAL_DEPTHS[(~lhs).entity_kind] - ENTITY_VISUAL_DEPTHS[(~rhs).entity_kind];
        }

        entities_to_draw: [..]*Entity;
        entities_to_draw.allocator = *temp;
        
        for i := 0; i < client.all_entities.slot_count; ++i {
            entity, occupied := index_bucket_array(*client.all_entities, i);
            if occupied && !bitfield_contains(*entity.entity_flags, Entity_Flags.Disabled_Temporarily) && visibility_check_entity(local_player, entity) {
                array_add(*entities_to_draw, entity);
            }
        }
        
        quick_sort([]*Entity.{ entities_to_draw.count, entities_to_draw.data }, compare_entities_by_depth);
        
        for i := 0; i < entities_to_draw.count; ++i {
            entity := array_get(*entities_to_draw, i);
            tint :: GE_Color.{ 255, 255, 255, 255 };
            sprite_index, flags := get_sprite_index_for_entity(client, entity);

            if !(entity.entity_flags & .Emissive) then flags |= .Lit;
            
            if entity.entity_kind == .Item_Stack {
                item_stack := down(entity, Item_Stack);
                count := min(VISUAL_ITEM_STACK_CAPACITY, item_stack.count);
                for i := 0; i < count; ++i {
                    world_position: v2f = .{ entity.visual_position.x + VISUAL_ITEM_STACK_OFFSETS[i].x, entity.visual_position.y + VISUAL_ITEM_STACK_OFFSETS[i].y };
                    draw_sprite_world_space(client, local_player, sprite_index, world_position, entity.visual_size, entity.visual_rotation, tint, flags);
                }
            } else {
                draw_sprite_world_space(client, local_player, sprite_index, entity.visual_position, entity.visual_size, entity.visual_rotation, tint, flags);

                if entity.entity_kind == .Guy {
                    // We want to draw the item that this guy is carrying in world space, so that
                    // the items appear under any overlays (like UI or beams)...
                    guy := down(entity, Guy);

                    if guy.state == .Carrying {
                        tint :: GE_Color.{ 255, 255, 255, 255 };
                        active_guy_sprite_index, flags := get_sprite_index_for_entity(client, guy);

                        world_position := get_visual_hand_position_for_guy(client, guy);
                        world_size := visual_size_for_item_kind(guy.carrying_item);
                        sprite_index := get_sprite_index_for_item(guy.carrying_item);
                        draw_sprite_world_space(client, local_player, sprite_index, world_position, world_size, 0, tint, .Lit);
                    }
                }
            }
        }
    }

    for i := 0; i < client.particle_systems.slot_count; ++i {
        system, occupied := index_bucket_array(*client.particle_systems, i);
        if occupied then draw_particle_system(client, local_player, system);
    }

    //
    // Draw all emitter states
    //
    for i := 0; i < client.emitters.slot_count; ++i {
        emitter, occupied := index_bucket_array(*client.emitters, i);
        if !occupied continue;

        if emitter.state != .Off {
            flags: Draw_Beam_Flags = .First_As_V;
            if emitter.beam_ends_in_other_emitter then flags |= .Last_As_V;
            draw_beam(client, local_player, *emitter.beam_data, .{ 255, 229, 167, 180 }, emitter.beam_intensity, flags);
        }
            
        if emitter.current_charge > 0 {
            draw_progress_bar_world_space(client, local_player, emitter.visual_position, PROGRESS_BAR_WORLD_SIZE, emitter.current_charge / EMITTER_MAX_CHARGE[client.game_mode]);
        }
    }

    //
    // Draw all frog states
    //
    for i := 0; i < client.frogs.slot_count; ++i {
        frog, occupied := index_bucket_array(*client.frogs, i);
        if !occupied continue;

        intensity := smoothstep(FROG_ATTACK_TIME - frog.state_t, 0, 0.5);
        draw_beam(client, local_player, *frog.beam_data, .{ 255, 82, 0, 150 }, intensity, .Default);
    }

    //
    // Draw all item stack states
    //
    for i := 0; i < client.item_stacks.slot_count; ++i {
        item_stack, occupied := index_bucket_array(*client.item_stacks, i);
        if !occupied continue;

        if item_stack.count > VISUAL_ITEM_STACK_CAPACITY {
            screen_center := screen_from_world_position(*local_player.camera, v2f.{ item_stack.visual_position.x + 0.3, item_stack.visual_position.y + 0.3 });
            draw_text_screen_space(client, *client.ui_font, tprint("%", item_stack.count), screen_center, .Center | .Median, WHITE_COLOR, .Default);
        }
    }
    
    //
    // Draw all guy states
    //
    for i := 0; i < client.guys.slot_count; ++i {
        guy, occupied := index_bucket_array(*client.guys, i);
        if !occupied continue;

        if guy.pid == local_player.guy_pid && guy.state != .Dead && position_in_bounds(client, guy.target_position) {
            TARGET_RECT_HALF_SIZE: f32 : 0.9 / 2;
            thickness: f32 = ceil((local_player.viewport[3] - local_player.viewport[1]) / 180);
            draw_outlined_rect_world_space(client, local_player, .{ xx guy.target_position.x - TARGET_RECT_HALF_SIZE, xx guy.target_position.y - TARGET_RECT_HALF_SIZE }, .{ xx guy.target_position.x + TARGET_RECT_HALF_SIZE, xx guy.target_position.y + TARGET_RECT_HALF_SIZE }, thickness, .{ 255, 255, 255, 255 });
        }
        
        if #complete guy.state == {
          case .Idle;
            
          case .Dead;
            draw_circle_world_space(client, local_player, .{ xx guy.visual_position.x, xx (guy.visual_position.y - 0.3 - sinf(client.game_epoch_time * FTAU) * 0.05) }, 0.25, 0.25 * 1.2, .{ 255, 238, 116, 255 });

          case .Digging;
            target_entity := find_entity_with_flags_at_position(client, .Diggable, guy.target_position);
            if target_entity {
                draw_progress_bar_world_space(client, local_player, target_entity.visual_position, PROGRESS_BAR_WORLD_SIZE, 1 - target_entity.health / ENTITY_DEFAULT_HEALTH[target_entity.entity_kind]);
            }

          case .Carrying;
            // This happened before, so that the items appear under the beams...
            
          case .Resurrecting;
            draw_progress_bar_world_space(client, local_player, .{ xx guy.target_position.x, xx guy.target_position.y }, PROGRESS_BAR_WORLD_SIZE, guy.resurrection_t);
        }

        if guy.pid == local_player.guy_pid then draw_input_hints_for_guy(client, local_player, guy);
    }

    ge_set_pipeline(*client.graphics, client.ui_pipeline);

    //
    // Draw all entity health bars
    //
    for i := 0; i < client.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*client.all_entities, i);
        if !occupied || bitfield_contains(*entity.entity_flags, Entity_Flags.Disabled_Temporarily) continue;

        draw_health: bool = ---;

        if entity.entity_kind == {
          case .Guy;
            guy := down(entity, Guy);
            draw_health = entity.health < ENTITY_DEFAULT_HEALTH[entity.entity_kind] && guy.state != .Dead;
          case; draw_health = bitfield_contains(*entity.entity_flags, Entity_Flags.Living) && entity.health < ENTITY_DEFAULT_HEALTH[entity.entity_kind];
        }
        
        if draw_health {
            draw_health_bar_world_space(client, local_player, entity, PROGRESS_BAR_WORLD_SIZE * 2);
        }
    }
    
    //
    // Draw the guy's name above their entities
    //
    for i := 0; i < client.remote_players.count; ++i {
        remote_player := array_get_pointer(*client.remote_players, i);
        draw_label(client, local_player, remote_player.name, remote_player.guy_pid);
    }

    for i := 0; i < client.local_player_count; ++i {
        other_local_player := *client.local_players[i];

        if local_player == other_local_player {
            draw_label(client, local_player, tprint("v % v", local_player.name), local_player.guy_pid);
        } else {
            draw_label(client, local_player, other_local_player.name, other_local_player.guy_pid);
        }
    }

    ge_set_scissors(*client.graphics, .[ 0, 0, xx client.window.w, xx client.window.h ]);
}

draw_viewport_information :: (client: *Client) {
    THICKNESS: f32 : 5;

    #assert(MAX_LOCAL_PLAYERS == 4);

    draw_viewport_label :: (client: *Client, local_player_index: s64, text: string, index: s64) -> s64 {
        local_player := *client.local_players[local_player_index];
        draw_text_screen_space(client, *client.ui_font, text, .{ local_player.viewport[2] - 10, local_player.viewport[3] - 10 - cast(f32) (index * client.ui_font.line_height) }, .Right | .Bottom, WHITE_COLOR, .Default);
        return index + 1;
    }

    //
    // Draw the viewport boundaries
    //
    if client.local_player_count == {
      case 2;
        center_x: f32 = floor(cast(f32) client.window.w * 0.5);
        draw_line_screen_space(client, .{ center_x, 0 }, .{ center_x, xx client.window.h }, WHITE_COLOR, THICKNESS);
      case 3, 4;
        center_x: f32 = floor(cast(f32) client.window.w * 0.5);
        center_y: f32 = floor(cast(f32) client.window.h * 0.5);
        draw_line_screen_space(client, .{ center_x, 0 }, .{ center_x, xx client.window.h }, WHITE_COLOR, THICKNESS);
        draw_line_screen_space(client, .{ 0, center_y }, .{ xx client.window.w, center_y }, WHITE_COLOR, THICKNESS);
    }

    //
    // Draw the viewport labels
    //
    for i := 0; i < client.local_player_count; ++i {
        j := 0;
        
        if client.local_player_count > 1 && client.game_epoch_time < 15 {
            j = draw_viewport_label(client, i, client.local_players[i].name, j);
        }
        
#if DEVELOPER {
    if i == 0 && client.free_camera_enabled {
        j = draw_viewport_label(client, i, "Freecam", j);
    }
}
    }
}



#file_scope

Draw_Sprite_Flags :: enum bitfield {
    None :: 0x0;
    Flipped;
    Lit;
}

Draw_Beam_Flags :: enum bitfield {
    Default :: 0;
    First_As_V;
    Last_As_V;
}

darken_color :: (color: GE_Color, brightness: f32) -> GE_Color {
    return .{ cast(u8) (cast(f32) color.r * brightness),
              cast(u8) (cast(f32) color.g * brightness),
              cast(u8) (cast(f32) color.b * brightness),
              color.a };
}

PROGRESS_BAR_AS_CIRCLE :: false;

get_time_animated_sprite_index :: (client: *Client, frame_time: f32, frames: []Sprite_Index, time: f32, looping: bool) -> Sprite_Index {
    frame_index := cast(s64) floor(time / frame_time);

    if looping {
        frame_index = frame_index % frames.count;
    } else {
        frame_index = clamp(frame_index, 0, frames.count - 1);
    }
    
    return frames[frame_index];
}

get_epoch_time_animated_sprite_index :: (client: *Client, frame_time: f32, frames: []Sprite_Index) -> Sprite_Index {
    return get_time_animated_sprite_index(client, frame_time, frames, client.game_epoch_time, true);
}

get_visual_hand_position_for_guy :: (client: *Client, guy: *Guy) -> v2f {
    ONE_PIXEL: f32 : 1 / 16;

    frame_index, flip := get_animation_frame_index(*client.animations[guy.animation], guy.physical_rotation, guy.animation_t);

    // The x and y coordinates are in pixels inside the guy's sprite.
    x: f32 = ifx flip then 14 else 1;
    y: f32 = 12 + xx (frame_index % 2);

    return .{ guy.visual_position.x + (x * ONE_PIXEL - 0.5), guy.visual_position.y + (y * ONE_PIXEL - 0.5) };
}

get_sprite_index_for_key_code :: (keycode: Key_Code) -> Sprite_Index {
    sprite: Sprite_Index = .Count;

    if keycode == {
      case .C;     sprite = .Hud_Key_C;
      case .E;     sprite = .Hud_Key_E;
      case .Space; sprite = .Hud_Key_Space;
      case .Shift; sprite = .Hud_Key_Shift;
    }
    
    return sprite;
}

get_sprite_index_for_gamepad_button :: (button: Gamepad_Button_Code) -> Sprite_Index {
    sprite: Sprite_Index = .Count;

    if button == {
      case .PS_Circle;   sprite = .Hud_PS_Circle;
      case .PS_Cross;    sprite = .Hud_PS_Cross;
      case .PS_Triangle; sprite = .Hud_PS_Triangle;
      case .PS_Square;   sprite = .Hud_PS_Square;
      case .XBox_A; sprite = .Hud_XBox_A;
      case .XBox_B; sprite = .Hud_XBox_B;
      case .XBox_X; sprite = .Hud_XBox_X;
      case .XBox_Y; sprite = .Hud_XBox_Y;
    }

    return sprite;
}

get_sprite_index_for_gamepad_gesture :: (gesture: Gamepad_Gesture_Code) -> Sprite_Index {
    return .Count;
}

get_sprite_index_for_entity :: (client: *Client, entity: *Entity) -> Sprite_Index, Draw_Sprite_Flags {
    index: Sprite_Index = ---;
    flags := Draw_Sprite_Flags.None;
    
    if entity.animation == .Count {
        //
        // Default sprite index for this entity
        //
        if #complete entity.entity_kind == {
          case .Emitter;    index = .Emitter;
          case .Mirror;     index = .Mirror;
          case .Lava;       index = .Lava_0;
          case .Bedrock;    index = .Bedrock;
          case .Rock;       index = .Rock;
          case .Coal;       index = .Coal_Block;
          case .Crystal;    index = .Crystal;
          case .Slime_Hole; index = .Slime_Hole_Empty;
          case .Item_Stack; index = get_sprite_index_for_item(down(entity, Item_Stack).item_kind);
          case .Slab;       index = .Slab_0;
          case .Torch;      index = .Torch_0;
          case .Flag;       index = .Flag_0;
          case .Chest;      index = .Chest_Closed;
          case .Guy;        index = .Guy_Idle_Front_0;
          case .Frog;       index = .Frog_Idle_Front_0;
          case .Goblin;     index = .Goblin_Idle_Front_0;
          case .Slime;      index = .Slime_Idle_Front_0;
          case .Trader;     index = .Trader_Idle_Front_0;
        }
    } else {
        //
        // Get the sprite index in the current animation
        //
        animation := *client.animations[entity.animation];
        flipped: bool = ---;
        index, flipped = get_animation_frame(animation, entity.physical_rotation, entity.animation_t);

        if flipped then flags |= .Flipped;
    }

    return index, flags;
}

draw_input_hints_for_guy :: (client: *Client, local_player: *Local_Player, guy: *Guy) {
    if local_player.hud.was_open_this_frame return;

    target_entity := find_any_entity_at_position(client, guy.target_position);
    if !target_entity return;

    vertical_icon_offset: f32 = 0;
    icon_size: f32 = 0.25 + sinf(client.game_epoch_time * FTAU * 2) * 0.05;
    input_sprites: []Sprite_Index;

    if target_entity.entity_kind == {
      case .Bedrock, .Crystal, .Rock, .Coal;
        if guy.state == .Idle {
            input_sprites = .[ get_sprite_index_for_input_action(client, local_player, .Interact_Primary) ];
        }
      case .Lava;
        if guy.state == .Carrying && guy.carrying_item == .Stone {
            input_sprites = .[ get_sprite_index_for_input_action(client, local_player, .Interact_Primary) ];
        }
      case .Mirror;
        if guy.state == .Idle {
            input_sprites = .[ get_sprite_index_for_input_action(client, local_player, .Interact_Primary), get_sprite_index_for_input_action(client, local_player, .Interact_Secondary) ];
        } else if guy.state == .Carrying {
            input_sprites = .[ get_sprite_index_for_input_action(client, local_player, .Interact_Secondary) ];
        }
      case .Emitter;
        if guy.state == .Carrying && guy.carrying_item == .Coal {
            input_sprites = .[ get_sprite_index_for_input_action(client, local_player, .Interact_Primary) ];
        }
      case .Trader;
        if guy.state == .Idle || guy.state == .Carrying {
            input_sprites = .[ get_sprite_index_for_input_action(client, local_player, .Hud_Toggle) ];
        }
      case .Guy;
        if guy.state == .Idle {
            other_guy := down(target_entity, Guy);
            if other_guy.state == .Dead {
                input_sprites = .[ get_sprite_index_for_input_action(client, local_player, .Interact_Primary) ];
            }
        }
      case .Item_Stack, .Torch, .Flag;
        if guy.state == .Idle {
            input_sprites = .[ get_sprite_index_for_input_action(client, local_player, .Interact_Primary) ];
            vertical_icon_offset = 0.25;
        }
      case .Chest;
        chest := down(target_entity, Chest);
        if guy.state == .Idle || guy.state == .Carrying {
            if chest.item_count {
                input_sprites = .[ get_sprite_index_for_input_action(client, local_player, .Interact_Primary), get_sprite_index_for_input_action(client, local_player, .Interact_Secondary) ];
            } else {
                input_sprites = .[ get_sprite_index_for_input_action(client, local_player, .Interact_Primary) ];
            }
        }
    }

    for i := 0; i < input_sprites.count; ++i {
        offset: f32 = (cast(f32) (i - input_sprites.count / 2) + cast(f32) (1 - input_sprites.count % 2) * 0.5) * 0.4;
        draw_sprite_world_space(client, local_player, input_sprites[i], .{ target_entity.visual_position.x + offset, target_entity.visual_position.y + vertical_icon_offset }, .{ icon_size, icon_size }, 0, .{ 255, 255, 255, 255 }, .None);
    }
}

calculate_uv_box_for_index_in_atlas :: (index: s64, flags: Draw_Sprite_Flags) -> [4]v2f {
    WIDTH:  f32 : 1.0 / xx SPRITE_ATLAS_COLUMNS;
    HEIGHT: f32 : 1.0 / xx SPRITE_ATLAS_ROWS;
    
    column := index % SPRITE_ATLAS_COLUMNS;
    row    := index / SPRITE_ATLAS_COLUMNS;

    x0 := xx cast(s64) column * WIDTH;
    y0 := xx cast(s64) row    * HEIGHT;
    x1 := x0 + WIDTH;
    y1 := y0 + HEIGHT;

    if flags & .Flipped {
        tmp := x0;
        x0 = x1;
        x1 = tmp;
    }
    
    return .[ .{ x0, y0 }, .{ x1, y0 }, .{ x1, y1 }, .{ x0, y1 } ];
}

visibility_check_box :: (local_player: *Local_Player, top_left, bottom_right: v2f) -> bool {
    camera := *local_player.camera;

    visible_top_left     := v2f.{ camera.world_center.x - camera.world_area.x / 2, camera.world_center.y - camera.world_area.y / 2 };
    visible_bottom_right := v2f.{ camera.world_center.x + camera.world_area.x / 2, camera.world_center.y + camera.world_area.y / 2 };
    
    return (bottom_right.x >= visible_top_left.x && bottom_right.y >= visible_top_left.y) &&
        (top_left.x <= visible_bottom_right.x && top_left.y <= visible_bottom_right.y);
}

visibility_check_tile :: (local_player: *Local_Player, tile: v2i) -> bool {
    return visibility_check_box(local_player, .{ xx tile.x - 0.5, xx tile.y - 0.5 }, .{ xx tile.x + 0.5, xx tile.y + 0.5 });
}

visibility_check_entity :: (local_player: *Local_Player, entity: *Entity) -> bool {
    entity_top_left := v2f.{ entity.visual_position.x - entity.visual_size.x / 2, entity.visual_position.y - entity.visual_size.y / 2 };
    entity_bottom_right := v2f.{ entity.visual_position.x + entity.visual_size.x / 2, entity.visual_position.y + entity.visual_size.y / 2 };
    return visibility_check_box(local_player, entity_top_left, entity_bottom_right);
}

draw_ui_text :: (client: *Client, font: *Font, text: string, position: UI_Vector2, foreground: UI_Color, background: UI_Color) {
    ge_set_pipeline(*client.graphics, client.ui_pipeline);
    ge_draw_text(*client.graphics, font, text, position.x, position.y, .Left | .Bottom, .{ foreground.r, foreground.g, foreground.b, foreground.a });    
}

draw_ui_rect :: (client: *Client, rect: UI_Rect, rounding: f32, color: UI_Color) {
    ge_set_pipeline(*client.graphics, client.ui_pipeline);
    ge_imm2d_colored_rect(*client.graphics, rect.x0, rect.y0, rect.x1, rect.y1, .{ color.r, color.g, color.b, color.a });
}

set_ui_scissors :: (client: *Client, rect: UI_Rect) {
    ge_set_scissors(*client.graphics, .[ rect.x0, rect.y0, rect.x1, rect.y1 ]);
}

clear_ui_scissors :: (client: *Client) {
    ge_set_scissors(*client.graphics, .[ 0, 0, xx client.window.w - 1, xx client.window.h - 1 ]);
}

build_mesh_for_beam :: (beam: *Beam_Data, flags: Draw_Beam_Flags) -> []v2f {
    vertices: [..]v2f;
    vertices.allocator = *temp;

    HALF_WIDTH: f32 : 0.75 / 2;
    HALF_HEIGHT: f32 : 1 / 2;
    OPEN_TRIANGLE_OFFSET:  f32 : -HALF_HEIGHT * 0.25;
    CLOSE_TRIANGLE_OFFSET: f32 : +HALF_HEIGHT * 0.25;

    for i := 0; i < beam.fields.count; ++i {
        field := array_get(*beam.fields, i);
        
        add_triangle :: (vertices: *[..]v2f, field: v2i, p0, p1, p2: v2f, rotation: Direction) {
            visual_position := v2f.{ xx field.x, xx field.y };

            angle := visual_from_physical_rotation(rotation);
            rotated_p0 := v2_rotate(p0, angle);
            rotated_p1 := v2_rotate(p1, angle);
            rotated_p2 := v2_rotate(p2, angle);
            array_add(vertices, v2f.{ visual_position.x + rotated_p0.x, visual_position.y + rotated_p0.y });
            array_add(vertices, v2f.{ visual_position.x + rotated_p1.x, visual_position.y + rotated_p1.y });
            array_add(vertices, v2f.{ visual_position.x + rotated_p2.x, visual_position.y + rotated_p2.y });
        }
        
        if i == 0 && flags & .First_As_V {
            add_triangle(*vertices, field, .{ -HALF_WIDTH, -HALF_HEIGHT }, .{ 0, OPEN_TRIANGLE_OFFSET }, .{ HALF_WIDTH, -HALF_HEIGHT }, field.incoming_direction);
        } else if i == beam.fields.count - 1 && flags & .Last_As_V {
            add_triangle(*vertices, field, .{ -HALF_WIDTH, HALF_HEIGHT }, .{ 0, CLOSE_TRIANGLE_OFFSET }, .{ HALF_WIDTH, HALF_HEIGHT }, field.incoming_direction);
        } else if i + 1 < beam.fields.count && field.incoming_direction != array_get(*beam.fields, i + 1).incoming_direction {
            mirror_rotation, valid_rotation := get_mirror_rotation_from_reflection(field.incoming_direction, array_get(*beam.fields, i + 1).incoming_direction);
            assert(valid_rotation, "The Beam Data somehow has an invalid corner.");
            add_triangle(*vertices, field, .{ -HALF_WIDTH, +HALF_WIDTH }, .{ -HALF_WIDTH, -HALF_HEIGHT }, .{ +HALF_WIDTH, -HALF_HEIGHT }, mirror_rotation);
            add_triangle(*vertices, field, .{ -HALF_WIDTH, +HALF_WIDTH }, .{ +HALF_HEIGHT, +HALF_WIDTH }, .{ +HALF_HEIGHT, -HALF_WIDTH }, mirror_rotation);
            add_triangle(*vertices, field, .{ -HALF_WIDTH, +HALF_WIDTH }, .{ +HALF_HEIGHT, -HALF_WIDTH }, .{ +HALF_WIDTH, -HALF_HEIGHT }, mirror_rotation);
        } else {
            add_triangle(*vertices, field, .{ -HALF_WIDTH, -HALF_HEIGHT }, .{ HALF_WIDTH, -HALF_HEIGHT }, .{ -HALF_WIDTH, HALF_HEIGHT }, field.incoming_direction);
            add_triangle(*vertices, field, .{ -HALF_WIDTH, HALF_HEIGHT }, .{ HALF_WIDTH, -HALF_HEIGHT }, .{ HALF_WIDTH, HALF_HEIGHT }, field.incoming_direction);
        }
    }

    return .{ vertices.count, vertices.data };
}

draw_particle_system :: (client: *Client, local_player: *Local_Player, system: *Particle_System) {
    for i := 0; i < system.emitters.count; ++i {
        emitter := *system.emitters[i];

        local_to_world_position := v2f.{ emitter.local_position.x + system.world_position.x, emitter.local_position.y + system.world_position.y };

        if !visibility_check_box(local_player, .{ emitter.local_bounding_box[0].x + local_to_world_position.x, emitter.local_bounding_box[0].y + local_to_world_position.y }, .{ emitter.local_bounding_box[1].x + local_to_world_position.x, emitter.local_bounding_box[1].y + local_to_world_position.y }) continue;
        
        for j := 0; j < emitter.particles.count; ++j {
            particle := *emitter.particles[j];
            
            if particle.elapsed < particle.lifetime {
                world_position := v2f.{ particle.local_position.x + local_to_world_position.x, particle.local_position.y + local_to_world_position.y };
                c0 := screen_from_world_position(*local_player.camera, .{ world_position.x - particle.size.x / 2, world_position.y - particle.size.y / 2 });
                c1 := screen_from_world_position(*local_player.camera, .{ world_position.x + particle.size.x / 2, world_position.y + particle.size.y / 2 });

                lifetime := min(particle.lifetime, system.time_to_live);
                local_alpha := smoothstep(particle.elapsed, 0, emitter.fadein) * (1 - smoothstep(particle.elapsed, lifetime - emitter.fadeout, lifetime));

                brightness := ifx !emitter.emissive then query_lightmap_at_fractional(*client.lightmap, world_position) else 1;
                color := GE_Color.{ particle.color.r, particle.color.g, particle.color.b, cast(u8) (cast(f32) particle.color.a * system.global_alpha * local_alpha * brightness) };

                ge_imm2d_colored_rect(*client.graphics, c0.x, c0.y, c1.x, c1.y, color);
            }
        }
    }
}
