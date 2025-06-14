TORCH_BRIGHTNESS: f32 : 0.75;
LAVA_BRIGHTNESS: f32 : 0.5;

DISABLE_LIGHTMAP :: false;

Lightmap :: struct {
    allocator: *Allocator;
    disabled: bool;
    intermediate: []f32;
    tiles: []f32;
    size: v2i;
}

create_lightmap :: (map: *Lightmap, allocator: *Allocator, size: v2i) {
    map.allocator = allocator;
    map.disabled  = false;
    map.size      = size;
    map.tiles     = allocate_array(allocator, f32, map.size.x * map.size.y);
    for i := 0; i < map.tiles.count; ++i map.tiles[i] = 0;
}

destroy_lightmap :: (map: *Lightmap) {
    deallocate_array(map.allocator, *map.tiles);
    map.size = .{ };
}

update_lightmap :: (client: *Client, map: *Lightmap, dt: f32) {
    map.intermediate = copy_array(*temp, map.tiles);
    
    for y := 0; y < map.size.y; ++y {
        for x := 0; x < map.size.x; ++x {
            previous := query_previous_map(map, .{ x, y }) - LIGHTMAP_FADE_PER_SECOND * dt;
            updated := previous;
            updated += calculate_neighbor_effect(client, map, .{ x + 1, y }, previous, dt);
            updated += calculate_neighbor_effect(client, map, .{ x - 1, y }, previous, dt);
            updated += calculate_neighbor_effect(client, map, .{ x, y + 1 }, previous, dt);
            updated += calculate_neighbor_effect(client, map, .{ x, y - 1 }, previous, dt);
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
    if map.disabled return 1;

    assert(tile.x >= 0 && tile.x < map.size.x && tile.y >= 0 && tile.y < map.size.y, "Tried to query the lightmap out of bounds.");

    index := tile.y * map.size.x + tile.x;
    return max(map.tiles[index], LIGHTMAP_AMBIENCE);
}

query_lightmap_at_fractional :: (map: *Lightmap, position: v2f) -> f32 {
    if map.disabled return 1;

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



#file_scope

LIGHTMAP_FADE_PER_SECOND: f32 : 0.25;
LIGHTMAP_NEIGHBOR_EFFECT: f32 : 1;
LIGHTMAP_AMBIENCE: f32 : 0.02;

query_previous_map :: (map: *Lightmap, tile: v2i) -> f32 {
    if tile.x < 0 || tile.x >= map.size.x || tile.y < 0 || tile.y >= map.size.y return 0;
    return map.intermediate[tile.y * map.size.x + tile.x];
}

calculate_neighbor_effect :: (client: *Client, map: *Lightmap, neighbor: v2i, previous: f32, dt: f32) -> f32 {
    // @Speed: This is really, really bad
    // @Speed: This is really, really bad
    // @Speed: This is really, really bad
    // @Speed: This is really, really bad
    if find_entity_with_flags_at_position(client, .Blocks_Los, neighbor) {
        return 0;
    }

    neighbor_value := query_previous_map(map, neighbor);
    return max((neighbor_value - previous) * LIGHTMAP_NEIGHBOR_EFFECT * dt, 0);
}
