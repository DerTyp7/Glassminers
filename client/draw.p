//
// UI Module Callbacks
//

draw_ui_callbacks :: (client: *Client) -> UI_Callbacks {
    return .{ client, draw_ui_text, draw_ui_rect, set_ui_scissors, clear_ui_scissors };
}

draw_ui_text :: (client: *Client, font: *Font, text: string, position: UI_Vector2, foreground: UI_Color, background: UI_Color) {
    ge_draw_text(*client.graphics, font, text, position.x, position.y, .Left | .Bottom, .{ foreground.r, foreground.g, foreground.b, foreground.a });    
}

draw_ui_rect :: (client: *Client, rect: UI_Rect, rounding: f32, color: UI_Color) {
    ge_imm2d_colored_rect(*client.graphics, rect.x0, rect.y0, rect.x1, rect.y1, .{ color.r, color.g, color.b, color.a });
    ge_imm2d_flush(*client.graphics);
}

set_ui_scissors :: (client: *Client, rect: UI_Rect) {

}

clear_ui_scissors :: (client: *Client) {
    
}



//
// HUD Drawing
//

draw_rect :: (client: *Client, x0, y0, x1, y1: f32, color: GE_Color) {
    ge_imm2d_colored_rect(*client.graphics, x0, y0, x1, y1, color);
    ge_imm2d_flush(*client.graphics);
}

draw_text :: (client: *Client, font: *Font, text: string, x: f32, y: f32, alignment: Text_Alignment, foreground: UI_Color) {
    ge_draw_text(*client.graphics, font, text, x, y, alignment, .{ foreground.r, foreground.g, foreground.b, foreground.a });
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

    draw_entity :: (client: *Client, kind: Entity_Kind, visual_position: v2f, rotation: Direction) {
        screen_center := screen_from_world_position(client, visual_position);
        screen_size   := screen_from_world_scale(client, .{ 1, 1 });

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
    
    world :: *client.world;

    ge_imm2d_blend_mode(*client.graphics, .Default);
    
    //
    // Draw implicit background inanimates
    //
    for x := 0; x < client.world.size.x; ++x {
        for y := 0; y < client.world.size.y; ++y {
            draw_entity(client, .Inanimate, .{ xx x, xx y }, .North);
        }
    }
    
    //
    // Draw all entities
    //
    for i := 0; i < world.entities.count; ++i {
        entity := array_get_pointer(*world.entities, i);
        draw_entity(client, entity.kind, entity.visual_position, entity.rotation);
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
        rotated_uvs[i] = unrotated_uvs[(i + shift) % unrotated_uvs.Capacity];
    }
    
    return rotated_uvs;
}
