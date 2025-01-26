Player_Id :: u32;

Player_Information_Message :: struct {
    id: Player_Id;
    name: string;
}

Message :: struct {
    type: Type; // This is type_id of the underlying message

    #using underlying: union {
        player_information: Player_Information_Message;
    };
}

send_reliable_message :: (connection: *Virtual_Connection, message: *Message) {
    packet: Packet   = ---;
    packet.body_size = 0;

    serialize_bytes(*packet, message.type);

    if message.type == {
      case type_id(Player_Information_Message);
        serialize_bytes(*packet, message.player_information.id);
        serialize_string(*packet, message.player_information.name);
    }
    
    send_reliable_packet(connection, *packet, .Message);
}

read_message :: (connection: *Virtual_Connection, message: *Message) {
    message.type = deserialize_bytes(*connection.incoming_packet, Type);
    
    if message.type == {
      case type_id(Player_Information_Message);
        message.player_information.id = deserialize_bytes(*connection.incoming_packet, Player_Id);
        message.player_information.name = deserialize_string(*connection.incoming_packet);
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
