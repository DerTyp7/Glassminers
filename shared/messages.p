Player_Id :: u32;

Message_Type :: enum {
    Player_Information :: 0x1;
    Player_Disconnect  :: 0x2;
    Request_Game_Start :: 0x3;
    Game_Start         :: 0x4;
}

Player_Information_Message :: struct {
    TYPE :: Message_Type.Player_Information;

    id: Player_Id;
    name: string;
}

Player_Disconnect_Message :: struct {
    TYPE :: Message_Type.Player_Disconnect;

    id: Player_Id;
}

Request_Game_Start_Message :: struct {
    TYPE :: Message_Type.Request_Game_Start;
}

Game_Start_Message :: struct {
    TYPE :: Message_Type.Game_Start;

    seed: s64;
}

Message :: struct {
    type: Message_Type;

    #using underlying: union {
        player_information: Player_Information_Message;
        player_disconnect: Player_Disconnect_Message;
        request_game_start: Request_Game_Start_Message;
        game_start: Game_Start_Message;
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
        serialize_bytes(*packet, message.player_information.id);
        serialize_string(*packet, message.player_information.name);

      case .Player_Disconnect;
        serialize_bytes(*packet, message.player_disconnect.id);

      case .Game_Start;
        serialize_bytes(*packet, message.game_start.seed);
    }
    
    send_reliable_packet(connection, *packet, .Message);
}

read_message :: (connection: *Virtual_Connection, message: *Message) {
    message.type = deserialize_bytes(*connection.incoming_packet, Message_Type);
    
    if #complete message.type == {
      case .Request_Game_Start;

      case .Player_Information;
        message.player_information.id   = deserialize_bytes(*connection.incoming_packet, Player_Id);
        message.player_information.name = deserialize_string(*connection.incoming_packet);

      case .Player_Disconnect;
        message.player_disconnect.id = deserialize_bytes(*connection.incoming_packet, Player_Id);

      case .Game_Start;
        message.game_start.seed = deserialize_bytes(*connection.incoming_packet, s64);
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

deserialize_bytes :: (packet: *Packet, $T: Type) -> T {
    assert(packet.body_read_offset + size_of(T) <= packet.body_size, "The packet ran out of available bytes.");
    result: T = ---;
    copy_memory(*result, *packet.body[packet.body_read_offset], size_of(T));
    packet.body_read_offset += size_of(T);
    return result;
}

deserialize_string :: (packet: *Packet) -> string {
    assert(packet.body_read_offset + size_of(s64) <= packet.body_size, "The packet ran out of available bytes.");
    result: string = ---;
    copy_memory(*result.count, *packet.body[packet.body_read_offset], size_of(s64));
    packet.body_read_offset += size_of(s64);
    assert(packet.body_read_offset + result.count <= packet.body_size, "The packet ran out of available bytes.");
    result.data = allocate(*temp, result.count);
    copy_memory(result.data, *packet.body[packet.body_read_offset], result.count);
    packet.body_read_offset += result.count;
    return result;
}
