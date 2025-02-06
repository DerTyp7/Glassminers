#load "math/Vector.p";

v2i :: Vector2_Base(s32);
v2f :: Vector2_Base(f32);

Pid :: u32;

INVALID_PID: Pid : -1;

DIGGING_TIME:  f32 : 5;
RECEIVER_TIME: f32 : 5;

Entity_Kind :: enum {
    Inanimate;
    Player;
    Crystal;
    Stone;
    Emitter;
    Receiver;
    Mirror;
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

Interaction_Kind :: enum {
    Dig;
    Build;
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

reflect_direction :: (incoming: Direction, mirror: Direction) -> Direction, bool {
    if incoming == (mirror + 2) % Direction.Count then
        return (incoming + 3) % Direction.Count, true;
    else if incoming == (mirror + 3) % Direction.Count then
        return mirror, true;
    else
        return .Count, false;
}



recalculate_emitters :: (world: *World) {
    for i := 0; i < world.entities.count; ++i {
        entity := array_get_pointer(*world.entities, i);
        if entity.kind != .Emitter continue;

        emitter := down(entity, Emitter);
        emitter.fields.allocator = *temp;
        array_clear_without_deallocation(*emitter.fields);
        
        direction := entity.physical_rotation;
        field     := entity.physical_position;
        
        while true {
            vector := vector_from_direction(direction);
            field.x += vector.x;
            field.y += vector.y;
            if !position_in_bounds(world, field) break;
            
            blocking := get_entity_at_position(world, field);
            
            if blocking == null {
                array_add(*emitter.fields, field);
            } else if blocking.kind == .Mirror {
                array_add(*emitter.fields, field);
                
                reflected_direction, reflection_success := reflect_direction(direction, blocking.physical_rotation);
                
                if reflection_success then
                    direction = reflected_direction;
                else break;
            } else if blocking.kind == .Player {
                array_add(*emitter.fields, field);
            } else if blocking.kind == .Receiver {
                array_add(*emitter.fields, field);
                break;
            } else {
                break;
            }
        }
    }
}
