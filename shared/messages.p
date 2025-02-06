Message_Type :: enum {
    Player_Information :: 0x1;
    Player_Disconnect  :: 0x2;
    Request_Game_Start :: 0x3;
    Game_Start         :: 0x4;
    Create_Entity      :: 0x5;
    Destroy_Entity     :: 0x6;
    Move_Entity        :: 0x7;
    Player_State       :: 0x8;
    Player_Interact    :: 0x9;
    Receiver_State     :: 0xa;
}

Player_Information_Message :: struct {
    TYPE :: Message_Type.Player_Information;

    player_pid: Pid;
    name: string;
    entity_pid: Pid;
}

Player_Disconnect_Message :: struct {
    TYPE :: Message_Type.Player_Disconnect;
    player_pid: Pid;
}

Request_Game_Start_Message :: struct {
    TYPE :: Message_Type.Request_Game_Start;
}

Game_Start_Message :: struct {
    TYPE :: Message_Type.Game_Start;

    seed: s64;
    size: v2i;
}

Create_Entity_Message :: struct {
    TYPE :: Message_Type.Create_Entity;
    
    entity_pid: Pid;
    kind: Entity_Kind;
    position: v2i;
    rotation: Direction;
}

Destroy_Entity_Message :: struct {
    TYPE :: Message_Type.Destroy_Entity;
    entity_pid: Pid;
}

Move_Entity_Message :: struct {
    TYPE :: Message_Type.Move_Entity;
    
    entity_pid: Pid;
    position: v2i;
    rotation: Direction;
}

Player_State_Message :: struct {
    TYPE :: Message_Type.Player_State;
    
    entity_pid: Pid;
    state: Player_State;
    target_position: v2i;
    progress_time_in_seconds: f32;
}

Player_Interact_Message :: struct {
    TYPE :: Message_Type.Player_Interact;
    entity_pid: Pid;
}

Receiver_State_Message :: struct {
    TYPE :: Message_Type.Receiver_State;
    entity_pid: Pid;
    progress_time_in_seconds: f32;
}

Message :: struct {
    type: Message_Type;

    #using underlying: union {
        player_information: Player_Information_Message;
        player_disconnect: Player_Disconnect_Message;
        request_game_start: Request_Game_Start_Message;
        game_start: Game_Start_Message;
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
    msg.type = T.TYPE;
    return msg;
}

send_reliable_message :: (connection: *Virtual_Connection, message: *Message) {
    packet: Packet   = ---;
    packet.body_size = 0;

    serialize_bytes(*packet, message.type);

    if #complete message.type == {
      case .Request_Game_Start;

      case .Player_Information;
        serialize_bytes(*packet, message.player_information.player_pid);
        serialize_string(*packet, message.player_information.name);
        serialize_bytes(*packet, message.player_information.entity_pid);

      case .Player_Disconnect;
        serialize_bytes(*packet, message.player_disconnect.player_pid);

      case .Game_Start;
        serialize_bytes(*packet, message.game_start.seed);
        serialize_bytes(*packet, message.game_start.size.x);
        serialize_bytes(*packet, message.game_start.size.y);
        
      case .Create_Entity;
        serialize_bytes(*packet, message.create_entity.entity_pid);
        serialize_bytes(*packet, message.create_entity.kind);
        serialize_bytes(*packet, message.create_entity.position.x);
        serialize_bytes(*packet, message.create_entity.position.y);
        serialize_bytes(*packet, message.create_entity.rotation);
        
      case .Destroy_Entity;
        serialize_bytes(*packet, message.destroy_entity.entity_pid);
        
      case .Move_Entity;
        serialize_bytes(*packet, message.move_entity.entity_pid);
        serialize_bytes(*packet, message.move_entity.position.x);
        serialize_bytes(*packet, message.move_entity.position.y);
        serialize_bytes(*packet, message.move_entity.rotation);
        
      case .Player_State;
        serialize_bytes(*packet, message.player_state.entity_pid);
        serialize_bytes(*packet, message.player_state.state);
        serialize_bytes(*packet, message.player_state.target_position);
        serialize_bytes(*packet, message.player_state.progress_time_in_seconds);

      case .Player_Interact;
        serialize_bytes(*packet, message.player_state.entity_pid);
        
      case .Receiver_State;
        serialize_bytes(*packet, message.receiver_state.entity_pid);
        serialize_bytes(*packet, message.receiver_state.progress_time_in_seconds);
    }
    
    send_reliable_packet(connection, *packet, .Message);
}

read_message :: (connection: *Virtual_Connection, message: *Message) {
    deserialize_bytes(*connection.incoming_packet, *message.type);
    
    if #complete message.type == {
      case .Request_Game_Start;

      case .Player_Information;
        deserialize_bytes(*connection.incoming_packet,  *message.player_information.player_pid);
        deserialize_string(*connection.incoming_packet, *message.player_information.name);
        deserialize_bytes(*connection.incoming_packet,  *message.player_information.entity_pid);

      case .Player_Disconnect;
        deserialize_bytes(*connection.incoming_packet, *message.player_disconnect.player_pid);

      case .Game_Start;
        deserialize_bytes(*connection.incoming_packet, *message.game_start.seed);
        deserialize_bytes(*connection.incoming_packet, *message.game_start.size.x);
        deserialize_bytes(*connection.incoming_packet, *message.game_start.size.y);
        
      case .Create_Entity;
        deserialize_bytes(*connection.incoming_packet, *message.create_entity.entity_pid);
        deserialize_bytes(*connection.incoming_packet, *message.create_entity.kind);
        deserialize_bytes(*connection.incoming_packet, *message.create_entity.position.x);
        deserialize_bytes(*connection.incoming_packet, *message.create_entity.position.y);
        deserialize_bytes(*connection.incoming_packet, *message.create_entity.rotation);
    
      case .Destroy_Entity;
        deserialize_bytes(*connection.incoming_packet, *message.destroy_entity.entity_pid);
        
      case .Move_Entity;
        deserialize_bytes(*connection.incoming_packet, *message.move_entity.entity_pid);
        deserialize_bytes(*connection.incoming_packet, *message.move_entity.position.x);
        deserialize_bytes(*connection.incoming_packet, *message.move_entity.position.y);
        deserialize_bytes(*connection.incoming_packet, *message.move_entity.rotation);
        
      case .Player_State;
        deserialize_bytes(*connection.incoming_packet, *message.player_state.entity_pid);
        deserialize_bytes(*connection.incoming_packet, *message.player_state.state);
        deserialize_bytes(*connection.incoming_packet, *message.player_state.target_position);
        deserialize_bytes(*connection.incoming_packet, *message.player_state.progress_time_in_seconds);
    
      case .Player_Interact;
        deserialize_bytes(*connection.incoming_packet, *message.player_interact.entity_pid);
    
      case .Receiver_State;
        deserialize_bytes(*connection.incoming_packet, *message.receiver_state.entity_pid);
        deserialize_bytes(*connection.incoming_packet, *message.receiver_state.progress_time_in_seconds);
    }
}



#file_scope

serialize_bytes :: (packet: *Packet, data: $T) {
    assert(packet.body_size + size_of(T) <= packet.body.Capacity, "The packet ran out of space.");
    copy_memory(*packet.body[packet.body_size], *data, size_of(T));
    packet.body_size += size_of(T);
}

serialize_string :: (packet: *Packet, data: string) {
    assert(packet.body_size + size_of(s64) + data.count <= packet.body.Capacity, "The packet ran out of space.");
    copy_memory(*packet.body[packet.body_size], *data.count, size_of(s64));
    packet.body_size += size_of(s64);
    copy_memory(*packet.body[packet.body_size], data.data, data.count);
    packet.body_size += data.count;
}

deserialize_bytes :: (packet: *Packet, data: *$T) {
    assert(packet.body_read_offset + size_of(T) <= packet.body_size, "The packet ran out of available bytes.");
    copy_memory(data, *packet.body[packet.body_read_offset], size_of(T));
    packet.body_read_offset += size_of(T);
}

deserialize_string :: (packet: *Packet, data: *string) {
    assert(packet.body_read_offset + size_of(s64) <= packet.body_size, "The packet ran out of available bytes.");
    copy_memory(*data.count, *packet.body[packet.body_read_offset], size_of(s64));
    packet.body_read_offset += size_of(s64);
    assert(packet.body_read_offset + data.count <= packet.body_size, "The packet ran out of available bytes.");
    data.data = allocate(*temp, data.count);
    copy_memory(data.data, *packet.body[packet.body_read_offset], data.count);
    packet.body_read_offset += data.count;
}
