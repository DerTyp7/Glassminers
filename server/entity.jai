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
    
    physical_rotation: Direction;
    physical_position: v2i;
    
    derived: *void;

#if DEVELOPER {
    derived_type_id: Type;
}
}

Player :: struct {
    #using entity : *Entity  = ---;
    state: Player_State      = .Idle;
    target_position: v2i     = .{ 0, 0 };

    carrying_item: Item_Kind = .Count;
    
    resurrection_pid: Pid    = INVALID_PID;
    resurrection_t: f32      = 0; // Between 0 and 1
    
    received_input: Player_Input_Message = ---;
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

Item_Stack :: struct {
    #using entity : *Entity = ---;
    item_kind: Item_Kind = 0;
    count: s64 = 0;
}

Dragon :: struct {
    #using entity : *Entity = ---;
    beam_data: Beam_Data = ---;
    state: Dragon_State;
    attack_t: f32 = 0; // How long this current attack will continue to last
    recovering_t: f32 = 0;
    damaged_entities_this_attack: [..]Pid; // @Leak when the entity is destroyed
}

Entity_Manager :: struct {
    pid_counter:  Pid;
    pid_lookup:   Probed_Hash_Table(Pid, *Entity);
    all_entities: Bucket_Array(Entity);
    players:     Bucket_Array(Player);
    emitters:    Bucket_Array(Emitter);
    receivers:   Bucket_Array(Receiver);
    item_stacks: Bucket_Array(Item_Stack);
    dragons:     Bucket_Array(Dragon);
}



//
// Entity Manager
//

create_entity_manager :: (server: *Server) {
    server.pid_counter = 0;
    server.pid_lookup.allocator = *server.world_allocator;
    probed_hash_table_create(*server.pid_lookup, 128, pid_hash, pids_equal);
    create_bucket_array(*server.all_entities, *server.world_allocator);
    create_bucket_array(*server.players, *server.world_allocator);
    create_bucket_array(*server.emitters, *server.world_allocator);
    create_bucket_array(*server.receivers, *server.world_allocator);
    create_bucket_array(*server.item_stacks, *server.world_allocator);
    create_bucket_array(*server.dragons, *server.world_allocator);
}

destroy_entity_manager :: (server: *Server) {
    probed_hash_table_destroy(*server.pid_lookup);
    destroy_bucket_array(*server.all_entities);
    destroy_bucket_array(*server.players);
    destroy_bucket_array(*server.emitters);
    destroy_bucket_array(*server.receivers);
    destroy_bucket_array(*server.item_stacks);
    destroy_bucket_array(*server.dragons);
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
    entity.health             = MAX_HEALTHS[kind];
    entity.physical_rotation  = rotation;
    entity.physical_position  = position;

    probed_hash_table_add(*server.pid_lookup, pid, entity);
    
    if #complete entity.entity_kind == {
      case .Player;     make_derived(entity, *server.players);
      case .Emitter;    make_derived(entity, *server.emitters);
      case .Receiver;   make_derived(entity, *server.receivers);
      case .Item_Stack; make_derived(entity, *server.item_stacks);
      case .Dragon;     make_derived(entity, *server.dragons);
      case .Crystal, .Bedrock, .Mirror, .Rock, .Coal;
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
    
    remove_deriveds(*server.players);
    remove_deriveds(*server.emitters);
    remove_deriveds(*server.receivers);
    remove_deriveds(*server.item_stacks);
    remove_deriveds(*server.dragons);
    remove_deriveds(*server.all_entities);
}

damage_entity :: (server: *Server, entity: *Entity, immediate_damage: f32) -> bool {
    has_died := false;

    entity.health -= immediate_damage;
    entity.health = max(entity.health, 0);

    if entity.health > 0 {
        //
        // Send information about the entity health to all clients
        //
        msg := make_message(Entity_Health_Message);
        msg.entity_health.entity_pid = entity.pid;
        msg.entity_health.current_health = entity.health;
        array_add(*server.outgoing_messages, msg);
    } else {
        //
        // Handle the entity dying
        //
        if entity.entity_kind == {
          case .Player;
            player := down(entity, Player);
            player.state = .Dead;

          case .Crystal;
            remove_entity(server, entity);
            try_to_put_item(server, entity.physical_position, .Shard);

          case .Rock;
            remove_entity(server, entity);
            try_to_put_item(server, entity.physical_position, .Stone);

          case .Coal;
            remove_entity(server, entity);
            try_to_put_item(server, entity.physical_position, .Coal);
            
          case;
            remove_entity(server, entity);
        }

        has_died = true;
    }

    return has_died;
}

set_entity_health :: (server: *Server, entity: *Entity, health: f32) {
    entity.health = health;
    msg := make_message(Entity_Health_Message);
    msg.entity_health.entity_pid = entity.pid;
    msg.entity_health.current_health = entity.health;
    array_add(*server.outgoing_messages, msg);
}



//
// Derived Types
//

update_player :: (server: *Server, player: *Player) {
    look_vector := vector_from_direction(player.physical_rotation);
    player.target_position = .{ player.physical_position.x + look_vector.x, player.physical_position.y + look_vector.y };
    
    if player.state == {
      case .Digging;
        target_entity := get_entity_at_position(server, player.target_position);
        if damage_entity(server, target_entity, PLAYER_DPS * server.tick_time) {
            player.state = .Idle;
        }

      case .Resurrecting;
        player.resurrection_t += server.tick_time / RESURRECTION_TIME;

        if player.resurrection_t >= 1 {
            other_entity := get_entity(server, player.resurrection_pid);
            if other_entity {
                other_player := down(other_entity, Player);
                other_player.state = .Idle; // This might be one frame late, depending on which order 'player' and 'other_player' are in the player list... But I'd say that's fine for now.
                set_entity_health(server, other_player, MAX_HEALTHS[other_player.entity_kind]);
            }

            player.state = .Idle;
        }
    }

    //
    // Send out the new player state
    // @NetworkTraffic: Only send this message if anything changed about the player
    //
    msg := make_message(Player_State_Message);
    msg.player_state.entity_pid      = player.pid;
    msg.player_state.state           = player.state;
    msg.player_state.target_position = player.target_position;
    msg.player_state.carrying_item   = player.carrying_item;
    array_add(*server.outgoing_messages, msg);
}

update_emitter :: (server: *Server, emitter: *Emitter) {
    clear_beam_data(*emitter.beam_data);

    // @NetworkTraffic: Simple client-side prediction

    previous := emitter.time_left_in_seconds;
    
    if emitter.time_left_in_seconds > 0 {
        emitter.time_left_in_seconds -= server.tick_time;
    }

    if previous != emitter.time_left_in_seconds {
        msg := make_message(Emitter_State_Message);
        msg.emitter_state.entity_pid = emitter.pid;
        msg.emitter_state.time_left_in_seconds = emitter.time_left_in_seconds;
        array_add(*server.outgoing_messages, msg);
    }
    
    if emitter.time_left_in_seconds > 0 {
        recalculate_beam(server, *emitter.beam_data, emitter.physical_position, emitter.physical_rotation, MAX_S64);
    }
}

update_dragon :: (server: *Server, dragon: *Dragon) {
    send_update :: (server: *Server, dragon: *Dragon) {
        msg := make_message(Dragon_State_Message);
        msg.dragon_state.entity_pid = dragon.pid;
        msg.dragon_state.state = dragon.state;
        array_add(*server.outgoing_messages, msg);
    }

    clear_beam_data(*dragon.beam_data);

    lit_up, _ := is_emitter_field_at(server, dragon.physical_position);
    if lit_up {
        damage_entity(server, dragon, 5 * server.tick_time);
    }

    if #complete dragon.state == {
      case .Idle;
        target_player: *Player = null;
        target_distance: s32 = MAX_S32;
        
        for j := 0; j < server.players.slot_count; ++j {
            player, occupied := index_bucket_array(*server.players, j);
            if !occupied continue;
            
            if !has_line_of_sight(server, dragon, player.physical_position) continue;
            
            distance := abs(player.physical_position.x - dragon.physical_position.x) + abs(player.physical_position.y - dragon.physical_position.y);
            if distance < target_distance {
                target_player = player;
                target_distance = distance;
            }
        }
        
        if target_player {
            delta := v2i.{ target_player.physical_position.x - dragon.physical_position.x, target_player.physical_position.y - dragon.physical_position.y };

            rotation := direction_from_vector(delta);
            update_physical_location(server, dragon, dragon.physical_position, rotation);

            if target_distance <= DRAGON_BEAM_LENGTH {
                // The target player is actually in reach for the dragon's beam. Since we are
                // checking for line-of-sight, we know the beam can actually reach the player
                // like this.
                dragon.state = .Attacking;
                dragon.attack_t = DRAGON_ATTACK_TIME;
                array_clear(*dragon.damaged_entities_this_attack);
                dragon.damaged_entities_this_attack.allocator = *server.world_allocator;
                send_update(server, dragon);
            }
        }

      case .Attacking;
        recalculate_beam(server, *dragon.beam_data, dragon.physical_position, dragon.physical_rotation, DRAGON_BEAM_LENGTH);
        dragon.attack_t -= server.tick_time;

        for i := 0; i < dragon.beam_data.fields.count; ++i {
            field := array_get(*dragon.beam_data.fields, i);
            entity := get_blocking_entity_at_position(server, field, is_living_entity);
            if entity && !array_contains(*dragon.damaged_entities_this_attack, entity.pid) {
                damage_entity(server, entity, HEALTH_PER_HEART);
                array_add(*dragon.damaged_entities_this_attack, entity.pid);
            }
        }
        
        if dragon.attack_t <= 0 {
            dragon.state = .Recovering;
            dragon.recovering_t = DRAGON_RECOVER_TIME;
            send_update(server, dragon);
        }
        
      case .Recovering;
        dragon.recovering_t -= server.tick_time;
        if dragon.recovering_t <= 0 {
            dragon.state = .Idle;
            send_update(server, dragon);
        }
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

try_to_put_item :: (server: *Server, target_position: v2i, kind: Item_Kind) -> bool {
    success := false;
    stack_entity := get_entity_at_position(server, target_position);

    if stack_entity == null {
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
    } else if stack_entity.entity_kind == .Item_Stack {
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
    }

    return success;
}



//
// Movement Code
//

position_in_bounds :: (server: *Server, position: v2i) -> bool {
    return position.x >= 0 && position.x < server.world_size.x && position.y >= 0 && position.y < server.world_size.y;
}

get_entity_at_position :: (server: *Server, position: v2i) -> *Entity {
    for i := 0; i < server.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.all_entities, i);
        if occupied && !entity.marked_for_removal && entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
}

get_entity_of_kind_at_position :: (server: *Server, kind: Entity_Kind, position: v2i) -> *Entity {
    for i := 0; i < server.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.all_entities, i);
        if occupied && !entity.marked_for_removal && entity.entity_kind == kind && entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
}

get_blocking_entity_at_position :: (server: *Server, position: v2i, lambda: (kind: Entity_Kind) -> bool) -> *Entity {
    for i := 0; i < server.all_entities.slot_count; ++i {
        entity, occupied := index_bucket_array(*server.all_entities, i);
        if occupied && !entity.marked_for_removal && lambda(entity.entity_kind) && entity.physical_position.x == position.x && entity.physical_position.y == position.y return entity;
    }
    
    return null;
}

can_move_to_position :: (server: *Server, entity: *Entity, position: v2i) -> bool {
    move_delta := v2i.{ position.x - entity.physical_position.x, position.y - entity.physical_position.y };
    if move_delta.x != 0 || move_delta.y != 0 {
        return recursive_move_check(server, entity, move_delta);
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

remove_entity :: (server: *Server, entity: *Entity) {
    entity.marked_for_removal = true;
    msg := make_message(Destroy_Entity_Message);
    msg.destroy_entity.entity_pid = entity.pid;
    array_add(*server.outgoing_messages, msg);
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

recursive_move_check :: (server: *Server, entity: *Entity, move_delta: v2i) -> bool {
    assert(move_delta.x != 0 || move_delta.y != 0, "Recursive move check with a delta of 0 leads to an infinite loop!");

    position := v2i.{ entity.physical_position.x + move_delta.x, entity.physical_position.y + move_delta.y };

    // Make sure the position is in bounds of the world
    if !position_in_bounds(server, position) then return false;

    // Make sure the space is unoccupied or can be moved away
    collision := get_blocking_entity_at_position(server, position, is_move_blocking_entity);
    if collision != null && (!is_pushable_entity(collision.entity_kind) || !recursive_move_check(server, collision, move_delta)) then return false;

    // Success!
    return true;
}

recursive_move :: (server: *Server, entity: *Entity, move_delta: v2i) {
    assert(move_delta.x != 0 || move_delta.y != 0, "Recursive move with a delta of 0 leads to an infinite loop!");

    position := v2i.{ entity.physical_position.x + move_delta.x, entity.physical_position.y + move_delta.y };

    collision := get_blocking_entity_at_position(server, position, is_move_blocking_entity);
    if collision recursive_move(server, collision, move_delta);

    update_physical_location(server, entity, .{ entity.physical_position.x + move_delta.x, entity.physical_position.y + move_delta.y }, entity.physical_rotation);
}

clear_beam_data :: (data: *Beam_Data) {
    array_clear_without_deallocation(*data.fields);
    data.fields.allocator = *temp;
}

has_line_of_sight :: (server: *Server, entity: *Entity, target: v2i) -> bool {
    delta := v2i.{ target.x - entity.physical_position.x, target.y - entity.physical_position.y };

    if delta.x != 0 && delta.y != 0 return false; // There's no clean line between the target and the entity

    // Normalize the delta so that one coordinate has magnitude 1, and the other coordinate has
    // magnitude 0.
    delta.x /= abs(delta.x + delta.y);
    delta.y /= abs(delta.x + delta.y);
    
    position := v2i.{ entity.physical_position.x + delta.x, entity.physical_position.y + delta.y };

    while position.x != target.x || position.y != target.y {
        if get_blocking_entity_at_position(server, position, is_los_blocking_entity) return false;
        position.x += delta.x;
        position.y += delta.y;
    }
    
    return true;
}

recalculate_beam :: (server: *Server, beam: *Beam_Data, position: v2i, direction: Direction, max_length: s64) {
    while beam.fields.count < max_length {
        vector := vector_from_direction(direction);
        position.x += vector.x;
        position.y += vector.y;
        if !position_in_bounds(server, position) break;
        
        blocking := get_blocking_entity_at_position(server, position, is_beam_blocking_entity);
        
        if blocking == null {
            array_add(*beam.fields, Beam_Data.Field.{ position, direction });
        } else if blocking.entity_kind == .Mirror {
            array_add(*beam.fields, Beam_Data.Field.{ position, direction });
            
            reflected_direction, reflection_success := reflect_direction(direction, blocking.physical_rotation);
            
            if reflection_success then direction = reflected_direction; else break;
        } else if blocking.entity_kind == .Receiver {
            array_add(*beam.fields, Beam_Data.Field.{ position, direction });
            break;
        } else {
            break;
        }
    }
}
