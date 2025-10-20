// @Cleanup: Should all the update_XXXentityXXX be in here or in tick.jai?

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
    damaged_this_frame: bool;
    entity_flags: Entity_Flags;
    
    physical_rotation: Direction;
    physical_position: v2i;
    
    derived: *void;

#if DEVELOPER {
    derived_type_id: Type;
}
}

Guy :: struct {
    #using entity : *Entity = ---;
    state: Guy_State        = .Idle;
    target_position: v2i    = .{ 0, 0 };

    carrying_item: Item_Kind = .Count;

    carrying_item_data: union { // Depending on the item we are carrying, we may want to remember more information
        chest_inventory: Item_Inventory;
        torch_time_left_in_seconds: f32;
    } = ---;

    resurrection_pid: Pid = INVALID_PID;
    resurrection_t: f32   = 0; // Between 0 and 1

    strength_t: f32 = 0;
    seconds_since_last_move: f32 = 0;
    
    // The client application will send out at most one Guy_Input_Message per frame. 
    // However, with varying latency (such as when on WiFi), it can happen that we receive no input message in one tick, 
    // and then multiple messages the next one. 
    // We don't want to drop these messages, therefore we need a buffer here to process multiple in the same tick, 
    // even though they originate from different ticks in the client.
    received_inputs: [10]Guy_Input_Message; 
    received_inputs_count: u8; // For a single game_tick

    invincible := false;
    ghost_mode := false;
}

Emitter :: struct {
    #using entity : *Entity  = ---;
    state: Emitter_State;
    current_charge: f32 = 0;
    beam_data: Beam_Data = ---;
}

Slab :: struct {
    #using entity : *Entity = ---;
    time_left_in_seconds: f32 = SLAB_TIME_TO_LIVE;
}

Torch :: struct {
    #using entity : *Entity = ---;
    time_left_in_seconds: f32 = TORCH_TIME_TO_LIVE;
}

Item_Stack :: struct {
    #using entity : *Entity = ---;
    item_kind: Item_Kind = 0;
    count: s64 = 0;
}

Chest :: struct {
    #using entity : *Entity = ---;
    #using inventory: Item_Inventory;
    visually_open_counter := 0; // This chest may be opened by multiple players at the same time...
}

Frog :: struct {
    #using entity : *Entity = ---;
    beam_data: Beam_Data = ---;
    state: Frog_State;
    state_t: f32; // How much time this frog spent in the current state
    damaged_entities_this_attack: [3]Pid; // We don't want to have to dynamically allocate this, because then we'd also have to free it...
}

Goblin :: struct {
    #using entity : *Entity = ---;
    state: Goblin_State;
    state_t: f32; // How much time this goblin spent in the current state
}

Slime :: struct {
    #using entity : *Entity = ---;
    state: Slime_State;
    time_in_hiding: f32;
    time_since_last_move: f32;
}

Void_Eye :: struct {
    #using entity : *Entity = ---;
    state: Void_Eye_State;
    time_since_last_move: f32;
    time_since_spawn: f32;
}

Entity_Manager :: struct {
    pid_counter:  Pid;
    pid_lookup:   Probed_Hash_Table(Pid, *Entity);
    all_entities: Bucket_Array(Entity);
    guys:         Bucket_Array(Guy);
    emitters:     Bucket_Array(Emitter);
    slabs:        Bucket_Array(Slab);
    torches:      Bucket_Array(Torch);
    item_stacks:  Bucket_Array(Item_Stack);
    chests:       Bucket_Array(Chest);
    frogs:        Bucket_Array(Frog);
    goblins:      Bucket_Array(Goblin);
    slimes:       Bucket_Array(Slime);
    void_eyes:    Bucket_Array(Void_Eye);
}



/* ---------------------------------------------- Entity Manager ---------------------------------------------- */

create_entity_manager :: (server: *Server) {
    server.pid_counter = 0;
    server.pid_lookup.allocator = *server.world_allocator;
    probed_hash_table_create(*server.pid_lookup, 128, pid_hash, pids_equal);
    create_bucket_array(*server.all_entities, *server.world_allocator);
    create_bucket_array(*server.guys, *server.world_allocator);
    create_bucket_array(*server.emitters, *server.world_allocator);
    create_bucket_array(*server.slabs, *server.world_allocator);
    create_bucket_array(*server.torches, *server.world_allocator);
    create_bucket_array(*server.item_stacks, *server.world_allocator);
    create_bucket_array(*server.chests, *server.world_allocator);
    create_bucket_array(*server.frogs, *server.world_allocator);
    create_bucket_array(*server.goblins, *server.world_allocator);
    create_bucket_array(*server.slimes, *server.world_allocator);
    create_bucket_array(*server.void_eyes, *server.world_allocator);
}

destroy_entity_manager :: (server: *Server) {
    probed_hash_table_destroy(*server.pid_lookup);
    destroy_bucket_array(*server.all_entities);
    destroy_bucket_array(*server.guys);
    destroy_bucket_array(*server.emitters);
    destroy_bucket_array(*server.slabs);
    destroy_bucket_array(*server.torches);
    destroy_bucket_array(*server.item_stacks);
    destroy_bucket_array(*server.chests);
    destroy_bucket_array(*server.frogs);
    destroy_bucket_array(*server.goblins);
    destroy_bucket_array(*server.slimes);
    destroy_bucket_array(*server.void_eyes);
}



/* ------------------------------------------------ Base Entity ----------------------------------------------- */

down :: (entity: *Entity, $T: Type) -> *T {
#if DEVELOPER {
    assert(entity.derived_type_id == type_id(T) && entity.derived != null, "Invalid down() cast on entity.");
}
    return cast(*T) entity.derived;
}

create_entity :: (server: *Server, kind: Entity_Kind, position: v2i, rotation: Direction) -> *Entity {
    make_derived :: (entity: *Entity, array: *Bucket_Array($T)) {
        derived := push_bucket_array(array);
        derived.entity = entity;
        entity.derived = derived;

        #if DEVELOPER {
            entity.derived_type_id = type_id(T);
        }
    }

    pid := ++server.pid_counter;
    
    slot, entity := push_bucket_array(*server.all_entities);
    entity.pid                = pid;
    entity.entity_kind        = kind;
    entity.marked_for_removal = false;
    entity.health             = DEFAULT_ENTITY_HEALTH[kind];
    entity.entity_flags       = DEFAULT_ENTITY_FLAGS[kind];
    entity.physical_rotation  = rotation;
    entity.physical_position  = position;

    entity_was_added := probed_hash_table_add(*server.pid_lookup, pid, entity);
    assert(entity_was_added, "Entity couldn't be added to the hash table.");
    
    if #complete entity.entity_kind == {
      case .Guy;        make_derived(entity, *server.guys);
      case .Emitter;    make_derived(entity, *server.emitters);
      case .Slab;       make_derived(entity, *server.slabs);
      case .Torch;      make_derived(entity, *server.torches);
      case .Item_Stack; make_derived(entity, *server.item_stacks);
      case .Chest;      make_derived(entity, *server.chests);
      case .Frog;       make_derived(entity, *server.frogs);
      case .Goblin;     make_derived(entity, *server.goblins);
      case .Slime;      make_derived(entity, *server.slimes);
      case .Void_Eye;   make_derived(entity, *server.void_eyes);
      case .Crystal, .Bedrock, .Mirror, .Lava, .Rock, .Coal, .Slime_Hole, .Trader, .Flag;
        entity.derived = null;
    }

    msg := make_message(Create_Entity_Message);
    msg.create_entity.entity_pid = entity.pid;
    msg.create_entity.kind       = entity.entity_kind;
    msg.create_entity.position   = entity.physical_position;
    msg.create_entity.rotation   = entity.physical_rotation;
    array_add(*server.outgoing_messages, msg);
    
    maybe_add_blocker(*server.lightmap, entity);

    return entity;
}

get_entity :: (server: *Server, pid: Pid) -> *Entity {
    pointer := probed_hash_table_query(*server.pid_lookup, pid);
    assert(pointer != null, "Tried to get a non-existent entity.");
    entity := ~pointer;
    return entity;
}

entity_exists :: (server: *Server, pid: Pid) -> bool {
    pointer := probed_hash_table_query(*server.pid_lookup, pid);
    return pointer != null;
}

remove_entity :: (server: *Server, entity: *Entity) {
    entity.marked_for_removal = true;
    msg := make_message(Destroy_Entity_Message);
    msg.destroy_entity.entity_pid = entity.pid;
    array_add(*server.outgoing_messages, msg);

    maybe_remove_blocker(*server.lightmap, entity);
}

physically_remove_dead_entities :: (server: *Server) {
    remove_deriveds :: (array: *Bucket_Array($T)) {
        for i := 0; i < array.slot_count; ++i {
            derived, occupied := index_bucket_array(array, i);
            if occupied && derived.marked_for_removal {
                remove_index_from_bucket_array(array, i);
            }
        }
    }
    
    remove_deriveds(*server.guys);
    remove_deriveds(*server.emitters);
    remove_deriveds(*server.slabs);
    remove_deriveds(*server.torches);
    remove_deriveds(*server.item_stacks);
    remove_deriveds(*server.chests);
    remove_deriveds(*server.frogs);
    remove_deriveds(*server.goblins);
    remove_deriveds(*server.slimes);
    remove_deriveds(*server.void_eyes);

    for i := 0; i < server.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.all_entities, i);
        if occupied && entity.marked_for_removal {
            probed_hash_table_remove(*server.pid_lookup, entity.pid);
            remove_index_from_bucket_array(*server.all_entities, i);
        }
    }
}

damage_entity :: (server: *Server, entity: *Entity, immediate_damage: f32) -> bool {
#if DEVELOPER {
    if entity.entity_kind == .Guy {
        guy := down(entity, Guy);
        if guy.invincible return false;
    }
}

    //
    // If the entity has no more health we consider it dead, but the entity itself might be kept in storage.
    // For example, guy entities should never go away, they go into a special "dead" mode (instead of removing
    // the entity physically).
    // When in that special state though, we don't want to damage these entities further (which might have weird
    // side effects, like the controller vibrating on "damage" when the guy is already dead...)
    //
    if entity.health <= 0 return false;

    if entity.entity_kind == .Guy {
        increase_player_statistic(server, entity.pid, .Damage_Taken, cast(s64) min(entity.health, immediate_damage));
    }

    entity.damaged_this_frame = true;
    entity.health = max(entity.health - immediate_damage, 0);
    has_died := entity.health <= 0;

    //
    // Send information about the entity health to all clients
    //
    msg := make_message(Entity_Health_Message);
    msg.entity_health.entity_pid = entity.pid;
    msg.entity_health.new_health = entity.health;
    array_add(*server.outgoing_messages, msg);

    return has_died;
}

kill_entity :: (server: *Server, entity: *Entity, killer: *Guy) {
    item_drop: Item_Kind = .Count;

    if entity.entity_kind == {
      case .Mirror;
        remove_entity(server, entity);
        item_drop = .Shard;

      case .Rock;
        remove_entity(server, entity);
        item_drop = .Stone;
        increment_player_statistic(server, killer.pid, .Resources_Mined);

      case .Coal;
        remove_entity(server, entity);
        item_drop = .Coal;
        increment_player_statistic(server, killer.pid, .Resources_Mined);

      case .Crystal;
        remove_entity(server, entity);
        item_drop = .Shard;
        increment_player_statistic(server, killer.pid, .Resources_Mined);

      case .Guy;
        guy := down(entity, Guy);
        switch_guy_state(server, guy, .Dead);
        increment_player_statistic(server, guy.pid, .Deaths);

      case .Frog, .Goblin, .Slime;
        remove_entity(server, entity);
        
        random := random_f32_zero_to_one(*server.entity_random);

        t := (cast(f32) server.current_section_index / cast(f32) COIN_DROP_CHANCE_POINT_SECTION_INDEX);
        chance := COIN_DROP_CHANCE[server.game_mode][1] * t + COIN_DROP_CHANCE[server.game_mode][0] * (1 - t);

        if random < chance {
            item_drop = .Coin;
        }

        increment_global_statistic(server, .Monsters_Killed);
        
      case;
        remove_entity(server, entity);
    }

    if item_drop != .Count then try_to_place_item(server, entity.physical_position, item_drop, null, killer);
}

damage_and_maybe_kill_entity :: (server: *Server, entity: *Entity, immediate_damage: f32) {
    if damage_entity(server, entity, immediate_damage) {
        kill_entity(server, entity, null);
    }
}

remove_if_in_lava :: (server: *Server, entity: *Entity) {
    is_on_lava := find_entity_of_kind_at_position(server, .Lava, entity.physical_position) != null;
    if is_on_lava remove_entity(server, entity);
}

damage_and_maybe_kill_if_in_lava :: (server: *Server, entity: *Entity) {
    is_on_lava := find_entity_of_kind_at_position(server, .Lava, entity.physical_position) != null;

    if is_on_lava damage_and_maybe_kill_entity(server, entity, server.tick_time * LAVA_DPS);
}

damage_and_maybe_kill_if_in_light :: (server: *Server, entity: *Entity) -> bool {
    lit_up, emitter, direction := is_emitter_beam_at(server, entity.physical_position);
    if lit_up {
        damage_and_maybe_kill_entity(server, entity, BEAM_DPS * server.tick_time);
    }
    return lit_up;
}

set_entity_health :: (server: *Server, entity: *Entity, health: f32) {
    previous := entity.health;
    entity.health = clamp(health, 0, DEFAULT_ENTITY_HEALTH[entity.entity_kind]);

    if previous != entity.health {
        msg := make_message(Entity_Health_Message);
        msg.entity_health.entity_pid = entity.pid;
        msg.entity_health.new_health = entity.health;
        array_add(*server.outgoing_messages, msg);
    }
}



/* --------------------------------------------- Position Queries --------------------------------------------- */

find_any_entity_at_position :: (server: *Server, position: v2i) -> *Entity {
    found_entity: *Entity = null;
    
    for i := 0; i < server.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.all_entities, i);
        if !occupied || entity.marked_for_removal || (entity.entity_flags & .Disabled_Temporarily) continue;
        if entity.physical_position.x != position.x || entity.physical_position.y != position.y continue;
        if found_entity && DEFAULT_ENTITY_VISUAL_DEPTH[entity.entity_kind] <= DEFAULT_ENTITY_VISUAL_DEPTH[found_entity.entity_kind] continue;

        found_entity = entity;        
    }
    
    return found_entity;
}

find_entity_of_kind_at_position :: (server: *Server, kind: Entity_Kind, position: v2i) -> *Entity {
    for i := 0; i < server.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.all_entities, i);
        if !occupied || entity.marked_for_removal || (entity.entity_flags & .Disabled_Temporarily) continue;
        if entity.entity_kind != kind || entity.physical_position.x != position.x || entity.physical_position.y != position.y continue;

        return entity;
    }
    
    return null;
}

find_entity_with_flags_at_position :: (server: *Server, flags: Entity_Flags, position: v2i) -> *Entity {
    for i := 0; i < server.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.all_entities, i);
        if !occupied || entity.marked_for_removal || (entity.entity_flags & .Disabled_Temporarily) continue;
        if (entity.entity_flags & flags) != flags || entity.physical_position.x != position.x || entity.physical_position.y != position.y continue;

        return entity;
    }
    
    return null;
}

find_nearest_alive_guy :: (server: *Server, position: v2i) -> *Guy, s32 {
    nearest_distance := MAX_S32;
    nearest_guy: *Guy = null;

    for i := 0; i < server.guys.slot_count; ++i {
        guy, occupied := index_bucket_array(*server.guys, i);
        if !occupied || guy.marked_for_removal || (guy.entity_flags & .Disabled_Temporarily) || guy.state == .Dead continue;

        distance := abs(position.x - guy.physical_position.x) + abs(position.y - guy.physical_position.y);
        if distance < nearest_distance {
            nearest_guy      = guy;
            nearest_distance = distance;
        }
    }
    
    return nearest_guy, nearest_distance;
}

find_nearest_entity_of_kind :: (server: *Server, kind: Entity_Kind, position: v2i) -> *Entity, s32 {
    nearest_distance := MAX_S32;
    nearest_entity: *Entity = null;

    for i := 0; i < server.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.all_entities, i);
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


/* ---------------------------------------------- Entity Movement --------------------------------------------- */

update_physical_location :: (server: *Server, entity: *Entity, position: v2i, rotation: Direction) {
    something_changed := position.x != entity.physical_position.x || position.y != entity.physical_position.y || rotation != entity.physical_rotation;

    if something_changed {
        if entity.entity_kind == .Guy {
            guy := down(entity, Guy);
            
            if #complete guy.state == {
              case .Dead, .Idle, .Carrying;
              case .Digging, .Resurrecting; switch_guy_state(server, guy, .Idle);
            }

            guy.seconds_since_last_move = 0;
        }

        maybe_move_blocker(*server.lightmap, entity, position);

        entity.physical_position = position;
        entity.physical_rotation = rotation;

        msg := make_message(Move_Entity_Message);
        msg.move_entity.entity_pid = entity.pid;
        msg.move_entity.position = entity.physical_position;
        msg.move_entity.rotation = entity.physical_rotation;
        array_add(*server.outgoing_messages, msg);
    }
}

can_move_to_position :: (server: *Server, entity: *Entity, position: v2i, strength: s64) -> bool {
    move_delta := v2i.{ position.x - entity.physical_position.x, position.y - entity.physical_position.y };
    if move_delta.x != 0 || move_delta.y != 0 {
        return recursive_move_check(server, entity, move_delta, strength);
    } else {
        return false;
    }
}

move_to_position :: (server: *Server, entity: *Entity, position: v2i) {
    move_delta := v2i.{ position.x - entity.physical_position.x, position.y - entity.physical_position.y };
    if move_delta.x != 0 || move_delta.y != 0 {
        recursive_move(server, entity, move_delta);
    }
}

move_and_rotate_to_position :: (server: *Server, entity: *Entity, position: v2i) {
    move_delta := v2i.{ position.x - entity.physical_position.x, position.y - entity.physical_position.y };
    if move_delta.x != 0 || move_delta.y != 0 {
        entity.physical_rotation = direction_from_vector(move_delta);
        recursive_move(server, entity, move_delta);
    }
}



/* ----------------------------------------------- Entity Logic ----------------------------------------------- */

switch_guy_state :: (server: *Server, guy: *Guy, state: Guy_State) {
    if guy.state != state {
        guy.state = state;
        broadcast_guy_state(server, guy);
    }
}

take_item_from_hand :: (server: *Server, guy: *Guy) {
    assert(guy.state == .Carrying && guy.carrying_item != .Count, "You shouldn't call take_item_from_hand if a guy isn't carrying anything.");
    guy.state = .Idle;
    guy.carrying_item = .Count;
    broadcast_guy_state(server, guy);
}

put_item_in_hand :: (server: *Server, guy: *Guy, kind: Item_Kind) {
    assert(guy.state != .Carrying && guy.carrying_item == .Count, "You shouldn't call put_item_in_hand if a player already holds an item.");
    guy.state = .Carrying;
    guy.carrying_item = kind;
    broadcast_guy_state(server, guy);    
}

start_strength_effect :: (server: *Server, guy: *Guy) {
    guy.strength_t = STRENGTH_POTION_TIME;
    broadcast_guy_state(server, guy);
}

update_guy :: (server: *Server, guy: *Guy) {
    previous_target_position := guy.target_position;
    look_vector := vector_from_direction(guy.physical_rotation);
    guy.target_position = .{ guy.physical_position.x + look_vector.x, guy.physical_position.y + look_vector.y };
    if previous_target_position.x != guy.target_position.x || previous_target_position.y != guy.target_position.y {
        broadcast_guy_state(server, guy);
    }

    if guy.strength_t > 0 guy.strength_t -= server.tick_time;

    guy.seconds_since_last_move += server.tick_time;

    if guy.state == {
      case .Digging;
        target_entity := find_entity_with_flags_at_position(server, .Diggable, guy.target_position); // This target entity might change (or become null) when the guy rotates because of player input, or the entity is destructed by someone else...

        if !target_entity {
            switch_guy_state(server, guy, .Idle);
            break;
        }
        
        damage := GUY_DPS;

        if guy.strength_t > 0 damage *= STRENGTH_POTION_FACTOR;

        if damage_entity(server, target_entity, damage * server.tick_time) {
            switch_guy_state(server, guy, .Idle);
            kill_entity(server, target_entity, guy);
        }

      case .Carrying;
        if guy.carrying_item == .Torch {
            guy.carrying_item_data.torch_time_left_in_seconds -= server.tick_time;
            if guy.carrying_item_data.torch_time_left_in_seconds <= 0 {
                take_item_from_hand(server, guy);
            }
        }

      case .Resurrecting;
        guy.resurrection_t += server.tick_time / RESURRECTION_TIME;

        if guy.resurrection_t >= 1 {
            other_entity := get_entity(server, guy.resurrection_pid);
            if other_entity {
                other_guy := down(other_entity, Guy);

                if other_guy.carrying_item != .Count {
                    put_item_in_hand(server, other_guy, other_guy.carrying_item);
                } else {
                    switch_guy_state(server, other_guy, .Idle);
                }


                set_entity_health(server, other_guy, HEALTH_PER_HEART);
                increment_player_statistic(server, guy.pid, .Resurrections);
            }

            switch_guy_state(server, guy, .Idle);
        } else {
            broadcast_guy_state(server, guy); // Update the resurrection time
        }
    }

    if server.current_biome == .Lava_Lake && guy.seconds_since_last_move >= LAVA_LAKE_SINK_TIME && 
            guy.physical_position.x >= server.current_section[0] && guy.physical_position.x <= server.current_section[1] &&
            !find_entity_of_kind_at_position(server, .Lava, guy.physical_position) {
        create_entity(server, .Lava, guy.physical_position, DEFAULT_ENTITY_ROTATION[.Lava]);
    }

    damage_and_maybe_kill_if_in_lava(server, guy);
}

set_emitter_state :: (server: *Server, emitter: *Emitter, state: Emitter_State, charge: f32) {
    default_charge := clamp(charge, 0, EMITTER_MAX_BASE_CHARGE[server.game_mode]);
    overcharge := max(charge - EMITTER_MAX_BASE_CHARGE[server.game_mode], 0) * 0.5;
    new_charge := default_charge + overcharge;

    something_changed := emitter.state != state || emitter.current_charge != new_charge;

    if something_changed {
        emitter.state = state;
        emitter.current_charge = new_charge;

        msg := make_message(Emitter_State_Message);
        msg.emitter_state.entity_pid = emitter.pid;
        msg.emitter_state.state      = emitter.state;
        msg.emitter_state.current_charge = emitter.current_charge;
        array_add(*server.outgoing_messages, msg);
    }
}

update_powered_emitter :: (server: *Server, emitter: *Emitter) {
    clear_beam_data(*emitter.beam_data);

    if emitter.state != .Off && emitter.current_charge > 0 {
        recalculate_beam(server, *emitter.beam_data, emitter.physical_position, emitter.physical_rotation, true, MAX_S64);
    }

    emitter.current_charge = max(emitter.current_charge - server.tick_time, 0);
}

update_off_emitter :: (server: *Server, emitter: *Emitter) {
    if emitter.state == .Off {
        is_beam, other_emitter, incoming_direction := is_emitter_beam_at(server, emitter.physical_position);

        delta_charge := server.tick_time * (EMITTER_MAX_BASE_CHARGE[server.game_mode] / EMITTER_TIME_TO_POWER_UP);
        sign: f32 = ifx (is_beam && incoming_direction == emitter.physical_rotation) then 1 else -1;
        set_emitter_state(server, emitter, .Off, emitter.current_charge + delta_charge * sign);
    }
}

set_torch_time_left_in_seconds :: (server: *Server, torch: *Torch, ttl: f32) {
    // The client does a predicition on this value, but if it changes abruptly (such as when creating a new torch
    // with a non-default TTL), then we need to inform the client about that.
    torch.time_left_in_seconds = ttl;

    msg := make_message(Torch_State_Message);
    msg.torch_state.entity_pid = torch.pid;
    msg.torch_state.time_left_in_seconds = ttl;
    array_add(*server.outgoing_messages, msg);
}

update_torch :: (server: *Server, torch: *Torch) {
    torch.time_left_in_seconds -= server.tick_time;
    if torch.time_left_in_seconds <= 0 then remove_entity(server, torch);
}

update_slab :: (server: *Server, slab: *Slab) {
    slab.time_left_in_seconds -= server.tick_time;

    if slab.time_left_in_seconds <= 0 {
        lava_position := slab.physical_position;
        
        remove_entity(server, slab);
        create_entity(server, .Lava, lava_position, .North);
    }
}

update_frog :: (server: *Server, frog: *Frog) {
    switch_state :: (server: *Server, frog: *Frog, new_state: Frog_State) {
        if frog.state == new_state return;

        frog.state = new_state;
        frog.state_t = 0;
        
        msg := make_message(Frog_State_Message);
        msg.frog_state.entity_pid = frog.pid;
        msg.frog_state.state = frog.state;
        array_add(*server.outgoing_messages, msg);
    }

    clear_beam_data(*frog.beam_data);

    damage_and_maybe_kill_if_in_light(server, frog);
    damage_and_maybe_kill_if_in_lava(server, frog);

    if #complete frog.state == {
      case .Idle;
        target_guy, target_distance := find_target_guy_for_npc(server, frog.physical_position);
        
        if target_guy {
            delta := v2i.{ target_guy.physical_position.x - frog.physical_position.x, target_guy.physical_position.y - frog.physical_position.y };

            rotation := direction_from_vector(delta);
            update_physical_location(server, frog, frog.physical_position, rotation);

            if target_distance <= FROG_BEAM_LENGTH {
                // The target guy is actually in reach for the frog's beam. Since we are
                // checking for line-of-sight, we know the beam can actually reach the guy
                // like this.
                frog.damaged_entities_this_attack = .[ INVALID_PID ];
                switch_state(server, frog, .Attacking);
            }
        }

      case .Attacking;
        recalculate_beam(server, *frog.beam_data, frog.physical_position, frog.physical_rotation, false, FROG_BEAM_LENGTH);

        for i := 0; i < frog.beam_data.fields.count; ++i {
            field := array_get(*frog.beam_data.fields, i);
            entity := find_entity_with_flags_at_position(server, .Living, field);
            if !entity continue;
            
            already_damaged := false;
            first_empty_slot: s64 = -1;
            for i := 0; i < frog.damaged_entities_this_attack.Capacity; ++i {
                if frog.damaged_entities_this_attack[i] == INVALID_PID {
                    first_empty_slot = i;
                    break;
                } else if frog.damaged_entities_this_attack[i] == entity.pid {
                    already_damaged = true;
                    break;
                }
            }
            
            if !already_damaged {
                damage_and_maybe_kill_entity(server, entity, HEALTH_PER_HEART);
                if first_empty_slot != -1 {
                    frog.damaged_entities_this_attack[first_empty_slot] = entity.pid;
                } else {
                    logprint(.Warning, "A frog ran out of available slots in the damaged_entities_this_attack array.");
                }
            }
        }
        
        if frog.state_t >= FROG_ATTACK_TIME {
            switch_state(server, frog, .Recovering);
        }
        
      case .Recovering;
        if frog.state_t >= FROG_RECOVER_TIME {
            switch_state(server, frog, .Idle);
        }
    }

    frog.state_t += server.tick_time;
}

update_goblin :: (server: *Server, goblin: *Goblin) {
    switch_state :: (server: *Server, goblin: *Goblin, new_state: Goblin_State) {
        if goblin.state == new_state return;

        goblin.state = new_state;
        goblin.state_t = 0;
        
        msg := make_message(Goblin_State_Message);
        msg.goblin_state.entity_pid = goblin.pid;
        msg.goblin_state.state = goblin.state;
        array_add(*server.outgoing_messages, msg);
    }

    damage_and_maybe_kill_if_in_light(server, goblin);
    damage_and_maybe_kill_if_in_lava(server, goblin);

    if #complete goblin.state == {
      case .Idle;
        target_guy, target_distance := find_target_guy_for_npc(server, goblin.physical_position);

        if target_guy {
            delta := v2i.{ target_guy.physical_position.x - goblin.physical_position.x, target_guy.physical_position.y - goblin.physical_position.y };

            rotation := direction_from_vector(delta);
            update_physical_location(server, goblin, goblin.physical_position, rotation);

            if target_distance == 1 {
                damage_and_maybe_kill_entity(server, target_guy, HEALTH_PER_HEART);
                switch_state(server, goblin, .Attacking);
            }
        }

      case .Attacking;
        if goblin.state_t >= GOBLIN_ATTACK_TIME {
            switch_state(server, goblin, .Recovering);
        }

      case .Recovering;
        if goblin.state_t >= GOBLIN_RECOVER_TIME {
            switch_state(server, goblin, .Idle);
        }
    }

    goblin.state_t += server.tick_time;
}

update_slime :: (server: *Server, slime: *Slime) {
    switch_state :: (server: *Server, slime: *Slime, new_state: Slime_State) {
        if slime.state == new_state return;

        slime.state = new_state;

        if slime.state == {
          case .Hiding; slime.time_in_hiding = 0; bitfield_add(*slime.entity_flags, Entity_Flags.Disabled_Temporarily);
          case; bitfield_remove(*slime.entity_flags, Entity_Flags.Disabled_Temporarily);
        }
        
        msg := make_message(Slime_State_Message);
        msg.slime_state.entity_pid = slime.pid;
        msg.slime_state.state = slime.state;
        array_add(*server.outgoing_messages, msg);
    }

    lit_up := false;

    if slime.state != .Hiding {
        lit_up = damage_and_maybe_kill_if_in_light(server, slime);
        damage_and_maybe_kill_if_in_lava(server, slime);
    }
        
    move_interval := ifx slime.state == .Fleeing then SLIME_FLEEING_MOVE_INTERVAL else SLIME_IDLE_MOVE_INTERVAL;

    if lit_up move_interval *= 2; // Move slower when currently in the light for easier killing...    

    if slime.time_since_last_move >= move_interval {
        //
        // Find the target position for this move
        //
        target_position: v2i = slime.physical_position;
        target_hole, distance_to_hole := find_nearest_entity_of_kind(server, .Slime_Hole, slime.physical_position);

        assert(target_hole != null, "A slime currently requires a slime hole to exist.");
        
        if slime.state == {
          case .Idle;
            target_item_stack, distance_to_item_stack := find_nearest_entity_of_kind(server, .Item_Stack, slime.physical_position);

            if target_item_stack != null && distance_to_item_stack == 0 {
                take_item_from_stack(server, down(target_item_stack, Item_Stack));
                switch_state(server, slime, .Fleeing);
            } else if target_item_stack != null && abs(target_item_stack.physical_position.x - target_hole.physical_position.x) <= SLIME_ACTION_RADIUS {
                // We want to limit the slime's action radius to be around the slime hole, so that they don't
                // run over the entire map to steal your items - that's just annoying.
                target_position = target_item_stack.physical_position;
            } else {
                direction := random_u64_in(*server.entity_random, 0, Direction.Count);
                for i := 0; i < Direction.Count; ++i {
                    random_vector := vector_from_direction((direction + i) % Direction.Count);
                    random_position := v2i.{ slime.physical_position.x + random_vector.x, slime.physical_position.y + random_vector.y };
                    is_emitter_field, emitter, emitter_field_direction := is_emitter_beam_at(server, random_position);
                    if !is_emitter_field && abs(random_position.x - target_hole.physical_position.x) <= SLIME_ACTION_RADIUS && can_move_to_position(server, slime, random_position, 0) {
                        // Again we want to limit the slime's action radius to be around the slime hole
                        target_position = random_position;
                        break;
                    }
                }
            }

            nearest_guy, distance_to_nearest_guy := find_nearest_entity_of_kind(server, .Guy, slime.physical_position);
            if distance_to_nearest_guy <= SLIME_SCARING_DISTANCE {
                target_position = target_hole.physical_position;
                switch_state(server, slime, .Fleeing);
            }
            
          case .Fleeing;
            target_position = target_hole.physical_position;

            if distance_to_hole == 0 {
                switch_state(server, slime, .Hiding);
            }

          case .Hiding;
            // Make sure that the slime hole isn't blocked by some moveable entity, otherwise the slime can't
            // physically get out of the hole
            hole_is_blocked := find_entity_with_flags_at_position(server, .Blocks_Movement, slime.physical_position);
            nearest_guy, distance_to_nearest_guy := find_nearest_entity_of_kind(server, .Guy, slime.physical_position);

            if !hole_is_blocked && slime.time_in_hiding > SLIME_MIN_TIME_IN_HIDING && distance_to_nearest_guy > SLIME_SCARING_DISTANCE + 1 {
                switch_state(server, slime, .Idle);
            }

            slime.time_in_hiding += server.tick_time;
        }

        //
        // Actually execute the move
        //
        light_tile_cost := ifx slime.state == .Fleeing then 1 else 10;
        next_step, found_path := find_next_step_on_path(server, .Avoid_Collisions, light_tile_cost, slime.physical_position, target_position);

        if found_path && can_move_to_position(server, slime, next_step, 0) {
            move_and_rotate_to_position(server, slime, next_step);
            slime.time_since_last_move = 0;
        }
    }
        
    slime.time_since_last_move += server.tick_time;
}

update_void_eye :: (server: *Server, eye: *Void_Eye) {
    eye.time_since_spawn += server.tick_time;
    if eye.time_since_spawn < VOID_EYE_SPAWN_TIME {
        return;
    }

    target_guy, distance_to_target := find_nearest_alive_guy(server, eye.physical_position);
    move_target: v2i = eye.physical_position;

    is_chasing_player := false;
    active_move_interval: f32 = ---;

    if target_guy != null && distance_to_target <= VOID_EYE_TRACKING_DISTANCE {
        if distance_to_target == 0 {
            // Is already on the player, damage him
            damage_and_maybe_kill_entity(server, target_guy, VOID_EYE_DPS_ON_PLAYER * server.tick_time);
            is_chasing_player = true;
        } else {
            // Try to find a path towards the player
            move_target, is_chasing_player = find_next_step_on_path(server, .Restrict_To_Shadows, 0, eye.physical_position, target_guy.physical_position);
        }

        active_move_interval = VOID_EYE_CHASING_MOVE_INTERVAL;
    }

    if !is_chasing_player {
        //
        // Move around randomly during idle
        //
        direction := random_u64_in(*server.entity_random, 0, Direction.Count);
        for i := 0; i < Direction.Count; ++i {
            random_vector := vector_from_direction((direction + i) % Direction.Count);
            random_position := v2i.{ eye.physical_position.x + random_vector.x, eye.physical_position.y + random_vector.y };
            if position_in_bounds(server, random_position) && query_shadow(*server.lightmap, random_position) != NO_SHADOW {
                move_target = random_position;
                break;
            }
        }

        active_move_interval = random_f32_normal_distribution(*server.entity_random, VOID_EYE_IDLE_MOVE_INTERVAL_BASE, VOID_EYE_IDLE_MOVE_INTERVAL_STDDEV);
    }

    if eye.time_since_last_move > active_move_interval && (move_target.x != eye.physical_position.x || move_target.y != eye.physical_position.y) {
        move_and_rotate_to_position(server, eye, move_target);
        eye.time_since_last_move = 0;
    }

    eye.time_since_last_move += server.tick_time;


    if distance_to_target == 0 {
        switch_void_eye_state(server, eye, .Attacking);
    } else if is_chasing_player {
        switch_void_eye_state(server, eye, .Chasing);
    } else {
        switch_void_eye_state(server, eye, .Idle);
    }
}

update_trader :: (server: *Server, trader: *Entity) {
    damage_and_maybe_kill_if_in_light(server, trader);
    damage_and_maybe_kill_if_in_lava(server, trader);
    rotate_npc_towards_target_guy(server, trader);
}

take_item_from_stack :: (server: *Server, stack: *Item_Stack) -> Item_Kind {
    --stack.count;

    if stack.count {
        msg := make_message(Item_Stack_State_Message);
        msg.item_stack_state.entity_pid = stack.pid;
        msg.item_stack_state.item_kind  = stack.item_kind;
        msg.item_stack_state.count      = stack.count;
        array_add(*server.outgoing_messages, msg);
    } else {
        remove_entity(server, stack);
    }

    return stack.item_kind;
}

update_visual_chest_state :: (server: *Server, chest: *Chest, visually_open: bool) {
    visually_open_before := chest.visually_open_counter > 0;

    if visually_open {
        ++chest.visually_open_counter;
    } else {
        --chest.visually_open_counter;
    }

    if chest.visually_open_counter > 0 != visually_open_before then broadcast_chest_inventory(server, chest); // Notify the clients that the visual openess of the chest has changed...
}

broadcast_chest_inventory :: (server: *Server, chest: *Chest) {
    msg := make_message(Chest_State_Message);
    msg.chest_state.entity_pid = chest.pid;
    msg.chest_state.inventory = chest.inventory;
    msg.chest_state.visually_open = chest.visually_open_counter > 0;
    array_add(*server.outgoing_messages, msg);
}



#file_scope

recursive_move_check :: (server: *Server, entity: *Entity, move_delta: v2i, strength: s64) -> bool {
    assert(move_delta.x != 0 || move_delta.y != 0, "Recursive move check with a delta of 0 leads to an infinite loop!");

    original_entity_flags := entity.entity_flags;
    position := v2i.{ entity.physical_position.x + move_delta.x, entity.physical_position.y + move_delta.y };

    // Make sure the position is in bounds of the world
    if !position_in_bounds(server, position) then return false;

    // Make sure the space is unoccupied or can be moved away
    pushable_entity: *Entity = null;
    blocking_entity: *Entity = null;

    for i := 0; i < server.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.all_entities, i);
        if !occupied || entity.physical_position.x != position.x || entity.physical_position.y != position.y || (entity.entity_flags & .Disabled_Temporarily) continue;

        if entity.entity_flags & .Pushable {
            pushable_entity = entity;
        } else if entity.entity_flags & .Blocks_Movement {
            blocking_entity = entity;
            break;
        } else if !(original_entity_flags & .Living) && (entity.entity_flags & .Blocks_Non_Living_Movement) {
            blocking_entity = entity;
            break;
        }
    }

    if blocking_entity return false;
    if pushable_entity && (strength <= 0 || !recursive_move_check(server, pushable_entity, move_delta, strength - 1)) return false;

    return true;
}

recursive_move :: (server: *Server, entity: *Entity, move_delta: v2i) {
    assert(move_delta.x != 0 || move_delta.y != 0, "Recursive move with a delta of 0 leads to an infinite loop!");

    position := v2i.{ entity.physical_position.x + move_delta.x, entity.physical_position.y + move_delta.y };

    if DEFAULT_ENTITY_FLAGS[entity.entity_kind] & .Blocks_Movement {
        collision := find_entity_with_flags_at_position(server, .Blocks_Movement, position);
        if collision recursive_move(server, collision, move_delta);
    }

    update_physical_location(server, entity, .{ entity.physical_position.x + move_delta.x, entity.physical_position.y + move_delta.y }, entity.physical_rotation);
}

clear_beam_data :: (data: *Beam_Data) {
    array_clear_without_deallocation(*data.fields);
    data.fields.allocator = *temp;
}

broadcast_guy_state :: (server: *Server, guy: *Guy) {
    msg := make_message(Guy_State_Message);
    msg.guy_state.entity_pid      = guy.pid;
    msg.guy_state.state           = guy.state;
    msg.guy_state.target_position = guy.target_position;
    msg.guy_state.carrying_item   = guy.carrying_item;
    msg.guy_state.strength_t      = guy.strength_t;
    array_add(*server.outgoing_messages, msg);
}

switch_void_eye_state :: (server: *Server, eye: *Void_Eye, new_state: Void_Eye_State) {
    if eye.state == new_state return;

    eye.state = new_state;

    msg := make_message(Void_Eye_State_Message);
    msg.void_eye_state.entity_pid = eye.pid;
    msg.void_eye_state.state = new_state;
    array_add(*server.outgoing_messages, msg);
}

find_target_guy_for_npc :: (server: *Server, npc_position: v2i) -> *Guy, s32 {
    target_guy: *Guy = null;
    target_distance: s32 = MAX_S32;

    for i := 0; i < server.guys.slot_count; ++i {
        guy, occupied := index_bucket_array(*server.guys, i);
        if !occupied|| guy.marked_for_removal || (guy.entity_flags & .Disabled_Temporarily) || guy.state == .Dead continue;
        
        if !has_line_of_sight(server, npc_position, guy.physical_position) continue;
        
        distance := abs(guy.physical_position.x - npc_position.x) + abs(guy.physical_position.y - npc_position.y);
        if distance < target_distance {
            target_guy = guy;
            target_distance = distance;
        }
    }

    return target_guy, target_distance;
}

rotate_npc_towards_target_guy :: (server: *Server, npc: *Entity) {
    target_guy, target_distance := find_target_guy_for_npc(server, npc.physical_position);

    if target_guy {
        delta := v2i.{ target_guy.physical_position.x - npc.physical_position.x, target_guy.physical_position.y - npc.physical_position.y };
        rotation := direction_from_vector(delta);
        update_physical_location(server, npc, npc.physical_position, rotation);
    }
}

has_line_of_sight :: (server: *Server, source: v2i, target: v2i) -> bool {
    delta := v2i.{ target.x - source.x, target.y - source.y };

    if delta.x == 0 && delta.y == 0 return true; 
    if delta.x != 0 && delta.y != 0 return false; // There's no clean line between the target and the entity

    // Normalize the delta so that one coordinate has magnitude 1, and the other coordinate has
    // magnitude 0.
    delta.x /= abs(delta.x + delta.y);
    delta.y /= abs(delta.x + delta.y);
    
    position := v2i.{ source.x + delta.x, source.y + delta.y };

    while position.x != target.x || position.y != target.y {
        if find_entity_with_flags_at_position(server, .Blocks_Line_Of_Sight, position) return false;
        position.x += delta.x;
        position.y += delta.y;
    }
    
    return true;
}

recalculate_beam :: (server: *Server, beam: *Beam_Data, position: v2i, direction: Direction, include_initial_position: bool, max_length: s64) {
    if include_initial_position then array_add(*beam.fields, Beam_Data.Field.{ position, direction });

    while beam.fields.count < max_length {
        vector := vector_from_direction(direction);
        position.x += vector.x;
        position.y += vector.y;
        if !position_in_bounds(server, position) break;
        
        blocking := find_entity_with_flags_at_position(server, .Blocks_Beam, position);
        
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
