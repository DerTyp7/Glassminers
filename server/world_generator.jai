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

generate_initial_world_section :: (server: *Server) {
    if is_predefined_world(server) {
        server.world_size = get_current_predefined_world_size(server.game_mode, server.current_section_index);
    } else {
        server.world_size = .{ SECTION_WIDTH, SECTION_HEIGHT };
    }

    server.current_section = .[ 0, server.world_size.x - 1];

    create_lightmap(*server.lightmap, *server.world_allocator, server.world_size);
    initiate_next_biome(server);

    if !is_predefined_world(server) {
        emitter_entity := create_entity(server, .Emitter, .{ 0, 2 }, .East);
        emitter := down(emitter_entity, Emitter);
        set_emitter_state(server, emitter, .Active, EMITTER_MAX_BASE_CHARGE[server.game_mode]);
        server.latest_emitter = emitter.pid;

        chest_entity := create_entity(server, .Chest, .{ 0, 3 }, .North);
        setup_initial_chest(server, down(chest_entity, Chest));

        create_entity(server, .Trader, .{ 0, 1 }, .North);
    }

    try_to_place_item(server, .{ 1, 2 }, .Flag, null, null);
    fill_current_biome(server);
}

generate_next_world_section :: (server: *Server) {
    ++server.current_section_index;
    server.void_eyes_spawn_cooldown = 5;    

    previous_width := server.world_size.x;

    if is_predefined_world(server) {
        server.world_size = get_current_predefined_world_size(server.game_mode, server.current_section_index);
    } else {
        server.world_size.x += SECTION_WIDTH;
    }

    server.current_section = .[ previous_width, server.world_size.x - 1 ];

    resize_lightmap(*server.lightmap, server.world_size);
    initiate_next_biome(server);
    fill_current_biome(server);
}



#file_scope

SPECIAL_BIOME_OCCURANCE :: 4;

DEVELOPER_WORLD_SECTION_SEPARATOR :: #char "|";
DEFAULT_SPAWN_PROBABILITY_TABLE :: #run setup_default_spawn_probabilities_table(); // This table contains the chance ([0-1]) that an entity of this category will spawn on one tile.

is_predefined_world :: (server: *Server) -> bool {
    return server.game_mode == .Tutorial || server.game_mode == .Developer;
}

initiate_next_biome :: (server: *Server) {
    section_number := server.current_section_index + 1;

    if is_predefined_world(server) {
        server.current_biome = .Predefined;
    } else if section_number % SPECIAL_BIOME_OCCURANCE == 0 {
        server.current_biome = (server.game_seed +% section_number / SPECIAL_BIOME_OCCURANCE) % (LAST_SPECIAL_BIOME - FIRST_SPECIAL_BIOME + 1) + FIRST_SPECIAL_BIOME;
    } else {
        server.current_biome = .Mineshaft;
    }

    msg := make_message(World_Resize_Message);
    msg.world_resize.new_world_size  = server.world_size;
    msg.world_resize.current_biome   = server.current_biome;
    msg.world_resize.current_section = server.current_section;
    array_add(*server.outgoing_messages, msg);
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

create_entity_from_character :: (server: *Server, position: v2i, character: char) -> bool {
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
           
    kind := Entity_Kind.Count;
    for i := 0; i < ENTITY_TO_CHAR.Capacity; ++i {
        if ENTITY_TO_CHAR[i] == character {
            kind = i;
            break;
        }
    }

    found_entity := true;

    if kind == {
      case .Emitter;
        entity := create_entity(server, kind, position, DEFAULT_ENTITY_ROTATION[kind]);
        if server.latest_emitter == INVALID_PID then set_emitter_state(server, down(entity, Emitter), .Active, EMITTER_MAX_BASE_CHARGE[server.game_mode]);

        if server.latest_emitter == INVALID_PID || get_entity(server, server.latest_emitter).physical_position.x < entity.physical_position.x {
            server.latest_emitter = entity.pid;
        }

      case .Slime_Hole;
        create_entity(server, kind, position, DEFAULT_ENTITY_ROTATION[kind]);
        create_entity(server, .Slime, position, DEFAULT_ENTITY_ROTATION[kind]);

      case;
        create_entity(server, kind, position, DEFAULT_ENTITY_ROTATION[kind]);

      case .Count;
        found_entity = false;
    }

    return found_entity;
}

fill_predefined_section :: (server: *Server, helper: *Biome_Helper) -> bool {
    lines, success := load_predefined_world_data(server.game_mode);
    if !success return false;

    //
    // Create entities for all characters in the world string
    //
    for y := 0; y < lines.count; ++y {
        line := array_get(*lines, y);
        x := 0;

        for char_idx := 0; char_idx < line.count; ++char_idx {
            char := line[char_idx];

            if char == DEVELOPER_WORLD_SECTION_SEPARATOR continue;

            if char == #char " " || x < helper.section[0] || x > helper.section[1] {
                ++x;
                continue;
            }

            found_entity := create_entity_from_character(server, .{ x, y }, char);
            if !found_entity logprint(.Error, "Failed to parse the world string for '%' in line %: The character '%' is not a known entity.", server.game_mode, y + 1, line[x]);

            ++x;
        }
    }
    
    return true;
}



/* --------------------------------------------- Probability Table -------------------------------------------- */

setup_default_spawn_probabilities_table :: () -> [Game_Mode.Count][Entity_Kind.Count]f32 {
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
        result[.Medium][.Slime_Hole] = desired_per_section(1.35);
        result[.Medium][.Trader]     = desired_per_section(0.6);
        result[.Medium][.Lava]       = desired_coverage(0.085);
        result[.Medium][.Bedrock]    = desired_coverage(0.17);
        result[.Medium][.Coal]       = desired_per_section(3.5);
        result[.Medium][.Rock]       = desired_per_section(4);
        result[.Medium][.Crystal]    = desired_per_section(2.9);
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
    server.latest_emitter = create_entity(server, .Emitter, .{ helper.section[1], random_u64_in(*server.world_random, 0, SECTION_HEIGHT) }, .East).pid;
}

make_biome_helper :: (server: *Server) -> Biome_Helper {
    helper: Biome_Helper = ---;
    helper.section = server.current_section;
    helper.previous_emitter = ifx server.latest_emitter != INVALID_PID then get_entity(server, server.latest_emitter) else null;
    return helper;
}

is_reserved_position :: (server: *Server, position: v2i, kind: Entity_Kind, helper: *Biome_Helper) -> bool {
    if position.x < 5 + count_total_players(server) && (kind == .Frog || kind == .Goblin || kind == .Slime_Hole) {
        return true; // Don't spawn monsters around the spawn positions of the players
    }

    if (position.y >= 1 && position.y <= 3 && position.x >= 0 && position.x <= 2 + server.clients.count + 1) {
        return true; // Don't spawn anything closely around the spawn positions of the players
    }
    
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

random_position :: (server: *Server, kind: Entity_Kind, helper: *Biome_Helper, retry_on_reserved: bool) -> v2i, bool {
    position := v2i.{ random_u64_in(*server.world_random, helper.section[0], helper.section[1] + 1),
                        random_u64_in(*server.world_random, 0, SECTION_HEIGHT) };

    success := true;
    
    iteration := 0;
    while find_any_entity_at_position(server, position) || (retry_on_reserved && is_reserved_position(server, position, kind, helper)) {
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
        success = success && !is_reserved_position(server, position, kind, helper);
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
        position, success := random_position(server, kind, helper, retry_on_reserved);
        if success {
            entity := create_entity(server, kind, position, DEFAULT_ENTITY_ROTATION[kind]);
            array_add(*result, entity);
        }
    }

    return result;
}

fill_mineshaft_biome :: (server: *Server, helper: *Biome_Helper) {
    generate_random_count :: (server: *Server, helper: *Biome_Helper, kind: Entity_Kind, modifier: f32) -> s32 {
        t := DEFAULT_SPAWN_PROBABILITY_TABLE[server.game_mode][kind] * modifier;
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

    // Generate some resources
    {
        left_helper: Biome_Helper = ~helper;
        left_helper.section[1] = left_helper.section[0] + LEFT_OFFSET - 2;
        generate_n_random_entities(server, *left_helper, .Rock, random_u64_in(*server.world_random, 3, 5), true);
        generate_n_random_entities(server, *left_helper, .Crystal, random_u64_in(*server.world_random, 1, 2), true);
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

fill_lava_fortress_biome :: (server: *Server, helper: *Biome_Helper) {
    fill_from_string :: (server: *Server, helper: *Biome_Helper, tilemap: string, offset_in_section: s32) {
        x, y: s32 = 0, 0;
        for i := 0; i < tilemap.count; ++i {
            if tilemap[i] == #char "\r" {
            } else if tilemap[i] == #char "\n" {
                x = 0;
                ++y;
            } else if tilemap[i] != #char " " {
                create_entity_from_character(server, .{ helper.section[0] + offset_in_section + x, y }, tilemap[i]);
                ++x;
            } else {
                ++x;
            }
        }
    }

    FIRST_PART: [3]string : .[
        "c lbF\n"
        "  lbb\n"
        "  lb \n"
        "  l b\n"
        "s lb \n",

        "  lsl\n"
        "  lbl\n"
        "  lbF\n"
        "g lbb\n"
        "c bbl\n",

        "g lbF\n"
        "s  bl\n"
        "  lbl\n"
        "   bb\n"
        "  lbl\n",
    ];

    SECOND_PART: [3]string : .[
        " l l \n"
        " bGb \n"
        "blslb\n"
        " bFb \n"
        " l l \n",

        "blllb\n"
        "b b b\n"
        "bbFbb\n"
        "llbll\n"
        "bbGbb\n",

        " blbF\n"
        "bGl b\n"
        " blb \n"
        "bGl b\n"
        " blbF\n",
    ];

    THIRD_PART: [3]string : .[
        "lbs  e\n"
        "lbG   \n"
        "lbbbbl\n"
        "      \n"
        " llbbF\n",

        "bbl  F\n"
        " bbl  \n"
        " gbb e\n"
        " bbl  \n"
        "bbl  F\n",

        "  blG\n"
        " Gbl \n"
        "bsb  \n"
        "bF  e\n"
        "sllbb\n",
    ];

    first_idx := random_u64_in(*server.world_random, 0, FIRST_PART.Capacity);
    fill_from_string(server, helper, FIRST_PART[first_idx], 0);

    second_idx := random_u64_in(*server.world_random, 0, SECOND_PART.Capacity);
    fill_from_string(server, helper, SECOND_PART[second_idx], 6);
    
    third_idx := random_u64_in(*server.world_random, 0, THIRD_PART.Capacity);
    fill_from_string(server, helper, THIRD_PART[third_idx], 12);
}

fill_goblin_nest_biome :: (server: *Server, helper: *Biome_Helper) {
    Tilemap :: []Entity_Kind;
    Path :: [..]v2i;

    Path_Kind :: enum {
        Main_Path;
        Sub_Path;
    }

    put :: (tilemap: Tilemap, tile: v2i, entity: Entity_Kind) {
        tilemap[tile.x * SECTION_HEIGHT + tile.y] = entity;
    }

    get :: (tilemap: Tilemap, tile: v2i) -> Entity_Kind {
        return tilemap[tile.x * SECTION_HEIGHT + tile.y];
    }

    generate_path_recursively :: (server: *Server, tilemap: Tilemap, path: *Path, head: v2i, kind: Path_Kind) -> bool {
        check_tile_neighbor :: (tilemap: Tilemap, path: *Path, neighbor: v2i, head: v2i, kind: Path_Kind) -> bool {
            if neighbor.x < 0 then return false;
            if neighbor.x >= tilemap.count / SECTION_HEIGHT then return true;
            if neighbor.y < 0 || neighbor.y >= SECTION_HEIGHT then return true;
            if neighbor.x == head.x && neighbor.y == head.y then return true;

            valid: bool = ---;

            if #complete kind == {
              case .Main_Path;
                valid = get(tilemap, neighbor) == .Bedrock;
              case .Sub_Path;
                valid = path.count > 3 || get(tilemap, neighbor) == .Bedrock;
                for i := 0; i < path.count; ++i {
                    if array_get(path, i).x == neighbor.x && array_get(path, i).y == neighbor.y {
                        valid = false;
                        break;
                    }
                }   
            }

            return valid;
        }

        is_tile_available :: (tilemap: Tilemap, path: *Path, target: v2i, head: v2i, kind: Path_Kind) -> bool {
            return (target.x >= 0 && target.x < tilemap.count &&
                    target.y >= 0 && target.y < SECTION_HEIGHT) &&
                    check_tile_neighbor(tilemap, path, .{ target.x + 1, target.y }, head, kind) &&
                    check_tile_neighbor(tilemap, path, .{ target.x - 1, target.y }, head, kind) && 
                    check_tile_neighbor(tilemap, path, .{ target.x, target.y + 1 }, head, kind) && 
                    check_tile_neighbor(tilemap, path, .{ target.x, target.y - 1 }, head, kind);
        }

        // Determine if we've already reached the end
        reached_end: bool = head.x + 1 == tilemap.count / SECTION_HEIGHT;
        if kind == .Sub_Path {
            reached_end |= path.count > 5 || (path.count > 2 && get(tilemap, head) == .Count);
        }

        // Add the current tile to the head
        previous_tile := get(tilemap, head);
        previous_path_length := path.count;
        put(tilemap, head, .Count);
        array_add(path, head);

        if !reached_end {
            neighbor_tiles: [4]v2i = .[ .{ head.x - 1, head.y }, .{ head.x + 1, head.y }, 
                                        .{ head.x, head.y - 1 }, .{ head.x, head.y + 1 } ];
            
            neighbor_possible: [4]bool = ---;
            for i := 0; i < neighbor_possible.Capacity; ++i {
                neighbor_possible[i] = is_tile_available(tilemap, path, neighbor_tiles[i], head, kind);
            }

            start_idx := random_u64_in(*server.world_random, 0, neighbor_tiles.Capacity);

            for i := 0; i < 4; ++i {
                neighbor_idx := (i + start_idx) % neighbor_tiles.Capacity;
                if neighbor_possible[neighbor_idx] && generate_path_recursively(server, tilemap, path, neighbor_tiles[neighbor_idx], kind) {
                    reached_end = true;
                    break;
                }
            }
        }

        if !reached_end {
            put(tilemap, head, previous_tile);
            array_remove_range(path, previous_path_length, path.count - 1);
        }

        return reached_end;
    }

    generate_path :: (server: *Server, tilemap: Tilemap, head: v2i, kind: Path_Kind) -> Path {
        path: Path;
        path.allocator = *temp;
        generate_path_recursively(server, tilemap, *path, head, kind);

        if path.count {
            field_index := random_u64_in(*server.world_random, 0, path.count);
            direction_offset := random_u64_in(*server.world_random, 0, 5);
            placed_goblin := false;

            for j := 0; !placed_goblin && j < 5; ++j {
                field := array_get(*path, field_index);
                direction_index := (j + direction_offset) % 5;
                
                if direction_index == {
                    case 4; 
                    put(tilemap, field, .Goblin);
                    placed_goblin = true;
                    case;
                    offset_vector := vector_from_direction(direction_index);
                    target_position := v2i.{ field.x + offset_vector.x, field.y + offset_vector.y };
                    if target_position.x >= 0 && target_position.x < tilemap.count / SECTION_HEIGHT && target_position.y >= 0 && target_position.y < SECTION_HEIGHT {
                        put(tilemap, target_position, .Goblin);
                        placed_goblin = true;
                    }
                }
            }
        }

        return path;
    }

    LEFT_OFFSET:            s32 : 2;
    RIGHT_OFFSET:           s32 : 2;
    DESIRED_SUBPATH_COUNT:  s32 : 5;
    MAX_SUBPATH_ATTEMPTS:   s32 : 20;
    LEAST_SUBPATH_DISTANCE: s32 : 3;

    // Set up the tilemap representing the maze
    maze_width := (helper.section[1] - helper.section[0] + 1) - LEFT_OFFSET - RIGHT_OFFSET;

    tilemap := allocate_slice(*temp, Entity_Kind, maze_width * SECTION_HEIGHT);
    for i := 0; i < tilemap.count; ++i tilemap[i] = .Bedrock;

    // Set up paths through the maze
    main_path: Path = ---;

    {
        main_path = generate_path(server, tilemap, .{ 0, random_u64_in(*server.world_random, 0, SECTION_HEIGHT) }, .Main_Path);
        if main_path.count == 0 {
            panic("Failed to generate a main path for the next goblin next section.");
        }

        max_subpath_distance := max(main_path.count / DESIRED_SUBPATH_COUNT, LEAST_SUBPATH_DISTANCE + 1);
        subpath_offset   := 0;
        valid_subpaths   := 0;
        subpath_attempts := 0;
        while valid_subpaths < DESIRED_SUBPATH_COUNT  && subpath_attempts < MAX_SUBPATH_ATTEMPTS {
            subpath_offset = (subpath_offset + random_u64_in(*server.world_random, LEAST_SUBPATH_DISTANCE, max_subpath_distance)) % main_path.count;
            valid := generate_path(server, tilemap, array_get(*main_path, subpath_offset), .Sub_Path).count > 0;
            if valid then ++valid_subpaths;
            ++subpath_attempts;
        }

        if valid_subpaths < DESIRED_SUBPATH_COUNT {
            logprint(.Warning, "Only managed to generate % of % desired subpaths for the section [%-%].", valid_subpaths, DESIRED_SUBPATH_COUNT, helper.section[0], helper.section[1]);
        }
    }

    // Actually create the entities from the tilemap
    create_latest_emitter(server, helper);
    create_entity(server, .Trader, .{ helper.section[0] + 1, (array_get(*main_path, 0).y + 2) % SECTION_HEIGHT }, DEFAULT_ENTITY_ROTATION[.Trader]);

    maze_x0 := helper.section[0] + LEFT_OFFSET;

    for x := 0; x < maze_width; ++x {
        for y := 0; y < SECTION_HEIGHT; ++y {
            entity := get(tilemap, .{ x, y });
            if entity != .Count then create_entity(server, entity, .{ maze_x0 + x, y }, DEFAULT_ENTITY_ROTATION[entity]);
        }
    }
}

fill_current_biome :: (server: *Server) {
    helper := make_biome_helper(server);

    if #complete server.current_biome == {
      case .Predefined;    fill_predefined_section(server, *helper);
      case .Mineshaft;     fill_mineshaft_biome(server, *helper);
      case .Lava_Lake;     fill_lava_lake_biome(server, *helper);
      case .Lava_Fortress; fill_lava_fortress_biome(server, *helper);
      case .Goblin_Nest;   fill_goblin_nest_biome(server, *helper);
    }
}
