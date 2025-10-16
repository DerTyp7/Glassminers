count_sections_in_predefined_world :: (game_mode: Game_Mode) -> s64 {
    lines, success := load_predefined_world_data(game_mode);
    if !success return 0;
    
    max_section_count: s64 = 0;

    for y := 0; y < lines.count; ++y {
        line := array_get(*lines, y);
        line_section_count := 1;

        for x := 0; x < line.count; ++x {
            if line[x] == DEVELOPER_WORLD_SECTION_SEPARATOR then ++line_section_count;
        }
        
        max_section_count = max(max_section_count, line_section_count);
    }

    return max_section_count;
}

get_initial_world_size :: (server: *Server) -> v2i {
    if use_random_world_generation(server) {
        return .{ SECTION_WIDTH, SECTION_HEIGHT };
    } else {
        return get_current_predefined_world_size(server.game_mode, server.current_section_index);
    }
}

generate_initial_world_section :: (server: *Server) {
    try_to_place_item(server, .{ 1, 2 }, .Flag, null, null);

    if use_random_world_generation(server) {
        emitter_entity := create_entity(server, .Emitter, .{ 0, 2 }, .East);
        emitter := down(emitter_entity, Emitter);
        set_emitter_state(server, emitter, .Active, EMITTER_MAX_CHARGE[server.game_mode]);

        chest_entity := create_entity(server, .Chest, .{ 0, 3 }, .North);
        chest := down(chest_entity, Chest);
        chest.inventory = setup_initial_chest_inventory(server);
        broadcast_chest_inventory(server, chest);

        fill_random_biome(server, .[ 0, server.world_size.x - 1], 0);
    } else {
        fill_predefined_world_section(server, server.game_mode, server.current_section_index);
    }
}

generate_next_world_section :: (server: *Server) {
    if server.game_mode == .Developer && server.current_section_index + 1 >= count_sections_in_predefined_world(server.game_mode) return;

    server.void_eyes_spawn_cooldown = 5;    
    ++server.current_section_index;

    if use_random_world_generation(server) {
        previous_width := server.world_size.x;
        server.world_size.x += SECTION_WIDTH;

        msg := make_message(World_Resize_Message);
        msg.world_resize.new_world_size = server.world_size;
        array_add(*server.outgoing_messages, msg);

        resize_lightmap(*server.lightmap, server.world_size);
        fill_random_biome(server, .[ previous_width, server.world_size.x - 1 ], server.current_section_index);
    } else {
        server.world_size = get_current_predefined_world_size(server.game_mode, server.current_section_index);

        msg := make_message(World_Resize_Message);
        msg.world_resize.new_world_size = server.world_size;
        array_add(*server.outgoing_messages, msg);

        resize_lightmap(*server.lightmap, server.world_size);
        fill_predefined_world_section(server, server.game_mode, server.current_section_index);
    }
}



#file_scope

Biome_Type :: enum {
    Mineshaft; // Default biome
    //Lava_Lake; // @Cleanup
    Goblin_Nest;
}

SPECIAL_BIOME_OCCURANCE :: 1; // @Cleanup

DEVELOPER_WORLD_SECTION_SEPARATOR :: #char "|";
MINESHAFT_SPAWN_PROBABILITY_TABLE :: #run setup_mineshaft_probabilities_table(); // This table contains the chance ([0-1]) that an entity of this category will spawn on one tile.

use_random_world_generation :: (server: *Server) -> bool {
    return !(server.game_mode == .Tutorial || server.game_mode == .Developer);
}



/* --------------------------------------------- Predefined World --------------------------------------------- */

#if BAKE_ASSETS {
    GAME_MODE_WORLD_STRINGS :: [Game_Mode.Count]string.[
        #run bake_raw_file(ASSET_FILE_PATH("run_tree/data/developer-world.txt")),
        #run bake_raw_file(ASSET_FILE_PATH("run_tree/data/tutorial-world.txt")),
        "", // Easy
        "", // Medium
        "" // Hard
    ];
} #else {
    GAME_MODE_WORLD_FILE_PATHS :: [Game_Mode.Count]string.[
        "data/developer-world.txt",
        "data/tutorial-world.txt",
        "", // Easy
        "", // Medium
        "", // Hard
    ];
}

load_predefined_world_data :: (game_mode: Game_Mode) -> [..]string, bool {
#if !BAKE_ASSETS {
    data, success := read_entire_file(*temp, GAME_MODE_WORLD_FILE_PATHS[game_mode]);
    if !success {
        logprint(.Error, "Failed to load the predefined world file '%' from disk.", GAME_MODE_WORLD_FILE_PATHS[game_mode]);
        return ---, false;
    }
} #else {
    data := GAME_MODE_WORLD_STRINGS[game_mode];
}

    lines := string_split(data, #char "\n", false, *temp);

    for i := 0; i < lines.count; {
        line := array_get(*lines, i);
        if line.count && line[0] == #char "#" {
            array_remove_index(*lines, i);
        } else if line.count && line[line.count - 1] == #char "\r" {
            array_put(*lines, i, substring_view(line, 0, line.count - 1));
            ++i;
        } else {
            ++i;
        }
    }
    
    return lines, true;
}

get_current_predefined_world_size :: (game_mode: Game_Mode, current_section_index: s64) -> v2i {
    lines, success := load_predefined_world_data(game_mode);
    if !success return .{};
    
    max_width: s64 = 0;

    for y := 0; y < lines.count; ++y {
        line := array_get(*lines, y);
        line_width: s64 = 0;
        line_section_index := 0;

        for x := 0; x < line.count && line_section_index <= current_section_index; ++x {
            if line[x] == DEVELOPER_WORLD_SECTION_SEPARATOR then ++line_section_index;

            line_width += 1;
        }
        
        max_width = max(max_width, line_width - line_section_index); // The separator characters don't actually represent entities and therefore don't count here
    }

    return .{ max_width, lines.count };
}

fill_predefined_world_section :: (server: *Server, game_mode: Game_Mode, section_index_to_fill: u32) -> bool {
    ENTITY_TO_CHAR: [Entity_Kind.Count]char : .[
        // Beams
        #char "e", // Emitter
        #char "m", // Mirror

        // Environment
        #char "l", // Lava
        #char "b", // Bedrock
        #char "s", // Rock
        #char "c", // Coal
        #char "g", // Crystal
        #char "h", // Slime Hole

        // Creations
        #char " ", // Item Stack
        #char " ", // Slab
        #char " ", // Torch
        #char " ", // Chest

        // Beings
        #char ".", // Guy
        #char "F", // Frog
        #char "G", // Goblin
        #char "S", // Slime
        #char "V", // Void Eye
        #char "T", // Trader

        // Misc
        #char "f", // Flag
    ];

    lines, success := load_predefined_world_data(game_mode);
    if !success return false;

    //
    // Create entities for all characters in the world string
    //
    for y := 0; y < lines.count; ++y {
        line := array_get(*lines, y);
        current_section_index := 0;
        for x := 0; x < line.count && current_section_index <= section_index_to_fill; ++x {
            if line[x] == #char " " continue;
            
            if line[x] == DEVELOPER_WORLD_SECTION_SEPARATOR {
                current_section_index += 1;
                continue;
            }
            if current_section_index < section_index_to_fill continue;

            direction: Direction = ---;
            xPos := x - current_section_index;
            
            kind := Entity_Kind.Count;
            for i := 0; i < ENTITY_TO_CHAR.Capacity; ++i {
                if ENTITY_TO_CHAR[i] == line[x] {
                    kind = i;
                    direction = DEFAULT_ENTITY_ROTATION[kind];
                    break;
                }
            }

            if kind != .Count {
                entity := create_entity(server, kind, .{ xPos, y }, direction);

                if kind == .Emitter {
                    emitter := down(entity, Emitter);

                    if x == 0 set_emitter_state(server, emitter, .Active, EMITTER_MAX_CHARGE[server.game_mode]);

                    if server.latest_emitter == INVALID_PID || get_entity(server, server.latest_emitter).physical_position.x < entity.physical_position.x then server.latest_emitter = emitter.pid;
                } else if kind == .Slime_Hole {
                    slime := create_entity(server, .Slime, .{ xPos, y }, direction);
                }
            } else {
                logprint(.Error, "Failed to parse the world string for '%' in line %: The character '%' is not a known entity.", game_mode, y + 1, line[x]);
                success = false;
            }
        }
    }
    
    return true;
}



/* --------------------------------------------- Probability Table -------------------------------------------- */

setup_mineshaft_probabilities_table :: () -> [Game_Mode.Count][Entity_Kind.Count]f32 {
    desired_per_section :: (x: f32) -> f32 { // On average I expect X entities in one section
        return cast(f32) x / cast(f32) (SECTION_WIDTH * SECTION_HEIGHT);
    }

    desired_coverage :: (p: f32) -> f32 { // On average I expect p % of the tiles to be this entity
        return p;
    }

    modify_default :: (target: Game_Mode, kind: Entity_Kind, modifier: f32) #macro {
        result[target][kind] = result[.Medium][kind] * modifier;
    }

    result: [Game_Mode.Count][Entity_Kind.Count]f32;

    // Set up the default difficulty
    {
        result[.Medium][.Slime_Hole] = desired_per_section(1);
        result[.Medium][.Trader]     = desired_per_section(0.75);
        result[.Medium][.Lava]       = desired_coverage(0.085);
        result[.Medium][.Bedrock]    = desired_coverage(0.17);
        result[.Medium][.Coal]       = desired_per_section(4);
        result[.Medium][.Rock]       = desired_per_section(4);
        result[.Medium][.Crystal]    = desired_per_section(3);
        result[.Medium][.Frog]       = desired_per_section(3);
        result[.Medium][.Goblin]     = desired_per_section(4);
    }

    // Set up the easy difficulty
    {
        modify_default(.Easy, .Slime_Hole, 0.75);
        modify_default(.Easy, .Trader,     1.34);
        modify_default(.Easy, .Lava,        1.0);
        modify_default(.Easy, .Bedrock,     1.0);
        modify_default(.Easy, .Coal,        1.1);
        modify_default(.Easy, .Rock,        1.1);
        modify_default(.Easy, .Crystal,     1.1);
        modify_default(.Easy, .Frog,       0.75);
        modify_default(.Easy, .Goblin,     0.75);
    }    

    // Set up the hard difficulty
    {
        modify_default(.Hard, .Slime_Hole, 1.2);
        modify_default(.Hard, .Trader,     1.1);
        modify_default(.Hard, .Lava,       1.2);
        modify_default(.Hard, .Bedrock,    1.0);
        modify_default(.Hard, .Coal,       0.75);
        modify_default(.Hard, .Rock,       0.75);
        modify_default(.Hard, .Crystal,    0.75);
        modify_default(.Hard, .Frog,       1.2);
        modify_default(.Hard, .Goblin,     1.2);
    }

    return result;
}



/* ------------------------------------------ Random World Generation ----------------------------------------- */

Biome_Helper :: struct {
    section: [2]s32;
    previous_emitter: *Entity;
}

create_latest_emitter :: (server: *Server, helper: *Biome_Helper) {
    latest_emitter := create_entity(server, .Emitter, .{ helper.section[1], random_u64_in(*server.world_random, 0, SECTION_HEIGHT) }, .East);
    server.latest_emitter = latest_emitter.pid;
}

make_biome_helper :: (server: *Server, section: [2]s32) -> Biome_Helper {
    helper: Biome_Helper = ---;
    helper.section = section;
    helper.previous_emitter = ifx server.latest_emitter != INVALID_PID then get_entity(server, server.latest_emitter) else null;
    return helper;
}

is_reserved_position :: (server: *Server, position: v2i, helper: *Biome_Helper) -> bool {
    // We want to free up space around the spawn positions of the player (so that players don't spawn on
    // top of monsters, etc) and the emitters.
    if (position.y >= 1 && position.y <= 3 && position.x >= 0 && position.x <= 2 + server.clients.count + 1)
        return true;
    
    if helper.previous_emitter {
        distance_to_emitter := abs(position.x - helper.previous_emitter.physical_position.x) + abs(position.y - helper.previous_emitter.physical_position.y);

        // We want to make sure the players can actually reach the emitter, e.g. to recharge it
        // and to use the lightbeam to kill monsters. Otherwise, this could be pretty annoying.
        // 
        //  B   | '<' represents the emitter
        // <BB  | 'B' represents a reserved position
        //  B   |

        if distance_to_emitter <= 2 return true;
    }
    
    return false;
}

random_position :: (server: *Server, helper: *Biome_Helper, retry_on_reserved: bool) -> v2i, bool {
    position := v2i.{ random_u64_in(*server.world_random, helper.section[0], helper.section[1] + 1),
                        random_u64_in(*server.world_random, 0, SECTION_HEIGHT) };

    success := true;
    
    iteration := 0;
    while find_any_entity_at_position(server, position) || (retry_on_reserved && is_reserved_position(server, position, helper)) {
        position = v2i.{ random_u64_in(*server.world_random, helper.section[0], helper.section[1] + 1),
                            random_u64_in(*server.world_random, 0, SECTION_HEIGHT) };

        if iteration > 10 {
            logprint(.Warning, "Failed to find a suitable spawn position while generating the world...");
            success = false;
            break;
        }

        ++iteration;
    }

    if !retry_on_reserved {
        success = success && !is_reserved_position(server, position, helper);
    }

    return position, success;
}

//
// When filling the world randomly, we want to block certain tiles to ensure they remain empty. Otherwise,
// the game can be really annoying to play.
// At the same time, we want to ensure that we generate enough resources on the available space of the
// section, while not overcrowding the section with other entity kinds (such as bedrock or monsters).
// In short, the retry_on_reserved flag tries to ensure that we actually generate 'count' entities of
// that kind. If it is false, we accept generating fewer entities to ensure we're not overloading the
// section (since the SPAWN_PROBABILITIY_TABLE assumes the entire section space as available, but that's
// not actually true).
//
generate_n_random_entities :: (server: *Server, helper: *Biome_Helper, kind: Entity_Kind, count: s64, retry_on_reserved: bool) -> [..]*Entity {
    result: [..]*Entity;
    result.allocator = *temp;

    for i := 0; i < count; ++i {
        position, success := random_position(server, helper, retry_on_reserved);
        if success {
            entity := create_entity(server, kind, position, DEFAULT_ENTITY_ROTATION[kind]);
            array_add(*result, entity);
        }
    }

    return result;
}

fill_mineshaft_biome :: (server: *Server, helper: *Biome_Helper) {
    generate_random_count :: (server: *Server, helper: *Biome_Helper, kind: Entity_Kind, modifier: f32) -> s32 {
        t := MINESHAFT_SPAWN_PROBABILITY_TABLE[server.game_mode][kind] * modifier;
        area := (helper.section[1] - helper.section[0] + 1) * SECTION_HEIGHT;
        mean := t * cast(f32) area;
        stddev: f32 : 0.25;
        return cast(s32) round(random_f32_normal_distribution(*server.world_random, mean, stddev * mean));
    }

    generate_randomly :: (server: *Server, helper: *Biome_Helper, kind: Entity_Kind, modifier: f32, retry_on_reserved: bool) -> [..]*Entity {
        count := generate_random_count(server, helper, kind, modifier);
        return generate_n_random_entities(server, helper, kind, count, retry_on_reserved);
    }

    // Generate a new emitter at the end of this section
    create_latest_emitter(server, helper);

    // Generate all kinds of entities randomly    
    x: f32 = xx (server.current_section_index + 1);
    friendly_modifier:   f32 = 1 / powf(x, 0.5); // The longer a game goes, the less friendly things we want to happen...
    neutral_modifier:    f32 = 1.0; // These things shouldn't really change with the duration of the game...
    unfriendly_modifier: f32 = -1 / powf(x, 0.5) + 2; // The longer a game goes, the more unfriendly things we want to happen

    generate_randomly(server, helper, .Lava,    neutral_modifier,    false);
    generate_randomly(server, helper, .Bedrock, neutral_modifier,    false);
    generate_randomly(server, helper, .Rock,    friendly_modifier,   false);
    generate_randomly(server, helper, .Crystal, friendly_modifier,   true);
    generate_randomly(server, helper, .Coal,    neutral_modifier,    true);
    generate_randomly(server, helper, .Frog,    unfriendly_modifier, false);
    generate_randomly(server, helper, .Goblin,  unfriendly_modifier, false);
    generate_randomly(server, helper, .Trader,  neutral_modifier,    true);
    holes := generate_randomly(server, helper, .Slime_Hole, neutral_modifier, false);
    
    for i := 0; i < holes.count; ++i {
        hole := array_get(*holes, i);
        create_entity(server, .Slime, hole.physical_position, DEFAULT_ENTITY_ROTATION[.Slime]);
    }
}

fill_lava_lake_biome :: (server: *Server, helper: *Biome_Helper) {
    LEFT_OFFSET:  s32 : 3;
    RIGHT_OFFSET: s32 : 1;

    create_latest_emitter(server, helper);

    // Calculate the area of the lake
    first_lake_x    := helper.section[0] + LEFT_OFFSET;
    lake_half_width := ((helper.section[1] - helper.section[0]) - (RIGHT_OFFSET + LEFT_OFFSET)) / 2;

    // Generate some rocks on the left
    {
        rock_count := random_u64_in(*server.world_random, 3, 5);
        generate_n_random_entities(server, helper, .Rock, rock_count, true);
        crystal_count := random_u64_in(*server.world_random, 1, 2);
        generate_n_random_entities(server, helper, .Crystal, crystal_count, true);
    }

    // Generate the actual lava lake including islands
    for x := helper.section[0] + LEFT_OFFSET; x < helper.section[1] - RIGHT_OFFSET; ++x {
        // Set up the spawn weights. These weights indicate the chances of different entities
        // spawning at this position.
        // We want to generate a little bridge in the middle of the lava lake to make it a
        // little easier to survive...
        lava_weight: s64 = min(abs((x - first_lake_x - lake_half_width)) * 50, 100);

        spawn_weights: []struct { weight: s64; kind: Entity_Kind; } = .[
            .{ lava_weight, .Lava },
            .{  48, .Count },
            .{   8, .Rock },
            .{   7, .Frog },
            .{   2, .Crystal },
        ];
        
        total_weight := 0;
        for i := 0; i < spawn_weights.count; ++i total_weight += spawn_weights[i].weight;

        // Spawn random entities in this column based on the weight table
        for y := 0; y < SECTION_HEIGHT; ++y {
            target_weight := random_u64_in(*server.world_random, 0, total_weight);
            entity_kind: Entity_Kind = ---;

            for i := 0; i < spawn_weights.count; ++i {
                if target_weight < spawn_weights[i].weight {
                    entity_kind = spawn_weights[i].kind;
                    break;
                } else {
                    target_weight -= spawn_weights[i].weight;
                }
            }

            if entity_kind != .Count then create_entity(server, entity_kind, .{ x, y }, DEFAULT_ENTITY_ROTATION[entity_kind]);
        }
    }
}

fill_goblin_nest_biome :: (server: *Server, helper: *Biome_Helper) {
    Tilemap :: []Entity_Kind;

    put :: (tilemap: Tilemap, tile: v2i, entity: Entity_Kind) {
        tilemap[tile.x * SECTION_HEIGHT + tile.y] = entity;
    }

    get :: (tilemap: Tilemap, tile: v2i) -> Entity_Kind {
        return tilemap[tile.x * SECTION_HEIGHT + tile.y];
    }

    generate_path_recursively :: (server: *Server, tilemap: Tilemap, head: v2i) -> bool {
        check_tile_neighbor :: (tilemap: Tilemap, neighbor: v2i) -> bool {
            if neighbor.x < 0 then return false;
            if neighbor.x >= tilemap.count / SECTION_HEIGHT then return true;
            if neighbor.y < 0 || neighbor.y >= SECTION_HEIGHT then return true;
            return get(tilemap, neighbor) == .Bedrock;
        }

        is_tile_available :: (tilemap: Tilemap, target: v2i) -> bool {
            return (target.x >= 0 && target.x < tilemap.count &&
                    target.y >= 0 && target.y < SECTION_HEIGHT) &&
                    check_tile_neighbor(tilemap, .{ target.x + 1, target.y }) &&
                    check_tile_neighbor(tilemap, .{ target.x - 1, target.y }) && 
                    check_tile_neighbor(tilemap, .{ target.x, target.y + 1 }) && 
                    check_tile_neighbor(tilemap, .{ target.x, target.y - 1 });
        }

        if head.x + 1 == tilemap.count / SECTION_HEIGHT {
            put(tilemap, head, .Count);
            return true;
        }    

        neighbor_tiles: [4]v2i = .[ .{ head.x - 1, head.y }, .{ head.x + 1, head.y }, 
                                    .{ head.x, head.y - 1 }, .{ head.x, head.y + 1 } ];
        
        neighbor_possible: [4]bool = ---;
        for i := 0; i < neighbor_possible.Capacity; ++i {
            neighbor_possible[i] = is_tile_available(tilemap, neighbor_tiles[i]);
        }

        put(tilemap, head, .Count);

        start_idx := random_u64_in(*server.world_random, 0, neighbor_tiles.Capacity);
        success := false;

        for i := 0; i < 4; ++i {
            neighbor_idx := (i + start_idx) % neighbor_tiles.Capacity;
            if neighbor_possible[neighbor_idx] && generate_path_recursively(server, tilemap, neighbor_tiles[neighbor_idx]) {
                success = true;
                break;
            }
        }

        if !success {
            put(tilemap, head, .Bedrock);
        }

        return success;
    }

    // Set up the tilemap representing the maze
    LEFT_OFFSET: s32 : 2;
    RIGHT_OFFSET: s32 : 2;
    maze_width := (helper.section[1] - helper.section[0] + 1) - LEFT_OFFSET - RIGHT_OFFSET;

    tilemap := allocate_slice(*temp, Entity_Kind, maze_width * SECTION_HEIGHT);
    for i := 0; i < tilemap.count; ++i tilemap[i] = .Bedrock;

    // Set up paths through the maze
    success := generate_path_recursively(server, tilemap, .{ 0, random_u64_in(*server.world_random, 0, SECTION_HEIGHT) });

    // Actually create the entities from the tilemap
    create_latest_emitter(server, helper);

    maze_x0 := helper.section[0] + LEFT_OFFSET;

    for x := 0; x < maze_width; ++x {
        for y := 0; y < SECTION_HEIGHT; ++y {
            entity := get(tilemap, .{ x, y });
            if entity != .Count then create_entity(server, entity, .{ maze_x0 + x, y }, DEFAULT_ENTITY_ROTATION[entity]);
        }
    }
}

fill_random_biome :: (server: *Server, section: [2]s32, section_index: s32) {
    special_biome := (section_index + 1) % SPECIAL_BIOME_OCCURANCE == 0;
    biome_type: Biome_Type = ifx special_biome then cast(Biome_Type) random_u64_in(*server.world_random, 1, Biome_Type.Count) else .Mineshaft;

    helper := make_biome_helper(server, section);

    if #complete biome_type == {
      case .Mineshaft;   fill_mineshaft_biome(server, *helper);
      //case .Lava_Lake;   fill_lava_lake_biome(server, *helper); // @Cleanup
      case .Goblin_Nest; fill_goblin_nest_biome(server, *helper);
    }
}
