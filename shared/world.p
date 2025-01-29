WORLD_WIDTH  :: 32;
WORLD_HEIGHT :: 5;

v2i :: Vector2_Base(s32);
v2f :: Vector2_Base(f32);

Pid :: u32;

Entity_Kind :: enum {
    Inanimate;
    Player;
    Crystal;
    Stone;
}

Entity_Prototype :: struct {
    kind: Entity_Kind;
    position: v2i;
}


generate_world :: (seed: s64, allocator: *Allocator) -> [..]Entity_Prototype {
    rand :: () -> s32 #foreign;
    
    random_position :: () -> v2i {
        return .{ rand() % WORLD_WIDTH, rand() % WORLD_HEIGHT };
    }

    srand(seed);

    entities: [..]Entity_Prototype;
    entities.allocator = allocator;
    
    //
    // Generate some stones
    //
    for i := 0; i < 15; ++i {
        entity := array_push(*entities);
        entity.kind = .Stone;
        entity.position = random_position();
    }
    
    //
    // Generate some crystals
    //
    for i := 0; i < 15; ++i {
        entity := array_push(*entities);
        entity.kind = .Crystal;
        entity.position = random_position();
    }
    
    return entities;
}