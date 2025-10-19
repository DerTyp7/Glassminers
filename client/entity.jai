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

    animation_t: f32;
    animation: Animation_Index  = .Count;
    taking_damage_duration: f32 = 0;
    time_since_last_damage: f32 = 0;

    health: f32;
    entity_flags: Entity_Flags;
    
    physical_position: v2i;
    physical_rotation: Direction;
    visual_position: v2f;
    visual_rotation: f32;
    visual_size: v2f;

    sound: Sound_Pid = INVALID_SOUND_PID;
    
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
    strength_particles: Pid = INVALID_PID;
    digging_particles: Pid = INVALID_PID;
}

Emitter :: struct {
    #using entity : *Entity = ---;
    state: Emitter_State;
    current_charge: f32 = 0;
    currently_charging_up: bool;
    particles: Pid = INVALID_PID;
    beam_data: Beam_Data = ---;
    beam_intensity: f32 = ---;
    beam_ends_in_other_emitter := false;
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

Chest :: struct {
    #using entity : *Entity = ---;
    #using inventory: Item_Inventory;
    visually_open := false;
}

Frog :: struct {
    #using entity : *Entity = ---;
    beam_data: Beam_Data = ---;
    state: Frog_State = .Idle;
    state_t: f32;
}

Goblin :: struct {
    #using entity : *Entity = ---;
    state: Goblin_State;
    state_t: f32; // How much time this goblin spent in the current state
}

Slime :: struct {
    #using entity : *Entity = ---;
    state: Slime_State;
    particles: Pid = INVALID_PID;
}

Void_Eye :: struct {
    #using entity : *Entity = ---;
    state: Void_Eye_State;
}

Torch :: struct {
    #using entity : *Entity = ---;
    particles: Pid = INVALID_PID;
    time_left_in_seconds: f32 = TORCH_TIME_TO_LIVE;
}

Entity_Manager :: struct {
    entity_pid_lookup: Probed_Hash_Table(Pid, *Entity);
    all_entities: Bucket_Array(Entity);
    guys:         Bucket_Array(Guy);
    emitters:     Bucket_Array(Emitter);
    slabs:        Bucket_Array(Slab);
    item_stacks:  Bucket_Array(Item_Stack);
    torches:      Bucket_Array(Torch);
    chests:       Bucket_Array(Chest);
    frogs:        Bucket_Array(Frog);
    goblins:      Bucket_Array(Goblin);
    slimes:       Bucket_Array(Slime);
    void_eyes:    Bucket_Array(Void_Eye);
}



/* ---------------------------------------------- Entity Manager ---------------------------------------------- */

create_entity_manager :: (client: *Client) {
    client.entity_pid_lookup.allocator = *client.world_allocator;

    probed_hash_table_create(*client.entity_pid_lookup, 128, pid_hash, pids_equal);
    create_bucket_array(*client.all_entities, *client.world_allocator);
    create_bucket_array(*client.guys, *client.world_allocator);
    create_bucket_array(*client.emitters, *client.world_allocator);
    create_bucket_array(*client.slabs, *client.world_allocator);
    create_bucket_array(*client.item_stacks, *client.world_allocator);
    create_bucket_array(*client.torches, *client.world_allocator);
    create_bucket_array(*client.chests, *client.world_allocator);
    create_bucket_array(*client.frogs, *client.world_allocator);
    create_bucket_array(*client.goblins, *client.world_allocator);
    create_bucket_array(*client.slimes, *client.world_allocator);
    create_bucket_array(*client.void_eyes, *client.world_allocator);
}

destroy_entity_manager :: (client: *Client) {
    probed_hash_table_destroy(*client.entity_pid_lookup);
    destroy_bucket_array(*client.all_entities);
    destroy_bucket_array(*client.guys);
    destroy_bucket_array(*client.emitters);
    destroy_bucket_array(*client.slabs);
    destroy_bucket_array(*client.item_stacks);
    destroy_bucket_array(*client.torches);
    destroy_bucket_array(*client.chests);
    destroy_bucket_array(*client.frogs);
    destroy_bucket_array(*client.goblins);
    destroy_bucket_array(*client.slimes);
    destroy_bucket_array(*client.void_eyes);
}



/* ------------------------------------------------ Base Entity ----------------------------------------------- */

down :: (entity: *Entity, $T: Type) -> *T {
#if DEVELOPER {
    assert(entity != null && entity.derived_type_id == type_id(T) && entity.derived != null, "Invalid down() cast on entity.");
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
    entity.health             = DEFAULT_ENTITY_HEALTH[kind];
    entity.entity_flags       = DEFAULT_ENTITY_FLAGS[kind];
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

    // Create the derived pointers
    if #complete entity.entity_kind == {
      case .Guy;        make_derived(entity, *client.guys);
      case .Emitter;    make_derived(entity, *client.emitters);
      case .Slab;       make_derived(entity, *client.slabs);
      case .Item_Stack; make_derived(entity, *client.item_stacks);
      case .Torch;      make_derived(entity, *client.torches);
      case .Chest;      make_derived(entity, *client.chests);
      case .Frog;       make_derived(entity, *client.frogs);
      case .Goblin;     make_derived(entity, *client.goblins);
      case .Slime;      make_derived(entity, *client.slimes);
      case .Void_Eye;   make_derived(entity, *client.void_eyes);
      case .Crystal, .Bedrock, .Mirror, .Lava, .Rock, .Coal, .Slime_Hole, .Trader, .Flag;
        entity.derived = null;
    }

    // Create some special particle systems
    if entity.entity_kind == {
      case .Torch;
        torch  := down(entity, Torch);
        system := create_particle_system(client, 1, entity.visual_position, 1);
        smoke  := create_particle_emitter(system, 0, 32);
        smoke.shape                = .Cone;
        smoke.cone_angles          = .[ -0.1, 0.1 ];
        smoke.turbulence           = 0.05;
        smoke.particles_per_second = 3;
        smoke.drag                 = 0.5;
        smoke.size                 = .[ .{ 0.05, 0.05 }, .{ 0.1, 0.1 } ];
        smoke.speed                = .[ 0.4, 0.8 ];
        smoke.lifetime             = .[ 4, 8 ];
        smoke.color                = .[ .{ 212, 191, 15, 200 }, .{ 176, 126, 67, 150 } ];
        torch.particles = system.pid;
        
      case .Lava;
        system := create_particle_system(client, MAX_F32, entity.visual_position, 2);

        smoke := create_particle_emitter(system, 0, 8);
        smoke.shape    = .Box;
        smoke.box_half_size           = .{ 0.5, 0.5 };
        smoke.random_initial_velocity = true;
        smoke.turbulence              = 0.05;
        smoke.particles_per_second    = 1.5;
        smoke.size     = .[ .{ 0.05, 0.05 }, .{ 0.15, 0.15 } ];
        smoke.speed    = .[ 0.05, 0.2 ];
        smoke.lifetime = .[ 4, 8 ];
        smoke.color    = .[ .{ 40, 40, 40, 200 }, .{ 80, 80, 80, 150 } ];

        fire := create_particle_emitter(system, 1, 16);
        fire.shape    = .Box;
        fire.box_half_size           = .{ 0.5, 0.5 };
        fire.random_initial_velocity = true;
        fire.emissive                = true;
        fire.turbulence              = 0.05;
        fire.particles_per_second    = 4;
        fire.size     = .[ .{ 0.02, 0.02 }, .{ 0.05, 0.05 } ];
        fire.speed    = .[ 0.5, 0.8 ];
        fire.lifetime = .[ 0.5, 2 ];
        fire.color    = .[ .{ 107, 16, 42, 200 }, .{ 255, 210, 103, 200 } ];
    }

    // Set the initial animation
    if entity.entity_kind == {
      case .Lava;     play_animation(entity, .Lava);
      case .Slab;     play_animation(entity, .Slab);
      case .Torch;    play_animation(entity, .Torch_High);
      case .Flag;     play_animation(entity, .Flag);
      case .Guy;      play_animation_from_group(client, entity, .Guy_Idle);
      case .Frog;     play_animation_from_group(client, entity, .Frog_Idle);
      case .Goblin;   play_animation_from_group(client, entity, .Goblin_Idle);
      case .Slime;    play_animation_from_group(client, entity, .Slime_Idle);
      case .Void_Eye; play_animation(entity, .Void_Eye_Spawn);
      case .Trader;   play_animation_from_group(client, entity, .Trader_Idle);
    }
    
    return entity;
}

get_entity :: (client: *Client, pid: Pid) -> *Entity {
    pointer := probed_hash_table_query(*client.entity_pid_lookup, pid);
    assert(pointer != null, "Tried to get a non-existent entity.");
    return ~pointer;
}

entity_exists :: (client: *Client, pid: Pid) -> bool {
    pointer := probed_hash_table_query(*client.entity_pid_lookup, pid);
    return pointer != null;
}

physically_remove_dead_entities :: (client: *Client) {
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
    remove_deriveds(*client.slabs);
    remove_deriveds(*client.item_stacks);
    remove_deriveds(*client.torches);
    remove_deriveds(*client.chests);
    remove_deriveds(*client.frogs);
    remove_deriveds(*client.goblins);
    remove_deriveds(*client.slimes);
    remove_deriveds(*client.void_eyes);

    for i := 0; i < client.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*client.all_entities, i);
        if occupied && entity.marked_for_removal {
            probed_hash_table_remove(*client.entity_pid_lookup, entity.pid);
            remove_index_from_bucket_array(*client.all_entities, i);
        }
    }
}

interpolate_visuals_and_play_sounds :: (client: *Client, entity: *Entity) {
    //
    // Interpolate the entity's visual transform
    //
    approx_distance_to_move: f32 = ---;
    
    {
        speed := min(client.tick_time * 10, 1);
        target_position := v2f.{ xx entity.physical_position.x, xx entity.physical_position.y };
        approx_distance_to_move = abs((target_position.x - entity.visual_position.x) + (target_position.y - entity.visual_position.y));

        entity.visual_position.x = lerp_with_snap(entity.visual_position.x, target_position.x, speed);
        entity.visual_position.y = lerp_with_snap(entity.visual_position.y, target_position.y, speed);
    }

    entity.visual_size = visual_size_for_entity(entity);
    
    if entity.entity_flags & .Disable_Visual_Rotation {
        // This is a hack, but for certain entities (e.g. guys) we have sprites for the all
        // the different physical rotations (because these are from different "perspectives").
        // For those sprites, we don't actually want to rotate them visually, because the sprites
        // themselves are "rotated"...
        entity.visual_rotation = 0;
    } else {
        speed := min(client.tick_time * 20, 1);
        target_rotation := visual_from_physical_rotation(entity.physical_rotation);
        entity.visual_rotation = lerp_with_wrap_and_snap(entity.visual_rotation, target_rotation, speed, 0, 1);
    }

    //
    // Interpolate the animations
    //
    entity.animation_t += client.tick_time;
    
    if entity.time_since_last_damage <= VISUAL_HEALTH_ANIMATION_FRAME_TIME * 2 {
        entity.taking_damage_duration += client.tick_time;
    } else {
        entity.taking_damage_duration = 0;
    }

    entity.time_since_last_damage += client.tick_time;

    //
    // Update the entity's sounds
    //
    if approx_distance_to_move > 0.25 && !sound_active(client, entity.sound) {
        // Play move sound
        pick_random_sound :: (sounds: []Sound_Index) -> Sound_Index {
            time := rdtsc();
            return sounds[time % sounds.count];
        }

        sound_index: Sound_Index = .Count;

        if entity.entity_kind == {
          case .Guy; sound_index = pick_random_sound(.[ .Guy_Walk_0, .Guy_Walk_1 ]);
          case .Rock, .Crystal, .Coal, .Mirror; sound_index = .Rock_Sliding_0;
          case .Slime; sound_index = pick_random_sound(.[ .Slime_Walk_0, .Slime_Walk_1 ]);
          case .Void_Eye;
            sound_index = pick_random_sound(.[ .Void_Eye_Move_0, .Void_Eye_Move_1, .Void_Eye_Move_2 ]);
        }

        if sound_index != .Count {
            entity.sound = play_sound_on_entity(client, sound_index, entity, .Once_Per_Frame);
        }
    }
}

disable_animation :: (entity: *Entity) {
    entity.animation = .Count;
}

// Definitely switches animation
play_animation :: (entity: *Entity, animation: Animation_Index) {
    entity.animation_t = 0;
    entity.animation = animation;
}

play_animation_from_group :: (client: *Client, entity: *Entity, animation_group: Animation_Group_Index) {
    group := *client.animation_groups[animation_group];
    play_animation(entity, group.for_direction[entity.physical_rotation]);
}

// Switches animation if the current animation is of a specific kind (e.g. of "lower priority")
maybe_play_animation_from_group_instead :: (client: *Client, entity: *Entity, if_any_current_flag: Animation_Flags, new_animation_group: Animation_Group_Index) {
    if entity.animation < .Count {
        current_animation := *client.animations[entity.animation];
        if current_animation.flags & if_any_current_flag || (current_animation.frame_time > 0 && entity.animation_t >= cast(f32) current_animation.frame_count * current_animation.frame_time) {
            play_animation_from_group(client, entity, new_animation_group);
        }
    } else {
        play_animation_from_group(client, entity, new_animation_group);
    }
}

// Switches animation if the previous animation has concluded
maybe_play_animation_from_group_after :: (client: *Client, entity: *Entity, new_animation_group: Animation_Group_Index) {
    if entity.animation < .Count {
        current_animation := *client.animations[entity.animation];
        if current_animation.frame_time > 0 && entity.animation_t >= cast(f32) current_animation.frame_count * current_animation.frame_time {
            play_animation_from_group(client, entity, new_animation_group);
        }
    } else {
        play_animation_from_group(client, entity, new_animation_group);
    }
}



/* --------------------------------------------- Position Queries --------------------------------------------- */

find_any_entity_at_position :: (client: *Client, position: v2i) -> *Entity {
    found_entity: *Entity = null;

    for i := 0; i < client.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*client.all_entities, i);
        if !occupied || entity.marked_for_removal || (entity.entity_flags & .Disabled_Temporarily) continue;
        if entity.physical_position.x != position.x || entity.physical_position.y != position.y continue;
        if found_entity && DEFAULT_ENTITY_VISUAL_DEPTH[entity.entity_kind] <= DEFAULT_ENTITY_VISUAL_DEPTH[found_entity.entity_kind] continue;
        
        found_entity = entity;
    }
    
    return found_entity;
}

find_entity_of_kind_at_position :: (client: *Client, kind: Entity_Kind, position: v2i) -> *Entity {
    for i := 0; i < client.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*client.all_entities, i);
        if !occupied || entity.marked_for_removal || (entity.entity_flags & .Disabled_Temporarily) continue;
        if entity.entity_kind != kind || entity.physical_position.x != position.x || entity.physical_position.y != position.y continue;

        return entity;
    }
    
    return null;
}

find_entity_with_flags_at_position :: (client: *Client, flags: Entity_Flags, position: v2i) -> *Entity {
    for i := 0; i < client.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*client.all_entities, i);
        if !occupied || entity.marked_for_removal || (entity.entity_flags & .Disabled_Temporarily) continue;
        if (entity.entity_flags & flags) != flags || entity.physical_position.x != position.x || entity.physical_position.y != position.y continue;

        return entity;
    }
    
    return null;
}

find_nearest_entity_of_kind :: (client: *Client, kind: Entity_Kind, position: v2i) -> *Entity, s32 {
    nearest_distance := MAX_S32;
    nearest_entity: *Entity = null;

    for i := 0; i < client.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*client.all_entities, i);
        if !occupied || entity.marked_for_removal || (entity.entity_flags & .Disabled_Temporarily) continue;
        if entity.entity_kind != kind continue;

        distance := abs(position.x - entity.physical_position.x) + abs(position.y - entity.physical_position.y);
        if distance < nearest_distance {
            nearest_entity   = entity;
            nearest_distance = distance;
        }
    }
    
    return nearest_entity, nearest_distance;
}

visual_size_for_item_kind :: (kind: Item_Kind) -> v2f {
    size: v2f = ---;
    
    if kind == {
      case .Coin; size = .{ 0.25, 0.25 };
      case; size = v2f.{ 0.5, 0.5 };
    }

    return size;
}



/* ----------------------------------------------- Entity Logic ----------------------------------------------- */

update_powered_emitter :: (client: *Client, emitter: *Emitter) {
    //
    // Update the emitter beam
    //
    clear_beam_data(client, *emitter.beam_data);

    previous_charge := emitter.current_charge;
    emitter.current_charge = max(emitter.current_charge - client.tick_time, 0);

    if emitter.current_charge > 0 {
        recalculate_beam(client, *emitter.beam_data, emitter.physical_position, emitter.physical_rotation, true, MAX_S64);

        if emitter.beam_data.fields.count {
            emitter.beam_ends_in_other_emitter = find_entity_of_kind_at_position(client, .Emitter, array_get(*emitter.beam_data.fields, emitter.beam_data.fields.count - 1).position) != null;
        } else {
            emitter.beam_ends_in_other_emitter = false;
        }

        x := 1 - emitter.current_charge / EMITTER_MAX_BASE_CHARGE[client.game_mode];
        t := cosf(powf(x * 2, 8)) * 0.5 + 0.5;
        emitter.beam_intensity = smoothstep(t, 0, powf(x, 4) / 3);

        /*    
        // :EmitterSound, currently don't have a good sound to use that isn't annoying...
        if !sound_active(client, emitter.sound) {
            emitter.sound = play_sound_on_entity(client, .Emitter_Humming, emitter, .Looping);
        }
        */
    } else if previous_charge > 0 && emitter.current_charge <= 0 && is_furthest_active_emitter(client, emitter) {
        stop_sound(client, *emitter.sound);
        emitter.sound = play_sound(client, .Emitter_Dying, .Default); // Don't spatialize this sound so that everyone can hear it
    }

    //
    // Update the emitter particle system
    //
    if emitter.current_charge > 0 {
        particles: *Particle_System = ---;

        // Create a new particle system if we don't have one yet
        if !particle_system_exists(client, emitter.particles) {
            particles = create_particle_system(client, MAX_F32, emitter.visual_position, 1);
            particle_emitter := create_particle_emitter(particles, 0, 256 * 5);
            particle_emitter.shape    = .Line_String;
            particle_emitter.lifetime = .[ MAX_F32, MAX_F32 ];
            particle_emitter.particles_per_second = 50;
            emitter.particles = particles.pid;
        } else {
            particles = get_particle_system(client, emitter.particles);
        }

        // Update the particle emitter
        particle_emitter := *particles.emitters[0];
        color_t := clamp((emitter.current_charge - EMITTER_MAX_BASE_CHARGE[client.game_mode]) / EMITTER_MAX_OVER_CHARGE, 0, 1);
        particle_emitter.color = .[ ge_mix_colors(.{ 183, 186, 59, 255 }, .{ 189, 89, 10, 255 }, color_t), ge_mix_colors(.{ 252, 252, 187, 255 }, .{ 245, 157, 87, 255 }, color_t) ];
        particles.global_alpha = emitter.beam_intensity;
        particles.world_position = emitter.visual_position;

        // Set the particle line string shape
        fields_with_particles_count := emitter.beam_data.fields.count - emitter.beam_ends_in_other_emitter;
        particle_emitter.line_strings = allocate_slice(*client.tick_allocator, Line_String, fields_with_particles_count);

        WIDTH: f32 : 0.9;
        
        for i := 1; i < fields_with_particles_count; ++i {
            field := array_get(*emitter.beam_data.fields, i);

            my_displacement := vector_from_direction(field.incoming_direction);

            previous_direction := array_get(*emitter.beam_data.fields, i - 1).incoming_direction;
            next_direction     := ifx i + 1 < fields_with_particles_count then array_get(*emitter.beam_data.fields, i + 1).incoming_direction else field.incoming_direction;

            start_angle := (visual_from_physical_rotation(previous_direction) - visual_from_physical_rotation(field.incoming_direction)) / 2 + 0.25;
            end_angle   := (visual_from_physical_rotation(next_direction) - visual_from_physical_rotation(field.incoming_direction)) / 2 + 0.25;
            
            start_field := v2f.{ xx field.position.x - xx my_displacement.x - emitter.visual_position.x,
                                    xx field.position.y - xx my_displacement.y - emitter.visual_position.y };
            end_field := v2f.{ xx field.position.x - emitter.visual_position.x,
                                xx field.position.y - emitter.visual_position.y };
            
            start_width := ifx i == 1 then 0 else WIDTH;
            end_width   := WIDTH;

            particle_emitter.line_strings[i - 1] = .{ .[ start_field, end_field ], .[ start_angle, end_angle ], .[ start_width, end_width ] };

            if i + 1 == fields_with_particles_count {
                final_field := v2f.{ xx field.position.x + xx my_displacement.x / 2 - emitter.visual_position.x,
                                        xx field.position.y + xx my_displacement.y / 2 - emitter.visual_position.y };
                particle_emitter.line_strings[i] = .{ .[ end_field, final_field ], .[ end_angle, end_angle ], .[ end_width, end_width] };
            }
        }
    } else if particle_system_exists(client, emitter.particles) {
        system := get_particle_system(client, emitter.particles);
        system.time_to_live = 0;
        system.emitters[0].line_strings = .[]; // The system will be updated one last time...
        emitter.particles = INVALID_PID;
    }
}

update_off_emitter :: (client: *Client, emitter: *Emitter) {
    clear_beam_data(client, *emitter.beam_data);

    is_beam, other_emitter, incoming_direction := is_emitter_beam_at(client, emitter.physical_position);
    is_lit := is_beam && incoming_direction == emitter.physical_rotation;

    if is_lit {
        emitter.current_charge = clamp(emitter.current_charge + client.tick_time * (EMITTER_MAX_BASE_CHARGE[client.game_mode] / EMITTER_TIME_TO_POWER_UP), 0, EMITTER_MAX_BASE_CHARGE[client.game_mode]);
    } else {
        emitter.current_charge = clamp(emitter.current_charge - client.tick_time * (EMITTER_MAX_BASE_CHARGE[client.game_mode] / EMITTER_TIME_TO_POWER_UP), 0, EMITTER_MAX_BASE_CHARGE[client.game_mode]);
    }

    emitter.currently_charging_up = is_lit && emitter.current_charge < EMITTER_MAX_BASE_CHARGE[client.game_mode];
}

update_slab :: (client: *Client, slab: *Slab) {
    slab.time_left_in_seconds -= client.tick_time;
}

update_torch :: (client: *Client, torch: *Torch) {
    system := get_particle_system(client, torch.particles);
    emitter := *system.emitters[0];
    system.time_to_live += client.tick_time;
    torch.time_left_in_seconds -= client.tick_time;

    desired_animation: Animation_Index = ---;

    if torch.time_left_in_seconds <= TORCH_TIME_TO_LIVE * TORCH_LOW_PERCENTAGE {
        desired_animation = .Torch_Low;
        emitter.particles_per_second = 7;
        emitter.lifetime = .[ 1, 2 ];
        emitter.speed = .[ 1.2, 1.4 ];
    } else if torch.time_left_in_seconds <= TORCH_TIME_TO_LIVE * TORCH_MEDIUM_PERCENTAGE {
        desired_animation = .Torch_Medium;
        emitter.particles_per_second = 5;
        emitter.lifetime = .[ 2, 4 ];
        emitter.speed = .[ 0.8, 1.2 ];
    } else {
        desired_animation = .Torch_High;
    }

    if torch.animation != desired_animation then play_animation(torch, desired_animation);
}

visually_open_chest :: (client: *Client, chest: *Chest) {
    play_sound(client, .Hud_Pickup_0, .Default);
    
    msg := make_message(Chest_State_Message);
    msg.chest_state.entity_pid    = chest.pid;
    msg.chest_state.visually_open = true;
    array_add(*client.outgoing_messages, msg);
}

visually_close_chest :: (client: *Client, chest: *Chest) {
    play_sound(client, .Hud_Placedown_0, .Default);

    msg := make_message(Chest_State_Message);
    msg.chest_state.entity_pid    = chest.pid;
    msg.chest_state.visually_open = false;
    array_add(*client.outgoing_messages, msg);
}

update_guy :: (client: *Client, guy: *Guy) {
    if guy.state == .Resurrecting {
        guy.resurrection_t += client.tick_time / RESURRECTION_TIME;
    }

    maybe_play_animation_from_group_after(client, guy, .Guy_Idle);

    //
    // Manage strength particles
    //
    if guy.strength_t > 0 && !particle_system_exists(client, guy.strength_particles) {
        system, emitter := create_halo_particles(client, guy, STRENGTH_POTION_TIME);
        emitter.color = .[ .{ 103, 34, 130, 170 }, .{ 164, 37, 214, 170 } ];
        guy.strength_particles = system.pid;
    } else if guy.strength_t <= 0 {
        guy.strength_particles = INVALID_PID;
    }

    if particle_system_exists(client, guy.strength_particles) {
        particles := get_particle_system(client, guy.strength_particles);
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
    if guy.state == .Digging && !particle_system_exists(client, guy.digging_particles) {
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
    } else if guy.state != .Digging {
        if particle_system_exists(client, guy.digging_particles) {
            particles := get_particle_system(client, guy.digging_particles);
            particles.emitters[0].particles_per_second = 0;
            particles.time_to_live = 0.5;
        }
        guy.digging_particles = INVALID_PID;
    }
}

update_frog :: (client: *Client, frog: *Frog) {
    clear_beam_data(client, *frog.beam_data);

    if frog.state == {
      case .Attacking;
        recalculate_beam(client, *frog.beam_data, frog.physical_position, frog.physical_rotation, false, FROG_BEAM_LENGTH);
    }

    frog.state_t += client.tick_time;
}

update_goblin :: (client: *Client, goblin: *Goblin) {
    maybe_play_animation_from_group_after(client, goblin, .Goblin_Idle);
}

update_slime :: (client: *Client, slime: *Slime) {
    maybe_play_animation_from_group_after(client, slime, .Slime_Idle);

    if #complete slime.state == {
      case .Idle, .Hiding;
        slime.particles = INVALID_PID;

      case .Fleeing;
        if !particle_system_exists(client, slime.particles) {
            system, emitter := create_halo_particles(client, slime, 0.5);
            emitter.color       = .[ .{ 0, 255, 253, 255 }, .{ 91, 166, 201, 255 } ];
            emitter.shape       = .Cone;
            emitter.cone_angles = .[ -0.1, 0.1 ];
            emitter.speed       = .[ 2, 3 ];
            emitter.drag        = 3;
            emitter.gravity     = .{ 0, 1 };
            emitter.lifetime    = .[ 0.3, 0.7 ];
            emitter.particles_per_second = 32;
            slime.particles     = system.pid;
        }

        system := get_particle_system(client, slime.particles);
        system.world_position = slime.visual_position;
        system.time_to_live = 0.5;
        system.emitters[0].alive_t = 0.5;
    }
}

update_void_eye :: (client: *Client, eye: *Void_Eye) {
    if eye.state == .Attacking && !sound_active(client, eye.sound) {
        eye.sound = play_sound_on_entity(client, .Void_Eye_Attack_0, eye, .Once_Per_Frame);
    }
}

update_slime_hole :: (client: *Client, hole: *Entity) {
    found_any_slime := false;

    for i := 0; i < client.slimes.slot_count; ++i {
        slime, occupied := index_bucket_array(*client.slimes, i);
        if occupied && !slime.marked_for_removal && slime.state == .Hiding && slime.physical_position.x == hole.physical_position.x && slime.physical_position.y == hole.physical_position.y {
            found_any_slime = true;
            break;
        }
    }
    
    if found_any_slime {
        play_animation(hole, .Slime_Hole_Filled);
    } else {
        disable_animation(hole);
    }
}



#file_scope

is_furthest_active_emitter :: (client: *Client, emitter: *Emitter) -> bool {
    for i := 0; i < client.emitters.slot_count; ++i {
        other_emitter, occupied := index_bucket_array(*client.emitters, i);
        if !occupied || other_emitter == emitter || other_emitter.state == .Off || other_emitter.physical_position.x < emitter.physical_position.x continue;

        return false;
    }

    return true;
}

is_emitter_beam_at :: (client: *Client, position: v2i) -> bool, *Emitter, Direction {
    for i := 0; i < client.emitters.slot_count; ++i {
        emitter, occupied := index_bucket_array(*client.emitters, i);
        if !occupied || emitter.state == .Off continue;

        for j := 0; j < emitter.beam_data.fields.count; ++j {
            field := array_get(*emitter.beam_data.fields, j);
            if field.x == position.x && field.y == position.y return true, emitter, field.incoming_direction;
        }
    }
    
    return false, ---, ---;
}

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
                direction = reflected_direction;
            } else {
                break;
            }
        } else if blocking.entity_kind == .Emitter {
            if direction == blocking.physical_rotation {
                array_add(*beam.fields, Beam_Data.Field.{ position, direction });
            }
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
      case .Rock, .Chest; colors = .[ .{ 134, 134, 134, 255 }, .{ 192, 192, 192, 255 } ];
    }
    
    return colors;
}
