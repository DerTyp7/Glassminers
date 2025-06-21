MAX_ANIMATION_FRAMES :: 12;

Animation_Index :: enum {
    // Guy Animations
    Guy_Idle_Back;
    Guy_Idle_Front;
    Guy_Idle_Side;
    Guy_Walk_Back;
    Guy_Walk_Front;
    Guy_Walk_Side;
    Guy_Damaged_Front;
    Guy_Damaged_Back;
    Guy_Damaged_Side;
    Guy_Dead_Back;
    Guy_Dead_Front;
    Guy_Dead_Side;
    
    // Frog Animations
    Frog_Idle_Back;
    Frog_Idle_Front;
    Frog_Idle_Side;
    Frog_Attacking_Back;
    Frog_Attacking_Front;
    Frog_Attacking_Side;
    Frog_Recovering_Back;
    Frog_Recovering_Front;
    Frog_Recovering_Side;
    Frog_Damaged_Back;
    Frog_Damaged_Front;
    Frog_Damaged_Side;
    
    // Goblin Animations
    Goblin_Idle_Back;
    Goblin_Idle_Front;
    Goblin_Idle_Side;
    Goblin_Attacking_Back;
    Goblin_Attacking_Front;
    Goblin_Attacking_Side;
    Goblin_Recovering_Back;
    Goblin_Recovering_Front;
    Goblin_Recovering_Side;
    Goblin_Damaged_Back;
    Goblin_Damaged_Front;
    Goblin_Damaged_Side;
    
    // Slime Animations
    Slime_Idle_Back;
    Slime_Idle_Front;
    Slime_Idle_Side;
    Slime_Walk_Back;
    Slime_Walk_Front;
    Slime_Walk_Side;
    Slime_Damaged_Back;
    Slime_Damaged_Front;
    Slime_Damaged_Side;
    
    // Trader Animations
    Trader_Idle_Back;
    Trader_Idle_Front;
    Trader_Idle_Side;

    // Generic Animations
    Lava;
    Slab;
    Torch;
    Slime_Hole_Filled;
}

Animation_Flags :: enum bitfield {
    Loop;
    Flip;

    Is_Idle;
    Is_Walk;
}

Animation :: struct {
    frames: [MAX_ANIMATION_FRAMES]Sprite_Index = ---;
    frame_count: s32;
    frame_time: f32;
    flags: Animation_Flags;

#if DEVELOPER {
    encountered_in_file := false;
}
}

Animation_Group_Index :: enum {
    Guy_Idle;
    Guy_Walk;
    Guy_Damaged;
    Guy_Dead;

    Frog_Idle;
    Frog_Attacking;
    Frog_Recovering;
    Frog_Damaged;
    
    Goblin_Idle;
    Goblin_Attacking;
    Goblin_Recovering;
    Goblin_Damaged;
    
    Slime_Idle;
    Slime_Walk;
    Slime_Damaged;
    
    Trader_Idle;
}

Animation_Group :: struct {
    for_direction: [Direction.Count]Animation_Index = .[ .Count ];

#if DEVELOPER {
    encountered_in_file := false;
}
}



create_animation_data :: (client: *Client) -> bool {
#if BAKE_ASSETS {
    client.animations = BAKED_ANIMATIONS;
    client.animation_groups = BAKED_ANIMATION_GROUPS;
    return true;
} #else {
    return load_animation_file(client.animations, client.animation_groups, "data/animation-pack.txt") != .Complete_Failure;
}
}

destroy_animation_data :: (client: *Client) {
    client.animations = .[];
    client.animation_groups = .[];
}

Animation_Packing_Result :: enum {
    Success;
    Complete_Failure;
    Partial_Failure;
}

load_animation_file :: (animations: []Animation, groups: []Animation_Group, filepath: string) -> Animation_Packing_Result {
    original_file_content, file_exists := read_entire_file(Default_Allocator, filepath);
    if !file_exists {
        logprint(.Error, "Failed to open the animation-pack file '%'!", filepath);
        return .Complete_Failure;
    }

    defer free_file_content(Default_Allocator, *original_file_content);

    result: Animation_Packing_Result = .Success;
    active_animation := Animation_Index.Count + 1;
    active_animation_group := Animation_Group_Index.Count + 1;

    file_content := original_file_content;
    line_number := 0;

    while file_content.count {
        ++line_number;
        line: string = read_next_line(*file_content);

        {
            pound_index, pound_found := search_string(line, #char "#");
            if pound_found {
                line = substring_view(line, 0, pound_index);
            }

            line = trim_string_view(line);

            if !line.count continue;
        }

        args := string_split(line, #char " ", true, Default_Allocator);
        defer array_clear(*args);
        
        identifier := array_get(*args, 0);
        
        if identifier[0] == #char ":" {
            //
            // Declaration of a new animation
            //
            active_animation_group = .Count;
            active_animation = .Count;
            
            if args.count < 2 {
                logprint(.Error, "%:%: A declaration of an animation was expected here, in the syntax ':<name> <frame_time> <...flags>'.", filepath, line_number);
                result = .Complete_Failure;
                continue;
            }

            name := substring_view(identifier, 1, identifier.count);
            active_animation = find_animation_index_from_name(name);

            if active_animation >= .Count {
                logprint(.Error, "%:%: '%' is not a known animation.", filepath, line_number, name);
                result = .Complete_Failure;
                continue;
            }

            frame_time, valid_frame_time := string_to_float(array_get(*args, 1));
            if !valid_frame_time {
                logprint(.Error, "%:%: '%' is not a valid floating point number, the frame time was expected here.", filepath, line_number, array_get(*args, 1));
                result = .Complete_Failure;
                continue;
            }

            flags: Animation_Flags = 0;

            for i := 2; i < args.count; ++i {
                flag := find_animation_flag_from_name(array_get(*args, i));
                flags |= flag;
                
                if flag == 0 {
                    logprint(.Error, "%:%: '%' is not a known animation flag.", filepath, line_number, array_get(*args, i));
                    result = .Complete_Failure;
                }
            }

            animations[active_animation].frame_count = 0;
            animations[active_animation].frame_time  = xx frame_time;
            animations[active_animation].flags       = flags;

            #if DEVELOPER {
                animations[active_animation].encountered_in_file = true;
            }
        } else if array_get(*args, 0)[0] == #char "@" {
            //
            // Declaration of a new group
            //
            active_animation_group = .Count;
            active_animation = .Count;

            name := substring_view(identifier, 1, identifier.count);
            active_animation_group = find_animation_group_index_from_name(name);

            if active_animation_group >= .Count {
                logprint(.Error, "%:%: '%' is not a known animation group.", filepath, line_number, name);
                result = .Complete_Failure;
                continue;
            }

            #if DEVELOPER {
                groups[active_animation_group].encountered_in_file = true;
            }
        } else if active_animation < .Count {
            //
            // Append a new frame to the current animation
            //
            if args.count != 1 {
                logprint(.Error, "%:%: A single animation frame was expected here.", filepath, line_number);
                result = .Complete_Failure;
                continue;
            }

            animation := *animations[active_animation];
            
            name := array_get(*args, 0);
            sprite_index, valid_sprite_index := find_sprite_index_from_name(name);

            if !valid_sprite_index {
                logprint(.Error, "%:%: '%' is not a known sprite name.", filepath, line_number, name);
                result = .Complete_Failure;
                continue;
            }
            
            if animation.frame_count == MAX_ANIMATION_FRAMES {
                logprint(.Error, "%:%: The animation '%' reached the maximum limit of % frames.", filepath, line_number, enum_names(Animation_Index)[active_animation], MAX_ANIMATION_FRAMES);
                result = .Complete_Failure;
                continue;
            }

            
            animation.frames[animation.frame_count] = sprite_index;
            ++animation.frame_count;
        } else if active_animation_group < .Count {
            //
            // Append a new animation to the current group
            //
            if args.count != 2 {
                logprint(.Error, "%:%: A mapping from a direction to an animation was expected here, in the syntax '<direction> <animation>'.", filepath, line_number);
                result = .Complete_Failure;
                continue;
            }

            direction := find_direction_from_name(array_get(*args, 0));
            if direction == .Count {
                logprint(.Error, "%:%: '%' is not a valid direction.", filepath, line_number, array_get(*args, 0));
                result = .Complete_Failure;
                continue;
            }
            
            animation_index := find_animation_index_from_name(array_get(*args, 1));
            
            if animation_index >= .Count {
                logprint(.Error, "%:%: '%' is not a known animation.", filepath, line_number, array_get(*args, 1));
                result = .Complete_Failure;
                continue;
            }

            groups[active_animation_group].for_direction[direction] = animation_index;
        } else if active_animation == Animation_Index.Count + 1 && active_animation_group == Animation_Group_Index.Count + 1 {
            logprint(.Error, "%:%: An animation or group declaration must come before the first frame.", filepath, line_number);
            result = .Complete_Failure;
        }
    }

    //
    // Check for missing entries and report errors on them
    //
    #if DEVELOPER {
        for i: Animation_Index = 0; i < animations.count; ++i {
            if !animations[i].encountered_in_file {
                logprint(.Error, "The animation '%' is missing in the animation pack.", i);
                result = .Partial_Failure;
            }
        }

        for i: Animation_Group_Index = 0; i < groups.count; ++i {
            if !groups[i].encountered_in_file {
                logprint(.Error, "The animation group '%' is missing in the animation pack.", i);
                result = .Partial_Failure;
            }
        }
    }
        
    return result;
}
    
get_animation_frame_index :: (animation: *Animation, rotation: Direction, t: f32) -> s64, bool {
    if animation.frame_count == 0 return -1, false;

    total_animation_time := xx animation.frame_count * animation.frame_time;

    flip := false;
    frame_index: s64 = ---;

    if animation.frame_time == 0 {
        frame_index = 0;
    } else if animation.flags & .Loop {
        frame_index = cast(s64) floor(fmodf(t, total_animation_time) / animation.frame_time);
    } else {
        frame_index = min(cast(s64) floor(t / animation.frame_time), animation.frame_count - 1);
    }
    
    if animation.flags & .Flip && (rotation == .East || rotation == .South) {
        flip = true;
    }
    
    return frame_index, flip;
}

get_animation_frame :: (animation: *Animation, rotation: Direction, t: f32) -> Sprite_Index, bool {
    frame_index, flip := get_animation_frame_index(animation, rotation, t);
    return ifx frame_index >= 0 then animation.frames[frame_index] else .Count, flip;
}



#file_scope

find_animation_index_from_name :: (name: string) -> Animation_Index {
    names :: enum_names(Animation_Index);
    
    for i := 0; i < names.count; ++i {
        if strings_equal(names[i], name, .Case_Insensitive) {
            return i;
        }
    }

    return .Count;
}

find_animation_group_index_from_name :: (name: string) -> Animation_Group_Index {
    names :: enum_names(Animation_Group_Index);
    
    for i := 0; i < names.count; ++i {
        if strings_equal(names[i], name, .Case_Insensitive) {
            return i;
        }
    }

    return .Count;
}

find_animation_flag_from_name :: (name: string) -> Animation_Flags {
    names := enum_names(Animation_Flags);
    
    for i := 0; i < names.count; ++i {
        if strings_equal(names[i], name, .Case_Insensitive) {
            return 1 << i;
        }
    }
    
    return 0;
}

find_direction_from_name :: (name: string) -> Direction {
    if strings_equal("North", name, .Case_Insensitive) {
        return .North;
    } else if strings_equal("East", name, .Case_Insensitive) {
        return .East;
    } else if strings_equal("South", name, .Case_Insensitive) {
        return .South;
    } else if strings_equal("West", name, .Case_Insensitive) {
        return .West;
    } else {
        return .Count;
    }
}
