#load "math/Vector.jai";


/* ------------------------------------------------- Typedefs ------------------------------------------------- */

v2i :: Vector2_Base(s32);
v2f :: Vector2_Base(f32);
Pid :: u32;
INVALID_PID: Pid : -1;

LOG_MESSAGES :: false;

Campaign :: enum {
    Tutorial;
    Easy;
    Medium;
    Hard;
}

pid_hash :: (pid: Pid) -> u64 {
    hash: u32 = ---;
    hash = ((pid >> 16) ^ pid) *% 0x45d9f3b;
    hash = ((pid >> 16) ^ pid) *% 0x45d9f3b;
    hash = ((pid >> 16) ^ pid);
    return hash;
}

pids_equal :: (lhs, rhs: Pid) -> bool {
    return lhs == rhs;
}

lerp_with_wrap_and_snap :: (from, to, speed: $T/float, low, high: T) -> T {
    direct_distance    := abs(to - from);
    wrap_high_distance := (high - from) + (to - low);
    wrap_low_distance  := (high - to) + (from - low);

    result: f32 = ---;
    
    if direct_distance < wrap_high_distance && direct_distance < wrap_low_distance {
        result = from * (1 - speed) + (to) * speed;
    } else if wrap_high_distance < wrap_low_distance {
        result = from * (1 - speed) + (wrap_high_distance + from) * speed;
    } else {
        result = from * (1 - speed) - (wrap_low_distance + from) * speed;
    }

    result = wrap(result, low, high);

    if abs(result - to) < 0.001 result = to;

    return result;
}

lerp_with_snap :: (from: $T, to: T, speed: f32) -> T {
    result := from * (1 - speed) + to * speed;
    if abs(result - to) < 0.001 result = to;
    return result;
}



/* ----------------------------------------------- Shared Data ----------------------------------------------- */

Server_State :: enum {
    Starting;
    Running;
    Closing;
    Closed;
}

Shared_Server_Data :: struct {
    state: Server_State;
    requested_port: u16;
}



/* ------------------------------------------------ Networking ------------------------------------------------ */

//
// The Virtual Connection was intended for use with UDP, but it also supports TCP. I have decided
// for this game to go with TCP, for the two following reasons:
//   1. Pretty much all of our information that we send over the network is crucial. That means
//      that in no case (right now) we'd send "unreliable" packets over our virtual connection.
//      Therefore, there's no real "advantage" to using UDP.
//   2. We heavily rely on the order in which messages are sent and received. For example, the
//      server may create an entity, and then send an item stack state message for that entity.
//      The client *must* receive the entity creation message first, otherwise it wouldn't know what
//      to do with the item stack state message (and right now, it would crash).
//
// The first point is actually handled by the Virtual Connection Module, where we have our own QoS
// protocol. I don't suspect that it is better than TCP though, when all packets are supposed to
// be reliable...
// The second point is *not* handled by the Virtual Connection. We could build our own, but what's
// the point really?
// Instead, we just rely on TCP to send us one stable, ordered stream of packets. The Virtual
// Connection abstracts the packets over the underlying protocol, so that we don't have to worry
// about reading packets partially (in the game code).
//
NETWORK_PROTOCOL :: Connection_Protocol.TCP;
NETWORK_PING_INTERVAL: f32 : 0.25;

#if DEVELOPER {
    NETWORK_TIMEOUT: f32 : 180; // Just to make debugging one endpoint easier
} #else {
    NETWORK_TIMEOUT: f32 : 7;
}



/* -------------------------------------------------- World -------------------------------------------------- */

VISUAL_ROOM_SIZE   :: v2f.{ 5, 5 };
VISUAL_ROOM_OFFSET :: v2f.{ #run floor(VISUAL_ROOM_SIZE.x / 2), #run floor(VISUAL_ROOM_SIZE.y / 2) };

RECEIVER_TIME_TO_CHARGE: f32 : 5;
EMITTER_MAX_TIME: f32 : 180;
COAL_EMITTER_CHARGE_TIME: f32 : 60;

RESURRECTION_TIME: f32 : 5;

DRAGON_BEAM_LENGTH :: 3;
DRAGON_ATTACK_TIME:  f32 : 1;
DRAGON_RECOVER_TIME: f32 : 5;

GOBLIN_ATTACK_TIME:  f32 : 0.5;
GOBLIN_RECOVER_TIME: f32 : 2;

HEALTH_PER_HEART: f32 : 10;
BEAM_DPS: f32 : HEALTH_PER_HEART / 2;
GUY_DPS:  f32 : HEALTH_PER_HEART;

Entity_Flags :: enum bitfield {
    Pushable;
    Living;
    Blocks_Move;
    Blocks_Beam;
    Blocks_Los;
}

DEFAULT_ENTITY_FLAGS: [Entity_Kind.Count]Entity_Flags : .[
    // Beams
    .Blocks_Move | .Blocks_Beam | .Blocks_Los, // Emitter
    .Blocks_Move | .Blocks_Beam | .Blocks_Los, // Receiver
    .Pushable | .Blocks_Move | .Blocks_Beam | .Blocks_Los, // Mirror

    // Environment
    .Blocks_Move | .Blocks_Beam | .Blocks_Los, // Bedrock
    .Pushable | .Blocks_Move | .Blocks_Beam | .Blocks_Los, // Rock
    .Pushable | .Blocks_Move | .Blocks_Beam | .Blocks_Los, // Crystal
    .Pushable | .Blocks_Move | .Blocks_Beam | .Blocks_Los, // Coal
    0, // Item Stack
    .Blocks_Move, // Lava

    // Beings
    .Living | .Pushable | .Blocks_Move, // Guy
    .Living | .Blocks_Move, // Dragon
    .Living | .Blocks_Move, // Goblin
];

MAX_HEALTHS: [Entity_Kind.Count]f32 : .[
    // Beams
    0,  // Emitter
    0,  // Receiver
    30, // Mirror

    // Environment
    120, // Bedrock
    50, // Rock
    30, // Crystal
    40, // Coal
    0,  // Item Stack
    0,  // Lava
    
    // Beings
    30, // Guy
    50, // Dragon
    20, // Goblin
];

Item_Kind :: enum {
    Shard;
    Stone;
    Coal;
    Coin;
}

Entity_Kind :: enum {
    // Beams
    Emitter;
    Receiver;
    Mirror;

    // Environment
    Bedrock;
    Rock;
    Coal;
    Crystal;
    Item_Stack;
    Lava;
    
    // Beings
    Guy;
    Dragon;
    Goblin;
}

Direction :: enum {
    North; // -Y
    East;  // +X
    South; // +Y
    West;  // -X
}

Guy_State :: enum {
    Dead;
    Idle;
    Digging;
    Carrying;
    Resurrecting;
}

Dragon_State :: enum {
    Idle;
    Attacking;
    Recovering;
}

Goblin_State :: enum {
    Idle;
    Attacking;
    Recovering;
}

Interaction_Kind :: enum {
    Primary;
    Secondary;
}

Crafting_Recipe :: enum {
    Mirror;
}

CRAFTING_RECIPE_REQUIREMENTS: [Crafting_Recipe.Count][]Item_Kind = .[
    .[ .Shard ],
];

direction_from_vector :: (vector: v2i) -> Direction {
    if vector.x == 0 && vector.y == 0 {
        return .North;
    } else if abs(vector.x) >= abs(vector.y) {
        return ifx vector.x > 0 then .East else .West;
    } else {
        return ifx vector.y > 0 then .South else .North;
    }
}

vector_from_direction :: (direction: Direction) -> v2i {
    result: v2i = ---;
    
    if #complete direction == {
      case .North; result = .{  0, -1 };
      case .East;  result = .{  1,  0 };
      case .South; result = .{  0,  1 };
      case .West;  result = .{ -1,  0 };
    }
    
    return result;
}

opposite_direction :: (in: Direction) -> Direction {
    return (in + 2) % Direction.Count;
}

reflect_direction :: (incoming: Direction, mirror: Direction) -> Direction, bool {
    if incoming == (mirror + 2) % Direction.Count then
        return (incoming + 3) % Direction.Count, true;
    else if incoming == (mirror + 3) % Direction.Count then
        return mirror, true;
    else
        return .Count, false;
}

visual_from_physical_rotation :: (in: Direction) -> f32 {
    out: f32 = ---;

    if #complete in == {
      case .North; out = 0;
      case .East;  out = 0.25;
      case .South; out = 0.5;
      case .West;  out = 0.75;
    }
    
    return out;
}

available_resources_fulfill :: (available: [..]Item_Kind, required: []Item_Kind) -> bool {
    copy := array_copy(*available, *temp);

    all_requirements_met := true;

    for i := 0; i < required.count; ++i {
        item_found := false;

        for j := 0; j < copy.count; ++j {
            if array_get(*copy, j) == required[i] {
                item_found = true;
                array_remove_index(*copy, j);
                break;
            }
        }

        all_requirements_met &= item_found;
    }
    
    return all_requirements_met;
}
