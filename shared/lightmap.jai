Puddle :: u8;

TORCH_BRIGHTNESS: f32 : 1.0;
LAVA_BRIGHTNESS: f32 : 0.5;

PUDDLE_THRESHOLD: f32 : 0.2;
NO_PUDDLE_ID: Puddle : -1;

Lightmap :: struct {
    allocator: *Allocator;
    blockers: []u8;
    tiles:    []f32;
    puddles:  []Puddle;
    size: v2i;
    gamma: f32;

    intermediate: []f32;
    puddle_sizes: [..]s64;

#if DEVELOPER {
    disabled: bool;
}
}

create_lightmap :: (map: *Lightmap, allocator: *Allocator, size: v2i) {
    map.allocator = allocator;
    map.size      = size;
    map.tiles     = allocate_array(map.allocator, f32, map.size.x * map.size.y);
    map.blockers  = allocate_array(map.allocator, u8, map.size.x * map.size.y);
    map.puddles   = allocate_array(map.allocator, Puddle, map.size.x * map.size.y);

    clear_slice(map.tiles);
    clear_slice(map.blockers);
    clear_slice(map.puddles);    

    map.gamma = 1;

#if DEVELOPER {
    map.disabled = false;
}
}

destroy_lightmap :: (map: *Lightmap) {
    deallocate_array(map.allocator, *map.tiles);
    map.size = .{ };
}

resize_lightmap :: (map: *Lightmap, new_size: v2i) {
    new_tiles    := allocate_array(map.allocator, f32, new_size.x * new_size.y);
    new_blockers := allocate_array(map.allocator, u8, new_size.x * new_size.y);

    clear_slice(new_tiles);
    clear_slice(new_blockers);
    
    size_to_copy := v2i.{ min(new_size.x, map.size.x), min(new_size.y, map.size.y) };
    
    for y := 0; y < size_to_copy.y; ++y {
        for x := 0; x < size_to_copy.x; ++x {
            new_tiles[y * new_size.x + x]    = map.tiles[y * map.size.x + x];
            new_blockers[y * new_size.x + x] = map.blockers[y * map.size.x + x];
        }
    }

    deallocate_array(map.allocator, *map.tiles);
    deallocate_array(map.allocator, *map.blockers);
    deallocate_array(map.allocator, *map.puddles);

    map.tiles    = new_tiles;
    map.blockers = new_blockers;
    map.puddles  = allocate_array(map.allocator, Puddle, new_size.x * new_size.y);
    map.size     = new_size;
}

update_lightmap :: (map: *Lightmap, em: *Entity_Manager, dt: f32) {
    //
    // Firstly update the lightmap with input based on the current entities.
    // Here we're relying on different declarations from server and client side (since both use the same
    // procedure here), so let's hope this keeps working...
    //
    for i := 0; i < em.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*em.all_entities, i);
        if occupied {
            if entity.entity_kind == {
              case .Guy;
                guy := down(entity, Guy);
                if guy.state == .Carrying && guy.carrying_item == .Torch then fill_lightmap_tile(map, guy.physical_position, TORCH_BRIGHTNESS);

              case .Emitter;
                emitter := down(entity, Emitter);
                if emitter.current_charge > 0 then fill_lightmap_with_beam(map, *emitter.beam_data, 1);

              case .Frog;
                frog := down(entity, Frog);
                if frog.state == .Attacking then fill_lightmap_with_beam(map, *frog.beam_data, 1);

              case .Torch;
                fill_lightmap_tile(map, entity.physical_position, TORCH_BRIGHTNESS);
                
              case .Lava;
                fill_lightmap_tile(map, entity.physical_position, LAVA_BRIGHTNESS);
            }
        }
    }


    //
    // Now propagate and fade the light values for each tile...
    //
    map.intermediate = copy_array(*temp, map.tiles);
    
    for y := 0; y < map.size.y; ++y {
        for x := 0; x < map.size.x; ++x {
            previous := query_previous_map(map, .{ x, y }) - LIGHTMAP_FADE_PER_SECOND * dt;
            updated := previous;
            updated += calculate_neighbor_effect(map, .{ x + 1, y }, previous, dt);
            updated += calculate_neighbor_effect(map, .{ x - 1, y }, previous, dt);
            updated += calculate_neighbor_effect(map, .{ x, y + 1 }, previous, dt);
            updated += calculate_neighbor_effect(map, .{ x, y - 1 }, previous, dt);
            map.tiles[y * map.size.x + x] = clamp(updated, 0, 1);
        }
    }
}

query_lightmap :: (map: *Lightmap, tile: v2i) -> f32 {
#if DEVELOPER {
    if map.disabled return 1;
}
    
    assert(tile.x >= 0 && tile.x < map.size.x && tile.y >= 0 && tile.y < map.size.y, "Tried to query the lightmap out of bounds.");

    index := tile.y * map.size.x + tile.x;
    return max(map.tiles[index], LIGHTMAP_AMBIENCE);
}

query_lightmap_gamma_adjusted :: (map: *Lightmap, tile: v2i) -> f32 {
    return powf(query_lightmap(map, tile), 1 / map.gamma);
}

query_lightmap_at_fractional_gamma_adjusted :: (map: *Lightmap, position: v2f) -> f32 {
#if DEVELOPER {
    if map.disabled return 1;
}
    
    // For fractional positions, it can happen that these are out of bounds. For example:
    //   1. Particles floating around
    //   2. World edges being drawn around the walkable world
    //   ...
    // For these cases, we just want to take the nearest world position
    tile := v2i.{ cast(s32) round(position.x), cast(s32) round(position.y) };
    tile.x = clamp(tile.x, 0, map.size.x - 1);
    tile.y = clamp(tile.y, 0, map.size.y - 1);
    return query_lightmap_gamma_adjusted(map, tile);
}

maybe_add_blocker :: (map: *Lightmap, entity: *Entity) {
    if entity.entity_flags & .Blocks_Line_Of_Sight {
        ++map.blockers[entity.physical_position.y * map.size.x + entity.physical_position.x];
    }
}

maybe_remove_blocker :: (map: *Lightmap, entity: *Entity) {
    if entity.entity_flags & .Blocks_Line_Of_Sight {
        --map.blockers[entity.physical_position.y * map.size.x + entity.physical_position.x];
    }
}

maybe_move_blocker :: (map: *Lightmap, entity: *Entity, new_position: v2i) {
    if entity.entity_flags & .Blocks_Line_Of_Sight {
        --map.blockers[entity.physical_position.y * map.size.x + entity.physical_position.x];
        ++map.blockers[new_position.y * map.size.x + new_position.x];
    }
}



calculate_puddles :: (map: *Lightmap, tick_allocator: *Allocator) {
    put_puddle :: (tile_position: v2i, puddle: Puddle) #macro {
        map.puddles[tile_position.y * map.size.x + tile_position.x] = puddle;
    }

    visit_tile_recursively :: (map: *Lightmap, target_tile: v2i, target_puddle: Puddle) {
        idx := target_tile.y * map.size.x + target_tile.x;
        if query_lightmap(map, target_tile) > PUDDLE_THRESHOLD || map.puddles[idx] == target_puddle return;
        assert(map.puddles[idx] == NO_PUDDLE_ID, "Somehow two different puddle IDs are direct neighbors??");
        map.puddles[idx] = target_puddle;
        array_put(*map.puddle_sizes, target_puddle, array_get(*map.puddle_sizes, target_puddle) + 1);
        visit_tile_neighbors_recursively(map, target_tile, target_puddle);
    }

    visit_tile_neighbors_recursively :: (map: *Lightmap, my_tile: v2i, my_puddle: Puddle) {
        if my_tile.x > 0 then visit_tile_recursively(map, .{ my_tile.x - 1, my_tile.y }, my_puddle);
        if my_tile.x + 1 < map.size.x then visit_tile_recursively(map, .{ my_tile.x + 1, my_tile.y }, my_puddle);
        if my_tile.y > 0 then visit_tile_recursively(map, .{ my_tile.x, my_tile.y - 1 }, my_puddle);
        if my_tile.y + 1 < map.size.y then visit_tile_recursively(map, .{ my_tile.x, my_tile.y + 1 }, my_puddle);
    }

    //
    // A puddle is a set of low-brightness, connected tiles.
    // Therefore, we need to walk through all tiles like a graph, so that each puddle fills out its entire
    // representation.
    //

    array_clear_without_deallocation(*map.puddle_sizes);
    map.puddle_sizes.allocator = tick_allocator;
    for i := 0; i < map.puddles.count; ++i map.puddles[i] = NO_PUDDLE_ID;

    for x := 0; x < map.size.x; ++x {
        for y := 0; y < map.size.y; ++y {
            idx := y * map.size.x + x;
            if map.puddles[idx] != NO_PUDDLE_ID || query_lightmap(map, .{ x, y}) > PUDDLE_THRESHOLD    continue;

            map.puddles[idx] = map.puddle_sizes.count;
            array_add(*map.puddle_sizes, 1);

            visit_tile_neighbors_recursively(map, .{ x, y }, map.puddles[idx]);
        }
    }
}

query_puddle :: (map: *Lightmap, tile: v2i) -> Puddle {
    return map.puddles[tile.y * map.size.x + tile.x];
}

get_random_position_in_puddle :: (map: *Lightmap, puddle: Puddle) -> v2i {
    tile_index_in_puddle := rdtsc() % array_get(*map.puddle_sizes, puddle);

    for x := 0; x < map.size.x; ++x {
        for y := 0; y < map.size.y; ++y {
            if query_puddle(map, .{ x, y }) == puddle {
                if tile_index_in_puddle == 0 then return .{ x, y };
                --tile_index_in_puddle;
            }
        }
    }

    panic("Failed to find a random position in a puddle.");
    return .{ 0, 0 };
}

debug_print_puddles :: (map: *Lightmap) {
    print("------------ PUDDLES ------------\n");

    for y := 0; y < map.size.y; ++y {
        for x := 0; x < map.size.x; ++x {
            puddle := query_puddle(map, .{ x, y });
            if puddle == NO_PUDDLE_ID {
                print(" ");
            } else {
                print("%", cast(u64) puddle);
            }
        }

        print("\n");
    }
    print("------------ PUDDLES ------------\n");
}



#file_scope

LIGHTMAP_FADE_PER_SECOND: f32 : 0.25;
LIGHTMAP_NEIGHBOR_EFFECT: f32 : 1;
LIGHTMAP_AMBIENCE: f32 : 0.02;

query_previous_map :: (map: *Lightmap, tile: v2i) -> f32 {
    if tile.x < 0 || tile.x >= map.size.x || tile.y < 0 || tile.y >= map.size.y return 0;
    return map.intermediate[tile.y * map.size.x + tile.x];
}

calculate_neighbor_effect :: (map: *Lightmap, neighbor: v2i, previous: f32, dt: f32) -> f32 {
    if neighbor.x < 0 || neighbor.x >= map.size.x || neighbor.y < 0 || neighbor.y >= map.size.y return 0;

    if map.blockers[neighbor.y * map.size.x + neighbor.x] > 0 {
        return 0;
    }

    neighbor_value := query_previous_map(map, neighbor);
    return max((neighbor_value - previous) * LIGHTMAP_NEIGHBOR_EFFECT * dt, 0);
}

fill_lightmap_tile :: (map: *Lightmap, tile: v2i, brightness: f32) {
    assert(tile.x >= 0 && tile.x < map.size.x && tile.y >= 0 && tile.y < map.size.y, "Tried to fill the lightmap out of bounds.");

    index := tile.y * map.size.x + tile.x;
    additive := max(brightness - map.tiles[index], 0);
    map.tiles[index] = clamp(map.tiles[index] + additive, 0, 1);
}

fill_lightmap_with_beam :: (map: *Lightmap, beam: *Beam_Data, brightness: f32) {
    for i := 0; i < beam.fields.count; ++i {
        fill_lightmap_tile(map, array_get(*beam.fields, i).position, brightness);
    }
}
