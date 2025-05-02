Entity :: struct {
    pid: Pid;
    kind: Entity_Kind;
    marked_for_removal: bool;

    health: f32;
    
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

Entity_Manager :: struct {
    pid_counter:  Pid;
    pid_lookup:   Probed_Hash_Table(Pid, *Entity);
    entities: Bucket_Array(Entity);
}



//
// Entity Manager
//

create_entity_manager :: (server: *Server) {
    server.pid_counter = 0;
    server.pid_lookup.allocator = *server.perm;
    probed_hash_table_create(*server.pid_lookup, 128, pid_hash, pids_equal);
    create_bucket_array(*server.entities, *server.perm);
}

destroy_entity_manager :: (server: *Server) {
    probed_hash_table_destroy(*server.pid_lookup);
    destroy_bucket_array(*server.entities);
}



//
// Base Entity
//

down :: (entity: *Entity, $T: Type) -> *T {
    assert(entity.kind == T.KIND && entity.derived != null, "Invalid down() cast on entity.");
    return cast(*T) entity.derived;
}

create_entity :: (server: *Server, kind: Entity_Kind, position: v2i, rotation: Direction) -> *Entity {
    pid := ++server.pid_counter;
    
    slot, entity := push_bucket_array(*server.entities);
    entity.pid                = pid;
    entity.kind               = kind;
    entity.marked_for_removal = false;
    entity.health             = MAX_HEALTHS[kind];
    entity.physical_rotation  = rotation;
    entity.physical_position  = position;
    entity.derived            = null;

    probed_hash_table_add(*server.pid_lookup, pid, entity);
    
    if entity.kind == {
      case .Player;   entity.derived = new(*server.perm, Player);
      case .Emitter;  entity.derived = new(*server.perm, Emitter);
      case .Receiver; entity.derived = new(*server.perm, Receiver);
    }

    msg := make_message(Create_Entity_Message);
    msg.create_entity.entity_pid = entity.pid;
    msg.create_entity.kind       = entity.kind;
    msg.create_entity.position   = entity.physical_position;
    msg.create_entity.rotation   = entity.physical_rotation;
    array_add(*server.outgoing_messages, msg);

    return entity;
}

get_entity :: (server: *Server, pid: Pid) -> *Entity {
    pointer := probed_hash_table_query(*server.pid_lookup, pid);
    assert(pointer != null, "Tried to get a non-existent entity.");
    entity := ~pointer;
    return entity;
}

physically_remove_all_marked_entities :: (server: *Server) {
    for i := 0; i < server.entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.entities, i);

        if occupied && entity.marked_for_removal {
            if entity.derived deallocate(*server.perm, entity.derived);
            remove_index_from_bucket_array(*server.entities, i);
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
    for i := 0; i < server.entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.entities, i);
        if occupied && entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
}

get_blocking_entity_at_position :: (server: *Server, position: v2i) -> *Entity {
    for i := 0; i < server.entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.entities, i);
        if occupied && is_blocking_entity(entity.kind) && entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
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

warp_entity :: (server: *Server, entity: *Entity, position: v2i, rotation: Direction) {
    entity.physical_position = position;
    entity.physical_rotation = rotation;

    msg := make_message(Move_Entity_Message);
    msg.move_entity.entity_pid = entity.pid;
    msg.move_entity.position = entity.physical_position;
    msg.move_entity.rotation = entity.physical_rotation;
    array_add(*server.outgoing_messages, msg);
}

remove_entity :: (server: *Server, entity: *Entity) {
    entity.marked_for_removal = true;
    msg := make_message(Destroy_Entity_Message);
    msg.destroy_entity.entity_pid = entity.pid;
    array_add(*server.outgoing_messages, msg);
}



//
// Helpers
//

is_emitter_field_at :: (server: *Server, position: v2i) -> bool {
    for i := 0; i < server.entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.entities, i);
        if !occupied continue;

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

    warp_entity(server, entity, .{ entity.physical_position.x + move_delta.x, entity.physical_position.y + move_delta.y }, entity.physical_rotation);
}
