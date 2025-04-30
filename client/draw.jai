//
// Draw Context
//

create_draw_data :: (client: *Client) {
    ge_create(*client.graphics, *client.window, *client.perm);
    client.ui_pipeline = ge_create_pipeline(*client.graphics, .{ .Default, .Disabled, .Disabled, true });
    client.entity_pipeline = ge_create_pipeline(*client.graphics, .{ .Default, .Disabled, .Disabled, false });

#if BAKE_ASSETS {
    ge_create_font_from_buffer(*client.graphics, *client.ui_font, BAKED_FONT, 13, .Ascii);
    ge_create_font_from_buffer(*client.graphics, *client.title_font, BAKED_FONT, 45, .Ascii);
    client.sprite_atlas = ge_create_texture_from_raw_buffer(*client.graphics, BAKED_SPRITE_ATLAS.width, BAKED_SPRITE_ATLAS.height, BAKED_SPRITE_ATLAS.channels, BAKED_SPRITE_ATLAS.pixels.data, .Filter_Nearest | .Wrap_Clamp_To_Edge);
} #else {
    ge_create_font_from_file(*client.graphics, *client.ui_font, "data/font.ttf", 13, .Ascii);
    ge_create_font_from_file(*client.graphics, *client.title_font, "data/font.ttf", 45, .Ascii);
    client.sprite_atlas = ge_create_texture_from_file(*client.graphics, "data/sprite_atlas.png", .Filter_Nearest | .Wrap_Clamp_To_Edge);
}
}

destroy_draw_data :: (client: *Client) {
    ge_destroy_texture(*client.graphics, client.sprite_atlas);
    ge_destroy_font(*client.graphics, *client.ui_font);
    ge_destroy_font(*client.graphics, *client.title_font);
    ge_destroy_pipeline(*client.graphics, client.ui_pipeline);
    ge_destroy_pipeline(*client.graphics, client.entity_pipeline);
    ge_destroy(*client.graphics);
}



//
// UI Module Callbacks
//

draw_ui_callbacks :: (client: *Client) -> UI_Callbacks {
    return .{ client, draw_ui_text, draw_ui_rect, set_ui_scissors, clear_ui_scissors };
}



//
// HUD Drawing
//

draw_rect_screen_space :: (client: *Client, c0, c1: v2f, color: GE_Color) {
    ge_imm2d_colored_rect(*client.graphics, c0.x, c0.y, c1.x, c1.y, color);
    ge_imm2d_flush(*client.graphics);
}

draw_outlined_rect_screen_space :: (client: *Client, c0, c1: v2f, thickness: f32, color: GE_Color) {
    ge_imm2d_colored_rect_outline(*client.graphics, c0.x, c0.y, c1.x, c1.y, thickness, color);
}

draw_text_screen_space :: (client: *Client, font: *Font, text: string, position: v2f, alignment: Text_Alignment, foreground: UI_Color) {
    ge_draw_text(*client.graphics, font, text, position.x, position.y, alignment, .{ foreground.r, foreground.g, foreground.b, foreground.a });
}

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



//
// World Drawing
//

draw_world :: (client: *Client) {
    draw_emitter_field :: (client: *Client, visual_position: v2f, color: GE_Color) {
        WORLD_HALF_SIZE: f32 : 0.75 / 2;
        draw_rect_world_space(client, .{ visual_position.x - WORLD_HALF_SIZE, visual_position.y - WORLD_HALF_SIZE }, .{ visual_position.x + WORLD_HALF_SIZE, visual_position.y + WORLD_HALF_SIZE }, color);
    }

    draw_entity :: (client: *Client, kind: Entity_Kind, visual_position: v2f, visual_size: v2f, visual_rotation: f32) {
        screen_center := screen_from_world_position(client, visual_position);
        screen_size   := screen_from_world_size(client, visual_size);

        vertices: [4]v2f =.[
                v2_rotate(v2f.{ -screen_size.x / 2, -screen_size.y / 2 }, visual_rotation),
                v2_rotate(v2f.{ +screen_size.x / 2, -screen_size.y / 2 }, visual_rotation),
                v2_rotate(v2f.{ +screen_size.x / 2, +screen_size.y / 2 }, visual_rotation),
                v2_rotate(v2f.{ -screen_size.x / 2, +screen_size.y / 2 }, visual_rotation) ];
        uvs:      [4]v2f = calculate_uv_box_for_entity_kind(kind);
        indices:  [6]s32 = .[ 0, 1, 2, 0, 2, 3 ];

        for i := 0; i < indices.Capacity; ++i {
            ge_imm2d_textured_vertex(*client.graphics, screen_center.x + vertices[indices[i]].x, screen_center.y + vertices[indices[i]].y, uvs[indices[i]].x, uvs[indices[i]].y, client.sprite_atlas, .{ 255, 255, 255, 255 });
        }
    }
    
    draw_label :: (client: *Client, label: string, entity_pid: Pid) {
        entity := get_entity(*client.world, entity_pid);
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
    
    world :: *client.world;

    ge_set_pipeline(*client.graphics, client.entity_pipeline);
    
    //
    // Draw implicit background inanimates
    //
    for x := 0; x < client.world.size.x; ++x {
        for y := 0; y < client.world.size.y; ++y {
            draw_entity(client, .Inanimate, .{ xx x, xx y }, .{ 1, 1 }, 0);
        }
    }
    
    //
    // Draw all entities
    //
    for i := 0; i < world.entities.count; ++i {
        entity := array_get_pointer(*world.entities, i);
        draw_entity(client, entity.kind, entity.visual_position, .{ 1, 1 }, entity.visual_rotation);
    }

    //
    // Draw all emitters
    //
    for i := 0; i < world.entities.count; ++i {
        entity := array_get_pointer(*world.entities, i);
        if entity.kind == .Emitter {
            emitter := down(entity, Emitter);
            
            for j := 0; j < emitter.fields.count; ++j {
                field := array_get(*emitter.fields, j);
                draw_emitter_field(client, .{ xx field.x, xx field.y }, .{ 255, 255, 255, 150 });
            }
        }
    }

    //
    // Draw all receiver states
    //
    for i := 0; i < world.entities.count; ++i {
        entity := array_get_pointer(*world.entities, i);
        if entity.kind == .Receiver {
            receiver := down(entity, Receiver);
            if receiver.progress_time_in_seconds > 0 {
                draw_progress_bar_world_space(client, entity.visual_position, PROGRESS_BAR_WORLD_SIZE, receiver.progress_time_in_seconds / RECEIVER_TIME_TO_CHARGE);
            }
        }
    }

    //
    // Draw all emitter states
    //
    for i := 0; i < world.entities.count; ++i {
        entity := array_get_pointer(*world.entities, i);
        if entity.kind == .Emitter {
            emitter := down(entity, Emitter);
            if emitter.time_left_in_seconds > 0 {
                draw_progress_bar_world_space(client, entity.visual_position, PROGRESS_BAR_WORLD_SIZE, emitter.time_left_in_seconds / EMITTER_TIME_TO_DIE);
            }
        }
    }
    
    //
    // Draw all player states
    //
    for i := 0; i < world.entities.count; ++i {
        entity := array_get_pointer(*world.entities, i);
        if entity.kind == .Player {
            player := down(entity, Player);

            TARGET_RECT_HALF_SIZE: f32 : 0.9 / 2;
            draw_outlined_rect_world_space(client, .{ xx player.target_position.x - TARGET_RECT_HALF_SIZE, xx player.target_position.y - TARGET_RECT_HALF_SIZE }, .{ xx player.target_position.x + TARGET_RECT_HALF_SIZE, xx player.target_position.y + TARGET_RECT_HALF_SIZE }, 4, .{ 255, 255, 255, 255 });
            
            if #complete player.state == {
              case .Idle;
              case .Dead;
                draw_circle_world_space(client, .{ xx entity.visual_position.x, xx (entity.visual_position.y - 0.3 - sinf(client.epoch_time + FTAU * 3) * 0.05) }, 0.25, 0.25 * 1.2, .{ 255, 238, 116, 255 });
              case .Digging;
                target_entity := get_entity_at_position(*client.world, player.target_position);
                draw_progress_bar_world_space(client, target_entity.visual_position, PROGRESS_BAR_WORLD_SIZE, 1 - target_entity.health / MAX_HEALTHS[target_entity.kind]);

              case .Carrying;
                world_position := entity.visual_position;
                world_position.x += 0.25;
                world_size :: v2f.{ 0.25, 0.25 };
                draw_entity(client, player.carrying_item, world_position, world_size, 0);
            }

            if entity.health < MAX_HEALTHS[.Player] {
                draw_health_bar_world_space(client, .{ xx entity.visual_position.x, xx (entity.visual_position.y + 0.55) }, PROGRESS_BAR_WORLD_SIZE, entity.health, MAX_HEALTHS[.Player]);
            }
        }
    }    

    ge_set_pipeline(*client.graphics, client.ui_pipeline);
    
    //
    // Draw the player's name above their entities
    //
    for i := 0; i < client.remote_clients.count; ++i {
        rc := array_get_pointer(*client.remote_clients, i);
        draw_label(client, rc.name, rc.entity_pid);
    }

    //
    // Draw an indicate above this player's entity
    //
    draw_label(client, "v YOU v", client.my_entity_pid);

    ge_imm2d_flush(*client.graphics);
}


#file_scope

PROGRESS_BAR_AS_CIRCLE :: false;
SPRITE_ATLAS_COLUMNS :: 8;

calculate_uv_box_for_entity_kind :: (kind: Entity_Kind) -> [4]v2f {
    WIDTH: f32 : 1.0 / xx SPRITE_ATLAS_COLUMNS;

    column := kind % SPRITE_ATLAS_COLUMNS;
    row    := kind / SPRITE_ATLAS_COLUMNS;

    x0 := xx cast(s64) column * WIDTH;
    y0 := xx cast(s64) row    * WIDTH;
    
    return .[ .{ x0, y0 }, .{ x0 + WIDTH, y0 }, .{ x0 + WIDTH, y0 + WIDTH }, .{ x0, y0 + WIDTH } ];
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

draw_circle_segment_screen_space :: (client: *Client, center: v2f, outer_radius: f32, inner_radius: f32, theta0, theta1: f32, color: GE_Color) {
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

draw_circle_world_space :: (client: *Client, world_center: v2f, inner_world_radius, outer_world_radius: f32, color: GE_Color) {
    screen_center := screen_from_world_position(client, world_center);
    inner_screen_radius := screen_from_world_height(client, inner_world_radius);
    outer_screen_radius := screen_from_world_height(client, outer_world_radius);
    draw_circle_screen_space(client, screen_center, inner_screen_radius, outer_screen_radius, color);
}

draw_progress_bar_screen_space :: (client: *Client, center: v2f, box_size: f32, percentage: f32) {
    box_count :: 6;
    foreground :: GE_Color.{ 100, 240, 150, 200 };
    draw_filling_boxes_screen_space(client, center, box_count, box_size, percentage, foreground);
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
    foreground :: GE_Color.{ 227, 60, 74, 255 };
    draw_filling_boxes_screen_space(client, screen_center, box_count, screen_size, health / max_health, foreground);    
}
