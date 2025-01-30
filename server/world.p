Entity :: struct {
    pid: Pid;
    kind: Entity_Kind;
    marked_for_removal: bool;

    physical_position: v2i;
}

World :: struct {
    entities: [..]Entity;
    pid_counter: Pid;    
}

//
// World
//

create_world :: (world: *World, allocator: *Allocator) {
    world.entities.allocator = allocator;
    world.pid_counter = 0;
}

destroy_world :: (world: *World) {
    array_clear(*world.entities);
}

generate_world :: (world: *World, seed: s64) {
    rand :: () -> s32 #foreign;
    
    random_position :: () -> v2i {
        return .{ rand() % WORLD_WIDTH, rand() % WORLD_HEIGHT };
    }

    srand(seed);
    
    //
    // Generate some stones
    //
    for i := 0; i < 15; ++i {
        create_entity(world, .Stone, random_position());
    }
    
    //
    // Generate some crystals
    //
    for i := 0; i < 15; ++i {
        create_entity(world, .Crystal, random_position());
    }
}



//
// Entity
//

create_entity :: (world: *World, kind: Entity_Kind, position: v2i) -> Pid, *Entity {
    pid := world.pid_counter;

    entity := array_push(*world.entities);
    entity.pid                = pid;
    entity.kind               = kind;
    entity.physical_position  = position;
    entity.marked_for_removal = false;

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
