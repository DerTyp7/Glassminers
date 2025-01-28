Entity :: struct {
    pid: Pid;
    kind: Entity_Kind;
    marked_for_removal: bool;
    
    physical_position: v2i;
    visual_position: v2f;
}

World :: struct {
    entities: [..]Entity;
    pid_counter: Pid;    
}

create_world :: (world: *World, allocator: *Allocator) {
    world.entities.allocator = allocator;
    world.pid_counter = 0;
}

destroy_world :: (world: *World) {
    array_clear(*world.entities);
}

create_entity_with_pid :: (world: *World, pid: Pid, kind: Entity_Kind, position: v2i) -> *Entity {
    assert(get_entity(world, pid) == null, "An entity with the requested id already exists.");
    entity := array_push(*world.entities);
    entity.pid                = pid;
    entity.kind               = kind;
    entity.marked_for_removal = false;
    entity.physical_position  = position;
    entity.visual_position    = .{ xx position.x, xx position.y };
    return entity;
}

create_entity :: (world: *World, kind: Entity_Kind, position: v2i) -> Pid, *Entity {
    pid := world.pid_counter;
    entity := create_entity_with_pid(world, pid, kind, position);
    ++world.pid_counter;
    return pid, entity;
}

get_entity :: (world: *World, pid: Pid) -> *Entity {
    for i := 0; i < world.entities.count; ++i {
        entity := array_get_pointer(*world.entities, i);
        if entity.pid == pid return entity;
    }
    
    return null;
}

remove_all_marked_entities :: (world: *World) {
    for i := 0; i < world.entities.count; {
        entity := array_get_pointer(*world.entities, i);
        if entity.marked_for_removal {
            array_remove_index(*world.entities, i);
        } else {
            ++i;
        }
    }
}