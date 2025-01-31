Entity :: struct {
    pid: Pid;
    kind: Entity_Kind;
    marked_for_removal: bool;
    moved_this_frame: bool;

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
    entity.moved_this_frame   = false;

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


//
// Movement Code
//

get_entity_at_position :: (world: *World, position: v2i) -> *Entity {
    for i := 0; i < world.entities.count; ++i {
        entity := array_get_pointer(*world.entities, i);
        if entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
}

can_move_to_position :: (world: *World, entity: *Entity, position: v2i) -> bool {
    move_delta := v2i.{ position.x - entity.physical_position.x, position.y - entity.physical_position.y };
    return recursive_move_check(world, entity, move_delta);
}

move_to_position :: (world: *World, entity: *Entity, position: v2i) {
    move_delta := v2i.{ position.x - entity.physical_position.x, position.y - entity.physical_position.y };
    recursive_move(world, entity, move_delta);
}



#file_scope

recursive_move_check :: (world: *World, entity: *Entity, move_delta: v2i) -> bool {
    position := v2i.{ entity.physical_position.x + move_delta.x, entity.physical_position.y + move_delta.y };

    // Make sure the position is in bounds of the world
    if position.x < 0 || position.y < 0 || position.x >= WORLD_WIDTH || position.y >= WORLD_HEIGHT then return false;

    // Make sure the space is unoccupied or can be moved away
    collision := get_entity_at_position(world, position);
    if collision != null && (!is_pushable_entity(collision.kind) || !recursive_move_check(world, collision, move_delta)) then return false;

    // Success!
    return true;
}

recursive_move :: (world: *World, entity: *Entity, move_delta: v2i) {
    position := v2i.{ entity.physical_position.x + move_delta.x, entity.physical_position.y + move_delta.y };

    collision := get_entity_at_position(world, position);
    if collision recursive_move(world, collision, move_delta);
    
    entity.physical_position.x += move_delta.x;
    entity.physical_position.y += move_delta.y;
    entity.moved_this_frame     = true;
}

is_pushable_entity :: (kind: Entity_Kind) -> bool {
    return kind == .Crystal;
}