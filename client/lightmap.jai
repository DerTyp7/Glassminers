TORCH_BRIGHTNESS: f32 : 0.75;
LAVA_BRIGHTNESS: f32 : 0.5;

Lightmap :: struct {
    allocator: *Allocator;
    blockers: []s32;
    tiles: []f32;
    size: v2i;

    intermediate: []f32;

#if DEVELOPER {
    disabled: bool;
}
}

create_lightmap :: (map: *Lightmap, allocator: *Allocator, size: v2i) {
    map.allocator = allocator;
    map.size      = size;
    map.tiles     = allocate_array(map.allocator, f32, map.size.x * map.size.y);
    map.blockers  = allocate_array(map.allocator, s32, map.size.x * map.size.y);
    for i := 0; i < map.tiles.count; ++i map.tiles[i] = 0;
    for i := 0; i < map.blockers.count; ++i map.blockers[i] = 0;

#if DEVELOPER {
    map.disabled  = false;
}
}

destroy_lightmap :: (map: *Lightmap) {
    deallocate_array(map.allocator, *map.tiles);
    map.size = .{ };
}

resize_lightmap :: (map: *Lightmap, new_size: v2i) {
    new_tiles    := allocate_array(map.allocator, f32, new_size.x * new_size.y);
    new_blockers := allocate_array(map.allocator, s32, new_size.x * new_size.y);
    clear_memory(new_tiles.data, new_tiles.count * size_of(f32));
    clear_memory(new_blockers.data, new_blockers.count * size_of(s32));
    
    size_to_copy := v2i.{ min(new_size.x, map.size.x), min(new_size.y, map.size.y) };
    
    for y := 0; y < size_to_copy.y; ++y {
        for x := 0; x < size_to_copy.x; ++x {
            new_tiles[y * new_size.x + x]    = map.tiles[y * map.size.x + x];
            new_blockers[y * new_size.x + x] = map.blockers[y * map.size.x + x];
        }
    }

    deallocate_array(map.allocator, *map.tiles);
    deallocate_array(map.allocator, *map.blockers);

    map.tiles = new_tiles;
    map.blockers = new_blockers;
    map.size = new_size;
}

update_lightmap :: (map: *Lightmap, dt: f32) {
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

query_lightmap :: (map: *Lightmap, tile: v2i) -> f32 {
#if DEVELOPER {
    if map.disabled return 1;
}
    
    assert(tile.x >= 0 && tile.x < map.size.x && tile.y >= 0 && tile.y < map.size.y, "Tried to query the lightmap out of bounds.");

    index := tile.y * map.size.x + tile.x;
    return max(map.tiles[index], LIGHTMAP_AMBIENCE);
}

query_lightmap_at_fractional :: (map: *Lightmap, position: v2f) -> f32 {
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
    return query_lightmap(map, tile);
}

maybe_add_blocker :: (map: *Lightmap, entity: *Entity) {
    if entity.entity_flags & .Blocks_Los {
        ++map.blockers[entity.physical_position.y * map.size.x + entity.physical_position.x];
    }
}

maybe_remove_blocker :: (map: *Lightmap, entity: *Entity) {
    if entity.entity_flags & .Blocks_Los {
        --map.blockers[entity.physical_position.y * map.size.x + entity.physical_position.x];
    }
}

maybe_move_blocker :: (map: *Lightmap, entity: *Entity, new_position: v2i) {
    if entity.entity_flags & .Blocks_Los {
        --map.blockers[entity.physical_position.y * map.size.x + entity.physical_position.x];
        ++map.blockers[new_position.y * map.size.x + new_position.x];
    }
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
