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

#if DEVELOPER {
    derived_type_id: Type;
}
}

Player :: struct {
    #using entity : *Entity = ---;
    state: Player_State = .Idle;
    target_position: v2i;
    carrying_item: Entity_Kind = 0;
}

Emitter :: struct {
    #using entity : *Entity = ---;
    fields: [..]v2i;
    time_left_in_seconds: f32 = EMITTER_TIME_TO_DIE;
}

Receiver :: struct {
    #using entity : *Entity = ---;
    progress_time_in_seconds: f32 = 0;
}

Entity_Manager :: struct {
    pid_lookup: Probed_Hash_Table(Pid, *Entity);
    all_entities: Bucket_Array(Entity);
    players:   Bucket_Array(Player);
    emitters:  Bucket_Array(Emitter);
    receivers: Bucket_Array(Receiver);
}



//
// Entity Manager
//

create_entity_manager :: (client: *Client) {
    client.pid_lookup.allocator = *client.perm;
    probed_hash_table_create(*client.pid_lookup, 128, pid_hash, pids_equal);
    create_bucket_array(*client.all_entities, *client.perm);
    create_bucket_array(*client.players, *client.perm);
    create_bucket_array(*client.emitters, *client.perm);
    create_bucket_array(*client.receivers, *client.perm);
}

destroy_entity_manager :: (client: *Client) {
    probed_hash_table_destroy(*client.pid_lookup);
    destroy_bucket_array(*client.all_entities);
    destroy_bucket_array(*client.players);
    destroy_bucket_array(*client.emitters);
    destroy_bucket_array(*client.receivers);
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
#if DEVELOPER {
    assert(entity.derived_type_id == type_id(T)/* && entity.derived != null*/, "Invalid down() cast on entity.");
}
    return cast(*T) entity.derived;
}

create_entity_with_pid :: (client: *Client, pid: Pid, kind: Entity_Kind, position: v2i, rotation: Direction) -> *Entity {
    make_derived :: (entity: *Entity, array: *Bucket_Array($T)) {
        derived := push_bucket_array(array);
        derived.entity = entity;
        entity.derived = derived;

#if DEVELOPER {
    entity.derived_type_id = type_id(T);
}
    }

    entity := push_bucket_array(*client.all_entities);
    entity.pid                = pid;
    entity.kind               = kind;
    entity.marked_for_removal = false;
    entity.health             = MAX_HEALTHS[kind];
    entity.physical_rotation  = rotation;
    entity.physical_position  = position;
    entity.visual_position    = .{ xx position.x, xx position.y };
    entity.visual_rotation    = visual_from_physical_rotation(rotation);

    probed_hash_table_add(*client.pid_lookup, pid, entity);

    if #complete entity.kind == {
      case .Player;   make_derived(entity, *client.players);
      case .Emitter;  make_derived(entity, *client.emitters);
      case .Receiver; make_derived(entity, *client.receivers);
      case .Crystal, .Bedrock, .Mirror, .Shard, .Rock, .Stone;
        entity.derived = null;
    }

    return entity;
}

get_entity :: (client: *Client, pid: Pid) -> *Entity {
    pointer := probed_hash_table_query(*client.pid_lookup, pid);
    assert(pointer != null, "Tried to get a non-existent entity.");
    entity := ~pointer;
    return entity;
}

physically_remove_all_marked_entities :: (client: *Client) {
    remove_deriveds :: (array: *Bucket_Array($T)) {
        for i := 0; i < array.slot_count; ++i {
            derived, occupied := index_bucket_array(array, i);
            if occupied && derived.marked_for_removal {
                remove_index_from_bucket_array(array, i);
            }
        }
    }
    
    remove_deriveds(*client.players);
    remove_deriveds(*client.emitters);
    remove_deriveds(*client.receivers);
    remove_deriveds(*client.all_entities);
}



//
// Emitter
//

recalculate_emitter :: (client: *Client, emitter: *Emitter) {
    emitter.fields.allocator = *temp;
    array_clear_without_deallocation(*emitter.fields);

    if emitter.time_left_in_seconds <= 0 return;
    
    direction := emitter.physical_rotation;
    field     := emitter.physical_position;
    
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
    for i := 0; i < client.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*client.all_entities, i);
        if occupied && entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
}

get_blocking_entity_at_position :: (client: *Client, position: v2i) -> *Entity {
    for i := 0; i < client.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*client.all_entities, i);
        if occupied && entity.physical_position.x == position.x && entity.physical_position.y == position.y && is_blocking_entity(entity.kind) return entity;
    }
    
    return null;
}
