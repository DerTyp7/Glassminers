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

    physical_position: v2i;
    physical_rotation: Direction;    
    visual_position: v2f;
    visual_rotation: f32;
    
    derived: *void;
}

Player :: struct {
    KIND :: Entity_Kind.Player;
    state: Player_State;
    target_position: v2i;
    progress_time_in_seconds: f32;
    carrying_item: Entity_Kind;
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

    dt: f32;
    size: v2i;
    entities: [..]Entity;
}



//
// Camera
//

screen_from_world_position :: (client: *Client, world: v2f) -> v2f {
    return .{ (world.x - client.camera.center.x) * client.camera.world_to_screen.x + xx client.window.w / 2, (world.y - client.camera.center.y) * client.camera.world_to_screen.y + xx client.window.h / 2 };
}

screen_from_world_scale :: (client: *Client, world: v2f) -> v2f {
    return .{ world.x * client.camera.world_to_screen.x, world.y * client.camera.world_to_screen.y };
}

update_camera_matrices :: (camera: *Camera, window: *Window) {
    camera.ratio             = xx window.w / xx window.h;
    camera.size.y            = camera.DESIRED_VERTICAL_UNITS;
    camera.size.x            = camera.DESIRED_VERTICAL_UNITS * camera.ratio;
    camera.world_to_screen.y = xx window.h / camera.DESIRED_VERTICAL_UNITS;
    camera.world_to_screen.x = camera.world_to_screen.y;
}


//
// World
//

create_world :: (world: *World, allocator: *Allocator) {
    world.allocator = allocator;
    world.entities.allocator = world.allocator;
}

destroy_world :: (world: *World) {
    array_clear(*world.entities);
}

update_client_side_predictions :: (world: *World, dt: f32) {
    for i := 0; i < world.entities.count; ++i {
        entity := array_get_pointer(*world.entities, i);

        if entity.kind == {
          case .Player;
            player := down(entity, Player);
            player.progress_time_in_seconds += dt;
        }
    }
}



//
// Entity
//

down :: (entity: *Entity, $T: Type) -> *T {
    assert(entity.kind == T.KIND && entity.derived != null, "Invalid down() cast on entity.");
    return cast(*T) entity.derived;
}

create_entity_with_pid :: (world: *World, pid: Pid, kind: Entity_Kind, position: v2i, rotation: Direction) -> *Entity {
    assert(get_entity(world, pid) == null, "An entity with the requested id already exists.");
    entity := array_push(*world.entities);
    entity.pid                = pid;
    entity.kind               = kind;
    entity.marked_for_removal = false;
    entity.physical_rotation  = rotation;
    entity.physical_position  = position;
    entity.visual_position    = .{ xx position.x, xx position.y };
    entity.visual_rotation    = visual_from_physical_rotation(rotation);
    entity.derived            = null;
    
    if entity.kind == {
      case .Player;   entity.derived = allocate(world.allocator, Player);
      case .Emitter;  entity.derived = allocate(world.allocator, Emitter);
      case .Receiver; entity.derived = allocate(world.allocator, Receiver);
    }

    return entity;
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
// Helpers
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
