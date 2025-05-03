#load "math/Vector.jai";


/* ------------------------------------------------- Typedefs ------------------------------------------------- */

v2i :: Vector2_Base(s32);
v2f :: Vector2_Base(f32);
Pid :: u32;
INVALID_PID: Pid : -1;

Campaign :: enum {
    Tutorial;
    Easy;
    Medium;
    Hard;
}

pid_hash :: (pid: Pid) -> u64 {
    hash: u32 = ---;
    hash = ((pid >> 16) ^ pid) * 0x45d9f3b;
    hash = ((pid >> 16) ^ pid) * 0x45d9f3b;
    hash = ((pid >> 16) ^ pid);
    return hash;
}

pids_equal :: (lhs, rhs: Pid) -> bool {
    return lhs == rhs;
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
NETWORK_TIMEOUT: f32 : 7;
NETWORK_PING_INTERVAL: f32 : 0.25;



/* -------------------------------------------------- World -------------------------------------------------- */

RECEIVER_TIME_TO_CHARGE: f32 : 5;
EMITTER_TIME_TO_DIE: f32 : 180;

RESURRECTION_TIME: f32 : 5;

DRAGON_BEAM_LENGTH :: 3;
DRAGON_ATTACK_TIME:  f32 : 2;
DRAGON_RECOVER_TIME: f32 : 5;

HEALTH_PER_HEART: f32 : 10;
PLAYER_DPS: f32 : HEALTH_PER_HEART;

MAX_HEALTHS: [Entity_Kind.Count]f32 : .[
    30, // Player
    30, // Crystal
    70, // Bedrock
    0,  // Emitter
    0,  // Receiver
    30, // Mirror
    50, // Rock
    0,  // Item Stack
    50, // Dragon,
];

Item_Kind :: enum {
    Shard;
    Stone;
}

Entity_Kind :: enum {
    Player;
    Crystal;
    Bedrock;
    Emitter;
    Receiver;
    Mirror;
    Rock;
    Item_Stack;
    Dragon;
}

Direction :: enum {
    North; // -Y
    East;  // +X
    South; // +Y
    West;  // -X
}

Player_State :: enum {
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

Interaction_Kind :: enum {
    None;
    Primary;
    Secondary;
}

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

is_pushable_entity :: (kind: Entity_Kind) -> bool {
    return kind == .Player || kind == .Crystal || kind == .Rock;
}

is_move_blocking_entity :: (kind: Entity_Kind) -> bool {
    result: bool = ---;

    if #complete kind == {
      case .Player, .Crystal, .Bedrock, .Emitter, .Receiver, .Mirror, .Rock, .Dragon;
        result = true;

      case .Item_Stack;
        result = false;
    }

    return result;
}

is_beam_blocking_entity :: (kind: Entity_Kind) -> bool {
    result: bool = ---;

    if #complete kind == {
      case .Crystal, .Bedrock, .Emitter, .Receiver, .Mirror, .Rock;
        result = true;

      case .Player, .Dragon, .Item_Stack;
        result = false;
    }

    return result;
}

is_los_blocking_entity :: (kind: Entity_Kind) -> bool {
    result: bool = ---;

    if #complete kind == {
      case .Crystal, .Bedrock, .Emitter, .Receiver, .Mirror, .Rock, .Player, .Dragon;
        result = true;

      case .Item_Stack;
        result = false;
    }

    return result;    
}

is_living_entity :: (kind: Entity_Kind) -> bool {
    result: bool = ---;

    if #complete kind == {
      case .Player, .Dragon;
        result = true;

      case .Crystal, .Bedrock, .Emitter, .Receiver, .Mirror, .Rock, .Item_Stack;
        result = false;
    }

    return result;    
}
