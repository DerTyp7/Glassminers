Camera :: struct {
    DESIRED_VERTICAL_UNITS: f32 : 5;

    ratio: f32;
    world_to_screen: v2f;
    size: v2f;
    center: v2f;
}

Beam_Data :: struct {
    fields: [..]v2i;
}

Entity :: struct {
    pid: Pid;
    entity_kind: Entity_Kind;
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
    carrying_item: Item_Kind = 0;
    resurrection_t: f32 = 0;
    sound_pid: Sound_Pid;
}

Emitter :: struct {
    #using entity : *Entity = ---;
    beam_data: Beam_Data = ---;
    time_left_in_seconds: f32 = EMITTER_MAX_TIME;
}

Receiver :: struct {
    #using entity : *Entity = ---;
    progress_time_in_seconds: f32 = 0;
}

Item_Stack :: struct {
    #using entity : *Entity = ---;
    item_kind: Item_Kind = 0;
    count: s64 = 0;
}

Dragon :: struct {
    #using entity : *Entity = ---;
    beam_data: Beam_Data = ---;
    state: Dragon_State = .Idle;
    state_t: f32;
}

Goblin :: struct {
    #using entity : *Entity = ---;
    state: Goblin_State;
    state_t: f32; // How much time this goblin spent in the current state
}

Entity_Manager :: struct {
    pid_lookup: Probed_Hash_Table(Pid, *Entity);
    all_entities: Bucket_Array(Entity);
    players:     Bucket_Array(Player);
    emitters:    Bucket_Array(Emitter);
    receivers:   Bucket_Array(Receiver);
    item_stacks: Bucket_Array(Item_Stack);
    dragons:     Bucket_Array(Dragon);
    goblins:     Bucket_Array(Goblin);
}



//
// Entity Manager
//

create_entity_manager :: (client: *Client) {
    client.pid_lookup.allocator = *client.world_allocator;
    probed_hash_table_create(*client.pid_lookup, 128, pid_hash, pids_equal);
    create_bucket_array(*client.all_entities, *client.world_allocator);
    create_bucket_array(*client.players, *client.world_allocator);
    create_bucket_array(*client.emitters, *client.world_allocator);
    create_bucket_array(*client.receivers, *client.world_allocator);
    create_bucket_array(*client.item_stacks, *client.world_allocator);
    create_bucket_array(*client.dragons, *client.world_allocator);
    create_bucket_array(*client.goblins, *client.world_allocator);
}

destroy_entity_manager :: (client: *Client) {
    probed_hash_table_destroy(*client.pid_lookup);
    destroy_bucket_array(*client.all_entities);
    destroy_bucket_array(*client.players);
    destroy_bucket_array(*client.emitters);
    destroy_bucket_array(*client.receivers);
    destroy_bucket_array(*client.item_stacks);
    destroy_bucket_array(*client.dragons);
    destroy_bucket_array(*client.goblins);
}



//
// Camera
//

screen_from_world_position :: (client: *Client, world: v2f) -> v2f {
    return .{ round((world.x - client.camera.center.x) * client.camera.world_to_screen.x + cast(f32) client.window.w / 2),
              round((world.y - client.camera.center.y) * client.camera.world_to_screen.y + cast(f32) client.window.h / 2) };
}

screen_from_world_size :: (client: *Client, world: v2f) -> v2f {
    return .{ round(world.x * client.camera.world_to_screen.x), round(world.y * client.camera.world_to_screen.y) };
}

screen_from_world_height :: (client: *Client, height: f32) -> f32 {
    return round(height * client.camera.world_to_screen.y);
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
    assert(entity.derived_type_id == type_id(T) && entity.derived != null, "Invalid down() cast on entity.");
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
    entity.entity_kind        = kind;
    entity.marked_for_removal = false;
    entity.health             = MAX_HEALTHS[kind];
    entity.physical_rotation  = rotation;
    entity.physical_position  = position;
    entity.visual_position    = .{ xx entity.physical_position.x, xx entity.physical_position.y };
    entity.visual_rotation    = visual_from_physical_rotation(entity.physical_rotation);

    if cast(f32) client.pid_lookup.count / cast(f32) client.pid_lookup.buckets.count >= 0.7 {
        probed_hash_table_resize(*client.pid_lookup, client.pid_lookup.buckets.count * 2);
    }
    
    successfully_added := probed_hash_table_add(*client.pid_lookup, pid, entity);
    assert(successfully_added, "For some reason we failed to register the entity pid on the client.");

    if #complete entity.entity_kind == {
      case .Player;     make_derived(entity, *client.players);
      case .Emitter;    make_derived(entity, *client.emitters);
      case .Receiver;   make_derived(entity, *client.receivers);
      case .Item_Stack; make_derived(entity, *client.item_stacks);
      case .Dragon;     make_derived(entity, *client.dragons);
      case .Goblin;     make_derived(entity, *client.goblins);
      case .Crystal, .Bedrock, .Mirror, .Rock, .Coal, .Lava;
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
    remove_deriveds(*client.dragons);
    remove_deriveds(*client.all_entities);
}



//
// Derived Types
//

interpolate_location :: (client: *Client, entity: *Entity, disable_visual_rotation: bool) {
    snap  :: (from: $T, to: T) -> T {
        return ifx abs(from - to) < 0.0005 then to else from;
    }

    {
        speed := client.tick_time * 10;
        target_position := v2f.{ xx entity.physical_position.x, xx entity.physical_position.y };
        entity.visual_position.x = snap(lerp(entity.visual_position.x, target_position.x, speed), target_position.x);
        entity.visual_position.y = snap(lerp(entity.visual_position.y, target_position.y, speed), target_position.y);
    }
        
    if disable_visual_rotation {
        // This is a hack, but for certain entities (e.g. players) we have sprites for the all
        // the different physical rotations (because these are from different "perspectives").
        // For those sprites, we don't actually want to rotate them visually, because the sprites
        // themselves are "rotated"...
        entity.visual_rotation = 0;
    } else {
        speed := client.tick_time * 20;
        target_rotation := visual_from_physical_rotation(entity.physical_rotation);
        entity.visual_rotation = snap(lerp_with_wrap(entity.visual_rotation, target_rotation, speed, 0, 1), target_rotation);
    }
}

update_emitter :: (client: *Client, emitter: *Emitter) {
    clear_beam_data(*emitter.beam_data);

    if emitter.time_left_in_seconds > 0 {
        emitter.time_left_in_seconds -= client.tick_time;
    }
    
    if emitter.time_left_in_seconds <= 0 return;

    recalculate_beam(client, *emitter.beam_data, emitter.physical_position, emitter.physical_rotation, MAX_S64);
}

update_player :: (client: *Client, player: *Player) {
    if player.state == .Resurrecting {
        player.resurrection_t += client.tick_time / RESURRECTION_TIME;
    }
}

update_dragon :: (client: *Client, dragon: *Dragon) {
    clear_beam_data(*dragon.beam_data);

    if #complete dragon.state == {
      case .Idle, .Recovering;
      case .Attacking;
        recalculate_beam(client, *dragon.beam_data, dragon.physical_position, dragon.physical_rotation, DRAGON_BEAM_LENGTH);
    }

    dragon.state_t += client.tick_time;
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

get_blocking_entity_at_position :: (client: *Client, position: v2i, lambda: (kind: Entity_Kind) -> bool) -> *Entity {
    for i := 0; i < client.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*client.all_entities, i);
        if occupied && entity.physical_position.x == position.x && entity.physical_position.y == position.y && lambda(entity.entity_kind) return entity;
    }
    
    return null;
}

clear_beam_data :: (data: *Beam_Data) {
    array_clear_without_deallocation(*data.fields);
    data.fields.allocator = *temp;
}

recalculate_beam :: (client: *Client, beam: *Beam_Data, position: v2i, direction: Direction, max_length: s64) {
    while beam.fields.count < max_length {
        vector := vector_from_direction(direction);
        position.x += vector.x;
        position.y += vector.y;
        if !position_in_bounds(client, position) break;
        
        blocking := get_blocking_entity_at_position(client, position, is_beam_blocking_entity);
        
        if blocking == null {
            array_add(*beam.fields, position);
        } else if blocking.entity_kind == .Mirror {
            array_add(*beam.fields, position);
            
            reflected_direction, reflection_success := reflect_direction(direction, blocking.physical_rotation);
            
            if reflection_success then direction = reflected_direction; else break;
        } else if blocking.entity_kind == .Receiver {
            array_add(*beam.fields, position);
            break;
        } else {
            break;
        }
    }
}
