Sprite_Index :: enum {
    Background;
    Bedrock;
    Crystal;
    Shard;
    Rock;
    Stone;
    Coal_Block;
    Coal_Item;
    Emitter;
    Receiver;
    Mirror;
    Player_Idle_Side_0;
    Player_Idle_Side_1;
    Player_Idle_Back_0;
    Player_Idle_Back_1;
    Player_Idle_Front_0;
    Player_Idle_Front_1;
    Player_Walk_Side_0;
    Player_Walk_Side_1;
    Player_Walk_Side_2;
    Player_Walk_Back_0;
    Player_Walk_Back_1;
    Player_Walk_Back_2;
    Player_Walk_Front_0;
    Player_Walk_Front_1;
    Player_Walk_Front_2;
    Dragon_Idle_0;
    Dragon_Idle_1;
    Dragon_Spitting_Fire;
    Dragon_Recovering_0;
    Dragon_Recovering_1;
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



//
// Screen Space Drawing
//

draw_rect_screen_space :: (client: *Client, c0, c1: v2f, color: GE_Color) {
    ge_imm2d_colored_rect(*client.graphics, c0.x, c0.y, c1.x, c1.y, color);
    ge_imm2d_flush(*client.graphics); // @Cleanup: Why are we flushing here? For the UI?
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

    draw_endpoint_sides := abs(theta0 - theta1) > 0.01;
    
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
    foreground :: GE_Color.{ 227, 60, 74, 255 };
    draw_filling_boxes_screen_space(client, screen_center, box_count, screen_size, health / max_health, foreground);    
}

draw_sprite_world_space :: (client: *Client, sprite_index: Sprite_Index, world_center: v2f, world_size: v2f, rotation: f32, tint: GE_Color, horizontally_mirrored: bool) {
    screen_center := screen_from_world_position(client, world_center);
    screen_size   := screen_from_world_size(client, world_size);
    draw_sprite_screen_space(client, sprite_index, screen_center, screen_size, rotation, tint, horizontally_mirrored);
}



//
// World Drawing
//

draw_world :: (client: *Client) {
    draw_beam :: (client: *Client, beam: *Beam_Data, color: GE_Color) {
        WORLD_HALF_SIZE: f32 : 0.75 / 2;

        for i := 0; i < beam.fields.count; ++i {
            field := array_get_pointer(*beam.fields, i);
            visual_position := v2f.{ xx field.x, xx field.y };
            draw_rect_world_space(client, .{ visual_position.x - WORLD_HALF_SIZE, visual_position.y - WORLD_HALF_SIZE }, .{ visual_position.x + WORLD_HALF_SIZE, visual_position.y + WORLD_HALF_SIZE }, color);
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
        for y := 0; y < client.world_size.y; ++y {
            draw_sprite_world_space(client, .Background, .{ xx x, xx y }, .{ 1, 1 }, 0, .{ 255, 255, 255, 255 }, false);
        }
    }
    
    //
    // Draw all entities
    //
    for i := 0; i < client.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*client.all_entities, i);
        if !occupied continue;
        
        sprite_index, tint, horizontally_mirrored := get_sprite_index_for_entity(client, entity);
        draw_sprite_world_space(client, sprite_index, entity.visual_position, .{ 1, 1 }, entity.visual_rotation, tint, horizontally_mirrored);
    }

    //
    // Draw all emitters
    //
    for i := 0; i < client.emitters.slot_count; ++i {
        emitter, occupied := index_bucket_array(*client.emitters, i);
        if !occupied continue;

        draw_beam(client, *emitter.beam_data, .{ 255, 255, 255, 150 });

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
    // Draw all dragon states
    //
    for i := 0; i < client.dragons.slot_count; ++i {
        dragon, occupied := index_bucket_array(*client.dragons, i);
        if !occupied continue;

        draw_beam(client, *dragon.beam_data, .{ 255, 209, 104, 150 });
        
        if dragon.health < MAX_HEALTHS[dragon.entity_kind] {
            draw_health_bar_world_space(client, dragon.visual_position, PROGRESS_BAR_WORLD_SIZE, dragon.health, MAX_HEALTHS[dragon.entity_kind]);
        }
    }

    //
    // Draw all item stack states
    //
    for i := 0; i < client.item_stacks.slot_count; ++i {
        item_stack, occupied := index_bucket_array(*client.item_stacks, i);
        if !occupied continue;

        if item_stack.count > 1 {
            screen_center := screen_from_world_position(client, v2f.{ item_stack.visual_position.x + 0.3, item_stack.visual_position.y + 0.3 });
            draw_text_screen_space(client, *client.ui_font, tprint("%", item_stack.count), screen_center, .Center | .Median, .{ 255, 255, 255, 255 });
        }
    }
    
    //
    // Draw all player states
    //
    for i := 0; i < client.players.slot_count; ++i {
        player, occupied := index_bucket_array(*client.players, i);
        if !occupied continue;

        if player.pid == client.my_entity_pid {
            TARGET_RECT_HALF_SIZE: f32 : 0.9 / 2;
            draw_outlined_rect_world_space(client, .{ xx player.target_position.x - TARGET_RECT_HALF_SIZE, xx player.target_position.y - TARGET_RECT_HALF_SIZE }, .{ xx player.target_position.x + TARGET_RECT_HALF_SIZE, xx player.target_position.y + TARGET_RECT_HALF_SIZE }, 4, .{ 255, 255, 255, 255 });
        }
            
        if #complete player.state == {
          case .Idle;

          case .Dead;
            draw_circle_world_space(client, .{ xx player.visual_position.x, xx (player.visual_position.y - 0.3 - sinf(client.epoch_time + FTAU * 3) * 0.05) }, 0.25, 0.25 * 1.2, .{ 255, 238, 116, 255 });

          case .Digging;
            target_entity := get_entity_at_position(client, player.target_position);
            draw_progress_bar_world_space(client, target_entity.visual_position, PROGRESS_BAR_WORLD_SIZE, 1 - target_entity.health / MAX_HEALTHS[target_entity.entity_kind]);

          case .Carrying;
            world_position := player.visual_position;
            world_position.x += 0.25;
            world_size :: v2f.{ 0.25, 0.25 };
            sprite_index := get_sprite_index_for_item(player.carrying_item);
            draw_sprite_world_space(client, sprite_index, world_position, world_size, 0, .{ 255, 255, 255, 255 }, false);

          case .Resurrecting;
            draw_progress_bar_world_space(client, .{ xx player.target_position.x, xx player.target_position.y }, PROGRESS_BAR_WORLD_SIZE, player.resurrection_t);
        }

        if player.state != .Dead && player.health < MAX_HEALTHS[.Player] {
            draw_health_bar_world_space(client, player.visual_position, PROGRESS_BAR_WORLD_SIZE, player.health, MAX_HEALTHS[player.entity_kind]);
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
}



#file_scope

PROGRESS_BAR_AS_CIRCLE :: false;

get_time_animated_sprite_index :: (client: *Client, frame_time: f32, frames: []Sprite_Index, time: f32) -> Sprite_Index {
    frame_index := cast(s64) floor(time / frame_time) % frames.count;
    return frames[frame_index];
}

get_epoch_time_animated_sprite_index :: (client: *Client, frame_time: f32, frames: []Sprite_Index) -> Sprite_Index {
    return get_time_animated_sprite_index(client, frame_time, frames, client.epoch_time);
}

get_sprite_index_for_item :: (item: Item_Kind) -> Sprite_Index { // @Temporary: The argument must be replaced with Item_Kind once that exists!
    index: Sprite_Index = ---;

    if #complete item == {
      case .Shard; index = .Shard;
      case .Stone; index = .Stone;
      case .Coal; index = .Coal_Item;
    }
    
    return index;
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
      case .Player;
        frames: []Sprite_Index = ---;
        frame_time: f32 = ---;

        if entity_is_moving(entity) {
            if #complete entity.physical_rotation == {
              case .North;
                frames = .[ .Player_Walk_Back_0, .Player_Walk_Back_1, .Player_Walk_Back_2 ];
                frame_time = 0.2;
              case .South;
                frames = .[ .Player_Walk_Front_0, .Player_Walk_Front_1, .Player_Walk_Front_2 ];
                frame_time = 0.2;
              case .East, .West;
                frames = .[ .Player_Walk_Side_0, .Player_Walk_Side_1, .Player_Walk_Side_2 ];
                frame_time = 0.2;
            }
        } else {
            if #complete entity.physical_rotation == {
              case .North;
                frames = .[ .Player_Idle_Back_0, .Player_Idle_Back_1 ];
                frame_time = 0.5;
              case .South;
                frames = .[ .Player_Idle_Front_0, .Player_Idle_Front_1 ];
                frame_time = 0.5;
              case .East, .West;
                frames = .[ .Player_Idle_Side_0, .Player_Idle_Side_1 ];
                frame_time = 0.5;
            }
        }
            
        horizontally_mirrored = entity.physical_rotation == .East;
        index = get_epoch_time_animated_sprite_index(client, frame_time, frames);
            
      case .Crystal;   index = .Crystal;
      case .Bedrock;   index = .Bedrock;
      case .Emitter;   index = .Emitter;
      case .Receiver;  index = .Receiver;
      case .Mirror;    index = .Mirror;
      case .Rock;      index = .Rock;
      case .Item_Stack;
        stack := down(entity, Item_Stack);
        index = get_sprite_index_for_item(stack.item_kind);
      case .Dragon;
        dragon := down(entity, Dragon);
        
        if #complete dragon.state == {
          case .Idle;
            index = get_epoch_time_animated_sprite_index(client, 0.5, .[ .Dragon_Idle_0, .Dragon_Idle_1 ]);
            
          case .Attacking;
            index = .Dragon_Spitting_Fire;

          case .Recovering;
            index = get_time_animated_sprite_index(client, DRAGON_RECOVER_TIME / 2, .[ .Dragon_Recovering_0, .Dragon_Recovering_1 ], dragon.state_t);
        }

        horizontally_mirrored = dragon.physical_rotation == .East;

        case .Coal; index = .Coal_Block;
    }
    
    return index, tint, horizontally_mirrored;
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

