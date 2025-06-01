Line_String :: struct {
    points: [2]v2f;
    angles: [2]f32;
    widths: [2]f32;
}

Particle :: struct {
    local_position: v2f;
    velocity: v2f;
    speed: f32;
    size: v2f;
    color: GE_Color;
    elapsed: f32;
    lifetime: f32;
    random_zero_to_one: f32;
}

Particle_Emitter_Shape :: enum {
    Box;
    Cone;
    Line_String;
}

Particle_Emitter :: struct {
    // Properties
    local_position: v2f;

    shape: Particle_Emitter_Shape;
    shape_cutout_factor: f32;
    #using derived: union {
        box_half_size: v2f;
        cone_angles: [2]f32;
        line_strings: []Line_String;
    };

    force_uniform_scale := true;
    random_initial_velocity := false;
    turbulence: f32 = 0;
    fadein, fadeout: f32 = 0.1, 0.3;
    particles_per_second: f32 = 256;
    alive_t: f32 = MAX_F32; // An emitter will only spawn new particles if it is alive
    
    drag: f32 = 0;
    size: [2]v2f = .[ .{ 0.02, 0.02 }, .{ 0.05, 0.05 } ];
    speed: [2]f32 = .[ 2, 3 ];
    lifetime: [2]f32 = .[ 2, 3 ];
    color: [2]GE_Color = .[ .{ 0, 0, 0, 255 }, .{ 255, 255, 255, 255 } ];
    gravity: v2f = .{ 0, 0 };

    // Internal State
    particles: []Particle;
    new_particle_accumulator: f32 = 0;
    local_bounding_box: [2]v2f;
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

    for i := 0; i < emitter.particles.count; ++i {
        emitter.particles[i].elapsed = 0;
        emitter.particles[i].lifetime = 0;
    }
    
    emitter.new_particle_accumulator = 0;
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

prewarm_particle_system :: (#using system: *Particle_System, total_time: f32, step_time: f32) {
    t: f32 = 0;

    while t < total_time {
        update_particle_system(system, step_time);
        t += step_time;
    }
}



#file_scope

update_particle_emitter :: (random: *Random_Generator, #using emitter: *Particle_Emitter, dt: f32) {
    new_particle_accumulator += particles_per_second * dt;

    local_bounding_box = .[ .{ MAX_F32, MAX_F32 }, .{ MIN_F32, MIN_F32 } ];
    
    for i := 0; i < emitter.particles.count; ++i {
        particle := *emitter.particles[i];

        if particle.elapsed >= particle.lifetime {
            if alive_t <= 0 || new_particle_accumulator < 1 {
                continue;
            }

            particle.local_position   = get_spawn_position(random, emitter);
            particle.velocity         = get_spawn_velocity(random, emitter, particle.local_position);
            particle.speed            = random_f32_in(random, emitter.speed[0], emitter.speed[1]);
            particle.size.x           = random_f32_in(random, emitter.size[0].x, emitter.size[1].x);
            particle.size.y           = ifx !emitter.force_uniform_scale then random_f32_in(random, emitter.size[0].y, emitter.size[1].y) else particle.size.x;
            particle.color            = ge_mix_colors(emitter.color[0], emitter.color[1], random_f32_zero_to_one(random));
            particle.elapsed          = 0;
            particle.lifetime         = random_f32_in(random, emitter.lifetime[0], emitter.lifetime[1]);
            particle.random_zero_to_one = random_f32_in(random, 0, 1);
            new_particle_accumulator -= 1;
        }

        if shape == .Line_String {
            target_position, total_travel_distance := get_position_along_line_string(emitter, particle.elapsed * particle.speed, particle.random_zero_to_one * 0.7 - 0.35);

            // If the line string changed drastically, we don't want to teleport this particle
            // to the next position, since that looks bad. Instead, we just want to kill it.
            if v2_magnitude_squared(v2f.{ target_position.x - particle.local_position.x, target_position.y - particle.local_position.y }) <= 0.5 {
                particle.local_position = target_position;
                particle.lifetime = total_travel_distance / particle.speed;
            } else {
                particle.lifetime = 0;
            }
        } else {
            particle.local_position.x += particle.velocity.x * particle.speed * dt;
            particle.local_position.y += particle.velocity.y * particle.speed * dt;
            particle.velocity.x += emitter.gravity.x * dt + emitter.turbulence * random_f32_in(random, -1, 1);
            particle.velocity.y += emitter.gravity.y * dt + emitter.turbulence * random_f32_in(random, -1, 1);
            particle.velocity.x *= expf(-emitter.drag * dt);
            particle.velocity.y *= expf(-emitter.drag * dt);
        }
        
        particle.elapsed += dt;

        local_bounding_box[0].x = min(local_bounding_box[0].x, particle.local_position.x - particle.size.x);
        local_bounding_box[0].y = min(local_bounding_box[0].y, particle.local_position.y - particle.size.y);
        local_bounding_box[1].x = max(local_bounding_box[1].x, particle.local_position.x + particle.size.x);
        local_bounding_box[1].y = max(local_bounding_box[1].y, particle.local_position.y + particle.size.y);
    }

    alive_t -= dt;
}

get_spawn_position :: (random: *Random_Generator, #using emitter: *Particle_Emitter) -> v2f {
    position: v2f = ---;

    if #complete emitter.shape == {
      case .Box;
        cutout_half_size: v2f = .{ shape_cutout_factor * box_half_size.x, shape_cutout_factor * box_half_size.y };

        // @Cleanup: I'm sure there's a smarter way of doing this, that isn't rejection sampling
        while true {
            position.x = random_f32_in(random, -box_half_size.x, box_half_size.x);
            position.y = random_f32_in(random, -box_half_size.y, box_half_size.y);

            if abs(position.x) >= cutout_half_size.x || abs(position.y) >= cutout_half_size.y break;
        }

      case .Cone, .Line_String;
        position = .{ 0, 0 };
    }
    
    return position;
}

get_spawn_velocity :: (random: *Random_Generator, #using emitter: *Particle_Emitter, position: v2f) -> v2f {
    velocity: v2f = ---;

    if !emitter.random_initial_velocity {
        if #complete emitter.shape == {
          case .Box; velocity = position;
          case .Cone;
            theta := random_f32_in(random, emitter.cone_angles[0], emitter.cone_angles[1]);
            velocity = .{ sinf(theta * FTAU), -cosf(theta * FTAU) };

          case .Line_String; velocity = .{ 0, 0 };
        }
    } else {
        velocity = .{ random_f32_in(random, -1, 1), random_f32_in(random, -1, 1) };
    }

    return velocity;
}

get_position_along_line_string :: (#using emitter: *Particle_Emitter, total_t: f32, normal_offset: f32) -> v2f, f32 {
    total_distance_travelled: f32 = 0;
    point_at_total_t: v2f = ---;
    found_point_at_total_t := false;

    for i := 0; i < emitter.line_strings.count; ++i {
        line_string := *emitter.line_strings[i];

        line_direction := v2_normalize(v2f.{ line_string.points[1].x - line_string.points[0].x, line_string.points[1].y - line_string.points[0].y });
        
        offset_lengths: [2]f32 = ---;
        offset_lengths[0] = (line_string.widths[0] * normal_offset) / sinf(line_string.angles[0] * FTAU);
        offset_lengths[1] = (line_string.widths[1] * normal_offset) / sinf(line_string.angles[1] * FTAU);

        offset: [2]v2f = ---;
        offset[0] = v2_rotate(v2f.{ offset_lengths[0] * line_direction.x, offset_lengths[0] * line_direction.y }, line_string.angles[0]);
        offset[1] = v2_rotate(v2f.{ offset_lengths[1] * line_direction.x, offset_lengths[1] * line_direction.y }, line_string.angles[1]);
        
        endpoint: [2]v2f = ---;
        endpoint[0] = .{ line_string.points[0].x + offset[0].x, line_string.points[0].y + offset[0].y };
        endpoint[1] = .{ line_string.points[1].x + offset[1].x, line_string.points[1].y + offset[1].y };
        endpoint_distance := v2_magnitude(v2_sub_v2(endpoint[1], endpoint[0]));
        
        if !found_point_at_total_t && (i == emitter.line_strings.count || total_distance_travelled + endpoint_distance > total_t) {
            t := (total_t - total_distance_travelled) / endpoint_distance;

            point_at_total_t = v2f.{ endpoint[0].x * (1 - t) + endpoint[1].x * t,
                                     endpoint[0].y * (1 - t) + endpoint[1].y * t };
            found_point_at_total_t = true;
        }

        total_distance_travelled += endpoint_distance;
    }

    return point_at_total_t, total_distance_travelled;
}
