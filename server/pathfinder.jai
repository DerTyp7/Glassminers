Pathfinding_Flags :: enum bitfield {
    Avoid_Collisions;
    Restrict_To_Puddles;
}

find_path :: (server: *Server, flags: Pathfinding_Flags, beam_tile_cost: s32, from, to: v2i) -> []v2i {
    grid: Grid = ---;

    //
    // Build the path grid.
    // We go through all entities in the world and update the grid for them.
    // For example, we block all nodes in the grid on which a move-blocking entity stands, and we set the
    // right cost for all tiles that are under a beam...
    //
    {
        grid.size  = server.world_size;
        grid.nodes = allocate_array(*temp, Node, grid.size.x * grid.size.y);
        for i := 0; i < grid.nodes.count; ++i grid.nodes[i] = .{};

        if flags & .Avoid_Collisions {
            for i := 0; i < server.all_entities.slot_count; ++i {
                entity, occupied := index_bucket_array(*server.all_entities, i);
                if !occupied continue;

                if entity.entity_kind == .Emitter {
                    emitter := down(entity, Emitter);

                    for i := 0; i < emitter.beam_data.fields.count; ++i {
                        node := grid.get(*grid, array_get(*emitter.beam_data.fields, i).position);
                        node.cost = beam_tile_cost;
                    }
                }

                if entity.entity_flags & .Blocks_Movement {
                    node := grid.get(*grid, entity.physical_position);
                    node.state = .Blocked;
                }
            }
        }

        if flags & .Restrict_To_Puddles {
            for x := 0; x < grid.size.x; ++x {
                for y := 0; y < grid.size.y; ++y {
                    if query_puddle(*server.lightmap, .{ x, y }) == NO_PUDDLE_ID {
                        node := grid.get(*grid, .{ x, y });
                        node.state = .Blocked;
                    }
                }
            }
        }
    }
    
    //
    // Do the actual path finding
    //
    return dijkstra(*grid, from, to);
}

find_next_step_on_path :: (server: *Server, flags: Pathfinding_Flags, beam_tile_cost: s32, from, to: v2i) -> v2i, bool {
    path := find_path(server, flags, beam_tile_cost, from, to);
    if path.count < 2 {
        return from, false; // Failed to find a valid path
    }
    return path[1], true; // The first index in this array is the *from* position
}



#file_scope

Node :: struct {
    state: enum { Blocked; Available; Visited; } = .Available;
    cost:      s32  = 1;
    sum_cost:  s32 = MAX_S32;
    previous: *Node = null;
}

Grid :: struct {
    nodes: []Node;
    size: v2i;

    get :: (#using self: *Grid, field: v2i) -> *Node {
        assert(field.x >= 0 && field.x < size.x && field.y >= 0 && field.y < size.y, "Tried to access a node out-of-bounds of the grid.");
        return *nodes[index_from_position(self, field)];
    }
    
    index_from_position :: (#using self: *Grid, position: v2i) -> s64 {
        return position.y * size.x + position.x;
    }

    position_from_index :: (#using self: *Grid, index: s64) -> v2i {
        return .{ index % size.x, index / size.x };
    }

    position_from_node :: (#using self: *Grid, node: *Node) -> v2i {
        index: s64 = cast(s64) ((node - nodes.data) / size_of(Node));
        return position_from_index(self, index);
    }
}

find_next_node :: (grid: *Grid) -> *Node, v2i {
    // @Speed: Maybe this would be faster if we used a separate queue... Who knows.
    least_sum_cost: s32 = MAX_S32;
    next_node: *Node = null;
    next_position: v2i = ---;

    for i := 0; i < grid.nodes.count; ++i {
        node := *grid.nodes[i];
        if node.state == .Available && node.sum_cost < least_sum_cost {
            least_sum_cost = node.sum_cost;
            next_node = node;
            next_position = grid.position_from_index(grid, i);
        }
    }
    
    return next_node, next_position;
}

maybe_register_path :: (grid: *Grid, from: *Node, to_position: v2i) {
    if to_position.x < 0 || to_position.x >= grid.size.x || to_position.y < 0 || to_position.y >= grid.size.y return;

    to := grid.get(grid, to_position);
    
    if to.state == .Blocked return;

    sum_cost := from.sum_cost + to.cost;
    if sum_cost < to.sum_cost {
        to.sum_cost = sum_cost;
        to.previous = from;
    }
}

dijkstra :: (grid: *Grid, from, to: v2i) -> []v2i {
    //
    // Populate the grid by linking together the shortest path
    //
    {
        grid.get(grid, from).sum_cost = 0;
        grid.get(grid, from).state    = .Available;
        
        while true {
            node, position := find_next_node(grid);
            if !node break;
                        
            node.state = .Visited;

            maybe_register_path(grid, node, .{ position.x - 1, position.y });
            maybe_register_path(grid, node, .{ position.x + 1, position.y });
            maybe_register_path(grid, node, .{ position.x, position.y - 1 });
            maybe_register_path(grid, node, .{ position.x, position.y + 1 });
        }
    }
    
    //
    // Actually build the path sequence for convenience
    //
    node := grid.get(grid, to);
    
    if node.previous { // This is null if we never reached the goal...
        path_length := 0;

        {
            traveller := node;
            while traveller {
                ++path_length;
                traveller = traveller.previous;
            }
        }
            
        result: []v2i = allocate_array(*temp, v2i, path_length);

        {
            traveller := node;
            while traveller {
                result[--path_length] = grid.position_from_node(grid, traveller);
                traveller = traveller.previous;
            }
        }
            
        return result;
    } else {
        return .[];
    }
}
