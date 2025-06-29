Input_Binding_Check :: enum bitfield {
    Pressed;
    Held;
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
    Turn_Modifier;
    
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

Input_Binder :: struct {
    active_input_device: Input_Device = 0;
    allowed_input_devices: Input_Device = 0;
    gamepad_index := 0;
    input_bindings_fired_this_frame: [..]Input_Binding; // We don't want the same input binding to fire two separate actions, e.g. rotating a mirror and opening the crafting menu with the same button press
    input_action_held: [Input_Action.Count]bool = .[ false ];
    input_action_hold_time: [Input_Action.Count]f32 = .[ 0 ]; // If an input action is currently being held for this binder, this value will count up the frame time. This is then used to determine repeating input actions
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
    ib[.Turn_Modifier]      = .[ keycode(.Shift), gamepad_button(.PS_Circle), gamepad_button(.XBox_B) ];
    ib[.Interact_Primary]   = .[ keycode(.Space), gamepad_button(.PS_Cross), gamepad_button(.XBox_A) ];
    ib[.Interact_Secondary] = .[ keycode(.E), gamepad_button(.PS_Square), gamepad_button(.XBox_X) ];
    ib[.Hud_Toggle]         = .[ keycode(.E), gamepad_button(.PS_Square), gamepad_button(.XBox_X) ];
    ib[.Hud_Confirm]        = .[ keycode(.Space), gamepad_button(.PS_Cross), gamepad_button(.XBox_A) ];
    ib[.Hud_Left]           = .[ keycode(.A), keycode(.Arrow_Left),  gamepad_button(.Left_Bumper) ];
    ib[.Hud_Right]          = .[ keycode(.D), keycode(.Arrow_Right), gamepad_button(.Right_Bumper) ];
    ib[.Cheat_Menu_Toggle]  = .[ keycode(.C), gamepad_button(.PS_Triangle), gamepad_button(.XBox_Y) ];
    
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

prepare_input_binders :: (client: *Client) {
    prepare_input_binder(*client.global_input_binder);

    if client.current_state == .Ingame {
        for i := 0; i < client.local_player_count; ++i {
            prepare_input_binder(*client.local_players[i].input_binder);
        }
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

check_input_binding_held :: (client: *Client, binder: *Input_Binder, binding: *Input_Binding) -> bool {
    if #complete binding.kind == {
      case .Keyboard; return client.window.keys[binding.keycode] & .Down;
      case .Gamepad_Button; return binder.gamepad_index < client.window.connected_gamepads && client.window.gamepads[binder.gamepad_index].buttons[binding.gamepad_button] & .Down;
      case .Gamepad_Gesture; return binder.gamepad_index < client.window.connected_gamepads && client.window.gamepads[binder.gamepad_index].gestures[binding.gamepad_gesture] & .Held;
      case; return false;
    }
}

check_input_binder_for_action :: (client: *Client, binder: *Input_Binder, action: Input_Action, check: Input_Binding_Check) -> bool {
    fired_binding: *Input_Binding = null;

    for i := 0; i < client.input_bindings[action].count; ++i {
        binding := *client.input_bindings[action][i];
        if !bitfield_contains(*binder.allowed_input_devices, INPUT_BINDING_KIND_DEVICE[binding.kind]) continue;
        
        // Make sure this binding hasn't been fired in this frame already
        {
            fired_already := false;
            
            for j := 0; j < binder.input_bindings_fired_this_frame.count; ++j {
                if compare_input_bindings(binding, array_get_pointer(*binder.input_bindings_fired_this_frame, j)) {
                    fired_already = true;
                    break;
                }
            }

            if fired_already break;
        }
        
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
        array_add(*binder.input_bindings_fired_this_frame, ~fired_binding);
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

prepare_input_binder :: (input_binder: *Input_Binder) {
    array_clear_without_deallocation(*input_binder.input_bindings_fired_this_frame);
    input_binder.input_bindings_fired_this_frame.allocator = *temp;
}
