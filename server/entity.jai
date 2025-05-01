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
    time_left_in_seconds: f32 = EMITTER_TIME_TO_DIE;
}

Receiver :: struct {
    KIND :: Entity_Kind.Receiver;
    progress_time_in_seconds: f32;
}



//
// Base Entity
//

down :: (entity: *Entity, $T: Type) -> *T {
    assert(entity.kind == T.KIND && entity.derived != null, "Invalid down() cast on entity.");
    return cast(*T) entity.derived;
}

create_entity :: (server: *Server, kind: Entity_Kind, position: v2i, rotation: Direction) -> Pid, *Entity {
    pid := server.entity_pid_counter;

    entity := array_push(*server.entities);
    entity.pid                = pid;
    entity.kind               = kind;
    entity.marked_for_removal = false;
    entity.created_this_frame = true;
    entity.moved_this_frame   = false;
    entity.health             = MAX_HEALTHS[kind];
    entity.physical_rotation  = rotation;
    entity.physical_position  = position;
    entity.derived            = null;

    if entity.kind == {
      case .Player;   entity.derived = new(*server.perm, Player);
      case .Emitter;  entity.derived = new(*server.perm, Emitter);
      case .Receiver; entity.derived = new(*server.perm, Receiver);
    }
    
    ++server.entity_pid_counter;
    return pid, entity;
}

get_entity :: (server: *Server, pid: Pid) -> *Entity {
    for i := 0; i < server.entities.count; ++i {
        entity := array_get_pointer(*server.entities, i);
        if entity.pid == pid return entity;
    }
    
    return null;
}

remove_all_marked_entities :: (server: *Server) {
    for i := 0; i < server.entities.count; {
        entity := array_get_pointer(*server.entities, i);
        if entity.marked_for_removal {
            if entity.derived deallocate(*server.perm, entity.derived);
            array_remove_index(*server.entities, i);
        } else {
            ++i;
        }
    }
}


//
// Emitter
//

recalculate_emitter :: (server: *Server, entity: *Entity, emitter: *Emitter) {
    emitter.fields.allocator = *temp;
    array_clear_without_deallocation(*emitter.fields);

    if emitter.time_left_in_seconds <= 0 return;
    
    direction := entity.physical_rotation;
    field     := entity.physical_position;
    
    while true {
        vector := vector_from_direction(direction);
        field.x += vector.x;
        field.y += vector.y;
        if !position_in_bounds(server, field) break;
        
        blocking := get_blocking_entity_at_position(server, field);
        
        if blocking == null || blocking.kind == .Player {
            array_add(*emitter.fields, field);
        } else if blocking.kind == .Mirror {
            array_add(*emitter.fields, field);
            
            reflected_direction, reflection_success := reflect_direction(direction, blocking.physical_rotation);
            
            if reflection_success then
            direction = reflected_direction;
            else break;
        } else if blocking.kind == .Receiver {
            array_add(*emitter.fields, field);
            break;
        } else {
            break;
        }
    }
}



//
// Movement Code
//

position_in_bounds :: (server: *Server, position: v2i) -> bool {
    return position.x >= 0 && position.x < server.world_size.x && position.y >= 0 && position.y < server.world_size.y;
}

get_entity_at_position :: (server: *Server, position: v2i) -> *Entity {
    for i := 0; i < server.entities.count; ++i {
        entity := array_get_pointer(*server.entities, i);
        if entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
}

get_blocking_entity_at_position :: (server: *Server, position: v2i) -> *Entity {
    for i := 0; i < server.entities.count; ++i {
        entity := array_get_pointer(*server.entities, i);
        if is_blocking_entity(entity.kind) && entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
}

can_move_to_position :: (server: *Server, entity: *Entity, position: v2i) -> bool {
    move_delta := v2i.{ position.x - entity.physical_position.x, position.y - entity.physical_position.y };
    if move_delta.x != 0 || move_delta.y != 0 {
        return recursive_move_check(server, entity, move_delta);
    } else {
        return true;
    }
}

move_to_position :: (server: *Server, entity: *Entity, position: v2i) {
    move_delta := v2i.{ position.x - entity.physical_position.x, position.y - entity.physical_position.y };
    if move_delta.x != 0 || move_delta.y != 0 {
        recursive_move(server, entity, move_delta);
    }
}



//
// Helpers
//

is_emitter_field_at :: (server: *Server, position: v2i) -> bool {
    for i := 0; i < server.entities.count; ++i {
        entity := array_get_pointer(*server.entities, i);
        
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

recursive_move_check :: (server: *Server, entity: *Entity, move_delta: v2i) -> bool {
    assert(move_delta.x != 0 || move_delta.y != 0, "Recursive move check with a delta of 0 leads to an infinite loop!");

    position := v2i.{ entity.physical_position.x + move_delta.x, entity.physical_position.y + move_delta.y };

    // Make sure the position is in bounds of the world
    if !position_in_bounds(server, position) then return false;

    // Make sure the space is unoccupied or can be moved away
    collision := get_blocking_entity_at_position(server, position);
    if collision != null && (!is_pushable_entity(collision.kind) || !recursive_move_check(server, collision, move_delta)) then return false;

    // Success!
    return true;
}

recursive_move :: (server: *Server, entity: *Entity, move_delta: v2i) {
    assert(move_delta.x != 0 || move_delta.y != 0, "Recursive move with a delta of 0 leads to an infinite loop!");

    position := v2i.{ entity.physical_position.x + move_delta.x, entity.physical_position.y + move_delta.y };

    collision := get_blocking_entity_at_position(server, position);
    if collision recursive_move(server, collision, move_delta);
    
    entity.physical_position.x += move_delta.x;
    entity.physical_position.y += move_delta.y;
    entity.moved_this_frame     = true;
}
