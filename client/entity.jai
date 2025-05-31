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

    sound_pid: Sound_Pid = INVALID_SOUND_PID;
    sound_cooldown: f32;
    
    derived: *void;
    
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
    strength_and_heal_particles: Pid = INVALID_PID;
    digging_particles: Pid = INVALID_PID;
}

Emitter :: struct {
    #using entity : *Entity = ---;
    beam_data: Beam_Data = ---;
    beam_intensity: f32 = ---;
    particles: Pid = INVALID_PID;
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

Frog :: struct {
    #using entity : *Entity = ---;
    beam_data: Beam_Data = ---;
    particles: Pid = INVALID_PID;
    state: Frog_State = .Idle;
    state_t: f32;
}

Goblin :: struct {
    #using entity : *Entity = ---;
    state: Goblin_State;
    state_t: f32; // How much time this goblin spent in the current state
}

Entity_Manager :: struct {
    entity_pid_lookup: Probed_Hash_Table(Pid, *Entity);
    all_entities: Bucket_Array(Entity);
    guys:         Bucket_Array(Guy);
    emitters:     Bucket_Array(Emitter);
    receivers:    Bucket_Array(Receiver);
    slabs:        Bucket_Array(Slab);
    item_stacks:  Bucket_Array(Item_Stack);
    frogs:        Bucket_Array(Frog);
    goblins:      Bucket_Array(Goblin);

    particle_pid_counter := 0;
    particle_pid_lookup: Probed_Hash_Table(Pid, *Particle_System);
    particle_systems: Bucket_Array(Particle_System);
}



//
// Entity Manager
//

create_entity_manager :: (client: *Client) {
    client.entity_pid_lookup.allocator = *client.world_allocator;
    probed_hash_table_create(*client.entity_pid_lookup, 128, pid_hash, pids_equal);
    create_bucket_array(*client.all_entities, *client.world_allocator);
    create_bucket_array(*client.guys, *client.world_allocator);
    create_bucket_array(*client.emitters, *client.world_allocator);
    create_bucket_array(*client.receivers, *client.world_allocator);
    create_bucket_array(*client.slabs, *client.world_allocator);
    create_bucket_array(*client.item_stacks, *client.world_allocator);
    create_bucket_array(*client.frogs, *client.world_allocator);
    create_bucket_array(*client.goblins, *client.world_allocator);

    client.entity_pid_lookup.allocator = *client.world_allocator;
    probed_hash_table_create(*client.particle_pid_lookup, 128, pid_hash, pids_equal);
    create_bucket_array(*client.particle_systems, *client.world_allocator);
}

destroy_entity_manager :: (client: *Client) {
    probed_hash_table_destroy(*client.entity_pid_lookup);
    destroy_bucket_array(*client.all_entities);
    destroy_bucket_array(*client.guys);
    destroy_bucket_array(*client.emitters);
    destroy_bucket_array(*client.receivers);
    destroy_bucket_array(*client.slabs);
    destroy_bucket_array(*client.item_stacks);
    destroy_bucket_array(*client.frogs);
    destroy_bucket_array(*client.goblins);

    probed_hash_table_destroy(*client.particle_pid_lookup);
    destroy_bucket_array(*client.particle_systems);
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
// Particle System
//

create_particle_system :: (client: *Client, ttl: f32, world_position: v2f, emitter_count: s64) -> *Particle_System {
    pid := ++client.particle_pid_counter;

    system := push_bucket_array(*client.particle_systems);
    system.pid            = pid;
    system.allocator      = *client.world_allocator;
    system.time_to_live   = ttl;
    system.world_position = world_position;
    system.global_alpha   = 1;
    system.emitters       = allocate_array(system.allocator, Particle_Emitter, emitter_count);
    seed_random_generator(*system.random, system.random.DEFAULT_X, system.random.DEFAULT_Y, system.random.DEFAULT_Z, system.random.DEFAULT_C);

    if cast(f32) client.particle_pid_lookup.count / cast(f32) client.particle_pid_lookup.buckets.count >= 0.7 {
        probed_hash_table_resize(*client.particle_pid_lookup, client.particle_pid_lookup.buckets.count * 2);
    }

    successfully_added := probed_hash_table_add(*client.particle_pid_lookup, pid, system);
    assert(successfully_added, "For some reason we failed to register the particle pid on the client.");

    return system;
}

physically_remove_dead_particle_systems :: (client: *Client) {
    for i := 0; i < client.particle_systems.slot_count; ++i {
        system, occupied := index_bucket_array(*client.particle_systems, i);
        if !occupied continue;
        
        if system.time_to_live <= 0 {
            probed_hash_table_remove(*client.particle_pid_lookup, system.pid);
            remove_index_from_bucket_array(*client.particle_systems, i);
        }
    }
}

particle_system_exists :: (client: *Client, pid: Pid) -> bool {
    return probed_hash_table_query(*client.particle_pid_lookup, pid) != null;
}

get_particle_system :: (client: *Client, pid: Pid) -> *Particle_System {
    pointer := probed_hash_table_query(*client.particle_pid_lookup, pid);
    assert(pointer != null, "Tried to get a non-existent particle system.");
    return ~pointer;
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
    entity.health             = ENTITY_DEFAULT_HEALTH[kind];
    entity.entity_flags       = ENTITY_DEFAULT_FLAGS[kind];
    entity.physical_rotation  = rotation;
    entity.physical_position  = position;
    entity.visual_position    = .{ xx entity.physical_position.x, xx entity.physical_position.y };
    entity.visual_rotation    = visual_from_physical_rotation(entity.physical_rotation);
    entity.visual_size        = .{ 1, 1 };
    
    if cast(f32) client.entity_pid_lookup.count / cast(f32) client.entity_pid_lookup.buckets.count >= 0.7 {
        probed_hash_table_resize(*client.entity_pid_lookup, client.entity_pid_lookup.buckets.count * 2);
    }
    
    successfully_added := probed_hash_table_add(*client.entity_pid_lookup, pid, entity);
    assert(successfully_added, "For some reason we failed to register the entity pid on the client.");

    if #complete entity.entity_kind == {
      case .Guy;        make_derived(entity, *client.guys);
      case .Emitter;    make_derived(entity, *client.emitters);
      case .Receiver;   make_derived(entity, *client.receivers);
      case .Slab;       make_derived(entity, *client.slabs);
      case .Item_Stack; make_derived(entity, *client.item_stacks);
      case .Frog;     make_derived(entity, *client.frogs);
      case .Goblin;     make_derived(entity, *client.goblins);
      case .Crystal, .Bedrock, .Mirror, .Rock, .Coal, .Lava, .Trader;
        entity.derived = null;
    }

    return entity;
}

get_entity :: (client: *Client, pid: Pid) -> *Entity {
    pointer := probed_hash_table_query(*client.entity_pid_lookup, pid);
    assert(pointer != null, "Tried to get a non-existent entity.");
    return ~pointer;
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
    remove_deriveds(*client.frogs);
    remove_deriveds(*client.goblins);

    for i := 0; i < client.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*client.all_entities, i);
        if occupied && entity.marked_for_removal {
            probed_hash_table_remove(*client.entity_pid_lookup, entity.pid);
            remove_index_from_bucket_array(*client.all_entities, i);
        }
    }
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
            entity.sound_pid = play_sound_once_per_frame(client, sound_index);
        }
    }

    if entity.sound_cooldown > 0 {
        entity.sound_cooldown -= client.tick_time;
    }
}

update_emitter :: (client: *Client, emitter: *Emitter) {
    clear_beam_data(client, *emitter.beam_data);

    if emitter.particles != INVALID_PID {
        particles := get_particle_system(client, emitter.particles);
        particle_emitter := *particles.emitters[0];
        particle_emitter.line_strings = .[];
    }
        
    if emitter.time_left_in_seconds > 0 {
        emitter.time_left_in_seconds -= client.tick_time;
    }
    
    if emitter.time_left_in_seconds <= 0 return;

    recalculate_beam(client, *emitter.beam_data, emitter.physical_position, emitter.physical_rotation, true, MAX_S64);

    t := (1 - emitter.time_left_in_seconds / EMITTER_MAX_TIME) * 3;
    emitter.beam_intensity = smoothstep(cosf(powf(t, 5) * FTAU) * 0.5 + 0.5, 0, (t * t) / 30);

    if emitter.particles == INVALID_PID {
        particles := create_particle_system(client, MAX_F32, emitter.visual_position, 1);
        particle_emitter := create_particle_emitter(particles, 0, 256 * 5);
        particle_emitter.shape    = .Line_String;
        particle_emitter.lifetime = .[ MAX_F32, MAX_F32 ];
        particle_emitter.color    = .[ .{ 168, 166, 52, 255 }, .{ 255, 240, 160, 255 } ];
        particle_emitter.particles_per_second = 50;
        emitter.particles = particles.pid;
    }

    {
        particles := get_particle_system(client, emitter.particles);
        particles.global_alpha = emitter.beam_intensity;
        particles.world_position = emitter.visual_position;
        
        particle_emitter := *particles.emitters[0];
        particle_emitter.line_strings = allocate_array(*client.tick_allocator, Line_String, emitter.beam_data.fields.count);

        WIDTH: f32 : 0.9;
        
        for i := 1; i < emitter.beam_data.fields.count; ++i {
            field := array_get(*emitter.beam_data.fields, i);

            my_displacement := vector_from_direction(field.incoming_direction);

            previous_direction := array_get(*emitter.beam_data.fields, i - 1).incoming_direction;
            next_direction     := ifx i + 1 < emitter.beam_data.fields.count then array_get(*emitter.beam_data.fields, i + 1).incoming_direction else field.incoming_direction;

            start_angle := (visual_from_physical_rotation(previous_direction) - visual_from_physical_rotation(field.incoming_direction)) / 2 + 0.25;
            end_angle   := (visual_from_physical_rotation(next_direction) - visual_from_physical_rotation(field.incoming_direction)) / 2 + 0.25;
            
            start_field := v2f.{ xx field.position.x - xx my_displacement.x - emitter.visual_position.x,
                                 xx field.position.y - xx my_displacement.y - emitter.visual_position.y };
            end_field := v2f.{ xx field.position.x - emitter.visual_position.x,
                               xx field.position.y - emitter.visual_position.y };
                                    
            start_width := ifx i == 1 then 0 else WIDTH;
            end_width   := WIDTH;

            particle_emitter.line_strings[i - 1] = .{ .[ start_field, end_field ], .[ start_angle, end_angle ], .[ start_width, end_width ] };

            if i == emitter.beam_data.fields.count - 1 {
                final_field := v2f.{ xx field.position.x + xx my_displacement.x / 2 - emitter.visual_position.x,
                                     xx field.position.y + xx my_displacement.y / 2 - emitter.visual_position.y };
                particle_emitter.line_strings[i] = .{ .[ end_field, final_field ], .[ end_angle, end_angle ], .[ end_width, end_width] };
            }
        }
    }
}

update_slab :: (client: *Client, slab: *Slab) {
    slab.time_left_in_seconds -= client.tick_time;
}

update_guy :: (client: *Client, guy: *Guy) {
    if guy.state == .Resurrecting {
        guy.resurrection_t += client.tick_time / RESURRECTION_TIME;
    }

    //
    // Manage strength particles
    //
    if guy.strength_t > 0 && guy.strength_and_heal_particles == INVALID_PID {
        particles := create_particle_system(client, STRENGTH_POTION_TIME, guy.visual_position, 1);
        emitter := create_particle_emitter(particles, 0, 64);
        emitter.drag = 0.95;
        emitter.box_half_size = .{ 0.45, 0.15 };
        emitter.shape_cutout_factor = 0.95;
        emitter.lifetime = .[ 0.5, 0.7 ];
        emitter.speed = .[ 0.3, 0.5 ];
        emitter.color = .[ .{ 103, 34, 130, 170 }, .{ 164, 37, 214, 170 } ];
        emitter.gravity = .{ 0, -2 };
        guy.strength_and_heal_particles = particles.pid;
    } else if !particle_system_exists(client, guy.strength_and_heal_particles) {
        guy.strength_and_heal_particles = INVALID_PID;
    }

    if guy.strength_and_heal_particles != INVALID_PID {
        particles := get_particle_system(client, guy.strength_and_heal_particles);
        particles.time_to_live = guy.strength_t;
        particles.world_position = .{ guy.visual_position.x, guy.visual_position.y - 0.35 };

        t := guy.strength_t / 10;
        if t <= 1 {
            particles.global_alpha = clamp(1 - powf(1 - t, 2), 0, 1);
        } else {
            particles.global_alpha = 1;
        }
    }

    //
    // Manage digging particles
    //
    if guy.state == .Digging && guy.digging_particles == INVALID_PID {
        target_entity := find_entity_with_flags_at_position(client, .Diggable, guy.target_position);
        if target_entity {
            estimated_digging_time: f32 = target_entity.health / GUY_DPS;
            particles := create_particle_system(client, estimated_digging_time, .{ xx guy.target_position.x, xx guy.target_position.y }, 1);
            emitter := create_particle_emitter(particles, 0, 32);
            emitter.shape = .Box;
            emitter.box_half_size = .{ 0.35, 0.35 };
            emitter.drag = 4;
            emitter.lifetime = .[ 0.4, 0.8 ];
            emitter.color = get_colors_for_digging_particles(target_entity);
            emitter.particles_per_second = xx emitter.particles.count / emitter.lifetime[1];
            guy.digging_particles = particles.pid;
        }
    } else if guy.state != .Digging && guy.digging_particles != INVALID_PID {
        if particle_system_exists(client, guy.digging_particles) { // The system might've already been cleaned up by TTL
            particles := get_particle_system(client, guy.digging_particles);
            particles.emitters[0].particles_per_second = 0;
            particles.time_to_live = 0.5;
        }
        guy.digging_particles = INVALID_PID;
    }
}

update_frog :: (client: *Client, frog: *Frog) {
    clear_beam_data(client, *frog.beam_data);

    if #complete frog.state == {
      case .Idle, .Recovering;
        frog.particles = INVALID_PID;

      case .Attacking;
        recalculate_beam(client, *frog.beam_data, frog.physical_position, frog.physical_rotation, false, FROG_BEAM_LENGTH);

        if frog.particles == INVALID_PID {
            particles := create_particle_system(client, FROG_ATTACK_TIME, frog.visual_position, 1);
            emitter := create_particle_emitter(particles, 0, 256);
            emitter.shape    = .Cone;
            emitter.drag     = .9;
            emitter.speed    = .[ 4, 6 ];
            emitter.lifetime = .[ 0.5, 0.8 ];
            emitter.color    = .[ .{ 255, 241, 99, 255 }, .{ 255, 111, 52, 255 } ];
            emitter.particles_per_second = 1024;
            emitter.alive_t  = 0.5;

            theta := visual_from_physical_rotation(frog.physical_rotation);
            emitter.cone_angles = .[ theta - 0.03, theta + 0.03 ];

            frog.particles = particles.pid;
        }
    }

    frog.state_t += client.tick_time;
}



#file_scope

//
// Helpers
//

clear_beam_data :: (client: *Client, data: *Beam_Data) {
    array_clear_without_deallocation(*data.fields);
    data.fields.allocator = *client.tick_allocator;
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

get_colors_for_digging_particles :: (target_entity: *Entity) -> [2]GE_Color {
    colors: [2] GE_Color = ---;

    if target_entity.entity_kind == {
      case .Bedrock; colors = .[ .{ 102, 102, 102, 220 }, .{ 130, 130, 130, 220 } ];
      case .Crystal, .Mirror; colors = .[ .{ 70, 115, 206, 150 }, .{ 154, 172, 206, 150 } ];
      case .Coal; colors = .[ .{ 76, 49, 53, 255 }, .{ 62, 58, 58, 255 } ];
      case .Rock; colors = .[ .{ 134, 134, 134, 255 }, .{ 192, 192, 192, 255 } ];
    }
    
    return colors;
}
