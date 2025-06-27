Input_Binding_Check :: enum bitfield {
    Pressed;
    Released;
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

    Interact_Primary;
    Interact_Secondary;

    Hud_Toggle;
    Hud_Confirm;
    Hud_Left;
    Hud_Right;

    Cheat_Menu_Toggle;
}

Input_Binding :: struct {
    kind: Input_Binding_Kind;

    #using data: union {
        keycode: Key_Code;
        gamepad_button: Window_Gamepad_Button_Code;
        gamepad_gesture: Window_Gamepad_Gesture_Code;
    };
}


register_all_input_bindings :: (client: *Client) {
    keycode :: (keycode: Key_Code) -> Input_Binding {
        binding: Input_Binding = ---;
        binding.kind = .Keyboard;
        binding.keycode = keycode;
        return binding;
    }

    gamepad_button :: (button: Window_Gamepad_Button_Code) -> Input_Binding {
        binding: Input_Binding = ---;
        binding.kind = .Gamepad_Button;
        binding.gamepad_button = button;
        return binding;
    }

    gamepad_gesture :: (gesture: Window_Gamepad_Gesture_Code) -> Input_Binding {
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
    ib[.Move_North]         = .[ keycode(.W), gamepad_gesture(.Left_Swipe_Up) ];
    ib[.Move_East]          = .[ keycode(.D), gamepad_gesture(.Left_Swipe_Right) ];
    ib[.Move_South]         = .[ keycode(.S), gamepad_gesture(.Left_Swipe_Down) ];
    ib[.Move_West]          = .[ keycode(.A), gamepad_gesture(.Left_Swipe_Left) ];
    ib[.Look_North]         = .[ keycode(.Arrow_Up),    gamepad_gesture(.Right_Swipe_Up) ];
    ib[.Look_East]          = .[ keycode(.Arrow_Right), gamepad_gesture(.Right_Swipe_Right) ];
    ib[.Look_South]         = .[ keycode(.Arrow_Down),  gamepad_gesture(.Right_Swipe_Down) ];
    ib[.Look_West]          = .[ keycode(.Arrow_Left),  gamepad_gesture(.Right_Swipe_Left) ];
    ib[.Interact_Primary]   = .[ keycode(.Space), gamepad_button(.PS_Cross), gamepad_button(.XBox_A) ];
    ib[.Interact_Secondary] = .[ keycode(.Shift), gamepad_button(.PS_Square), gamepad_button(.XBox_X) ];
    ib[.Hud_Toggle]         = .[ keycode(.Shift), gamepad_button(.PS_Square), gamepad_button(.XBox_X) ];
    ib[.Hud_Confirm]        = .[ keycode(.Space), gamepad_button(.PS_Cross), gamepad_button(.XBox_A) ];
    ib[.Hud_Left]           = .[ keycode(.A), keycode(.Arrow_Left),  gamepad_gesture(.Left_Swipe_Left),  gamepad_gesture(.Left_Swipe_Up) ];
    ib[.Hud_Right]          = .[ keycode(.D), keycode(.Arrow_Right), gamepad_gesture(.Left_Swipe_Right), gamepad_gesture(.Left_Swipe_Down) ];
    ib[.Cheat_Menu_Toggle]  = .[ keycode(.C), gamepad_button(.PS_Triangle), gamepad_button(.XBox_Y) ];
    
    for i := 0; i < ib.Capacity; ++i {
        client.input_bindings[i] = copy_array(*client.engine_allocator, ib[i]);
    }
}

input_action_fired_globally :: (client: *Client, action: Input_Action, check: Input_Binding_Check) -> bool {
    return check_input_action(client, .ALL, 0, action, check) != null;
}

input_action_fired_for_local_player :: (client: *Client, local_player: *Local_Player, action: Input_Action, check: Input_Binding_Check) -> bool {
    // Make sure no binding associated with this input action has been fired this frame already, to prevent
    // a single binding causing multiple actions to go off.
    for i := 0; i < client.input_bindings[action].count; ++i {
        for j := 0; j < local_player.input_bindings_fired_this_frame.count; ++j {
            if compare_input_bindings(*client.input_bindings[action][i], array_get_pointer(*local_player.input_bindings_fired_this_frame, j)) return false;
        }
    }

    fired := check_input_action(client, local_player.allowed_input_devices, local_player.gamepad_index, action, check);

    // Register all bindings of this action to be used this frame, so that we ensure no other action will
    // be fired that uses the same bindings.
    if fired {
        for i := 0; i < client.input_bindings[action].count; ++i {
            array_add(*local_player.input_bindings_fired_this_frame, client.input_bindings[action][i]);
        }

        local_player.active_input_device = INPUT_BINDING_KIND_DEVICE[fired.kind];
    }
    
    return fired != null;
}

reset_input_actions_for_local_players :: (client: *Client) {
    for i := 0; i < client.local_player_count; ++i {
        array_clear_without_deallocation(*client.local_players[i].input_bindings_fired_this_frame);
        client.local_players[i].input_bindings_fired_this_frame.allocator = *temp;
    }
}



#file_scope

Input_Binding_Kind :: enum {
    Keyboard;
    Gamepad_Button;
    Gamepad_Gesture;
}

INPUT_BINDING_KIND_DEVICE: [Input_Binding_Kind.Count]Input_Device : .[
        .Keyboard,
        .Gamepad,
        .Gamepad,
];

check_input_action :: (client: *Client, allowed_input_devices: Input_Device, gamepad_index: s64, action: Input_Action, check: Input_Binding_Check) -> *Input_Binding {
    fired_binding: *Input_Binding = null;

    for i := 0; i < client.input_bindings[action].count; ++i {
        binding := *client.input_bindings[action][i];
        if !bitfield_contains(*allowed_input_devices, INPUT_BINDING_KIND_DEVICE[binding.kind]) continue;
        
        if #complete binding.kind == {
          case .Keyboard;
            if #complete check == {
              case .Pressed;  if client.window.keys[binding.keycode] & .Pressed  fired_binding = binding;
              case .Released; if client.window.keys[binding.keycode] & .Released fired_binding = binding;
            }

          case .Gamepad_Button;
            if gamepad_index >= client.window.connected_gamepads break;
            gamepad := *client.window.gamepads[gamepad_index];
            
            if #complete check == {
              case .Pressed;  if gamepad.buttons[binding.gamepad_button] & .Pressed  fired_binding = binding;
              case .Released; if gamepad.buttons[binding.gamepad_button] & .Released fired_binding = binding;
            }

          case .Gamepad_Gesture;
            if gamepad_index >= client.window.connected_gamepads break;
            gamepad := *client.window.gamepads[gamepad_index];

            if #complete check == {
              case .Pressed; if gamepad.gestures[binding.gamepad_gesture] fired_binding = binding;
              case .Released;
            }
        }
    }

    return fired_binding;
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
