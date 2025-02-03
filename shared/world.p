#load "math/Vector.p";

v2i :: Vector2_Base(s32);
v2f :: Vector2_Base(f32);

Pid :: u32;

INVALID_PID: Pid : -1;

DIGGING_TIME: f32 : 5;

Entity_Kind :: enum {
    Inanimate;
    Player;
    Crystal;
    Stone;
    Emitter;
    Receiver;
}

Direction :: enum {
    North; // -Y
    East;  // +X
    South; // +Y
    West;  // -X
}

Player_State :: enum {
    Idle;
    Digging;
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