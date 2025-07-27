#load "math/Vector.jai";


/* ------------------------------------------------- Typedefs ------------------------------------------------- */

v2i :: Vector2_Base(s32);
v2f :: Vector2_Base(f32);
Pid :: u32;
INVALID_PID: Pid : -1;

MAX_LOCAL_PLAYERS :: 4;

LOG_MESSAGES :: false;

Campaign :: enum {
    Developer;
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
    result := lerp_with_wrap(from, to, speed, low, high);
    if abs(result - to) < 0.001 result = to;
    return result;
}

lerp_with_snap :: (from: $T, to: T, speed: f32) -> T {
    result := lerp(from, to, speed);
    if abs(result - to) < 0.001 result = to;
    return result;
}

find_nearest_point_on_line_segment :: (point: v2f, line: [2]v2f) -> v2f, f32, f32 {
    A := v2f.{ line[1].x - line[0].x, line[1].y - line[0].y };
    B := v2f.{ point.x   - line[0].x, point.y   - line[0].y };

    line_length := A.x * A.x + A.y * A.y;
    dot := A.x * B.x + A.y * B.y;
    t := clamp(dot / line_length, 0, 1);
    point_on_line := v2f.{ line[0].x + t * A.x, line[0].y + t * A.y };
    point_to_line := v2f.{ point_on_line.x - point.x, point_on_line.y - point.y };
    
    return point_on_line, sqrt(point_to_line.x * point_to_line.x + point_to_line.y * point_to_line.y), t;
}



/* ----------------------------------------------- Shared Data ----------------------------------------------- */

Server_State :: enum {
    Closed;
    Starting;
    Running;
    Closing;
}

Shared_Server_Data :: struct {
    state: Server_State;
    requested_port: u16;
    startup_error: Socket_Error;
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

// When we send the last data via a TCP connection and then immediately close it, the OS might
// just internally drop all the data we wanted to send. Now, we are a game and so we'd rather
// drop some data than wait forever until it actually arrived, but we still want good chances
// of the data arriving. Therefore, this hack attempts to bring the OS to send the data, before
// we then actually close the connection...
NETWORK_DIE_TIME: f32 : 3;

#if DEVELOPER {
    NETWORK_TIMEOUT: f32 : 180; // Just to make debugging one endpoint easier
} #else {
    NETWORK_TIMEOUT: f32 : 7;
}



/* -------------------------------------------------- World -------------------------------------------------- */

VISUAL_ROOM_SIZE   :: v2f.{ 5, 5 };
VISUAL_ROOM_OFFSET :: v2f.{ #run VISUAL_ROOM_SIZE.x / 2 - 0.5, #run VISUAL_ROOM_SIZE.y / 2 - 0.5 };
VISUAL_ITEM_STACK_CAPACITY :: 5;

VISUAL_ITEM_STACK_OFFSETS: [VISUAL_ITEM_STACK_CAPACITY]v2f : .[ .{ 0, 0 }, .{ -0.1, 0.2 }, .{ 0.2, 0.1 }, .{ -0.2, -0.1 }, .{ 0.2, -0.2 } ];

EMITTER_TIME_TO_POWER_UP: f32 : 5;
EMITTER_MAX_CHARGE: f32 : 180;
COAL_EMITTER_CHARGE: f32 : 60;
SLAB_TIME_TO_LIVE: f32 : 10;

RESURRECTION_TIME: f32 : 5;
STRENGTH_POTION_TIME: f32 : 30;
STRENGTH_POTION_FACTOR: f32 : 2;

GUY_PUSH_STRENGTH: s64 : 2;

CHEST_CAPACITY :: 8;

FROG_BEAM_LENGTH :: 3;
FROG_ATTACK_TIME:  f32 : 1;
FROG_RECOVER_TIME: f32 : 5;

GOBLIN_ATTACK_TIME:  f32 : 0.5;
GOBLIN_RECOVER_TIME: f32 : 2;

SLIME_IDLE_MOVE_INTERVAL:    f32 : 0.55;
SLIME_FLEEING_MOVE_INTERVAL: f32 : 0.25;
SLIME_ACTION_RADIUS:         s32 : 8;
SLIME_SCARING_DISTANCE:      s32 : 2;
SLIME_MIN_TIME_IN_HIDING:    f32 : 2;

HEALTH_PER_HEART: f32 : 10;
BEAM_DPS: f32 : HEALTH_PER_HEART / 2;
GUY_DPS:  f32 : HEALTH_PER_HEART;
LAVA_DPS: f32 : HEALTH_PER_HEART * 3;

Entity_Flags :: enum bitfield {
    Pushable;
    Diggable;
    Living;
    Blocks_Movement; // Blocks all movement
    Blocks_Non_Living_Movement; // Only blocks movement for non-living entities (rocks, mirrors, ...)
    Blocks_Beam;
    Blocks_Line_Of_Sight;
    Blocks_Crafting;
    Disable_Visual_Rotation;
    Disabled_Temporarily;
    Auto_Heal;
    Emissive;
}

ENTITY_DEFAULT_FLAGS: [Entity_Kind.Count]Entity_Flags : .[
    // Beams
    .Blocks_Movement | .Blocks_Beam | .Blocks_Line_Of_Sight | .Blocks_Crafting, // Emitter
    .Pushable | .Diggable | .Blocks_Movement | .Blocks_Beam | .Blocks_Line_Of_Sight | .Blocks_Crafting | .Auto_Heal, // Mirror

    // Environment
    .Blocks_Movement | .Blocks_Crafting | .Emissive, // Lava
    .Blocks_Movement | .Blocks_Crafting | .Diggable | .Blocks_Beam | .Blocks_Line_Of_Sight, // Bedrock
    .Pushable | .Diggable | .Blocks_Movement | .Blocks_Beam | .Blocks_Line_Of_Sight | .Blocks_Crafting, // Rock
    .Pushable | .Diggable | .Blocks_Movement | .Blocks_Beam | .Blocks_Line_Of_Sight | .Blocks_Crafting, // Coal
    .Pushable | .Diggable | .Blocks_Movement | .Blocks_Beam | .Blocks_Line_Of_Sight | .Blocks_Crafting, // Crystal
    .Blocks_Crafting, // Slime Hole
    
    // Creations
    0, // Item Stack
    0, // Slab
    .Blocks_Crafting, // Torch
    .Pushable | .Diggable | .Blocks_Movement | .Blocks_Beam | .Blocks_Crafting | .Auto_Heal, // Chest
    
    // Beings
    .Living | .Pushable | .Blocks_Movement | .Blocks_Crafting | .Disable_Visual_Rotation, // Guy
    .Living | .Blocks_Movement | .Blocks_Crafting | .Disable_Visual_Rotation, // Frog
    .Living | .Blocks_Movement | .Blocks_Crafting | .Disable_Visual_Rotation, // Goblin
    .Living | .Blocks_Movement | .Blocks_Crafting | .Disable_Visual_Rotation, // Slime
    .Living | .Blocks_Movement | .Blocks_Crafting | .Disable_Visual_Rotation, // Trader
    
    // Misc
    .Blocks_Non_Living_Movement | .Blocks_Crafting, // Flag
];

ENTITY_DEFAULT_HEALTH: [Entity_Kind.Count]f32 : .[
    // Beams
    0,  // Emitter
    30, // Mirror

    // Environment
    0,   // Lava
    120, // Bedrock
    50,  // Rock
    40,  // Coal
    30,  // Crystal
    0,   // Slime Hole
    
    // Creations
    0,  // Item Stack
    0,  // Slab
    0,  // Torch
    30, // Chest
    
    // Beings
    30, // Guy
    50, // Frog
    20, // Goblin
    20, // Slime
    30, // Trader
    
    // Misc
    1, // Flag
];

ENTITY_DEFAULT_DIRECTION: [Entity_Kind.Count]Direction : .[
    // Beams
    .East,  // Emitter
    .North, // Mirror

    // Environment
    .North, // Lava
    .North, // Bedrock
    .North, // Rock
    .North, // Coal
    .North, // Crystal
    .North, // Slime Hole
    
    // Creations
    .North, // Item Stack
    .North, // Slab
    .North, // Torch
    .North, // Chest
    
    // Beings
    .North, // Guy
    .South, // Frog
    .South, // Goblin
    .South, // Slime
    .South, // Trader
    
    // Misc
    .North, // Flag
];

ENTITY_VISUAL_DEPTHS: [Entity_Kind.Count]s32 : .[ // A higher depth will be rendered on top of a lower depth
    // Beams
    2, // Emitter
    2, // Mirror

    // Environment
    0, // Lava
    2, // Bedrock
    2, // Rock
    2, // Coal
    2, // Crystal
    2, // Slime Hole

    // Creations
    1, // Item Stack
    0, // Slab
    1, // Torch
    2, // Chest
    
    // Beings
    3, // Guy
    3, // Frog
    3, // Goblin
    3, // Slime
    3, // Trader
    
    // Misc
    3, // Flag
];

Item_Kind :: enum {
    Shard;
    Stone;
    Coal;
    Coin;
    Torch;
    Flag;
}

Entity_Kind :: enum {
    // Beams
    Emitter;
    Mirror;

    // Environment
    Lava;
    Bedrock;
    Rock;
    Coal;
    Crystal;
    Slime_Hole;
    
    // Creations
    Item_Stack;
    Slab;
    Torch;
    Chest;
    
    // Beings
    Guy;
    Frog;
    Goblin;
    Slime;
    Trader;
    
    // Misc
    Flag;
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

Emitter_State :: enum {
    Off; // Hasn't yet been powered on by another emitter
    Active; // Is the currently active emitter - Losing charge over time
    Complete; // Has powered another emitter - Always on for better playing experience
}

Frog_State :: enum {
    Idle;
    Attacking;
    Recovering;
}

Goblin_State :: enum {
    Idle;
    Attacking;
    Recovering;
}

Slime_State :: enum {
    Idle;
    Fleeing;
    Hiding;
}

Interaction_Kind :: enum {
    Primary_Start;
    Primary_End;
    Secondary_Start;
    Secondary_End;
}

Crafting_Recipe :: enum {
    Mirror;
    Torch;
    Chest;
    Health_Potion;
    Strength_Potion;
}

CRAFTING_RECIPE_REQUIRED_ITEMS: [Crafting_Recipe.Count][]Item_Kind = .[
    .[ .Shard ], // Mirror
    .[ .Coal ],  // Torch
    .[ .Stone ], // Chest
    .[ .Coin ],  // Health Potion
    .[ .Coin ],  // Strength Potion
];

CRAFTING_RECIPE_ENABLER: [Crafting_Recipe.Count]Entity_Kind = .[
    .Count,  // Mirror
    .Count,  // Torch
    .Count,  // Chest
    .Trader, // Health Potion
    .Trader, // Strength Potion
];

CRAFTING_RECIPE_REQUIRES_EMPTY_TARGET: [Crafting_Recipe.Count]bool = .[
    true,  // Mirror
    false, // Torch
    true,  // Chest
    false, // Health Potion
    false, // Strength Potion
];

Game_Over_Reason :: enum {
    All_Players_Dead;
    Flag_Destroyed;
}

Cheat :: enum {
    Give_Coin;
    Give_Coal;
    Give_Shard;
    Give_Stone;
    Give_Health;
    Give_Strength;
    Spawn_Goblin;
    Spawn_Frog;
    Spawn_Slime;
    Spawn_Trader;
    Toggle_Invincibility;
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

get_mirror_rotation_from_reflection :: (incoming, outgoing: Direction) -> Direction, bool {
    if (outgoing + 1) % Direction.Count == incoming {
        return (incoming + 2) % Direction.Count, true;
    } else if (outgoing - 1) % Direction.Count == incoming {
        return outgoing, true;
    } else {
        return .Count, false;
    }
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
