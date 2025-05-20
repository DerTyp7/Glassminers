Camera :: struct {
    DESIRED_VERTICAL_UNITS: f32 : 6.3;

    ratio: f32;
    world_to_screen: v2f;
    size: v2f;
    center: v2f;
}

Beam_Data :: struct {
    Field :: struct {
        #using position: v2i;
        incoming_direction: Direction;
    }

    fields: [..]Field;
}

Entity :: struct {
    pid: Pid;
    entity_kind: Entity_Kind;
    marked_for_removal: bool;

    health: f32;
    entity_flags: Entity_Flags;
    
    physical_position: v2i;
    physical_rotation: Direction;
    visual_position: v2f;
    visual_rotation: f32;
    visual_size: v2f;
    
    derived: *void;
    sound_pid: Sound_Pid;
    sound_cooldown: f32;
    
#if DEVELOPER {
    derived_type_id: Type;
}
}

Guy :: struct {
    #using entity : *Entity = ---;
    state: Guy_State = .Idle;
    target_position: v2i;
    carrying_item: Item_Kind = 0;
    resurrection_t: f32 = 0;
    strength_t: f32 = 0;
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

Slab :: struct {
    #using entity : *Entity = ---;
    time_left_in_seconds: f32 = SLAB_TIME_TO_LIVE;
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
    pid_lookup:   Probed_Hash_Table(Pid, *Entity);
    all_entities: Bucket_Array(Entity);
    guys:         Bucket_Array(Guy);
    emitters:     Bucket_Array(Emitter);
    receivers:    Bucket_Array(Receiver);
    slabs:        Bucket_Array(Slab);
    item_stacks:  Bucket_Array(Item_Stack);
    dragons:      Bucket_Array(Dragon);
    goblins:      Bucket_Array(Goblin);
}



//
// Entity Manager
//

create_entity_manager :: (client: *Client) {
    client.pid_lookup.allocator = *client.world_allocator;
    probed_hash_table_create(*client.pid_lookup, 128, pid_hash, pids_equal);
    create_bucket_array(*client.all_entities, *client.world_allocator);
    create_bucket_array(*client.guys, *client.world_allocator);
    create_bucket_array(*client.emitters, *client.world_allocator);
    create_bucket_array(*client.receivers, *client.world_allocator);
    create_bucket_array(*client.slabs, *client.world_allocator);
    create_bucket_array(*client.item_stacks, *client.world_allocator);
    create_bucket_array(*client.dragons, *client.world_allocator);
    create_bucket_array(*client.goblins, *client.world_allocator);
}

destroy_entity_manager :: (client: *Client) {
    probed_hash_table_destroy(*client.pid_lookup);
    destroy_bucket_array(*client.all_entities);
    destroy_bucket_array(*client.guys);
    destroy_bucket_array(*client.emitters);
    destroy_bucket_array(*client.receivers);
    destroy_bucket_array(*client.slabs);
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
    entity.entity_flags       = DEFAULT_ENTITY_FLAGS[kind];
    entity.physical_rotation  = rotation;
    entity.physical_position  = position;
    entity.visual_position    = .{ xx entity.physical_position.x, xx entity.physical_position.y };
    entity.visual_rotation    = visual_from_physical_rotation(entity.physical_rotation);
    entity.visual_size        = .{ 1, 1 };
    
    if cast(f32) client.pid_lookup.count / cast(f32) client.pid_lookup.buckets.count >= 0.7 {
        probed_hash_table_resize(*client.pid_lookup, client.pid_lookup.buckets.count * 2);
    }
    
    successfully_added := probed_hash_table_add(*client.pid_lookup, pid, entity);
    assert(successfully_added, "For some reason we failed to register the entity pid on the client.");

    if #complete entity.entity_kind == {
      case .Guy;        make_derived(entity, *client.guys);
      case .Emitter;    make_derived(entity, *client.emitters);
      case .Receiver;   make_derived(entity, *client.receivers);
      case .Slab;       make_derived(entity, *client.slabs);
      case .Item_Stack; make_derived(entity, *client.item_stacks);
      case .Dragon;     make_derived(entity, *client.dragons);
      case .Goblin;     make_derived(entity, *client.goblins);
      case .Crystal, .Bedrock, .Mirror, .Rock, .Coal, .Lava, .Trader;
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

find_any_entity_at_position :: (client: *Client, position: v2i) -> *Entity {
    for i := 0; i < client.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*client.all_entities, i);
        if occupied && !entity.marked_for_removal && entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
}

find_entity_of_kind_at_position :: (client: *Client, kind: Entity_Kind, position: v2i) -> *Entity {
    for i := 0; i < client.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*client.all_entities, i);
        if occupied && !entity.marked_for_removal && entity.entity_kind == kind && entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
}

find_entity_with_flags_at_position :: (client: *Client, flags: Entity_Flags, position: v2i) -> *Entity {
    for i := 0; i < client.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*client.all_entities, i);
        if occupied && !entity.marked_for_removal && (entity.entity_flags & flags) == flags && entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
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
    
    remove_deriveds(*client.guys);
    remove_deriveds(*client.emitters);
    remove_deriveds(*client.receivers);
    remove_deriveds(*client.slabs);
    remove_deriveds(*client.item_stacks);
    remove_deriveds(*client.dragons);
    remove_deriveds(*client.goblins);
    remove_deriveds(*client.all_entities);
}

visual_size_for_item_kind :: (kind: Item_Kind) -> v2f {
    size: v2f = ---;
    
    if kind == {
      case .Coin; size = .{ 0.25, 0.25 };
      case; size = v2f.{ 0.5, 0.5 };
    }

    return size;
}

position_in_bounds :: (client: *Client, position: v2i) -> bool {
    return position.x >= 0 && position.x < client.world_size.x && position.y >= 0 && position.y < client.world_size.y;
}



//
// Derived Types
//

interpolate_visuals_and_play_sounds :: (client: *Client, entity: *Entity, disable_visual_rotation: bool) {
    //
    // Interpolate the entity's visuals
    //
    approx_distance_to_move: f32 = ---;
    
    {
        speed := client.tick_time * 10;
        target_position := v2f.{ xx entity.physical_position.x, xx entity.physical_position.y };
        approx_distance_to_move = abs((target_position.x - entity.visual_position.x) + (target_position.y - entity.visual_position.y));

        entity.visual_position.x = lerp_with_snap(entity.visual_position.x, target_position.x, speed);
        entity.visual_position.y = lerp_with_snap(entity.visual_position.y, target_position.y, speed);
    }

    entity.visual_size = visual_size_for_entity(entity);
    
    if disable_visual_rotation {
        // This is a hack, but for certain entities (e.g. guys) we have sprites for the all
        // the different physical rotations (because these are from different "perspectives").
        // For those sprites, we don't actually want to rotate them visually, because the sprites
        // themselves are "rotated"...
        entity.visual_rotation = 0;
    } else {
        speed := client.tick_time * 20;
        target_rotation := visual_from_physical_rotation(entity.physical_rotation);
        entity.visual_rotation = lerp_with_wrap_and_snap(entity.visual_rotation, target_rotation, speed, 0, 1);
    }

    //
    // Update the entity's sounds
    //
    if approx_distance_to_move > 0.25 && !sound_active(client, entity.sound_pid) {
        // Play move sound
        pick_random_sound :: (sounds: []Sound_Index) -> Sound_Index {
            time := rdtsc();
            return sounds[time % sounds.count];
        }

        sound_index: Sound_Index = .Count;

        if entity.entity_kind == {
          case .Guy; sound_index = pick_random_sound(.[ .Concrete_Footsteps_0, .Concrete_Footsteps_1 ]);
          case .Rock, .Crystal, .Coal, .Mirror; sound_index = .Rock_Sliding_0;
        }

        if sound_index != .Count {
            entity.sound_pid = play_sound(client, sound_index, false);
        }
    }

    if entity.sound_cooldown > 0 {
        entity.sound_cooldown -= client.tick_time;
    }
}

update_emitter :: (client: *Client, emitter: *Emitter) {
    clear_beam_data(*emitter.beam_data);

    if emitter.time_left_in_seconds > 0 {
        emitter.time_left_in_seconds -= client.tick_time;
    }
    
    if emitter.time_left_in_seconds <= 0 return;

    recalculate_beam(client, *emitter.beam_data, emitter.physical_position, emitter.physical_rotation, true, MAX_S64);
}

update_slab :: (client: *Client, slab: *Slab) {
    slab.time_left_in_seconds -= client.tick_time;
}

update_guy :: (client: *Client, guy: *Guy) {
    if guy.state == .Resurrecting {
        guy.resurrection_t += client.tick_time / RESURRECTION_TIME;
    }
}

update_dragon :: (client: *Client, dragon: *Dragon) {
    clear_beam_data(*dragon.beam_data);

    if #complete dragon.state == {
      case .Idle, .Recovering;
      case .Attacking;
        recalculate_beam(client, *dragon.beam_data, dragon.physical_position, dragon.physical_rotation, false, DRAGON_BEAM_LENGTH);
    }

    dragon.state_t += client.tick_time;
}



#file_scope

//
// Helpers
//

clear_beam_data :: (data: *Beam_Data) {
    array_clear_without_deallocation(*data.fields);
    data.fields.allocator = *temp;
}

recalculate_beam :: (client: *Client, beam: *Beam_Data, position: v2i, direction: Direction, include_initial_position: bool, max_length: s64) {
    if include_initial_position then array_add(*beam.fields, Beam_Data.Field.{ position, direction });
    
    while beam.fields.count < max_length {
        vector := vector_from_direction(direction);
        position.x += vector.x;
        position.y += vector.y;
        if !position_in_bounds(client, position) break;
        
        blocking := find_entity_with_flags_at_position(client, .Blocks_Beam, position);
        
        if blocking == null {
            array_add(*beam.fields, Beam_Data.Field.{ position, direction });
        } else if blocking.entity_kind == .Mirror {
            reflected_direction, reflection_success := reflect_direction(direction, blocking.physical_rotation);
            if reflection_success {
                array_add(*beam.fields, Beam_Data.Field.{ position, direction });
                direction = reflected_direction;;
            } else {
                break;
            }
        } else if blocking.entity_kind == .Receiver {
            array_add(*beam.fields, Beam_Data.Field.{ position, direction });
            break;
        } else {
            break;
        }
    }
}

visual_size_for_entity :: (entity: *Entity) -> v2f {
    size: v2f = ---;

    if entity.entity_kind == {
      case .Item_Stack;
        stack := down(entity, Item_Stack);
        size = visual_size_for_item_kind(stack.item_kind);
        
      case; size = v2f.{ 1, 1 };
    }
    
    return size;
}
