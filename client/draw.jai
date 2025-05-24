Sprite_Index :: enum {
    // HUD
    Heart;
    Hud_PS_Circle;
    Hud_PS_Cross;
    Hud_PS_Triangle;
    Hud_PS_Square;
    Hud_Key_C;
    Hud_Key_Space;
    Hud_Key_Shift;
    
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
    Receiver;
    Mirror;

    // Environment
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
    
    // Guy
    Guy_Idle_Side_0;
    Guy_Idle_Side_1;
    Guy_Idle_Back_0;
    Guy_Idle_Back_1;
    Guy_Idle_Front_0;
    Guy_Idle_Front_1;
    Guy_Walk_Side_0;
    Guy_Walk_Side_1;
    Guy_Walk_Side_2;
    Guy_Walk_Back_0;
    Guy_Walk_Back_1;
    Guy_Walk_Back_2;
    Guy_Walk_Front_0;
    Guy_Walk_Front_1;
    Guy_Walk_Front_2;
    Guy_Dead_Side;
    Guy_Dead_Front;
    Guy_Dead_Back;
    
    // Frog
    Frog_Idle_Side_0;
    Frog_Idle_Side_1;
    Frog_Idle_Side_2;
    Frog_Idle_Side_3;
    Frog_Idle_Back_0;
    Frog_Idle_Back_1;
    Frog_Idle_Back_2;
    Frog_Idle_Back_3;
    Frog_Idle_Front_0;
    Frog_Idle_Front_1;
    Frog_Idle_Front_2;
    Frog_Idle_Front_3;
    Frog_Attacking_Side_0;
    Frog_Attacking_Side_1;
    Frog_Attacking_Side_2;
    Frog_Attacking_Side_3;
    Frog_Attacking_Back_0;
    Frog_Attacking_Back_1;
    Frog_Attacking_Back_2;
    Frog_Attacking_Back_3;
    Frog_Attacking_Front_0;
    Frog_Attacking_Front_1;
    Frog_Attacking_Front_2;
    Frog_Attacking_Front_3;
    Frog_Recovering_Side_0;
    Frog_Recovering_Side_1;
    Frog_Recovering_Back_0;
    Frog_Recovering_Back_1;
    Frog_Recovering_Front_0;
    Frog_Recovering_Front_1;

    // Goblin
    Goblin_Idle_Back_0;
    Goblin_Idle_Back_1;
    Goblin_Idle_Front_0;
    Goblin_Idle_Front_1;
    Goblin_Idle_Side_0;
    Goblin_Idle_Side_1;
    Goblin_Attack_Back;
    Goblin_Attack_Front;
    Goblin_Attack_Side;

    // Trader
    Trader_Idle_Back_0;
    Trader_Idle_Back_1;
    Trader_Idle_Front_0;
    Trader_Idle_Front_1;
    Trader_Idle_Side_0;
    Trader_Idle_Side_1;
}

//
// Draw Context
//

create_draw_data :: (client: *Client) {
    ge_create(*client.graphics, *client.window, *client.engine_allocator);
    client.ui_pipeline = ge_create_pipeline(*client.graphics, .{ .Default, .Disabled, .Disabled, true });
    client.entity_pipeline = ge_create_pipeline(*client.graphics, .{ .Default, .Disabled, .Disabled, false });

#if BAKE_ASSETS {
    ge_create_font_from_buffer(*client.graphics, *client.ui_font, BAKED_FONT, 13, .Ascii);
    ge_create_font_from_buffer(*client.graphics, *client.title_font, BAKED_FONT, 45, .Ascii);
    for i := 0; i < SPRITE_ATLAS_COUNT; ++i {
        client.sprite_atlases[i] = ge_create_texture_from_raw_buffer(*client.graphics, BAKED_SPRITE_ATLASES[i].width, BAKED_SPRITE_ATLASES[i].height, BAKED_SPRITE_ATLASES[i].channels, BAKED_SPRITE_ATLASES[i].pixels.data, .Filter_Nearest | .Wrap_Clamp_To_Edge);
    }
} #else {
    ge_create_font_from_file(*client.graphics, *client.ui_font, "data/font.ttf", 13, .Ascii);
    ge_create_font_from_file(*client.graphics, *client.title_font, "data/font.ttf", 45, .Ascii);
    reload_sprite_atlases_from_disk(client);
}
}

destroy_draw_data :: (client: *Client) {
    for i := 0; i < SPRITE_ATLAS_COUNT; ++i {
        ge_destroy_texture(*client.graphics, client.sprite_atlases[i]);
    }

    ge_destroy_font(*client.graphics, *client.ui_font);
    ge_destroy_font(*client.graphics, *client.title_font);
    ge_destroy_pipeline(*client.graphics, client.ui_pipeline);
    ge_destroy_pipeline(*client.graphics, client.entity_pipeline);
    ge_destroy(*client.graphics);
}

draw_ui_callbacks :: (client: *Client) -> UI_Callbacks {
    return .{ client, draw_ui_text, draw_ui_rect, set_ui_scissors, clear_ui_scissors };
}

reload_sprite_atlases_from_disk :: (client: *Client) {
    for i := 0; i < SPRITE_ATLAS_COUNT; ++i {
        file_path := tprint("data/sprite_atlas_%.png", i);
        if client.sprite_atlases[i] ge_destroy_texture(*client.graphics, client.sprite_atlases[i]);
        client.sprite_atlases[i] = ge_create_texture_from_file(*client.graphics, file_path, .Filter_Nearest | .Wrap_Clamp_To_Edge);
    }
}

get_sprite_index_for_item :: (item: Item_Kind) -> Sprite_Index { // @Temporary: The argument must be replaced with Item_Kind once that exists!
    index: Sprite_Index = ---;

    if #complete item == {
      case .Shard; index = .Shard;
      case .Stone; index = .Stone;
      case .Coal;  index = .Coal_Item;
      case .Coin;  index = .Coin;
    }
    
    return index;
}

get_sprite_index_for_input_action :: (client: *Client, action: Input_Action) -> Sprite_Index {
    for i := 0; i < client.input_bindings[action].count; ++i {
        binding := *client.input_bindings[action][i];

        if #complete binding.kind == {
          case .Keyboard;        if client.active_input_device == .Keyboard then return get_sprite_index_for_key_code(binding.keycode);
          case .Gamepad_Button;  if client.active_input_device == .Gamepad then return get_sprite_index_for_gamepad_button(binding.gamepad_button);
          case .Gamepad_Gesture; if client.active_input_device == .Gamepad then return get_sprite_index_for_gamepad_gesture(binding.gamepad_gesture);
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

draw_text_screen_space :: (client: *Client, font: *Font, text: string, position: v2f, alignment: Text_Alignment, foreground: UI_Color) {
    ge_draw_text(*client.graphics, font, text, position.x, position.y, alignment, .{ foreground.r, foreground.g, foreground.b, foreground.a });
}

draw_filling_boxes_screen_space :: (client: *Client, center: v2f, box_count: s64, box_size: f32, percentage: f32, foreground: GE_Color) {
    background :: GE_Color.{ 100, 100, 100, 200 };

    gap_size := round(cast(f32) box_size * 0.1);
    
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

draw_filling_sprites_screen_space :: (client: *Client, sprite_index: Sprite_Index, center: v2f, sprite_count: s64, sprite_size: f32, percentage: f32) {
    background :: GE_Color.{ 100, 100, 100, 200 };

    gap_size := round(cast(f32) sprite_size * 0.1);
    leftmost_center := center.x - xx (sprite_count - 1) * cast(f32) 0.5 * (sprite_size + gap_size);
    
    for i := 0; i < sprite_count; ++i {
        theta := cast(f32) i / cast(f32) sprite_count;

        sprite_center := v2f.{ leftmost_center + xx i * (sprite_size + gap_size), center.y };

        t: f32 = ---;
        if theta + (cast(f32) 1 / cast(f32) sprite_count) <= percentage then
            t = 0;
        else
            t = 1 - clamp((percentage - theta) / (cast(f32) 1 / cast(f32) sprite_count), 0, 1);

        tint := ge_mix_colors(.{ 255, 255, 255, 255 }, background, t);

        draw_sprite_screen_space(client, sprite_index, sprite_center, .{ sprite_size, sprite_size }, 0, tint, false);
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

draw_sprite_screen_space :: (client: *Client, sprite_index: Sprite_Index, screen_center: v2f, screen_size: v2f, rotation: f32, tint: GE_Color, horizontally_mirrored: bool) {
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
    
    uvs:      [4]v2f = calculate_uv_box_for_index_in_atlas(index_in_atlas, horizontally_mirrored);
    indices:  [6]s32 = .[ 0, 1, 2, 0, 2, 3 ];
    texture := client.sprite_atlases[atlas_index];

    for i := 0; i < indices.Capacity; ++i {
        ge_imm2d_textured_vertex(*client.graphics, screen_center.x + vertices[indices[i]].x, screen_center.y + vertices[indices[i]].y, uvs[indices[i]].x, uvs[indices[i]].y, texture, tint);
    }
}



//
// World Space Drawing
//

draw_rect_world_space :: (client: *Client, world_c0, world_c1: v2f, color: GE_Color) {
    screen_c0 := screen_from_world_position(client, world_c0);
    screen_c1 := screen_from_world_position(client, world_c1);
    draw_rect_screen_space(client, screen_c0, screen_c1, color);
}

draw_outlined_rect_world_space :: (client: *Client, world_c0, world_c1: v2f, screen_thickness: f32, color: GE_Color) {
    screen_c0 := screen_from_world_position(client, world_c0);
    screen_c1 := screen_from_world_position(client, world_c1);
    draw_outlined_rect_screen_space(client, screen_c0, screen_c1, screen_thickness, color);
}

draw_circle_world_space :: (client: *Client, world_center: v2f, inner_world_radius, outer_world_radius: f32, color: GE_Color) {
    screen_center := screen_from_world_position(client, world_center);
    inner_screen_radius := screen_from_world_height(client, inner_world_radius);
    outer_screen_radius := screen_from_world_height(client, outer_world_radius);
    draw_circle_screen_space(client, screen_center, inner_screen_radius, outer_screen_radius, color);
}

draw_progress_bar_world_space :: (client: *Client, world_center: v2f, world_size: f32, percentage: f32) {
    screen_center := screen_from_world_position(client, world_center);
    screen_size   := screen_from_world_height(client, world_size);
    draw_progress_bar_screen_space(client, screen_center, screen_size, percentage);
}

draw_health_bar_world_space :: (client: *Client, world_center: v2f, world_size: f32, health, max_health: f32) {
    screen_center := screen_from_world_position(client, world_center);
    screen_size   := screen_from_world_height(client, world_size);

    box_count: s64 = cast(s64) ceil(max_health / HEALTH_PER_HEART);
    draw_filling_sprites_screen_space(client, .Heart, screen_center, box_count, screen_size, health / max_health);    
}

draw_sprite_world_space :: (client: *Client, sprite_index: Sprite_Index, world_center: v2f, world_size: v2f, rotation: f32, tint: GE_Color, horizontally_mirrored: bool) {
    atlas_index    := sprite_index / SPRITES_PER_ATLAS;
    index_in_atlas := sprite_index % SPRITES_PER_ATLAS;

    world_vertices: [4]v2f =.[
        v2_rotate(v2f.{ -world_size.x / 2, -world_size.y / 2 }, rotation),
        v2_rotate(v2f.{ +world_size.x / 2, -world_size.y / 2 }, rotation),
        v2_rotate(v2f.{ +world_size.x / 2, +world_size.y / 2 }, rotation),
        v2_rotate(v2f.{ -world_size.x / 2, +world_size.y / 2 }, rotation) ];
    
    uvs:      [4]v2f = calculate_uv_box_for_index_in_atlas(index_in_atlas, horizontally_mirrored);
    indices:  [6]s32 = .[ 0, 1, 2, 0, 2, 3 ];
    texture := client.sprite_atlases[atlas_index];

    for i := 0; i < indices.Capacity; ++i {
        screen_position := screen_from_world_position(client, v2f.{ world_center.x + world_vertices[indices[i]].x, world_center.y + world_vertices[indices[i]].y });
        ge_imm2d_textured_vertex(*client.graphics, screen_position.x, screen_position.y, uvs[indices[i]].x, uvs[indices[i]].y, texture, tint);
    }
}



//
// World Drawing
//

draw_world :: (client: *Client) {
    draw_beam :: (client: *Client, beam: *Beam_Data, color: GE_Color, intensity: f32, first_field_as_v: bool) {
        intense_color := GE_Color.{ color.r, color.g, color.b, cast(u8) (cast(f32) color.a * intensity) };

        vertices: []v2f = build_mesh_for_beam(client, beam, first_field_as_v);

        for i := 0; i < vertices.count; ++i {
            world_space := vertices[i];
            screen_space := screen_from_world_position(client, world_space);
            ge_imm2d_colored_vertex(*client.graphics, screen_space.x, screen_space.y, intense_color);
        }
    }
    
    draw_label :: (client: *Client, label: string, entity_pid: Pid) {
        entity := get_entity(client, entity_pid);
        if entity {
            screen_center := screen_from_world_position(client, v2f.{ entity.visual_position.x, entity.visual_position.y - 0.55 });
            screen_size   := v2f.{ xx get_string_width_in_pixels(*client.ui_font, label) + 5, xx client.ui_font.line_height };
            
            draw_rect_screen_space(client, .{ screen_center.x - screen_size.x / 2,
                                              screen_center.y - screen_size.y / 2 },
                                           .{ screen_center.x + screen_size.x / 2,
                                              screen_center.y + screen_size.y / 2 },
                                   .{ 100, 100, 100, 100 });
            draw_text_screen_space(client, *client.ui_font, label, screen_center, .Center | .Median, .{ 255, 255, 255, 255 });
        }
    }

    PROGRESS_BAR_WORLD_SIZE: f32 : 0.9 * 0.13333;

    ge_set_pipeline(*client.graphics, client.entity_pipeline);
    
    //
    // Draw implicit background inanimates
    //
    for x := 0; x < client.world_size.x; ++x {
        draw_sprite_world_space(client, .World_Edge, .{ xx x, -1 }, .{ 1, 1 }, 0.5, .{ 255, 255, 255, 255 }, false);
        draw_sprite_world_space(client, .World_Edge, .{ xx x, xx client.world_size.y }, .{ 1, 1 }, 0, .{ 255, 255, 255, 255 }, false);

        for y := 0; y < client.world_size.y; ++y {
            draw_sprite_world_space(client, .Background, .{ xx x, xx y }, .{ 1, 1 }, 0, .{ 255, 255, 255, 255 }, false);
        }
    }
    
    //
    // Draw all entities, sorted by their kind's depth. We also do some simple
    // visibility checks on these entities
    //
    {
        compare_entities_by_depth :: (lhs, rhs: **Entity) -> s32 {
            return ENTITY_VISUAL_DEPTHS[(~lhs).entity_kind] - ENTITY_VISUAL_DEPTHS[(~rhs).entity_kind];
        }

        entities_to_draw: [..]*Entity;
        entities_to_draw.allocator = *temp;
        
        for i := 0; i < client.all_entities.slot_count; ++i {
            entity, occupied := index_bucket_array(*client.all_entities, i);
            if occupied && visibility_check_entity(client, entity) then array_add(*entities_to_draw, entity);
        }
        
        quick_sort([]*Entity.{ entities_to_draw.count, entities_to_draw.data }, compare_entities_by_depth);
        
        for i := 0; i < entities_to_draw.count; ++i {
            entity := array_get(*entities_to_draw, i);
            sprite_index, tint, horizontally_mirrored := get_sprite_index_for_entity(client, entity);

            if entity.entity_kind == .Item_Stack {
                item_stack := down(entity, Item_Stack);
                count := min(VISUAL_ITEM_STACK_CAPACITY, item_stack.count);
                for i := 0; i < count; ++i {
                    world_position: v2f = .{ entity.visual_position.x + VISUAL_ITEM_STACK_OFFSETS[i].x, entity.visual_position.y + VISUAL_ITEM_STACK_OFFSETS[i].y };
                    draw_sprite_world_space(client, sprite_index, world_position, entity.visual_size, entity.visual_rotation, tint, horizontally_mirrored);
                }
            } else {
                draw_sprite_world_space(client, sprite_index, entity.visual_position, entity.visual_size, entity.visual_rotation, tint, horizontally_mirrored);
            }
        }
    }

    for i := 0; i < client.particle_systems.slot_count; ++i {
        system, occupied := index_bucket_array(*client.particle_systems, i);
        if occupied then draw_particle_system(client, system);
    }
    
    //
    // Draw all emitter states
    //
    for i := 0; i < client.emitters.slot_count; ++i {
        emitter, occupied := index_bucket_array(*client.emitters, i);
        if !occupied continue;

        draw_beam(client, *emitter.beam_data, .{ 255, 229, 167, 220 }, emitter.beam_intensity, true);

        if emitter.time_left_in_seconds > 0 {
            draw_progress_bar_world_space(client, emitter.visual_position, PROGRESS_BAR_WORLD_SIZE, emitter.time_left_in_seconds / EMITTER_MAX_TIME);
        }
    }

    //
    // Draw all receiver states
    //
    for i := 0; i < client.receivers.slot_count; ++i {
        receiver, occupied := index_bucket_array(*client.receivers, i);
        if !occupied continue;

        if receiver.progress_time_in_seconds > 0 {
            draw_progress_bar_world_space(client, receiver.visual_position, PROGRESS_BAR_WORLD_SIZE, receiver.progress_time_in_seconds / RECEIVER_TIME_TO_CHARGE);
        }
    }

    //
    // Draw all frog states
    //
    for i := 0; i < client.frogs.slot_count; ++i {
        frog, occupied := index_bucket_array(*client.frogs, i);
        if !occupied continue;

        intensity := smoothstep(FROG_ATTACK_TIME - frog.state_t, 0, 0.5);
        draw_beam(client, *frog.beam_data, .{ 255, 82, 0, 150 }, intensity, false);
    }

    //
    // Draw all item stack states
    //
    for i := 0; i < client.item_stacks.slot_count; ++i {
        item_stack, occupied := index_bucket_array(*client.item_stacks, i);
        if !occupied continue;

        if item_stack.count > VISUAL_ITEM_STACK_CAPACITY {
            screen_center := screen_from_world_position(client, v2f.{ item_stack.visual_position.x + 0.3, item_stack.visual_position.y + 0.3 });
            draw_text_screen_space(client, *client.ui_font, tprint("%", item_stack.count), screen_center, .Center | .Median, .{ 255, 255, 255, 255 });
        }
    }
    
    //
    // Draw all guy states
    //
    for i := 0; i < client.guys.slot_count; ++i {
        guy, occupied := index_bucket_array(*client.guys, i);
        if !occupied continue;

        if guy.pid == client.my_entity_pid && guy.state != .Dead && position_in_bounds(client, guy.target_position) {
            TARGET_RECT_HALF_SIZE: f32 : 0.9 / 2;
            draw_outlined_rect_world_space(client, .{ xx guy.target_position.x - TARGET_RECT_HALF_SIZE, xx guy.target_position.y - TARGET_RECT_HALF_SIZE }, .{ xx guy.target_position.x + TARGET_RECT_HALF_SIZE, xx guy.target_position.y + TARGET_RECT_HALF_SIZE }, 4, .{ 255, 255, 255, 255 });
        }
        
        if #complete guy.state == {
          case .Idle;
            
          case .Dead;
            draw_circle_world_space(client, .{ xx guy.visual_position.x, xx (guy.visual_position.y - 0.3 - sinf(client.epoch_time * FTAU) * 0.05) }, 0.25, 0.25 * 1.2, .{ 255, 238, 116, 255 });

          case .Digging;
            target_entity := find_entity_with_flags_at_position(client, .Diggable, guy.target_position);
            draw_progress_bar_world_space(client, target_entity.visual_position, PROGRESS_BAR_WORLD_SIZE, 1 - target_entity.health / MAX_HEALTHS[target_entity.entity_kind]);

          case .Carrying;
            active_guy_sprite_index, tint, horizontally_mirrored := get_sprite_index_for_entity(client, guy);

            world_position := get_visual_hand_position_for_guy(client, guy);
            world_size := visual_size_for_item_kind(guy.carrying_item);
            sprite_index := get_sprite_index_for_item(guy.carrying_item);
            draw_sprite_world_space(client, sprite_index, world_position, world_size, 0, .{ 255, 255, 255, 255 }, false);

          case .Resurrecting;
            draw_progress_bar_world_space(client, .{ xx guy.target_position.x, xx guy.target_position.y }, PROGRESS_BAR_WORLD_SIZE, guy.resurrection_t);
        }

        if guy.pid == client.my_entity_pid then draw_input_hint_for_guy(client, guy);
    }

    ge_set_pipeline(*client.graphics, client.ui_pipeline);

    //
    // Draw all entity health bars
    //
    for i := 0; i < client.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*client.all_entities, i);
        if !occupied continue;

        draw_health: bool = ---;

        if entity.entity_kind == {
          case .Guy;
            guy := down(entity, Guy);
            draw_health = entity.health < MAX_HEALTHS[entity.entity_kind] && guy.state != .Dead;
          case; draw_health = bitfield_contains(*entity.entity_flags, Entity_Flags.Living) && entity.health < MAX_HEALTHS[entity.entity_kind];
        }
        
        if draw_health {
            draw_health_bar_world_space(client, .{ entity.visual_position.x, entity.visual_position.y + 0.1 }, PROGRESS_BAR_WORLD_SIZE * 2, entity.health, MAX_HEALTHS[entity.entity_kind]);
        }
    }
    
    //
    // Draw the guy's name above their entities
    //
    for i := 0; i < client.remote_clients.count; ++i {
        rc := array_get_pointer(*client.remote_clients, i);
        draw_label(client, rc.name, rc.entity_pid);
    }

    //
    // Draw an indicate above this guy's entity
    //
    draw_label(client, "v YOU v", client.my_entity_pid);
}



#file_scope

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
    return get_time_animated_sprite_index(client, frame_time, frames, client.epoch_time, true);
}

get_visual_hand_position_for_guy :: (client: *Client, guy: *Guy) -> v2f {
    frame_index := cast(s64) floor(client.epoch_time / 0.5) % 2;
    ONE_PIXEL: f32 : 1 / 16;

    // The x and y coordinates are in pixels inside the guy's sprite.
    x: f32 = ifx guy.physical_rotation == .West then 1 else 14;
    y: f32 = 12 + xx frame_index;

    return .{ guy.visual_position.x + (x * ONE_PIXEL - 0.5), guy.visual_position.y + (y * ONE_PIXEL - 0.5) };
}

get_sprite_index_for_key_code :: (keycode: Key_Code) -> Sprite_Index {
    sprite: Sprite_Index = .Count;

    if keycode == {
      case .C;     sprite = .Hud_Key_C;
      case .Space; sprite = .Hud_Key_Space;
      case .Shift; sprite = .Hud_Key_Shift;
    }
    
    return sprite;
}

get_sprite_index_for_gamepad_button :: (button: Window_Gamepad_Button_Code) -> Sprite_Index {
    sprite: Sprite_Index = .Count;

    if button == {
      case .PS_Circle;   sprite = .Hud_PS_Circle;
      case .PS_Cross;    sprite = .Hud_PS_Cross;
      case .PS_Triangle; sprite = .Hud_PS_Triangle;
      case .PS_Square;   sprite = .Hud_PS_Square;
    }

    return sprite;
}

get_sprite_index_for_gamepad_gesture :: (gesture: Window_Gamepad_Gesture_Code) -> Sprite_Index {
    return .Count;
}

get_sprite_index_for_entity :: (client: *Client, entity: *Entity) -> Sprite_Index, GE_Color, bool {
    entity_is_moving :: (entity: *Entity) -> bool {
        EPSILON: f32 : 0.01;
        target_position := v2f.{ xx entity.physical_position.x, xx entity.physical_position.y };
        return abs(entity.visual_position.x - target_position.x) > EPSILON ||
            abs(entity.visual_position.y - target_position.y) > EPSILON;
    }

    index: Sprite_Index = ---;
    tint: GE_Color = .{ 255, 255, 255, 255 };
    horizontally_mirrored := false;
    
    if #complete entity.entity_kind == {
      case .Guy;
        guy := down(entity, Guy);

        frames: []Sprite_Index = ---;
        frame_time: f32 = ---;

        if guy.state == .Dead {
            frame_time = 0.5;
            if #complete entity.physical_rotation == {
              case .North; frames = .[ .Guy_Dead_Back ];
              case .South; frames = .[ .Guy_Dead_Front ];
              case .East, .West; frames = .[ .Guy_Dead_Side ];
            }
        } else if entity_is_moving(entity) {
            frame_time = 0.2;

            if #complete entity.physical_rotation == {
              case .North; frames = .[ .Guy_Walk_Back_0, .Guy_Walk_Back_1, .Guy_Walk_Back_2 ];
              case .South; frames = .[ .Guy_Walk_Front_0, .Guy_Walk_Front_1, .Guy_Walk_Front_2 ];
              case .East, .West; frames = .[ .Guy_Walk_Side_0, .Guy_Walk_Side_1, .Guy_Walk_Side_2 ];
            }
        } else {
            frame_time = 0.5;

            if #complete entity.physical_rotation == {
              case .North; frames = .[ .Guy_Idle_Back_0, .Guy_Idle_Back_1 ];
              case .South; frames = .[ .Guy_Idle_Front_0, .Guy_Idle_Front_1 ];
              case .East, .West; frames = .[ .Guy_Idle_Side_0, .Guy_Idle_Side_1 ];
            }
        }
        
        horizontally_mirrored = entity.physical_rotation == .East;
        index = get_epoch_time_animated_sprite_index(client, frame_time, frames);

      case .Emitter;   index = .Emitter;
      case .Receiver;  index = .Receiver;
      case .Mirror;    index = .Mirror;
            
      case .Bedrock;   index = .Bedrock;
      case .Rock;      index = .Rock;
      case .Coal; index = .Coal_Block;
      case .Crystal;   index = .Crystal;

      case .Item_Stack;
        stack := down(entity, Item_Stack);
        index = get_sprite_index_for_item(stack.item_kind);

      case .Lava;
        index = get_epoch_time_animated_sprite_index(client, 0.75, .[ .Lava_0, .Lava_1, .Lava_2, .Lava_3, .Lava_4 ]);

      case .Slab;
        slab := down(entity, Slab);
        frames: []Sprite_Index = .[ .Slab_0, .Slab_1, .Slab_2, .Slab_3, .Slab_4 ];
        index = get_time_animated_sprite_index(client, SLAB_TIME_TO_LIVE / cast(f32) frames.count, frames, SLAB_TIME_TO_LIVE - slab.time_left_in_seconds, false);
        
      case .Frog;
        frog := down(entity, Frog);
        frames: []Sprite_Index = ---;
        
        if #complete frog.state == {
          case .Idle;
            if #complete entity.physical_rotation == {
              case .North; frames = .[ .Frog_Idle_Back_0, .Frog_Idle_Back_1, .Frog_Idle_Back_2, .Frog_Idle_Back_3 ];
              case .South; frames = .[ .Frog_Idle_Front_0, .Frog_Idle_Front_1, .Frog_Idle_Front_2, .Frog_Idle_Front_3 ];
              case .East, .West; frames = .[ .Frog_Idle_Side_0, .Frog_Idle_Side_1, .Frog_Idle_Side_2, .Frog_Idle_Side_3 ];
            }
            index = get_epoch_time_animated_sprite_index(client, 0.33, frames);
            
          case .Attacking;
            if #complete entity.physical_rotation == {
              case .North; frames = .[ .Frog_Attacking_Back_0, .Frog_Attacking_Back_1, .Frog_Attacking_Back_2, .Frog_Attacking_Back_3 ];
              case .South; frames = .[ .Frog_Attacking_Front_0, .Frog_Attacking_Front_1, .Frog_Attacking_Front_2, .Frog_Attacking_Front_3 ];
              case .East, .West; frames = .[ .Frog_Attacking_Side_0, .Frog_Attacking_Side_1, .Frog_Attacking_Side_2, .Frog_Attacking_Side_3 ];
            }
            index = get_time_animated_sprite_index(client, FROG_ATTACK_TIME / xx frames.count, frames, frog.state_t, false);

          case .Recovering;
            if #complete entity.physical_rotation == {
              case .North; frames = .[ .Frog_Recovering_Back_0, .Frog_Recovering_Back_1 ];
              case .South; frames = .[ .Frog_Recovering_Front_0, .Frog_Recovering_Front_1 ];
              case .East, .West; frames = .[ .Frog_Recovering_Side_0, .Frog_Recovering_Side_1 ];
            }
            index = get_time_animated_sprite_index(client, FROG_RECOVER_TIME / xx frames.count, frames, frog.state_t, false);
        }

        horizontally_mirrored = frog.physical_rotation == .East;

      case .Goblin;
        goblin := down(entity, Goblin);
        frames: []Sprite_Index = ---;
        
        if #complete goblin.state == {
          case .Idle;
            if #complete entity.physical_rotation == {
              case .North; frames = .[ .Goblin_Idle_Back_0, .Goblin_Idle_Back_1 ];
              case .South; frames = .[ .Goblin_Idle_Front_0, .Goblin_Idle_Front_1 ];
              case .East, .West; frames = .[ .Goblin_Idle_Side_0, .Goblin_Idle_Side_1 ];
            }

            index = get_epoch_time_animated_sprite_index(client, 0.33, frames);

          case .Attacking;
            if #complete entity.physical_rotation == {
              case .North; frames = .[ .Goblin_Attack_Back ];
              case .South; frames = .[ .Goblin_Attack_Front ];
              case .East, .West; frames = .[ .Goblin_Attack_Side ];
            }

            index = get_epoch_time_animated_sprite_index(client, GOBLIN_ATTACK_TIME, frames);

          case .Recovering;
            if #complete entity.physical_rotation == {
              case .North; frames = .[ .Goblin_Idle_Back_0, .Goblin_Idle_Back_1 ];
              case .South; frames = .[ .Goblin_Idle_Front_0, .Goblin_Idle_Front_1 ];
              case .East, .West; frames = .[ .Goblin_Idle_Side_0, .Goblin_Idle_Side_1 ];
            }

            index = get_epoch_time_animated_sprite_index(client, 0.5, frames);
        }
        
        horizontally_mirrored = entity.physical_rotation == .East;

      case .Trader;
        frames: []Sprite_Index = ---;

        if #complete entity.physical_rotation == {
          case .North; frames = .[ .Trader_Idle_Back_0, .Trader_Idle_Back_1 ];
          case .South; frames = .[ .Trader_Idle_Front_0, .Trader_Idle_Front_1 ];
          case .East, .West; frames = .[ .Trader_Idle_Side_0, .Trader_Idle_Side_1 ];
        }

        horizontally_mirrored = entity.physical_rotation == .East;
        index = get_epoch_time_animated_sprite_index(client, 0.5, frames);
    }
    
    return index, tint, horizontally_mirrored;
}

draw_input_hint_for_guy :: (client: *Client, guy: *Guy) {
    if client.hud.was_open_this_frame return;

    target_entity := find_any_entity_at_position(client, guy.target_position);
    if !target_entity return;

    vertical_icon_offset: f32 = 0;
    icon_size: f32 = 0.25 + sinf(client.epoch_time * FTAU * 2) * 0.05;
    input_sprites: []Sprite_Index;

    if target_entity.entity_kind == {
      case .Bedrock, .Crystal, .Rock, .Coal;
        if guy.state == .Idle {
            input_sprites = .[ get_sprite_index_for_input_action(client, .Interact_Primary) ];
        }
      case .Lava;
        if guy.state == .Carrying && guy.carrying_item == .Stone {
            input_sprites = .[ get_sprite_index_for_input_action(client, .Interact_Primary) ];
        }
      case .Mirror;
        if guy.state == .Idle {
            input_sprites = .[ get_sprite_index_for_input_action(client, .Interact_Primary), get_sprite_index_for_input_action(client, .Interact_Secondary) ];
        }
      case .Emitter;
        if guy.state == .Carrying && guy.carrying_item == .Coal {
            input_sprites = .[ get_sprite_index_for_input_action(client, .Interact_Primary) ];
        }
      case .Trader;
        if guy.state == .Idle || guy.state == .Carrying {
            input_sprites = .[ get_sprite_index_for_input_action(client, .Crafting_Menu_Toggle) ];
        }
      case .Guy;
        if guy.state == .Idle {
            other_guy := down(target_entity, Guy);
            if other_guy.state == .Dead {
                input_sprites = .[ get_sprite_index_for_input_action(client, .Interact_Primary) ];
            }
        }
      case .Item_Stack;
        if guy.state == .Idle {
            input_sprites = .[ get_sprite_index_for_input_action(client, .Interact_Primary) ];
            vertical_icon_offset = 0.25;
        }
    }

    for i := 0; i < input_sprites.count; ++i {
        offset: f32 = (cast(f32) (i - input_sprites.count / 2) + cast(f32) (1 - input_sprites.count % 2) * 0.5) * 0.4;
        draw_sprite_world_space(client, input_sprites[i], .{ target_entity.visual_position.x + offset, target_entity.visual_position.y + vertical_icon_offset }, .{ icon_size, icon_size }, 0, .{ 255, 255, 255, 255 }, false);
    }
}

calculate_uv_box_for_index_in_atlas :: (index: s64, horizontally_mirrored: bool) -> [4]v2f {
    WIDTH:  f32 : 1.0 / xx SPRITE_ATLAS_COLUMNS;
    HEIGHT: f32 : 1.0 / xx SPRITE_ATLAS_ROWS;
    
    column := index % SPRITE_ATLAS_COLUMNS;
    row    := index / SPRITE_ATLAS_COLUMNS;

    x0 := xx cast(s64) column * WIDTH;
    y0 := xx cast(s64) row    * HEIGHT;
    x1 := x0 + WIDTH;
    y1 := y0 + HEIGHT;

    if horizontally_mirrored {
        tmp := x0;
        x0 = x1;
        x1 = tmp;
    }
    
    return .[ .{ x0, y0 }, .{ x1, y0 }, .{ x1, y1 }, .{ x0, y1 } ];
}

visibility_check_entity :: (client: *Client, entity: *Entity) -> bool {
    entity_top_left := v2f.{ entity.visual_position.x - entity.visual_size.x / 2, entity.visual_position.y - entity.visual_size.y / 2 };
    entity_bottom_right := v2f.{ entity.visual_position.x + entity.visual_size.x / 2, entity.visual_position.y + entity.visual_size.y / 2 };

    screen_top_left := v2f.{ client.camera.center.x - client.camera.size.x / 2, client.camera.center.y - client.camera.size.y / 2 };
    screen_bottom_right := v2f.{ client.camera.center.x + client.camera.size.x / 2, client.camera.center.y + client.camera.size.y / 2 };
    
    return (entity_bottom_right.x >= screen_top_left.x && entity_bottom_right.y >= screen_top_left.y) &&
        (entity_top_left.x <= screen_bottom_right.x && entity_top_left.y <= screen_bottom_right.y);
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

build_mesh_for_beam :: (client: *Client, beam: *Beam_Data, first_field_as_v: bool) -> []v2f {
    vertices: [..]v2f;
    vertices.allocator = *temp;

    HALF_WIDTH: f32 : 0.75 / 2;
    HALF_HEIGHT: f32 : 1 / 2;

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
        
        if i == 0 && first_field_as_v {
            add_triangle(*vertices, field, .{ -HALF_WIDTH, -HALF_HEIGHT }, .{ 0, HALF_HEIGHT * 0.8 }, .{ HALF_WIDTH, -HALF_HEIGHT }, field.incoming_direction);
        } else if i + 1 < beam.fields.count && field.incoming_direction != array_get(*beam.fields, i + 1).incoming_direction {
            mirror_rotation, valid_rotation := get_mirror_rotation_from_reflection(field.incoming_direction, array_get(*beam.fields, i + 1).incoming_direction);
            assert(valid_rotation, "The Beam Data somehow has a valid corner.");
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

draw_particle_system :: (client: *Client, system: *Particle_System) {
    for i := 0; i < system.emitters.count; ++i {
        emitter := *system.emitters[i];

        local_to_world_position := v2f.{ emitter.local_position.x + system.world_position.x, emitter.local_position.y + system.world_position.y };

        for j := 0; j < emitter.particles.count; ++j {
            particle := *emitter.particles[j];
            
            if particle.remaining_time > 0 {
                color := GE_Color.{ particle.color.r, particle.color.g, particle.color.b, cast(u8) (cast(f32) particle.color.a * system.global_alpha) };
                world_position := v2f.{ particle.local_position.x + local_to_world_position.x, particle.local_position.y + local_to_world_position.y };
                c0 := screen_from_world_position(client, .{ world_position.x - particle.size.x / 2, world_position.y - particle.size.y / 2 });
                c1 := screen_from_world_position(client, .{ world_position.x + particle.size.x / 2, world_position.y + particle.size.y / 2 });
                ge_imm2d_colored_rect(*client.graphics, c0.x, c0.y, c1.x, c1.y, color);
            }
        }
    }
}
