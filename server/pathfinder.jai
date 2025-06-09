find_path :: (server: *Server, from, to: v2i) -> []v2i {
    grid: Grid = ---;

    //
    // Build the path grid
    //
    {
        grid.size  = server.world_size;
        grid.nodes = allocate_array(*temp, Node, grid.size.x * grid.size.y);
        for i := 0; i < grid.nodes.count; ++i grid.nodes[i] = .{};

        for i := 0; i < server.all_entities.slot_count; ++i {
            entity, occupied := index_bucket_array(*server.all_entities, i);
            if !occupied continue;

            if !(entity.entity_flags & .Blocks_Move) || (entity.physical_position.x == to.x && entity.physical_position.y == to.y) continue;

            node := grid.get(*grid, entity.physical_position);
            node.state = .Blocked;
        }
    }
    
    //
    // Do the actual path finding
    //
    return dijkstra(*grid, from, to);
}

find_next_step_on_path :: (server: *Server, from, to: v2i) -> v2i {
    path := find_path(server, from, to);
    if !path.count return from;
    return path[1]; // The first index in this array is the *from* position
}

#file_scope

Node :: struct {
    state: enum { Blocked; Available; Visited; } = .Available;
    distance:  s32  = MAX_S32;
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
    least_distance: s32 = MAX_S32;
    next_node: *Node = null;
    next_position: v2i = ---;

    for i := 0; i < grid.nodes.count; ++i {
        node := *grid.nodes[i];
        if node.state == .Available && node.distance < least_distance {
            least_distance = node.distance;
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

    distance := from.distance + 1;
    if distance < to.distance {
        to.distance = distance;
        to.previous = from;
    }
}

dijkstra :: (grid: *Grid, from, to: v2i) -> []v2i {
    //
    // Populate the grid by linking together the shortest path
    //
    {
        grid.get(grid, from).distance = 0;
        grid.get(grid, from).state    = .Available;
        
        while true {
            node, position := find_next_node(grid);
            if !node break;

            if position.x == to.x && position.y == to.y break; // Since we have a uniform cost of 1, we can assume that this is the shortest path we will find...
                        
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
        result: []v2i = allocate_array(*temp, v2i, node.distance + 1);

        while node {
            result[node.distance] = grid.position_from_node(grid, node);
            node = node.previous;
        }

        return result;
    } else {
        return .[];
    }
}
