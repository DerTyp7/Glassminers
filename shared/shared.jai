#load "math/Vector.jai";

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



/* ------------------------------------------------ Constants ------------------------------------------------ */

v2i :: Vector2_Base(s32);
v2f :: Vector2_Base(f32);
Pid :: u32;
INVALID_PID: Pid : -1;

MAX_LOCAL_PLAYERS :: 4;
LOG_MESSAGES :: false;

SECTION_WIDTH: s32 : 18; // The world is extended when the players have activated the latest checkpoint. The world is grown by this number of tiles.
SECTION_HEIGHT: s32 : 5; // The height of the world for randomly generated worlds

CAMERA_AREA_WIDTH: f32 : 5; // The camera position snaps to multiples of this area width, to decrease the number of camera movements.
CAMERA_AREA_OFFSET: f32 : CAMERA_AREA_WIDTH / 2 - 0.5;

ITEM_INVENTORY_CAPACITY :: 8;
PHYSICAL_ITEM_STACK_CAPACITY :: 1; // How many items of the same kind can be stacked upon each other
VISUAL_ITEM_STACK_CAPACITY :: 5; // Obviously only actually useful if this value is smaller than the PHYSICAL_ITEM_STACK_CAPACITY value
VISUAL_ITEM_STACK_OFFSETS: [VISUAL_ITEM_STACK_CAPACITY]v2f : .[ .{ 0, 0 }, .{ -0.1, 0.2 }, .{ 0.2, 0.1 }, .{ -0.2, -0.1 }, .{ 0.2, -0.2 } ];
VISUAL_HEALTH_ANIMATION_FRAME_TIME: f32 : 0.2;


COAL_EMITTER_CHARGE: f32 : 45;
SLAB_TIME_TO_LIVE:   f32 : 10;
EMITTER_TIME_TO_POWER_UP: f32 : 5;
EMITTER_MAX_CHARGE:  [Game_Mode.Count]f32 : .[
    180, // Developer
    110, // Tutorial
    110, // Easy
    90,  // Medium
    70,  // Hard
];

TORCH_TIME_TO_LIVE: f32 : 30; // In seconds
TORCH_MEDIUM_PERCENTAGE: f32 : 0.3; // This this percent of TTL left, the torch is only medium size...
TORCH_LOW_PERCENTAGE: f32 : 0.1; // This this percent of TTL left, the torch is only low size...

COIN_DROP_CHANCE: [Game_Mode.Count][2]f32 : .[
    .[ 1,    1   ], // Developer
    .[ 1,    0.5 ], // Tutorial
    .[ 0.9,  0.7 ], // Easy
    .[ 0.75, 0.4 ], // Medium
    .[ 0.5,  0.2 ], // Hard
];

COIN_DROP_CHANCE_POINT_SECTION_INDEX :: 8; // From this section index forwards, the actual drop chance will be the low point indicated in the above array...

RESURRECTION_TIME: f32 : 5;
STRENGTH_POTION_TIME: f32 : 30;
STRENGTH_POTION_FACTOR: f32 : 2;

GUY_PUSH_STRENGTH: s64 : 2;

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

MIN_SHADOW_SIZE_FOR_VOID_EYE: s64 : 5;
SHADOW_SIZE_PER_VOID_EYE: s64 : 20;
VOID_EYE_DPS_ON_PLAYER:     f32 : DEFAULT_ENTITY_HEALTH[.Guy] / 3;
VOID_EYE_DPS_IN_BRIGHTNESS: f32 : HEALTH_PER_HEART * 0.5;
VOID_EYE_HPS_IN_DARKNESS:   f32 : HEALTH_PER_HEART * 0.5;
VOID_EYE_SPAWN_RATE: f32 : 1 / 20; // How many void eyes to spawn per second, assuming there's space to spawn them...
VOID_EYE_IDLE_MOVE_INTERVAL_BASE: f32 : 2;
VOID_EYE_IDLE_MOVE_INTERVAL_STDDEV: f32 : 0.5;
VOID_EYE_CHASING_MOVE_INTERVAL: f32 : 0.1;
VOID_EYE_TRACKING_DISTANCE: s64 : 5;
VOID_EYE_SPAWN_TIME: f32 : 1.5; // Time before the void eye actually starts behaving. Should match the duration of the spawn animation


/* -------------------------------------------------- Enums -------------------------------------------------- */

Game_Mode :: enum {
    // Developer
    Developer;

    // Campaigns
    Tutorial;

    // Random Generations
    Easy;
    Medium;
    Hard;
}

Entity_Flags :: enum bitfield {
    Inanimate :: 0;
    Pushable;
    Diggable;
    Living;
    Blocks_Movement; // Blocks all movement
    Blocks_Non_Living_Movement; // Only blocks movement for non-living entities (rocks, mirrors, ...)
    Blocks_Beam;
    Blocks_Line_Of_Sight;
    Blocks_Crafting;
    Disable_Visual_Rotation;
    Disable_Visual_Lighting;
    Disabled_Temporarily;
    Auto_Heal;
}

Item_Kind :: enum {
    Shard;
    Stone;
    Coal;
    Coin;
    Torch;
    Flag;
    Chest;
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
    Void_Eye;
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
    Off;    // Hasn't yet been powered on by another emitter
    Active; // Is the currently active emitter - Losing charge over time
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

Void_Eye_State :: enum {
    Idle;
    Chasing;
    Attacking;
}

Interaction_Kind :: enum {
    Primary_Start;
    Primary_End;
    Secondary_Start;
    Secondary_End;
}

Crafting_Recipe :: enum {
    // Crafting hud
    Mirror;
    Torch;
    Chest;

    // Trader hud
    Health_Potion;
    Strength_Potion;
    Shard;
    Coal;
}

Game_Result :: enum {
    Unfinished_Game;
    Completed_Tutorial;
    All_Players_Died;
    Flag_Was_Destroyed;
    Connection_Lost;
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
    Toggle_GhostMode;
    Remove_Entity;
    Complete_Emitters;
}

Item_Inventory :: struct {
    item_count: s64;
    item_kinds: [ITEM_INVENTORY_CAPACITY]Item_Kind = ---;
}



/* -------------------------------------------- Entity Properties -------------------------------------------- */

DEFAULT_ENTITY_FLAGS: [Entity_Kind.Count]Entity_Flags : .[
    // Beams
    .Blocks_Movement | .Blocks_Beam | .Blocks_Line_Of_Sight | .Blocks_Crafting, // Emitter
    .Pushable | .Diggable | .Blocks_Movement | .Blocks_Beam | .Blocks_Line_Of_Sight | .Blocks_Crafting | .Auto_Heal, // Mirror

    // Environment
    .Blocks_Movement | .Blocks_Crafting | .Disable_Visual_Lighting, // Lava
    .Blocks_Movement | .Blocks_Crafting | .Diggable | .Blocks_Beam | .Blocks_Line_Of_Sight, // Bedrock
    .Pushable | .Diggable | .Blocks_Movement | .Blocks_Beam | .Blocks_Line_Of_Sight | .Blocks_Crafting, // Rock
    .Pushable | .Diggable | .Blocks_Movement | .Blocks_Beam | .Blocks_Line_Of_Sight | .Blocks_Crafting, // Coal
    .Pushable | .Diggable | .Blocks_Movement | .Blocks_Beam | .Blocks_Line_Of_Sight | .Blocks_Crafting, // Crystal
    .Inanimate, // Slime Hole
    
    // Creations
    .Inanimate, // Item Stack
    .Inanimate, // Slab
    .Blocks_Crafting, // Torch
    .Pushable | .Blocks_Movement | .Blocks_Beam | .Blocks_Crafting, // Chest
    
    // Beings
    .Living | .Pushable | .Blocks_Movement | .Blocks_Crafting | .Disable_Visual_Rotation, // Guy
    .Living | .Blocks_Movement | .Blocks_Crafting | .Disable_Visual_Rotation, // Frog
    .Living | .Blocks_Movement | .Blocks_Crafting | .Disable_Visual_Rotation, // Goblin
    .Living | .Blocks_Movement | .Blocks_Crafting | .Disable_Visual_Rotation, // Slime
    .Disable_Visual_Rotation | .Disable_Visual_Lighting, // Void Eye
    .Living | .Blocks_Movement | .Blocks_Crafting | .Disable_Visual_Rotation | .Auto_Heal, // Trader
    
    // Misc
    .Blocks_Non_Living_Movement | .Blocks_Crafting, // Flag
];

DEFAULT_ENTITY_HEALTH: [Entity_Kind.Count]f32 : .[
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
    10, // Slime
    10, // Void Eye
    30, // Trader
    
    // Misc
    1, // Flag
];

DEFAULT_ENTITY_ROTATION: [Entity_Kind.Count]Direction : .[
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
    .South, // Void Eye
    .South, // Trader
    
    // Misc
    .North, // Flag
];

Visual_Layer :: enum (s32) { // Useful for grouping kinds of entities together. You can still just assign any random number of an entity kind as its visual depth.
    Background           :: 0;
    Resources            :: 1;
    Creations_Immoveable :: 2;
    Creations_Moveable   :: 3;
    Beings               :: 4;
    Void_Eyes            :: 5;
}

DEFAULT_ENTITY_VISUAL_DEPTH: [Entity_Kind.Count]Visual_Layer : .[ // A higher depth will be rendered on top of a lower depth
    // Beams
    .Creations_Immoveable, // Emitter
    .Creations_Moveable, // Mirror

    // Environment
    .Background, // Lava
    .Resources, // Bedrock
    .Resources, // Rock
    .Resources, // Coal
    .Resources, // Crystal
    .Background, // Slime Hole

    // Creations
    .Creations_Immoveable, // Item Stack
    .Background, // Slab
    .Creations_Immoveable, // Torch
    .Creations_Moveable, // Chest
    
    // Beings
    .Beings, // Guy
    .Beings, // Frog
    .Beings, // Goblin
    .Beings, // Slime
    .Void_Eyes, // Void Eye
    .Beings, // Trader
    
    // Misc
    .Creations_Moveable, // Flag
];

CRAFTING_RECIPE_REQUIRED_ITEMS: [Crafting_Recipe.Count][]Item_Kind = .[
    // Crafting hud
    .[ .Shard ], // Mirror
    .[ .Coal ],  // Torch
    .[ .Stone ], // Chest

    // Trader hud
    .[ .Coin ], // Health Potion
    .[ .Coin ], // Strength Potion
    .[ .Coin ], // Shard
    .[ .Coin ], // Coal
];

CRAFTING_RECIPE_ENABLER: [Crafting_Recipe.Count]Entity_Kind = .[
    // Crafting hud
    .Count,  // Mirror
    .Count,  // Torch
    .Count,  // Chest
    
    // Trader hud    
    .Trader, // Health Potion
    .Trader, // Strength Potion
    .Trader, // Shard
    .Trader, // Coal
];

CRAFTING_RECIPE_REQUIRES_EMPTY_TARGET: [Crafting_Recipe.Count]bool = .[
    // Crafting hud
    true,  // Mirror
    false, // Torch
    true,  // Chest

    // Trader hud
    false, // Health Potion
    false, // Strength Potion
    false, // Shard
    false, // Coal
];



/* --------------------------------------------------- Stats -------------------------------------------------- */

Player_Stat_Kind :: enum {
    Moves;
    Deaths;
    Resurrections;
    Resources_Mined;
    Mirrors_Constructed;
    Coins_Spent_Total;
    Coins_Spent_Healing;
    Damage_Taken;
}

Global_Stat_Kind :: enum {
    Monsters_Killed;
    Sections_Reached;
}

Statistic :: struct {
    counter: s64;
}

format_player_stat :: (allocator: *Allocator, player_name: string, kind: Player_Stat_Kind, stat: Statistic) -> string {
    result: string = ---;

    f :: print_into_allocator;

    if #complete kind == {
      case .Moves;               result = f(allocator, "% has walked over % tiles!", player_name, stat.counter);
      case .Deaths;              result = f(allocator, "% has died % times!", player_name, stat.counter);
      case .Resurrections;       result = f(allocator, "% has resurrected over % players!", player_name, stat.counter);
      case .Resources_Mined;     result = f(allocator, "% has mined over % resources!", player_name, stat.counter);
      case .Mirrors_Constructed; result = f(allocator, "% has built over % mirrors!", player_name, stat.counter);
      case .Coins_Spent_Total;   result = f(allocator, "% has spent over % coins!", player_name, stat.counter);
      case .Coins_Spent_Healing; result = f(allocator, "% has spent over % coins healing themselves!", player_name, stat.counter);
      case .Damage_Taken;        result = f(allocator, "% has taken over % hearts of damage!", player_name, stat.counter / cast(s64) HEALTH_PER_HEART);
    }

    return result;
}

format_global_stat :: (allocator: *Allocator, kind: Global_Stat_Kind, stat: Statistic) -> string {
    result: string = ---;

    f :: print_into_allocator;

    if #complete kind == {
      case .Monsters_Killed;  result = f(allocator, "Over % monsters have been slain!", stat.counter);
      case .Sections_Reached; result = f(allocator, "Section % was reached!", stat.counter);
    }

    return result;
}



/* -------------------------------------------------- Helpers ------------------------------------------------- */

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

random_one_of :: (random: *Random_Generator, elements: []$T) -> T {
    index := random_u64_in(random, 0, elements.count);
    return elements[index];
}



/* ------------------------------------------------ File Baking ----------------------------------------------- */

bake_raw_file :: (filepath: string) -> string {
    file_content, success := read_entire_file(Default_Allocator, filepath);
    if !success {
        compiler_report_error(print_into_allocator(Default_Allocator, "[ASSET BAKE]: Failed to bake the raw file '%': The file does not exist.\n", filepath));
        return "";
    }

    return file_content;
}

// This turns a file path relative to the project root into an absolute file path on the current file system.
// This makes the build robust against when building in a different directory than the project root.
ASSET_FILE_PATH :: (root_path: string) -> string {
    current_directory := compiler_get_current_source_directory(); // This includes the 'shared' directory
    end_of_shared, found_directory := search_file_path_for_directory_delimiter_reverse(current_directory);
    assert(found_directory, "Whoops, can't make an absolute asset file path...");
    return print_into_allocator(Default_Allocator, "%/%", substring_view(current_directory, 0, end_of_shared), root_path);
}
