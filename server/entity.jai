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
      case .Torch;      make_derived(entity, *server.torches);
      case .Item_Stack; make_derived(entity, *server.item_stacks);
      case .Chest;      make_derived(entity, *server.chests);
      case .Frog;       make_derived(entity, *server.frogs);
      case .Goblin;     make_derived(entity, *server.goblins);
      case .Slime;      make_derived(entity, *server.slimes);
      case .Void_Eye;   make_derived(entity, *server.void_eyes);
      case .Crystal, .Bedrock, .Mirror, .Lava, .Rock, .Coal, .Slab, .Slime_Hole, .Trader, .Flag;
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

position_in_bounds :: (server: *Server, position: v2i) -> bool {
    return position.x >= 0 && position.x < server.world_size.x && position.y >= 0 && position.y < server.world_size.y;
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

rotate_npc_towards_target_guy :: (server: *Server, npc: *Entity) {
    target_guy, target_distance := find_target_guy_for_npc(server, npc.physical_position);

    if target_guy {
        delta := v2i.{ target_guy.physical_position.x - npc.physical_position.x, target_guy.physical_position.y - npc.physical_position.y };
        rotation := direction_from_vector(delta);
        update_physical_location(server, npc, npc.physical_position, rotation);
    }
}


/* ---------------------------------------------- Entity Helpers ---------------------------------------------- */

broadcast_guy_state :: (server: *Server, guy: *Guy) {
    msg := make_message(Guy_State_Message);
    msg.guy_state.entity_pid      = guy.pid;
    msg.guy_state.state           = guy.state;
    msg.guy_state.target_position = guy.target_position;
    msg.guy_state.carrying_item   = guy.carrying_item;
    msg.guy_state.strength_t      = guy.strength_t;
    array_add(*server.outgoing_messages, msg);
}

broadcast_chest_inventory :: (server: *Server, chest: *Chest) {
    msg := make_message(Chest_State_Message);
    msg.chest_state.entity_pid = chest.pid;
    msg.chest_state.inventory = chest.inventory;
    msg.chest_state.visually_open = chest.visually_open_counter > 0;
    array_add(*server.outgoing_messages, msg);
}

switch_guy_state :: (server: *Server, guy: *Guy, state: Guy_State) {
    if guy.state != state {
        guy.state = state;
        broadcast_guy_state(server, guy);
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

switch_void_eye_state :: (server: *Server, eye: *Void_Eye, new_state: Void_Eye_State) {
    if eye.state == new_state return;

    eye.state = new_state;

    msg := make_message(Void_Eye_State_Message);
    msg.void_eye_state.entity_pid = eye.pid;
    msg.void_eye_state.state = new_state;
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
