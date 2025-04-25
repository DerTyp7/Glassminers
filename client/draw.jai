//
// Draw Context
//

create_draw_data :: (client: *Client) {
    ge_create(*client.graphics, *client.window, *client.perm);
    client.ui_pipeline = ge_create_pipeline(*client.graphics, .{ .Default, .Disabled, .Disabled, true });
    client.entity_pipeline = ge_create_pipeline(*client.graphics, .{ .Default, .Disabled, .Disabled, false });
    ge_create_font_from_file(*client.graphics, *client.ui_font, "data/font.ttf", 13, .Ascii);
    ge_create_font_from_file(*client.graphics, *client.title_font, "data/font.ttf", 45, .Ascii);
    client.sprite_atlas = ge_create_texture_from_file(*client.graphics, "data/sprite_atlas.png", .Filter_Nearest | .Wrap_Clamp_To_Edge);
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

draw_rect :: (client: *Client, x0, y0, x1, y1: f32, color: GE_Color) {
    ge_imm2d_colored_rect(*client.graphics, x0, y0, x1, y1, color);
    ge_imm2d_flush(*client.graphics);
}

draw_outlined_rect :: (client: *Client, x0, y0, x1, y1: f32, thickness: f32, color: GE_Color) {
    ge_imm2d_colored_rect_outline(*client.graphics, x0, y0, x1, y1, thickness, color);
}

draw_text :: (client: *Client, font: *Font, text: string, x: f32, y: f32, alignment: Text_Alignment, foreground: UI_Color) {
    ge_draw_text(*client.graphics, font, text, x, y, alignment, .{ foreground.r, foreground.g, foreground.b, foreground.a });
}


#if PROGRESS_BAR_AS_CIRCLE {

draw_progress_bar :: (client: *Client, x, y: f32, outer_radius: f32, percentage: f32) {
    draw_circle_segment :: (client: *Client, x, y: f32, outer_radius: f32, inner_radius: f32, theta0, theta1: f32, color: GE_Color) {
        subsegments :: 4;
        
        for i := 0; i < subsegments; ++i {
            range  := theta1 - theta0;
            seg_t0 := (cast(f32) i / cast(f32) subsegments * range + theta0) * FTAU;
            seg_t1 := (cast(f32) (i + 1 % subsegments) / cast(f32) subsegments * range + theta0) * FTAU;
            
            p0 := v2f.{ x + sinf(seg_t0) * outer_radius, y - cosf(seg_t0) * outer_radius };
            p1 := v2f.{ x + sinf(seg_t1) * outer_radius, y - cosf(seg_t1) * outer_radius };
            p2 := v2f.{ x + sinf(seg_t0) * inner_radius, y - cosf(seg_t0) * inner_radius };
            p3 := v2f.{ x + sinf(seg_t1) * inner_radius, y - cosf(seg_t1) * inner_radius };
            
            ge_imm2d_colored_vertex(*client.graphics, p0.x, p0.y, color);
            ge_imm2d_colored_vertex(*client.graphics, p1.x, p1.y, color);
            ge_imm2d_colored_vertex(*client.graphics, p2.x, p2.y, color);

            ge_imm2d_colored_vertex(*client.graphics, p2.x, p2.y, color);
            ge_imm2d_colored_vertex(*client.graphics, p1.x, p1.y, color);
            ge_imm2d_colored_vertex(*client.graphics, p3.x, p3.y, color);
        }
    }

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

        draw_circle_segment(client, x, y, outer_radius, inner_radius, theta0 + gap_size / 2, theta1 - gap_size / 2, background);
        draw_circle_segment(client, x, y, outer_radius, inner_radius, theta0 + gap_size / 2, theta1 - gap_size / 2, color);
    }
}

} #else {

draw_progress_bar :: (client: *Client, x, y: f32, box_size: f32, percentage: f32) {
    boxes :: 6;
    background :: GE_Color.{ 100, 100, 100, 200 };
    foreground :: GE_Color.{ 100, 240, 150, 200 };

    gap_size := round(cast(f32) box_size * 0.1);
    
    //
    // Draw the boxes
    //
    for i := 0; i < boxes; ++i {
        theta := cast(f32) i / cast(f32) boxes;
        
        x0 := x + (theta - 0.5) * xx boxes * (box_size + gap_size);
        x1 := x0 + box_size;
        y0 := y - box_size / 2;
        y1 := y + box_size / 2;
        
        alpha: f32 = ---;
        if theta + (cast(f32) 1 / cast(f32) boxes) <= percentage then
            alpha = 1;
        else
            alpha = clamp((percentage - theta) / (cast(f32) 1 / cast(f32) boxes), 0, 1);

        color := GE_Color.{ foreground.r, foreground.g, foreground.b, xx (xx foreground.a * alpha) };

        draw_rect(client, x0, y0, x1, y1, background);
        draw_rect(client, x0, y0, x1, y1, color);
    }
}

}


//
// World Drawing
//

draw_world :: (client: *Client) {
    draw_emitter_field :: (client: *Client, visual_position: v2f, color: GE_Color) {
        screen_center := screen_from_world_position(client, visual_position);
        screen_size   := screen_from_world_scale(client, .{ 0.75, 0.75 });

        vertices: [4]v2f = .[ .{ screen_center.x - screen_size.x / 2, screen_center.y - screen_size.y / 2 },
                              .{ screen_center.x + screen_size.x / 2, screen_center.y - screen_size.y / 2 },
                              .{ screen_center.x - screen_size.x / 2, screen_center.y + screen_size.y / 2 },
                              .{ screen_center.x + screen_size.x / 2, screen_center.y + screen_size.y / 2 } ];
        indices:  [6]s32 = .[ 0, 1, 2, 1, 3, 2 ];
        
        for i := 0; i < indices.Capacity; ++i {
            ge_imm2d_colored_vertex(*client.graphics, vertices[indices[i]].x, vertices[indices[i]].y, color);
        }    
    }

    draw_entity :: (client: *Client, kind: Entity_Kind, visual_position: v2f, visual_size: v2f, rotation: Direction) {
        screen_center := screen_from_world_position(client, visual_position);
        screen_size   := screen_from_world_scale(client, visual_size);

        vertices: [4]v2f = .[ .{ screen_center.x - screen_size.x / 2, screen_center.y - screen_size.y / 2 },
                              .{ screen_center.x + screen_size.x / 2, screen_center.y - screen_size.y / 2 },
                              .{ screen_center.x + screen_size.x / 2, screen_center.y + screen_size.y / 2 },
                              .{ screen_center.x - screen_size.x / 2, screen_center.y + screen_size.y / 2 } ];
        uvs:      [4]v2f = calculate_uv_box_for_entity_kind(kind, rotation);
        indices:  [6]s32 = .[ 0, 1, 2, 0, 2, 3 ];
        
        for i := 0; i < indices.Capacity; ++i {
            ge_imm2d_textured_vertex(*client.graphics, vertices[indices[i]].x, vertices[indices[i]].y, uvs[indices[i]].x, uvs[indices[i]].y, client.sprite_atlas, .{ 255, 255, 255, 255 });
        }
    }
    
    draw_label :: (client: *Client, label: string, entity_pid: Pid) {
        entity := get_entity(*client.world, entity_pid);
        if entity {
            screen_center := screen_from_world_position(client, v2f.{ entity.visual_position.x, entity.visual_position.y - 0.55 });
            screen_size   := v2f.{ xx get_string_width_in_pixels(*client.ui_font, label) + 5, xx client.ui_font.line_height };
            
            draw_rect(client, screen_center.x - screen_size.x / 2, screen_center.y - screen_size.y / 2, screen_center.x + screen_size.x / 2, screen_center.y + screen_size.y / 2, .{ 100, 100, 100, 100 });
            draw_text(client, *client.ui_font, label, screen_center.x, screen_center.y, .Center | .Median, .{ 255, 255, 255, 255 });
        }
    }

    progress_bar_scale := round(screen_from_world_scale(client, .{ 0.9, 0.9 }).y * 0.13333);
    
    world :: *client.world;

    ge_set_pipeline(*client.graphics, client.entity_pipeline);
    
    //
    // Draw implicit background inanimates
    //
    for x := 0; x < client.world.size.x; ++x {
        for y := 0; y < client.world.size.y; ++y {
            draw_entity(client, .Inanimate, .{ xx x, xx y }, .{ 1, 1 }, .North);
        }
    }
    
    //
    // Draw all entities
    //
    for i := 0; i < world.entities.count; ++i {
        entity := array_get_pointer(*world.entities, i);
        draw_entity(client, entity.kind, entity.visual_position, .{ 1, 1 }, entity.physical_rotation);
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
                target_position := screen_from_world_position(client, .{ xx entity.visual_position.x, xx entity.visual_position.y });
                draw_progress_bar(client, target_position.x, target_position.y, progress_bar_scale, receiver.progress_time_in_seconds / RECEIVER_TIME);
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

            target_scale := screen_from_world_scale(client, .{ 0.9, 0.9 });
            target_position := screen_from_world_position(client, .{ xx player.target_position.x, xx player.target_position.y });
            draw_outlined_rect(client, target_position.x - target_scale.x / 2, target_position.y - target_scale.y / 2, target_position.x + target_scale.x / 2, target_position.y + target_scale.y / 2, 4, .{ 255, 255, 255, 255 });
            
            if #complete player.state == {
              case .Idle;
              case .Digging;
                target_entity := get_entity_at_position(*client.world, player.target_position);
                draw_progress_bar(client, target_position.x, target_position.y, progress_bar_scale, player.progress_time_in_seconds / DIGGING_TIMES[target_entity.kind]);
              case .Carrying;
                world_position := entity.visual_position;
                world_position.x += 0.25;
                world_size :: v2f.{ 0.25, 0.25 };
                draw_entity(client, player.carrying_item, world_position, world_size, .North);
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

calculate_uv_box_for_entity_kind :: (kind: Entity_Kind, rotation: Direction) -> [4]v2f {
    WIDTH: f32 : 1.0 / xx SPRITE_ATLAS_COLUMNS;

    column := kind % SPRITE_ATLAS_COLUMNS;
    row    := kind / SPRITE_ATLAS_COLUMNS;

    x0 := xx cast(s64) column * WIDTH;
    y0 := xx cast(s64) row    * WIDTH;
    
    unrotated_uvs := [4]v2f.[ .{ x0, y0 }, .{ x0 + WIDTH, y0 }, .{ x0 + WIDTH, y0 + WIDTH }, .{ x0, y0 + WIDTH } ];
    rotated_uvs: [4]v2f = ---;
    
    shift: u32 = rotation;
    
    for i := 0; i < rotated_uvs.Capacity; ++i {
        rotated_uvs[i] = unrotated_uvs[(i -% shift) % unrotated_uvs.Capacity];
    }
    
    return rotated_uvs;
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
