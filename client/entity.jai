Camera :: struct {
    DESIRED_VERTICAL_UNITS: f32 : 5;

    ratio: f32;
    world_to_screen: v2f;
    size: v2f;
    center: v2f;
}

Entity :: struct {
    pid: Pid;
    kind: Entity_Kind;
    marked_for_removal: bool;
    health: f32;
    
    physical_position: v2i;
    physical_rotation: Direction;    
    visual_position: v2f;
    visual_rotation: f32;
    
    derived: *void;
}

Player :: struct {
    KIND :: Entity_Kind.Player;
    state: Player_State = .Idle;
    target_position: v2i;
    carrying_item: Entity_Kind = 0;
}

Emitter :: struct {
    KIND :: Entity_Kind.Emitter;
    fields: [..]v2i;
    time_left_in_seconds: f32 = EMITTER_TIME_TO_DIE;
}

Receiver :: struct {
    KIND :: Entity_Kind.Receiver;
    progress_time_in_seconds: f32 = 0;
}



//
// Entity Manager
//

create_entity_arrays :: (client: *Client) {
    create_bucket_array(*client.entities, *client.perm);
}

destroy_entity_arrays :: (client: *Client) {
    for i := 0; i < client.entities.count; ++i {
        entity := index_bucket_array(*client.entities, i);
        if entity.derived deallocate(*client.perm, entity.derived);
    }
    destroy_bucket_array(*client.entities);
}



//
// Camera
//

screen_from_world_position :: (client: *Client, world: v2f) -> v2f {
    return .{ (world.x - client.camera.center.x) * client.camera.world_to_screen.x + xx client.window.w / 2, (world.y - client.camera.center.y) * client.camera.world_to_screen.y + xx client.window.h / 2 };
}

screen_from_world_size :: (client: *Client, world: v2f) -> v2f {
    return .{ world.x * client.camera.world_to_screen.x, world.y * client.camera.world_to_screen.y };
}

screen_from_world_height :: (client: *Client, height: f32) -> f32 {
    return height * client.camera.world_to_screen.y;
}

update_camera_matrices :: (camera: *Camera, window: *Window) {
    camera.ratio             = xx window.w / xx window.h;
    camera.size.y            = camera.DESIRED_VERTICAL_UNITS;
    camera.size.x            = camera.DESIRED_VERTICAL_UNITS * camera.ratio;
    camera.world_to_screen.y = xx window.h / camera.DESIRED_VERTICAL_UNITS;
    camera.world_to_screen.x = camera.world_to_screen.y;
}



//
// Base Entity
//

down :: (entity: *Entity, $T: Type) -> *T {
    assert(entity.kind == T.KIND && entity.derived != null, "Invalid down() cast on entity.");
    return cast(*T) entity.derived;
}

create_entity_with_pid :: (client: *Client, pid: Pid, kind: Entity_Kind, position: v2i, rotation: Direction) -> *Entity {
    assert(!entity_exists(client, pid), "An entity with the requested id already exists.");

    entity := push_bucket_array_with_pid(*client.entities, pid);
    entity.pid                = pid;
    entity.kind               = kind;
    entity.marked_for_removal = false;
    entity.health             = MAX_HEALTHS[kind];
    entity.physical_rotation  = rotation;
    entity.physical_position  = position;
    entity.visual_position    = .{ xx position.x, xx position.y };
    entity.visual_rotation    = visual_from_physical_rotation(rotation);
    entity.derived            = null;
    
    if entity.kind == {
      case .Player;   entity.derived = new(*client.perm, Player);
      case .Emitter;  entity.derived = new(*client.perm, Emitter);
      case .Receiver; entity.derived = new(*client.perm, Receiver);
    }
    
    return entity;
}

get_entity :: (client: *Client, pid: Pid) -> *Entity {
    // Asserts when pid does not exist!
    return query_bucket_array(*client.entities, pid);
}

entity_exists :: (client: *Client, pid: Pid) -> bool {
    // Returns null when pid does not exist!
    return bucket_array_contains(*client.entities, pid);
}

remove_all_marked_entities :: (client: *Client) {
    for i := 0; i < client.entities.count; {
        entity := index_bucket_array(*client.entities, i);
        if entity.marked_for_removal {
            if entity.derived deallocate(*client.perm, entity.derived);
            remove_index_from_bucket_array(*client.entities, i);
        } else {
            ++i;
        }
    }
}



//
// Emitter
//

recalculate_emitter :: (client: *Client, entity: *Entity, emitter: *Emitter) {
    emitter.fields.allocator = *temp;
    array_clear_without_deallocation(*emitter.fields);

    if emitter.time_left_in_seconds <= 0 return;
    
    direction := entity.physical_rotation;
    field     := entity.physical_position;
    
    while true {
        vector := vector_from_direction(direction);
        field.x += vector.x;
        field.y += vector.y;
        if !position_in_bounds(client, field) break;
        
        blocking := get_blocking_entity_at_position(client, field);
        
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
// Helpers
//

position_in_bounds :: (client: *Client, position: v2i) -> bool {
    return position.x >= 0 && position.x < client.world_size.x && position.y >= 0 && position.y < client.world_size.y;
}

get_entity_at_position :: (client: *Client, position: v2i) -> *Entity {
    for i := 0; i < client.entities.count; ++i {
        entity := index_bucket_array(*client.entities, i);
        if entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
}

get_blocking_entity_at_position :: (client: *Client, position: v2i) -> *Entity {
    for i := 0; i < client.entities.count; ++i {
        entity := index_bucket_array(*client.entities, i);
        if is_blocking_entity(entity.kind) && entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
}
