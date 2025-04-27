Message_Type :: enum {
    Player_Information :: 0x1;
    Player_Disconnect;
    Request_Game_Start;
    Game_Start;
    Game_Over;
    Create_Entity;
    Destroy_Entity;
    Move_Entity;
    Player_State;
    Player_Interact;
    Receiver_State;
}

Player_Information_Message :: struct {
    MSG_TYPE :: Message_Type.Player_Information;
    player_pid: Pid;
    name: string;
    entity_pid: Pid;
}

Player_Disconnect_Message :: struct {
    MSG_TYPE :: Message_Type.Player_Disconnect;
    player_pid: Pid;
}

Request_Game_Start_Message :: struct {
    MSG_TYPE :: Message_Type.Request_Game_Start;
}

Game_Start_Message :: struct {
    MSG_TYPE :: Message_Type.Game_Start;
    seed: s64;
    size: v2i;
}

Game_Over_Message :: struct {
    MSG_TYPE :: Message_Type.Game_Over;
    you_won: bool;
}

Create_Entity_Message :: struct {
    MSG_TYPE :: Message_Type.Create_Entity;
    entity_pid: Pid;
    kind: Entity_Kind;
    position: v2i;
    rotation: Direction;
}

Destroy_Entity_Message :: struct {
    MSG_TYPE :: Message_Type.Destroy_Entity;
    entity_pid: Pid;
}

Move_Entity_Message :: struct {
    MSG_TYPE :: Message_Type.Move_Entity;
    entity_pid: Pid;
    position: v2i;
    rotation: Direction;
}

Player_State_Message :: struct {
    MSG_TYPE :: Message_Type.Player_State;
    entity_pid: Pid;
    state: Player_State;
    target_position: v2i;
    progress_time_in_seconds: f32;
    carrying_item: Entity_Kind;
}

Player_Interact_Message :: struct {
    MSG_TYPE :: Message_Type.Player_Interact;
    entity_pid: Pid;
    interaction_kind: Interaction_Kind;
}

Receiver_State_Message :: struct {
    MSG_TYPE :: Message_Type.Receiver_State;
    entity_pid: Pid;
    progress_time_in_seconds: f32;
}

Message :: struct {
    msg_type: Message_Type;
    local_type_id: Type;
    
    #using underlying: union {
        player_information: Player_Information_Message;
        player_disconnect: Player_Disconnect_Message;
        request_game_start: Request_Game_Start_Message;
        game_start: Game_Start_Message;
        game_over: Game_Over_Message;
        create_entity: Create_Entity_Message;
        destroy_entity: Destroy_Entity_Message;
        move_entity: Move_Entity_Message;
        player_state: Player_State_Message;
        player_interact: Player_Interact_Message;
        receiver_state: Receiver_State_Message;
    };
}


make_message :: ($T: Type) -> Message {
    msg: Message = ---;
    msg.msg_type = T.MSG_TYPE;
    msg.local_type_id = type_id(T);
    return msg;
}

send_reliable_message :: (connection: *Virtual_Connection, message: *Message) {
    packet: Packet   = ---;
    packet.body_size = 0;

    serialize(*packet, *message.msg_type, type_info(Message_Type));
    serialize(*packet, *message.underlying, type_info(message.local_type_id));
    send_reliable_packet(connection, *packet, .Message);
}

read_message :: (connection: *Virtual_Connection, message: *Message) {
    deserialize(*connection.incoming_packet, *message.msg_type, type_info(Message_Type));
    message.local_type_id = message_type_to_type_id(message.msg_type);
    deserialize(*connection.incoming_packet, *message.underlying, type_info(message.local_type_id));
}



#file_scope


message_type_to_type_id :: (type: Message_Type) -> Type {
    result: Type = type_id(void);

    if #complete type == {
      case .Player_Information; result = type_id(Player_Information_Message);
      case .Player_Disconnect;  result = type_id(Player_Disconnect_Message);
      case .Request_Game_Start; result = type_id(Request_Game_Start_Message);
      case .Game_Start;         result = type_id(Game_Start_Message);
      case .Game_Over;          result = type_id(Game_Over_Message);
      case .Create_Entity;      result = type_id(Create_Entity_Message);
      case .Destroy_Entity;     result = type_id(Destroy_Entity_Message);
      case .Move_Entity;        result = type_id(Move_Entity_Message); 
      case .Player_State;       result = type_id(Player_State_Message);
      case .Player_Interact;    result = type_id(Player_Interact_Message);
      case .Receiver_State;     result = type_id(Receiver_State_Message);
      case; panic("Received an unknown message type, cannot convert into a local message type id.");
    }

    return result;
}

serialize :: (packet: *Packet, pointer: *void, type: *Type_Info) {
    if #complete type.kind == {
      case .Procedure, .Type, .Variadic, .Any, .Pointer, .Slice, .Array, .Void;
        panic("We cannot serialize values of this type from messages!");

      case .Integer, .Boolean, .Floating_Point, .Enum;
        assert(packet.body_size + type.size_in_bytes <= packet.body.Capacity, "The packet ran out of space.");
        copy_memory(*packet.body[packet.body_size], pointer, type.size_in_bytes);
        packet.body_size += type.size_in_bytes;

      case .String;
        _string := cast(*string) pointer;
        assert(packet.body_size + size_of(s64) + _string.count <= packet.body.Capacity, "The packet ran out of space.");
        copy_memory(*packet.body[packet.body_size], *_string.count, size_of(s64));
        packet.body_size += size_of(s64);
        copy_memory(*packet.body[packet.body_size], _string.data, _string.count);
        packet.body_size += _string.count;

      case .Struct;
        _struct := cast(*Type_Info_Struct) type;
        for i := 0; i < _struct.members.count; ++i {
            member := *_struct.members[i];
            serialize(packet, pointer + member.offset_in_bytes, member.type_info);
        }
    }
}

deserialize :: (packet: *Packet, pointer: *void, type: *Type_Info) {
    if #complete type.kind == {
      case .Procedure, .Type, .Variadic, .Any, .Pointer, .Slice, .Array, .Void;
        panic("We cannot deserialize values of this type from messages!");
        
      case .Integer, .Boolean, .Floating_Point, .Enum;
        assert(packet.body_read_offset + type.size_in_bytes <= packet.body_size, "The packet ran out of available bytes.");
        copy_memory(pointer, *packet.body[packet.body_read_offset], type.size_in_bytes);
        packet.body_read_offset += type.size_in_bytes;

      case .String;
        _string := cast(*string) pointer;
        assert(packet.body_read_offset + size_of(s64) <= packet.body_size, "The packet ran out of available bytes.");
        copy_memory(*_string.count, *packet.body[packet.body_read_offset], size_of(s64));
        packet.body_read_offset += size_of(s64);
        assert(packet.body_read_offset + _string.count <= packet.body_size, "The packet ran out of available bytes.");
        _string.data = allocate(*temp, _string.count);
        copy_memory(_string.data, *packet.body[packet.body_read_offset], _string.count);
        packet.body_read_offset += _string.count;

        case .Struct;
        _struct := cast(*Type_Info_Struct) type;
        for i := 0; i < _struct.members.count; ++i {
            member := *_struct.members[i];
            deserialize(packet, pointer + member.offset_in_bytes, member.type_info);
        }        
    }
}
