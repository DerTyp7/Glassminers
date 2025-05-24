Particle :: struct {
    local_position: v2f;
    velocity: v2f;
    speed: f32;
    size: v2f;
    color: GE_Color;
    remaining_time: f32;
}

Particle_Emitter_Shape :: enum {
    Box;
    Cone;
}

Particle_Emitter :: struct {
    // Properties
    local_position: v2f;

    shape: Particle_Emitter_Shape;
    shape_cutout_factor: f32;
    #using derived: union {
        box_half_size: v2f;
        cone_angles: [2]f32;
    };

    drag: f32 = 0;
    size: [2]v2f = .[ .{ 0.02, 0.02 }, .{ 0.05, 0.05 } ];
    speed: [2]f32 = .[ 2, 3 ];
    lifetime: [2]f32 = .[ 2, 3 ];
    color: [2]GE_Color = .[ .{ 0, 0, 0, 255 }, .{ 255, 255, 255, 255 } ];
    gravity: v2f = .{ 0, 0 };
    particles_per_second: f32 = 256;
    alive_t: f32 = MAX_F32; // An emitter will only spawn new particles if it is alive

    // Internal State
    particles: []Particle;
    new_particle_accumulator: f32 = 0;
}

Particle_System :: struct {
    allocator: *Allocator;
    pid: Pid;
    
    time_to_live: f32;
    
    world_position: v2f;
    global_alpha: f32;
    
    random: Random_Generator;
    emitters: []Particle_Emitter;
}

create_particle_emitter :: (#using system: *Particle_System, emitter_index: s64, particle_count: s64) -> *Particle_Emitter {
    emitter := *emitters[emitter_index];
    ~emitter = Particle_Emitter.{};
    emitter.particles = allocate_array(allocator, Particle, particle_count);
    return emitter;
}

destroy_particle_system :: (#using system: *Particle_System) {
    for i := 0; i < emitters.count; ++i {
        deallocate_array(allocator, *emitters[i].particles);
    }
    deallocate_array(allocator, *emitters);
}

update_particle_system :: (#using system: *Particle_System, dt: f32) {
    system.time_to_live -= dt;

    for i := 0; i < emitters.count; ++i {
        update_particle_emitter(*system.random, *emitters[i], dt);
    }
}



#file_scope

update_particle_emitter :: (random: *Random_Generator, #using emitter: *Particle_Emitter, dt: f32) {
    new_particle_accumulator += particles_per_second * dt;
    
    for i := 0; i < emitter.particles.count; ++i {
        particle := *emitter.particles[i];

        if particle.remaining_time <= 0 {
            if alive_t <= 0 || new_particle_accumulator < 1 {
                continue;
            }

            particle.local_position = get_spawn_position(random, emitter);
            particle.velocity = get_spawn_velocity(random, emitter, particle.local_position);
            particle.speed    = random_f32_in(random, emitter.speed[0], emitter.speed[1]);
            particle.size.x   = random_f32_in(random, emitter.size[0].x, emitter.size[1].x);
            particle.size.y   = random_f32_in(random, emitter.size[0].y, emitter.size[1].y);
            particle.color    = ge_mix_colors(emitter.color[0], emitter.color[1], random_f32_zero_to_one(random));
            particle.remaining_time = random_f32_in(random, emitter.lifetime[0], emitter.lifetime[1]);
            new_particle_accumulator -= 1;
        }
        
        particle.local_position.x += particle.velocity.x * particle.speed * dt;
        particle.local_position.y += particle.velocity.y * particle.speed * dt;
        particle.velocity.x += emitter.gravity.x * dt;
        particle.velocity.y += emitter.gravity.y * dt;
        particle.velocity.x *= expf(-emitter.drag * dt);
        particle.velocity.y *= expf(-emitter.drag * dt);
        particle.remaining_time -= dt;
    }

    alive_t -= dt;
}

get_spawn_position :: (random: *Random_Generator, #using emitter: *Particle_Emitter) -> v2f {
    position: v2f = ---;

    if #complete emitter.shape == {
      case .Box;
        cutout_half_size: v2f = .{ emitter.shape_cutout_factor * emitter.box_half_size.x, emitter.shape_cutout_factor * emitter.box_half_size.y };

        // @Cleanup: I'm sure there's a smarter way of doing this, that isn't rejection sampling
        while true {
            position.x = random_f32_in(random, -emitter.box_half_size.x, emitter.box_half_size.x);
            position.y = random_f32_in(random, -emitter.box_half_size.y, emitter.box_half_size.y);

            if abs(position.x) >= cutout_half_size.x || abs(position.y) >= cutout_half_size.y break;
        }

      case .Cone;
        position = .{ 0, 0 };
    }
    
    return position;
}

get_spawn_velocity :: (random: *Random_Generator, #using emitter: *Particle_Emitter, position: v2f) -> v2f {
    velocity: v2f = ---;

    if #complete emitter.shape == {
      case .Box; velocity = position;
      case .Cone;
        theta := random_f32_in(random, emitter.cone_angles[0], emitter.cone_angles[1]);
        velocity = .{ sinf(theta * FTAU), -cosf(theta * FTAU) };
    }

    return velocity;
}
