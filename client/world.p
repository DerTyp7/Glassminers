Camera :: struct {
    DESIRED_VERTICAL_UNITS: f32 : 5;

    ratio: f32;
    world_to_screen: v2f;
    center: v2f;
}

Entity :: struct {
    pid: Pid;
    kind: Entity_Kind;
    marked_for_removal: bool;
    
    physical_position: v2i;
    visual_position: v2f;
}

World :: struct {
    allocator: *Allocator;

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



//
// Entity
//

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

get_entity :: (world: *World, pid: Pid) -> *Entity {
    for i := 0; i < world.entities.count; ++i {
        entity := array_get_pointer(*world.entities, i);
        if entity.pid == pid return entity;
    }
    
    return null;
}

mark_entity_for_removal :: (world: *World, pid: Pid) {
    entity := get_entity(world, pid);
    if entity entity.marked_for_removal = true;
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
