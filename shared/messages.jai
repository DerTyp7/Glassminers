Message_Type :: enum {
    Client_Disconnect :: 0x1;
    Player_Information;
    Remove_Local_Player;
    Request_Game_Start;
    Game_Pause;
    Game_Start;
    Game_Over;
    World_Resize;
    Create_Entity;
    Destroy_Entity;
    Move_Entity;
    Entity_Health;
    Guy_State;
    Guy_Input;
    Emitter_State;
    Item_Stack_State;
    Chest_State;
    Frog_State;
    Goblin_State;
    Slime_State;
    Score_State;
}

Client_Disconnect_Message :: struct {
    MSG_TYPE :: Message_Type.Client_Disconnect;
    client_pid: Pid;
}

Player_Information_Message :: struct {
    MSG_TYPE :: Message_Type.Player_Information;
    local_player_index: s64;
    client_pid: Pid;
    guy_pid: Pid;
    name: string;
}

Remove_Local_Player_Message :: struct {
    MSG_TYPE :: Message_Type.Remove_Local_Player;
    local_player_index: s64;
    client_pid: Pid;
}

Request_Game_Start_Message :: struct {
    MSG_TYPE :: Message_Type.Request_Game_Start;
    campaign: Campaign;
}

Game_Pause_Message :: struct {
    MSG_TYPE :: Message_Type.Game_Pause;
    client_pid: Pid;
    should_pause: bool;
}

Game_Start_Message :: struct {
    MSG_TYPE :: Message_Type.Game_Start;
    seed: s64;
    size: v2i;
}

Game_Over_Message :: struct {
    MSG_TYPE :: Message_Type.Game_Over;
    point_score: u64;
}

World_Resize_Message :: struct {
    MSG_TYPE :: Message_Type.World_Resize;
    new_world_size: v2i;
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

Entity_Health_Message :: struct {
    MSG_TYPE :: Message_Type.Entity_Health;
    entity_pid: Pid;
    new_health: f32;
}

Guy_State_Message :: struct {
    MSG_TYPE :: Message_Type.Guy_State;
    entity_pid: Pid;
    state: Guy_State;
    target_position: v2i;
    carrying_item: Item_Kind;
    strength_t: f32;
}

Guy_Input_Message :: struct {
    MSG_TYPE :: Message_Type.Guy_Input;
    guy_pid: Pid;
    position: v2i;
    wants_to_move: bool;
    aim_direction: Direction;
    interaction_kind: Interaction_Kind;
    crafting_recipe: Crafting_Recipe;
    cheat: Cheat;
    chest_item: Item_Kind;
}

Emitter_State_Message :: struct {
    MSG_TYPE :: Message_Type.Emitter_State;
    entity_pid: Pid;
    state: Emitter_State;
    current_charge: f32;
}

Item_Stack_State_Message :: struct {
    MSG_TYPE :: Message_Type.Item_Stack_State;
    entity_pid: Pid;
    item_kind: Item_Kind;
    count: s64;
}

Chest_State_Message :: struct {
    MSG_TYPE :: Message_Type.Chest_State;
    entity_pid: Pid;
    items: [CHEST_CAPACITY]Item_Kind = ---;
    item_count: s64;
}

Frog_State_Message :: struct {
    MSG_TYPE :: Message_Type.Frog_State;
    entity_pid: Pid;
    state: Frog_State;
}

Goblin_State_Message :: struct {
    MSG_TYPE :: Message_Type.Goblin_State;
    entity_pid: Pid;
    state: Goblin_State;
}

Slime_State_Message :: struct {
    MSG_TYPE :: Message_Type.Slime_State;
    entity_pid: Pid;
    state: Slime_State;
}

Score_State_Message :: struct {
    MSG_TYPE :: Message_Type.Score_State;
    point_score: u64;
}

Message :: struct {
    msg_type: Message_Type;
    local_type_id: Type;
    
    #using underlying: union {
        client_disconnect:  Client_Disconnect_Message;
        player_information: Player_Information_Message;
        remove_local_player: Remove_Local_Player_Message;
        request_game_start: Request_Game_Start_Message;
        game_pause: Game_Pause_Message;
        game_start: Game_Start_Message;
        game_over: Game_Over_Message;
        world_resize: World_Resize_Message;
        create_entity: Create_Entity_Message;
        destroy_entity: Destroy_Entity_Message;
        move_entity: Move_Entity_Message;
        entity_health: Entity_Health_Message;
        guy_state: Guy_State_Message;
        guy_input: Guy_Input_Message;
        emitter_state: Emitter_State_Message;
        item_stack_state: Item_Stack_State_Message;
        chest_state: Chest_State_Message;
        frog_state: Frog_State_Message;
        goblin_state: Goblin_State_Message;
        slime_state: Slime_State_Message;
        score_state: Score_State_Message;
    };
}


make_message :: ($T: Type) -> Message {
    msg: Message = ---;
    msg.msg_type = T.MSG_TYPE;
    msg.local_type_id = type_id(T);
    return msg;
}

make_message_from :: (underlying: $T) -> Message {
    msg := make_message(T);
    copy_memory(*msg.underlying, *underlying, size_of(T));
    return msg;
}

send_reliable_messages :: (connection: *Virtual_Connection, messages: *[..]Message) {
    packet: Packet = ---;
    packet.body_size = 0;
    
    for i := 0; i < messages.count; ++i {
        message := array_get_pointer(messages, i);

#if LOG_MESSAGES {
        print_message(message, " OUT: ");
}
        
        if !serialize_message(*packet, message) {
            send_packet(connection, *packet, .Message); // We're using TCP anyway, so we don't have to bother with this entire reliability overhead!
            packet.body_size = 0;
            
            success := serialize_message(*packet, message);
            assert(success, "This message did not fit into a single packet!");
        }
    }

    if packet.body_size {
        send_packet(connection, *packet, .Message); // We're using TCP anyway, so we don't have to bother with this entire reliability overhead!
    }
}

send_reliable_message :: (connection: *Virtual_Connection, message: *Message) {
#if LOG_MESSAGES {
    print_message(message, " OUT: ");
}

    packet: Packet   = ---;
    packet.body_size = 0;
    success := serialize_message(*packet, message);
    assert(success, "This message did not fit into a single packet!");
    
    send_packet(connection, *packet, .Message); // We're using TCP anyway, so we don't have to bother with this entire reliability overhead!
}

read_message :: (packet: *Packet, message: *Message) -> bool {
    if packet.body_read_offset >= packet.body_size return false;

    deserialize(packet, *message.msg_type, type_info(Message_Type));
    message.local_type_id = message_type_to_type_id(message.msg_type);
    deserialize(packet, *message.underlying, type_info(message.local_type_id));

#if LOG_MESSAGES {
    print_message(message, " IN : ");
}

    return true;
}



#file_scope


message_type_to_type_id :: (type: Message_Type) -> Type {
    result: Type = type_id(void);

    if #complete type == {
      case .Client_Disconnect;   result = type_id(Client_Disconnect_Message);
      case .Player_Information;  result = type_id(Player_Information_Message);
      case .Remove_Local_Player; result = type_id(Remove_Local_Player_Message);
      case .Request_Game_Start;  result = type_id(Request_Game_Start_Message);
      case .Game_Pause;          result = type_id(Game_Pause_Message);
      case .Game_Start;          result = type_id(Game_Start_Message);
      case .Game_Over;           result = type_id(Game_Over_Message);
      case .World_Resize;        result = type_id(World_Resize_Message);
      case .Create_Entity;       result = type_id(Create_Entity_Message);
      case .Destroy_Entity;      result = type_id(Destroy_Entity_Message);
      case .Move_Entity;         result = type_id(Move_Entity_Message); 
      case .Entity_Health;       result = type_id(Entity_Health_Message);
      case .Guy_State;           result = type_id(Guy_State_Message);
      case .Guy_Input;           result = type_id(Guy_Input_Message);
      case .Emitter_State;       result = type_id(Emitter_State_Message);
      case .Item_Stack_State;    result = type_id(Item_Stack_State_Message);
      case .Chest_State;         result = type_id(Chest_State_Message);
      case .Frog_State;          result = type_id(Frog_State_Message);
      case .Goblin_State;        result = type_id(Goblin_State_Message);
      case .Slime_State;         result = type_id(Slime_State_Message);
      case .Score_State;         result = type_id(Score_State_Message);
    }

    return result;
}

serialize :: (packet: *Packet, pointer: *void, type: *Type_Info) -> bool {
    success := true;

    if #complete type.kind == {
      case .Procedure, .Type, .Variadic, .Any, .Pointer, .Slice, .Void;
        panic("We cannot serialize values of this type from messages!");
        success = false;
        
      case .Integer, .Boolean, .Floating_Point, .Enum;
        success = packet.body_size + type.size_in_bytes <= packet.body.Capacity;
        if success {
            copy_memory(*packet.body[packet.body_size], pointer, type.size_in_bytes);
            packet.body_size += type.size_in_bytes;
        }

      case .String;
        _string := cast(*string) pointer;

        success = packet.body_size + size_of(s64) + _string.count <= packet.body.Capacity;

        if success {
            copy_memory(*packet.body[packet.body_size], *_string.count, size_of(s64));
            packet.body_size += size_of(s64);
            copy_memory(*packet.body[packet.body_size], _string.data, _string.count);
            packet.body_size += _string.count;
        }
            
      case .Array;
        _array := cast(*Type_Info_Array) type;

        offset_before := packet.body_size;
        success = true;
        
        for i := 0; i < _array.count; ++i {
            success &= serialize(packet, pointer + i * _array.element_type_info.size_in_bytes, _array.element_type_info);
        }

        if !success packet.body_size = offset_before;

      case .Struct;
        _struct := cast(*Type_Info_Struct) type;

        offset_before := packet.body_size;
        success = true;
        
        for i := 0; i < _struct.members.count; ++i {
            member := *_struct.members[i];
            success &= serialize(packet, pointer + member.offset_in_bytes, member.type_info);
        }

        if !success packet.body_size = offset_before;
    }

    return success;
}

serialize_message :: (packet: *Packet, message: *Message) -> bool {
    offset_before := packet.body_size;

    success := serialize(packet, *message.msg_type, type_info(Message_Type)) &&
        serialize(packet, *message.underlying, type_info(message.local_type_id));

    if !success packet.body_size = offset_before;

    return success;
}

deserialize :: (packet: *Packet, pointer: *void, type: *Type_Info) {
    if #complete type.kind == {
      case .Procedure, .Type, .Variadic, .Any, .Pointer, .Slice, .Void;
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

      case .Array;
        _array := cast(*Type_Info_Array) type;
        for i := 0; i < _array.count; ++i {
            deserialize(packet, pointer + i * _array.element_type_info.size_in_bytes, _array.element_type_info);
        }
        
      case .Struct;
        _struct := cast(*Type_Info_Struct) type;
        for i := 0; i < _struct.members.count; ++i {
            member := *_struct.members[i];
            deserialize(packet, pointer + member.offset_in_bytes, member.type_info);
        }        
    }
}

print_message :: (message: *Message, prefix: string) {
    builder: String_Builder;
    create_string_builder(*builder, *temp);

    sprint(*builder, prefix);
    sprint(*builder, "%", message.msg_type);
    
    if #complete message.msg_type == {
      case .Client_Disconnect;  sprint(*builder, "%", message.client_disconnect);
      case .Player_Information; sprint(*builder, "%", message.player_information);
      case .Remove_Local_Player; sprint(*builder, "%", message.remove_local_player);
      case .Request_Game_Start; sprint(*builder, "%", message.request_game_start);
      case .Game_Pause;         sprint(*builder, "%", message.game_pause);
      case .Game_Start;         sprint(*builder, "%", message.game_start);
      case .Game_Over;          sprint(*builder, "%", message.game_over);
      case .World_Resize;       sprint(*builder, "%", message.world_resize);
      case .Create_Entity;      sprint(*builder, "%", message.create_entity);
      case .Destroy_Entity;     sprint(*builder, "%", message.destroy_entity);
      case .Move_Entity;        sprint(*builder, "%", message.move_entity);
      case .Entity_Health;      sprint(*builder, "%", message.entity_health);
      case .Guy_State;          sprint(*builder, "%", message.guy_state);
      case .Guy_Input;          sprint(*builder, "%", message.guy_input);
      case .Emitter_State;      sprint(*builder, "%", message.emitter_state);
      case .Item_Stack_State;   sprint(*builder, "%", message.item_stack_state);
      case .Chest_State;        sprint(*builder, "%", message.chest_state);
      case .Frog_State;         sprint(*builder, "%", message.frog_state);
      case .Goblin_State;       sprint(*builder, "%", message.goblin_state);
      case .Slime_State;        sprint(*builder, "%", message.slime_state);
      case .Score_State;        sprint(*builder, "%", message.score_state);
    }
    
    logprint(.Debug, finish_string_builder(*builder));
}
