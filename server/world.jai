Entity :: struct {
    pid: Pid;
    kind: Entity_Kind;
    health: f32;

    marked_for_removal: bool;
    created_this_frame: bool;
    moved_this_frame: bool;
    
    physical_rotation: Direction;
    physical_position: v2i;
    
    derived: *void;
}

Player :: struct {
    KIND :: Entity_Kind.Player;
    state: Player_State = .Idle;
    aim_direction: Direction = .North;
    target_position: v2i = .{ 0, 0 };
    carrying_item: Entity_Kind = 0;
}

Emitter :: struct {
    KIND :: Entity_Kind.Emitter;
    fields: [..]v2i;
}

Receiver :: struct {
    KIND :: Entity_Kind.Receiver;
    progress_time_in_seconds: f32;
}

World :: struct {
    allocator: *Allocator;

    size: v2i;
    pid_counter: Pid;    
    entities: [..]Entity;
}



//
// World
//

create_world :: (world: *World, allocator: *Allocator, size: v2i) {
    world.allocator   = allocator;
    world.size        = size;
    world.pid_counter = 0;
    world.entities.allocator = world.allocator;
}

destroy_world :: (world: *World) {
    array_clear(*world.entities);
}



//
// Entity
//

down :: (entity: *Entity, $T: Type) -> *T {
    assert(entity.kind == T.KIND && entity.derived != null, "Invalid down() cast on entity.");
    return cast(*T) entity.derived;
}

create_entity :: (world: *World, kind: Entity_Kind, position: v2i, rotation: Direction) -> Pid, *Entity {
    pid := world.pid_counter;

    entity := array_push(*world.entities);
    entity.pid                = pid;
    entity.kind               = kind;
    entity.marked_for_removal = false;
    entity.created_this_frame = true;
    entity.moved_this_frame   = false;
    entity.health             = MAX_HEALTHS[kind];
    entity.physical_rotation  = rotation;
    entity.physical_position  = position;
    entity.derived            = null;

    if kind == {
      case .Player;   entity.derived = new(world.allocator, Player);
      case .Emitter;  entity.derived = new(world.allocator, Emitter);
      case .Receiver; entity.derived = new(world.allocator, Receiver);
    }
    
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
            if entity.derived deallocate(world.allocator, entity.derived);
            array_remove_index(*world.entities, i);
        } else {
            ++i;
        }
    }
}



//
// Movement Code
//

position_in_bounds :: (world: *World, position: v2i) -> bool {
    return position.x >= 0 && position.x < world.size.x && position.y >= 0 && position.y < world.size.y;
}

get_entity_at_position :: (world: *World, position: v2i) -> *Entity {
    for i := 0; i < world.entities.count; ++i {
        entity := array_get_pointer(*world.entities, i);
        if entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
}

get_blocking_entity_at_position :: (world: *World, position: v2i) -> *Entity {
    for i := 0; i < world.entities.count; ++i {
        entity := array_get_pointer(*world.entities, i);
        if is_blocking_entity(entity.kind) && entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
}

can_move_to_position :: (world: *World, entity: *Entity, position: v2i) -> bool {
    move_delta := v2i.{ position.x - entity.physical_position.x, position.y - entity.physical_position.y };
    if move_delta.x != 0 || move_delta.y != 0 {
        return recursive_move_check(world, entity, move_delta);
    } else {
        return true;
    }
}

move_to_position :: (world: *World, entity: *Entity, position: v2i) {
    move_delta := v2i.{ position.x - entity.physical_position.x, position.y - entity.physical_position.y };
    if move_delta.x != 0 || move_delta.y != 0 {
        recursive_move(world, entity, move_delta);
    }
}



//
// Helpers
//

is_emitter_field_at :: (world: *World, position: v2i) -> bool {
    for i := 0; i < world.entities.count; ++i {
        entity := array_get_pointer(*world.entities, i);
        
        if entity.kind == .Emitter {
            emitter := down(entity, Emitter);
            
            for j := 0; j < emitter.fields.count; ++j {
                field := array_get(*emitter.fields, j);
                if field.x == position.x && field.y == position.y return true;
            }
        }
    }
    
    return false;
}



#file_scope

recursive_move_check :: (world: *World, entity: *Entity, move_delta: v2i) -> bool {
    assert(move_delta.x != 0 || move_delta.y != 0, "Recursive move check with a delta of 0 leads to an infinite loop!");

    position := v2i.{ entity.physical_position.x + move_delta.x, entity.physical_position.y + move_delta.y };

    // Make sure the position is in bounds of the world
    if !position_in_bounds(world, position) then return false;

    // Make sure the space is unoccupied or can be moved away
    collision := get_blocking_entity_at_position(world, position);
    if collision != null && (!is_pushable_entity(collision.kind) || !recursive_move_check(world, collision, move_delta)) then return false;

    // Success!
    return true;
}

recursive_move :: (world: *World, entity: *Entity, move_delta: v2i) {
    assert(move_delta.x != 0 || move_delta.y != 0, "Recursive move with a delta of 0 leads to an infinite loop!");

    position := v2i.{ entity.physical_position.x + move_delta.x, entity.physical_position.y + move_delta.y };

    collision := get_blocking_entity_at_position(world, position);
    if collision recursive_move(world, collision, move_delta);
    
    entity.physical_position.x += move_delta.x;
    entity.physical_position.y += move_delta.y;
    entity.moved_this_frame     = true;
}
