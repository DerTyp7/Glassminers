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
    
    resurrection_pid: Pid = INVALID_PID;
    resurrection_t: f32   = 0; // Between 0 and 1

    strength_t: f32 = 0;
    
    received_input: Guy_Input_Message = ---;
    received_input_this_tick: bool = false;
}

Emitter :: struct {
    #using entity : *Entity  = ---;
    beam_data: Beam_Data = ---;
    time_left_in_seconds: f32 = EMITTER_MAX_TIME;
}

Receiver :: struct {
    #using entity : *Entity  = ---;
    progress_time_in_seconds: f32;
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
    state: Frog_State;
    state_t: f32; // How much time this frog spent in the current state
    damaged_entities_this_attack: [3]Pid; // We don't want to have to dynamically allocate this, because then we'd also have to free it...
}

Goblin :: struct {
    #using entity : *Entity = ---;
    state: Goblin_State;
    state_t: f32; // How much time this goblin spent in the current state
}

Entity_Manager :: struct {
    pid_counter:  Pid;
    pid_lookup:   Probed_Hash_Table(Pid, *Entity);
    all_entities: Bucket_Array(Entity);
    guys:         Bucket_Array(Guy);
    emitters:     Bucket_Array(Emitter);
    receivers:    Bucket_Array(Receiver);
    slabs:        Bucket_Array(Slab);
    item_stacks:  Bucket_Array(Item_Stack);
    frogs:        Bucket_Array(Frog);
    goblins:      Bucket_Array(Goblin);
}



//
// Entity Manager
//

create_entity_manager :: (server: *Server) {
    server.pid_counter = 0;
    server.pid_lookup.allocator = *server.world_allocator;
    probed_hash_table_create(*server.pid_lookup, 128, pid_hash, pids_equal);
    create_bucket_array(*server.all_entities, *server.world_allocator);
    create_bucket_array(*server.guys, *server.world_allocator);
    create_bucket_array(*server.emitters, *server.world_allocator);
    create_bucket_array(*server.receivers, *server.world_allocator);
    create_bucket_array(*server.slabs, *server.world_allocator);
    create_bucket_array(*server.item_stacks, *server.world_allocator);
    create_bucket_array(*server.frogs, *server.world_allocator);
    create_bucket_array(*server.goblins, *server.world_allocator);
}

destroy_entity_manager :: (server: *Server) {
    probed_hash_table_destroy(*server.pid_lookup);
    destroy_bucket_array(*server.all_entities);
    destroy_bucket_array(*server.guys);
    destroy_bucket_array(*server.emitters);
    destroy_bucket_array(*server.receivers);
    destroy_bucket_array(*server.slabs);
    destroy_bucket_array(*server.item_stacks);
    destroy_bucket_array(*server.frogs);
    destroy_bucket_array(*server.goblins);
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
    entity.health             = ENTITY_DEFAULT_HEALTH[kind];
    entity.entity_flags       = ENTITY_DEFAULT_FLAGS[kind];
    entity.physical_rotation  = rotation;
    entity.physical_position  = position;

    probed_hash_table_add(*server.pid_lookup, pid, entity);
    
    if #complete entity.entity_kind == {
      case .Guy;        make_derived(entity, *server.guys);
      case .Emitter;    make_derived(entity, *server.emitters);
      case .Receiver;   make_derived(entity, *server.receivers);
      case .Slab;       make_derived(entity, *server.slabs);
      case .Item_Stack; make_derived(entity, *server.item_stacks);
      case .Frog;       make_derived(entity, *server.frogs);
      case .Goblin;     make_derived(entity, *server.goblins);
      case .Crystal, .Bedrock, .Mirror, .Rock, .Coal, .Lava, .Trader;
        entity.derived = null;
    }

    msg := make_message(Create_Entity_Message);
    msg.create_entity.entity_pid = entity.pid;
    msg.create_entity.kind       = entity.entity_kind;
    msg.create_entity.position   = entity.physical_position;
    msg.create_entity.rotation   = entity.physical_rotation;
    array_add(*server.outgoing_messages, msg);
    
    return entity;
}

get_entity :: (server: *Server, pid: Pid) -> *Entity {
    pointer := probed_hash_table_query(*server.pid_lookup, pid);
    assert(pointer != null, "Tried to get a non-existent entity.");
    entity := ~pointer;
    return entity;
}

physically_remove_all_marked_entities :: (server: *Server) {
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
    remove_deriveds(*server.receivers);
    remove_deriveds(*server.slabs);
    remove_deriveds(*server.item_stacks);
    remove_deriveds(*server.frogs);
    remove_deriveds(*server.goblins);

    for i := 0; i < server.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.all_entities, i);
        if occupied && entity.marked_for_removal {
            probed_hash_table_remove(*server.pid_lookup, entity.pid);
            remove_index_from_bucket_array(*server.all_entities, i);
        }
    }
}

damage_entity :: (server: *Server, entity: *Entity, immediate_damage: f32) -> bool {
    entity.health -= immediate_damage;
    entity.health = max(entity.health, 0);
    has_died := entity.health <= 0;

    //
    // Send information about the entity health to all clients
    //
    msg := make_message(Entity_Health_Message);
    msg.entity_health.entity_pid = entity.pid;
    msg.entity_health.current_health = entity.health;
    array_add(*server.outgoing_messages, msg);

    return has_died;
}

kill_entity :: (server: *Server, entity: *Entity, killer: *Guy) {
    if entity.entity_kind == {
      case .Guy;
        guy := down(entity, Guy);
        guy.state = .Dead;

      case .Crystal;
        remove_entity(server, entity);
        try_to_put_item(server, entity.physical_position, .Shard, killer);

      case .Rock;
        remove_entity(server, entity);
        try_to_put_item(server, entity.physical_position, .Stone, killer);

      case .Coal;
        remove_entity(server, entity);
        try_to_put_item(server, entity.physical_position, .Coal, killer);

      case .Mirror;
        remove_entity(server, entity);
        try_to_put_item(server, entity.physical_position, .Shard, killer);

      case .Frog, .Goblin;
        remove_entity(server, entity);
        try_to_put_item(server, entity.physical_position, .Coin, killer);
        
      case;
        remove_entity(server, entity);
    }
}

damage_and_maybe_kill_entity :: (server: *Server, entity: *Entity, immediate_damage: f32) {
    if damage_entity(server, entity, immediate_damage) {
        kill_entity(server, entity, null);
    }
}

damage_and_maybe_kill_if_in_lava :: (server: *Server, entity: *Entity) {
    is_on_lava := find_entity_of_kind_at_position(server, .Lava, entity.physical_position) != null;

    if is_on_lava damage_and_maybe_kill_entity(server, entity, server.tick_time * LAVA_DPS);
}

set_entity_health :: (server: *Server, entity: *Entity, health: f32) {
    entity.health = health;
    msg := make_message(Entity_Health_Message);
    msg.entity_health.entity_pid = entity.pid;
    msg.entity_health.current_health = entity.health;
    array_add(*server.outgoing_messages, msg);
}

remove_entity :: (server: *Server, entity: *Entity) {
    entity.marked_for_removal = true;
    msg := make_message(Destroy_Entity_Message);
    msg.destroy_entity.entity_pid = entity.pid;
    array_add(*server.outgoing_messages, msg);
}

find_any_entity_at_position :: (server: *Server, position: v2i) -> *Entity {
    found_entity: *Entity = null;
    
    for i := 0; i < server.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.all_entities, i);
        if occupied && !entity.marked_for_removal && entity.physical_position.x == position.x && entity.physical_position.y == position.y && (!found_entity || ENTITY_VISUAL_DEPTHS[entity.entity_kind] > ENTITY_VISUAL_DEPTHS[found_entity.entity_kind]) {
            found_entity = entity;
        }
    }
    
    return found_entity;
}

find_entity_of_kind_at_position :: (server: *Server, kind: Entity_Kind, position: v2i) -> *Entity {
    for i := 0; i < server.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.all_entities, i);
        if occupied && !entity.marked_for_removal && entity.entity_kind == kind && entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
}

find_entity_with_flags_at_position :: (server: *Server, flags: Entity_Flags, position: v2i) -> *Entity {
    for i := 0; i < server.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.all_entities, i);
        if occupied && !entity.marked_for_removal && (entity.entity_flags & flags) == flags && entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
}

update_physical_location :: (server: *Server, entity: *Entity, position: v2i, rotation: Direction) {
    something_changed := position.x != entity.physical_position.x || position.y != entity.physical_position.y || rotation != entity.physical_rotation;

    entity.physical_position = position;
    entity.physical_rotation = rotation;

    if something_changed {
        msg := make_message(Move_Entity_Message);
        msg.move_entity.entity_pid = entity.pid;
        msg.move_entity.position = entity.physical_position;
        msg.move_entity.rotation = entity.physical_rotation;
        array_add(*server.outgoing_messages, msg);
    }
}

position_in_bounds :: (server: *Server, position: v2i) -> bool {
    return position.x >= 0 && position.x < server.world_size.x && position.y >= 0 && position.y < server.world_size.y;
}

can_move_to_position :: (server: *Server, entity: *Entity, position: v2i, strength: s64) -> bool {
    move_delta := v2i.{ position.x - entity.physical_position.x, position.y - entity.physical_position.y };
    if move_delta.x != 0 || move_delta.y != 0 {
        return recursive_move_check(server, entity, move_delta, strength);
    } else {
        return true;
    }
}

move_to_position :: (server: *Server, entity: *Entity, position: v2i) {
    move_delta := v2i.{ position.x - entity.physical_position.x, position.y - entity.physical_position.y };
    if move_delta.x != 0 || move_delta.y != 0 {
        recursive_move(server, entity, move_delta);
    }
}



//
// Derived Types
//

update_guy :: (server: *Server, guy: *Guy) {
    look_vector := vector_from_direction(guy.physical_rotation);
    guy.target_position = .{ guy.physical_position.x + look_vector.x, guy.physical_position.y + look_vector.y };
    
    if guy.state == {
      case .Digging;
        target_entity := find_entity_with_flags_at_position(server, .Diggable, guy.target_position); // This target entity might change (or become null) when the guy rotates because of player input, or the entity is destructed by someone else...

        if !target_entity {
            guy.state = .Idle;
            break;
        }
        
        damage := GUY_DPS;

        if guy.strength_t > 0 damage *= STRENGTH_POTION_FACTOR;

        if damage_entity(server, target_entity, damage * server.tick_time) {
            guy.state = .Idle;
            kill_entity(server, target_entity, guy);
        }

      case .Resurrecting;
        guy.resurrection_t += server.tick_time / RESURRECTION_TIME;

        if guy.resurrection_t >= 1 {
            other_entity := get_entity(server, guy.resurrection_pid);
            if other_entity {
                other_guy := down(other_entity, Guy);
                other_guy.state = .Idle; // This might be one frame late, depending on which order 'guy' and 'other_guy' are in the guy list... But I'd say that's fine for now.
                set_entity_health(server, other_guy, HEALTH_PER_HEART);
            }

            guy.state = .Idle;
        }
    }

    if guy.strength_t > 0 guy.strength_t -= server.tick_time;

    damage_and_maybe_kill_if_in_lava(server, guy);
    
    //
    // Send out the new guy state
    // @NetworkTraffic: Only send this message if anything changed about the guy
    //
    msg := make_message(Guy_State_Message);
    msg.guy_state.entity_pid      = guy.pid;
    msg.guy_state.state           = guy.state;
    msg.guy_state.target_position = guy.target_position;
    msg.guy_state.carrying_item   = guy.carrying_item;
    msg.guy_state.strength_t      = guy.strength_t;
    array_add(*server.outgoing_messages, msg);
}

set_emitter_time_left :: (server: *Server, emitter: *Emitter, time_left_in_seconds: f32) {
    emitter.time_left_in_seconds = clamp(time_left_in_seconds, 0, EMITTER_MAX_TIME);
    msg := make_message(Emitter_State_Message);
    msg.emitter_state.entity_pid = emitter.pid;
    msg.emitter_state.time_left_in_seconds = emitter.time_left_in_seconds;
    array_add(*server.outgoing_messages, msg);
}

update_emitter :: (server: *Server, emitter: *Emitter) {
    clear_beam_data(*emitter.beam_data);
    
    if emitter.time_left_in_seconds > 0 {
        recalculate_beam(server, *emitter.beam_data, emitter.physical_position, emitter.physical_rotation, true, MAX_S64);
        emitter.time_left_in_seconds -= server.tick_time;
    }
}

update_receiver :: (server: *Server, receiver: *Receiver) {
    // @NetworkTraffic: Simple client-side predicition
    
    previous := receiver.progress_time_in_seconds;

    lit_up, incoming_direction := is_emitter_field_at(server, receiver.physical_position);
    if lit_up && incoming_direction == opposite_direction(receiver.physical_rotation) {
        receiver.progress_time_in_seconds = clamp(receiver.progress_time_in_seconds + server.tick_time, 0, RECEIVER_TIME_TO_CHARGE);
    } else {
        receiver.progress_time_in_seconds = clamp(receiver.progress_time_in_seconds - server.tick_time, 0, RECEIVER_TIME_TO_CHARGE);
    }

    if receiver.progress_time_in_seconds != previous {
        msg := make_message(Receiver_State_Message);
        msg.receiver_state.entity_pid = receiver.pid;
        msg.receiver_state.progress_time_in_seconds = receiver.progress_time_in_seconds;
        array_add(*server.outgoing_messages, msg);
    }
}

update_slab :: (server: *Server, slab: *Slab) {
    slab.time_left_in_seconds -= server.tick_time;

    if slab.time_left_in_seconds <= 0 {
        remove_entity(server, slab);
        create_entity(server, .Lava, slab.physical_position, .North);
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

    lit_up, _ := is_emitter_field_at(server, frog.physical_position);
    if lit_up {
        damage_and_maybe_kill_entity(server, frog, BEAM_DPS * server.tick_time);
    }

    damage_and_maybe_kill_if_in_lava(server, frog);

    if #complete frog.state == {
      case .Idle;
        target_guy, target_distance := find_target_guy_for_monster(server, frog.physical_position);
        
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

    lit_up, _ := is_emitter_field_at(server, goblin.physical_position);
    if lit_up {
        damage_and_maybe_kill_entity(server, goblin, BEAM_DPS * server.tick_time);
    }

    damage_and_maybe_kill_if_in_lava(server, goblin);

    if #complete goblin.state == {
      case .Idle;
        target_guy, target_distance := find_target_guy_for_monster(server, goblin.physical_position);

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

update_trader :: (server: *Server, entity: *Entity) {
    target_guy, target_distance := find_target_guy_for_monster(server, entity.physical_position);

    if target_guy {
        delta := v2i.{ target_guy.physical_position.x - entity.physical_position.x, target_guy.physical_position.y - entity.physical_position.y };
        rotation := direction_from_vector(delta);
        update_physical_location(server, entity, entity.physical_position, rotation);
    }    
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

// This will first try to put the item on the ground, and if that doesn't work it'll try to
// place the item inside the guy's hand.
try_to_put_item :: (server: *Server, target_position: v2i, kind: Item_Kind, target_guy: *Guy) -> bool {
    if !position_in_bounds(server, target_position) return false;

    success := false;

    collision := find_entity_with_flags_at_position(server, .Blocks_Move, target_position);
    stack_entity := find_entity_of_kind_at_position(server, .Item_Stack, target_position);

    if collision {
        success = false;
    } else if stack_entity {
        stack := down(stack_entity, Item_Stack);

        if stack.item_kind == kind {
            ++stack.count;

            msg := make_message(Item_Stack_State_Message);
            msg.item_stack_state.entity_pid = stack.pid;
            msg.item_stack_state.item_kind  = stack.item_kind;
            msg.item_stack_state.count      = stack.count;
            array_add(*server.outgoing_messages, msg);

            success = true;
        }
    } else {
        stack_entity = create_entity(server, .Item_Stack, target_position, .North);
        stack := down(stack_entity, Item_Stack);
        stack.item_kind = kind;
        stack.count = 1;

        msg := make_message(Item_Stack_State_Message);
        msg.item_stack_state.entity_pid = stack.pid;
        msg.item_stack_state.item_kind  = stack.item_kind;
        msg.item_stack_state.count      = stack.count;
        array_add(*server.outgoing_messages, msg);

        success = true;
    }

    if !success && target_guy && target_guy.state == .Idle {
        target_guy.state = .Carrying;
        target_guy.carrying_item = kind;
        success = true;
    }
    
    return success;
}

// This will first try to put the item inside the guy's hand, and if that doesn't work it'll try to
// place the item on the ground
try_to_give_item :: (server: *Server, guy: *Guy, kind: Item_Kind) {
    if guy.state == .Idle {
        guy.state = .Carrying;
        guy.carrying_item = kind;
    } else {
        try_to_put_item(server, guy.physical_position, kind, null);
    }
}



//
// Helpers
//

is_emitter_field_at :: (server: *Server, position: v2i) -> bool, Direction {
    for i := 0; i < server.emitters.slot_count; ++i {
        emitter, occupied := index_bucket_array(*server.emitters, i);
        if !occupied continue;

        for j := 0; j < emitter.beam_data.fields.count; ++j {
            field := array_get(*emitter.beam_data.fields, j);
            if field.x == position.x && field.y == position.y return true, field.incoming_direction;
        }
    }
    
    return false, ---;
}



#file_scope

recursive_move_check :: (server: *Server, entity: *Entity, move_delta: v2i, strength: s64) -> bool {
    assert(move_delta.x != 0 || move_delta.y != 0, "Recursive move check with a delta of 0 leads to an infinite loop!");

    position := v2i.{ entity.physical_position.x + move_delta.x, entity.physical_position.y + move_delta.y };

    // Make sure the position is in bounds of the world
    if !position_in_bounds(server, position) then return false;

    // Make sure the space is unoccupied or can be moved away
    pushable_entity: *Entity = null;
    blocking_entity: *Entity = null;

    for i := 0; i < server.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.all_entities, i);
        if !occupied || entity.physical_position.x != position.x || entity.physical_position.y != position.y continue;

        if entity.entity_flags & .Pushable {
            pushable_entity = entity;
        } else if entity.entity_flags & .Blocks_Move {
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

    collision := find_entity_with_flags_at_position(server, .Blocks_Move, position);
    if collision recursive_move(server, collision, move_delta);

    update_physical_location(server, entity, .{ entity.physical_position.x + move_delta.x, entity.physical_position.y + move_delta.y }, entity.physical_rotation);
}

clear_beam_data :: (data: *Beam_Data) {
    array_clear_without_deallocation(*data.fields);
    data.fields.allocator = *temp;
}

find_target_guy_for_monster :: (server: *Server, monster_position: v2i) -> *Guy, s32 {
    target_guy: *Guy = null;
    target_distance: s32 = MAX_S32;

    for i := 0; i < server.guys.slot_count; ++i {
        guy, occupied := index_bucket_array(*server.guys, i);
        if !occupied continue;
        
        if !has_line_of_sight(server, monster_position, guy.physical_position) continue;
        
        distance := abs(guy.physical_position.x - monster_position.x) + abs(guy.physical_position.y - monster_position.y);
        if distance < target_distance {
            target_guy = guy;
            target_distance = distance;
        }
    }

    return target_guy, target_distance;
}

has_line_of_sight :: (server: *Server, source: v2i, target: v2i) -> bool {
    delta := v2i.{ target.x - source.x, target.y - source.y };

    if delta.x != 0 && delta.y != 0 return false; // There's no clean line between the target and the entity

    // Normalize the delta so that one coordinate has magnitude 1, and the other coordinate has
    // magnitude 0.
    delta.x /= abs(delta.x + delta.y);
    delta.y /= abs(delta.x + delta.y);
    
    position := v2i.{ source.x + delta.x, source.y + delta.y };

    while position.x != target.x || position.y != target.y {
        if find_entity_with_flags_at_position(server, .Blocks_Los, position) return false;
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
        } else if blocking.entity_kind == .Receiver {
            array_add(*beam.fields, Beam_Data.Field.{ position, direction });
            break;
        } else {
            break;
        }
    }
}
