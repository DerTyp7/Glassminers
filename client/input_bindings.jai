Input_Binding_Check :: enum bitfield {
    Pressed;
    Held;
    Released;
}

Input_Binding_Kind :: enum {
    Keyboard;
    Gamepad_Button;
    Gamepad_Gesture;
}

Input_Device :: enum {
    Keyboard :: 0x1;
    Gamepad  :: 0x2;
    ALL :: .Keyboard | .Gamepad;
}

Input_Action :: enum {
    Toggle_Pause_Menu;
    Toggle_Fullscreen;

    Move_North;
    Move_East;
    Move_South;
    Move_West;
    Look_North;
    Look_East;
    Look_South;
    Look_West;
    Turn_Modifier;
    
    Interact_Primary;
    Interact_Secondary;

    Hud_Toggle;
    Hud_Close;
    Hud_Confirm;
    Hud_Left;
    Hud_Right;

    Cheat_Menu_Toggle;
    Developer_Panel_Toggle;
    Message_History_Panel_Toggle;
    Sound_Hud_Toggle;
    Shadow_Hud_Toggle;
}

Input_Binding :: struct {
    kind: Input_Binding_Kind;

    #using data: union {
        keycode: Key_Code;
        gamepad_button: Gamepad_Button_Code;
        gamepad_gesture: Gamepad_Gesture_Code;
    };
}

Input_Binder :: struct {
    active_input_device: Input_Device = 0;
    allowed_input_devices: Input_Device = 0;
    gamepad_index := 0;
    input_action_held: [Input_Action.Count]bool = .[ false ];
    input_action_hold_time: [Input_Action.Count]f32 = .[ 0 ]; // If an input action is currently being held for this binder, this value will count up the frame time. This is then used to determine repeating input actions
}

Input_Binding_Tracker :: struct {
    Gamepad_Tracker :: struct {
        buttons_fired_this_frame: [..]Gamepad_Button_Code;
        gestures_fired_this_frame: [..]Gamepad_Gesture_Code;
    }
    
    keys_fired_this_frame: [..]Key_Code; // If a key already triggered any input action this frame, it is added to this list
    gamepads: [WINDOW_MAX_GAMEPADS]Gamepad_Tracker;
}



register_all_input_bindings :: (client: *Client) {
    keycode :: (keycode: Key_Code) -> Input_Binding {
        binding: Input_Binding = ---;
        binding.kind = .Keyboard;
        binding.keycode = keycode;
        return binding;
    }

    gamepad_button :: (button: Gamepad_Button_Code) -> Input_Binding {
        binding: Input_Binding = ---;
        binding.kind = .Gamepad_Button;
        binding.gamepad_button = button;
        return binding;
    }

    gamepad_gesture :: (gesture: Gamepad_Gesture_Code) -> Input_Binding {
        binding: Input_Binding = ---;
        binding.kind = .Gamepad_Gesture;
        binding.gamepad_gesture = gesture;
        return binding;
    }
    
    //
    // The input bindings need to live forever, but making slices in here allocates them on the
    // stack (and so they are dead when the procedure exits).
    // Therefore, for easier setup I construct them locally here, and then copy them into the
    // engine allocator later on.
    //
    
    ib: [Input_Action.Count][]Input_Binding = .[];
    ib[.Toggle_Pause_Menu]  = .[ keycode(.Escape), gamepad_button(.PS_Options), gamepad_button(.XBox_Menu) ];
    ib[.Toggle_Fullscreen]  = .[ keycode(.F11) ];
    ib[.Move_North]         = .[ keycode(.W), gamepad_gesture(.Left_Stick_Swipe_Up) ];
    ib[.Move_East]          = .[ keycode(.D), gamepad_gesture(.Left_Stick_Swipe_Right) ];
    ib[.Move_South]         = .[ keycode(.S), gamepad_gesture(.Left_Stick_Swipe_Down) ];
    ib[.Move_West]          = .[ keycode(.A), gamepad_gesture(.Left_Stick_Swipe_Left) ];
    ib[.Look_North]         = .[ keycode(.Arrow_Up),    gamepad_gesture(.Right_Stick_Swipe_Up) ];
    ib[.Look_East]          = .[ keycode(.Arrow_Right), gamepad_gesture(.Right_Stick_Swipe_Right) ];
    ib[.Look_South]         = .[ keycode(.Arrow_Down),  gamepad_gesture(.Right_Stick_Swipe_Down) ];
    ib[.Look_West]          = .[ keycode(.Arrow_Left),  gamepad_gesture(.Right_Stick_Swipe_Left) ];
    ib[.Turn_Modifier]      = .[ keycode(.Shift), gamepad_button(.PS_Circle), gamepad_button(.XBox_B) ];
    ib[.Interact_Primary]   = .[ keycode(.Space), gamepad_button(.PS_Cross), gamepad_button(.XBox_A) ];
    ib[.Interact_Secondary] = .[ keycode(.E), gamepad_button(.PS_Square), gamepad_button(.XBox_X) ];
    ib[.Hud_Toggle]         = .[ keycode(.E), gamepad_button(.PS_Square), gamepad_button(.XBox_X) ];
    ib[.Hud_Close]          = .[ keycode(.Escape), gamepad_button(.PS_Circle), gamepad_button(.XBox_B) ];
    ib[.Hud_Confirm]        = .[ keycode(.Space), gamepad_button(.PS_Cross), gamepad_button(.XBox_A) ];
    ib[.Hud_Left]           = .[ keycode(.A), keycode(.Arrow_Left),  gamepad_button(.Left_Bumper) ];
    ib[.Hud_Right]          = .[ keycode(.D), keycode(.Arrow_Right), gamepad_button(.Right_Bumper) ];
    ib[.Cheat_Menu_Toggle]  = .[ keycode(.C), gamepad_button(.PS_Triangle), gamepad_button(.XBox_Y) ];
    ib[.Developer_Panel_Toggle]       = .[ keycode(.F5) ];
    ib[.Message_History_Panel_Toggle] = .[ keycode(.F6) ];
    ib[.Sound_Hud_Toggle]             = .[ keycode(.F7) ];
    ib[.Shadow_Hud_Toggle]            = .[ keycode(.F8) ];

    for i := 0; i < ib.Capacity; ++i {
        client.input_bindings[i] = copy_array(*client.engine_allocator, ib[i]);
    }

    MOVE_INTERVAL: f32 : 0.33;
    client.input_action_repetition_intervals[.Move_North] = MOVE_INTERVAL;
    client.input_action_repetition_intervals[.Move_East]  = MOVE_INTERVAL;
    client.input_action_repetition_intervals[.Move_South] = MOVE_INTERVAL;
    client.input_action_repetition_intervals[.Move_West]  = MOVE_INTERVAL;

    client.global_input_binder.active_input_device = .Keyboard;
    client.global_input_binder.allowed_input_devices = .ALL;
}

input_action_fired_globally :: (client: *Client, action: Input_Action, check: Input_Binding_Check) -> bool {
    return check_input_binder_for_action(client, *client.global_input_binder, action, check);
}

input_action_fired_for_local_player :: (client: *Client, local_player: *Local_Player, action: Input_Action, check: Input_Binding_Check) -> bool {
    return check_input_binder_for_action(client, *local_player.input_binder, action, check);
}

update_input_binders :: (client: *Client) {
    update_input_binder(client, *client.global_input_binder);

    if client.current_state == .Ingame {
        for i := 0; i < client.local_player_count; ++i {
            update_input_binder(client, *client.local_players[i].input_binder);
        }
    }
}

reset_input_binding_tracker :: (client: *Client) {
    array_clear(*client.input_binding_tracker.keys_fired_this_frame);
    client.input_binding_tracker.keys_fired_this_frame.allocator = *temp;

    for i := 0; i < client.input_binding_tracker.gamepads.Capacity; ++i {
        gamepad := *client.input_binding_tracker.gamepads[i];
        array_clear(*gamepad.buttons_fired_this_frame);
        array_clear(*gamepad.gestures_fired_this_frame);
    }
}

input_action_string :: (action: Input_Action) -> string {
    name: string = ---;

    if #complete action == {
      case .Toggle_Pause_Menu;      name = "Pause Game";
      case .Toggle_Fullscreen;      name = "Toggle Fullscreen";
      case .Move_North;             name = "Move Up";
      case .Move_East;              name = "Move Right";
      case .Move_South;             name = "Move Down";
      case .Move_West;              name = "Move Left";
      case .Look_North;             name = "Turn Up";
      case .Look_East;              name = "Turn Right";
      case .Look_South;             name = "Turn Down";
      case .Look_West;              name = "Turn Left";
      case .Turn_Modifier;          name = "Hold to turn";
      case .Interact_Primary;       name = "Primary Interaction";
      case .Interact_Secondary;     name = "Secondary Interaction";
      case .Hud_Toggle;             name = "Toggle Interaction Wheel";
      case .Hud_Close;              name = "Close Interaction Wheel";
      case .Hud_Confirm;            name = "Confirm in Wheel";
      case .Hud_Left;               name = "Left in Wheel";
      case .Hud_Right;              name = "Right in Wheel";
      case .Cheat_Menu_Toggle;      name = "Toggle Cheat Wheel";
      case .Developer_Panel_Toggle; name = "Toggle Dev Panel";
      case .Message_History_Panel_Toggle; name = "Toggle Message History";
      case .Sound_Hud_Toggle;       name = "Toggle Sound Hud";
      case .Shadow_Hud_Toggle;      name = "Toggle Shadow Hud";
    }

    return name;
}

input_action_available :: (action: Input_Action) -> bool {
    #if !DEVELOPER {
        available: bool = ---;

        if action == {
          case .Cheat_Menu_Toggle, .Developer_Panel_Toggle, .Message_History_Panel_Toggle, .Sound_Hud_Toggle, .Shadow_Hud_Toggle; available = false;
          case; available = true;
        }

        return available;
    } #else {
        return true;
    }
}

input_bindings_string :: (client: *Client, action: Input_Action) -> string {
    builder: String_Builder = ---;
    create_string_builder(*builder, *temp);
    sprint(*builder, "`");

    // @Incomplete: Only append input bindings for input devices that are actually active...?

    for i := 0; i < client.input_bindings[action].count; ++i {
        if i > 0 {
            sprint(*builder, " // ");
        }

        binding := *client.input_bindings[action][i];
        if #complete binding.kind == {
          case .Keyboard;        sprint(*builder, "%", string_from_key_code(binding.keycode));
          case .Gamepad_Button;  sprint(*builder, "%", string_from_gamepad_button_code(binding.gamepad_button));
          case .Gamepad_Gesture; sprint(*builder, "%", string_from_gamepad_gesture_code(binding.gamepad_gesture));
        }
    }

    sprint(*builder, "`");

    return finish_string_builder(*builder);
}



#file_scope

INPUT_BINDING_KIND_DEVICE: [Input_Binding_Kind.Count]Input_Device : .[
        .Keyboard,
        .Gamepad,
        .Gamepad,
];

check_input_binding_held :: (client: *Client, binder: *Input_Binder, binding: *Input_Binding) -> bool {
    if #complete binding.kind == {
      case .Keyboard; return client.window.keys[binding.keycode] & .Down;
      case .Gamepad_Button; return binder.gamepad_index < client.window.connected_gamepads && client.window.gamepads[binder.gamepad_index].buttons[binding.gamepad_button] & .Down;
      case .Gamepad_Gesture; return binder.gamepad_index < client.window.connected_gamepads && client.window.gamepads[binder.gamepad_index].gestures[binding.gamepad_gesture] & .Held;
      case; return false;
    }
}

input_binding_already_fired_this_frame :: (client: *Client, binding: *Input_Binding, gamepad_index: s64) -> bool {
    already_fired: bool = ---;
    
    if #complete binding.kind == {
      case .Keyboard; already_fired = array_contains(*client.input_binding_tracker.keys_fired_this_frame, binding.keycode);
      case .Gamepad_Button;
        gamepad := *client.input_binding_tracker.gamepads[gamepad_index];
        already_fired = array_contains(*gamepad.buttons_fired_this_frame, binding.gamepad_button);
      case .Gamepad_Gesture;
        gamepad := *client.input_binding_tracker.gamepads[gamepad_index];
        already_fired = array_contains(*gamepad.gestures_fired_this_frame, binding.gamepad_gesture);
    }

    return already_fired;
}

register_input_binding_fired_this_frame :: (client: *Client, binding: *Input_Binding, gamepad_index: s64) {
    if #complete binding.kind == {
      case .Keyboard; array_add(*client.input_binding_tracker.keys_fired_this_frame, binding.keycode);
      case .Gamepad_Button; 
        gamepad := *client.input_binding_tracker.gamepads[gamepad_index];
        array_add(*gamepad.buttons_fired_this_frame, binding.gamepad_button);
      case .Gamepad_Gesture;
        gamepad := *client.input_binding_tracker.gamepads[gamepad_index];
        array_add(*gamepad.gestures_fired_this_frame, binding.gamepad_gesture);
    }
}

check_input_binder_for_action :: (client: *Client, binder: *Input_Binder, action: Input_Action, check: Input_Binding_Check) -> bool {
    fired_binding: *Input_Binding = null;

    for i := 0; i < client.input_bindings[action].count; ++i {
        binding := *client.input_bindings[action][i];
        if !bitfield_contains(*binder.allowed_input_devices, INPUT_BINDING_KIND_DEVICE[binding.kind]) continue;

        if input_binding_already_fired_this_frame(client, binding, binder.gamepad_index) continue;
        
        // Check if this binding has actually been fired this frame
        if #complete binding.kind == {
          case .Keyboard;
            if #complete check == {
              case .Pressed;
                if client.window.keys[binding.keycode] & .Pressed {
                    fired_binding = binding;
                } else if client.window.keys[binding.keycode] & .Down && binder.input_action_hold_time[action] >= client.input_action_repetition_intervals[action] {
                    fired_binding = binding;
                }
                
              case .Held;     if client.window.keys[binding.keycode] & .Down     fired_binding = binding;
              case .Released; if client.window.keys[binding.keycode] & .Released fired_binding = binding;
            }

          case .Gamepad_Button;
            if binder.gamepad_index >= client.window.connected_gamepads break;
            gamepad := *client.window.gamepads[binder.gamepad_index];
            
            if #complete check == {
              case .Pressed;
                if gamepad.buttons[binding.gamepad_button] & .Pressed {
                    fired_binding = binding;
                } else if gamepad.buttons[binding.gamepad_button] & .Down && binder.input_action_hold_time[action] >= client.input_action_repetition_intervals[action] {
                    fired_binding = binding;
                }
                
              case .Held;     if gamepad.buttons[binding.gamepad_button] & .Down     fired_binding = binding;
              case .Released; if gamepad.buttons[binding.gamepad_button] & .Released fired_binding = binding;
            }

          case .Gamepad_Gesture;
            if binder.gamepad_index >= client.window.connected_gamepads break;
            gamepad := *client.window.gamepads[binder.gamepad_index];

            if #complete check == {
              case .Pressed;
                if gamepad.gestures[binding.gamepad_gesture] & .Committed {
                    fired_binding = binding;
                } else if gamepad.gestures[binding.gamepad_gesture] & .Held && binder.input_action_hold_time[action] >= client.input_action_repetition_intervals[action] {
                    fired_binding = binding;
                }

              case .Held;     if gamepad.gestures[binding.gamepad_gesture] & .Held     fired_binding = binding;
              case .Released; if gamepad.gestures[binding.gamepad_gesture] & .Released fired_binding = binding;
            }
        }
    }

    // Register the potentially fired binding in the binder, so that it won't fire anything else
    // this frame
    if fired_binding {
        register_input_binding_fired_this_frame(client, fired_binding, binder.gamepad_index);
        binder.active_input_device = INPUT_BINDING_KIND_DEVICE[fired_binding.kind];
        
        if #complete check == {
          case .Pressed;
            binder.input_action_held[action] = true;
            binder.input_action_hold_time[action] = 0;
          case .Held; binder.input_action_held[action] = true;
          case .Released; binder.input_action_held[action] = false;
        }
    }

    return fired_binding != null;
}

compare_input_bindings :: (lhs, rhs: *Input_Binding) -> bool {
    if lhs.kind != rhs.kind return false;

    if #complete lhs.kind == {
      case .Keyboard;        if lhs.keycode == rhs.keycode return true;
      case .Gamepad_Button;  if lhs.gamepad_button == rhs.gamepad_button return true;
      case .Gamepad_Gesture; if lhs.gamepad_gesture == rhs.gamepad_gesture return true;
    }

    return false;
}

update_input_binder :: (client: *Client, binder: *Input_Binder) {
    for action := 0; action < binder.input_action_held.Capacity; ++action {
        if binder.input_action_held[action] {
            still_held := false;

            for j := 0; j < client.input_bindings[action].count; ++j {
                still_held |= check_input_binding_held(client, binder, *client.input_bindings[action][j]);
            }

            binder.input_action_held[action] = still_held;
        }

        if binder.input_action_held[action] {
            binder.input_action_hold_time[action] += client.tick_time;
        } else {
            binder.input_action_hold_time[action] = 0;
        }
    }
}
