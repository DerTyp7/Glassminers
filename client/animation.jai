MAX_ANIMATION_FRAMES :: 4;

Animation_Index :: enum {
    None;

    // Guy Animations
    Guy_Idle_Side;
    Guy_Idle_Back;
    Guy_Idle_Front;
    Guy_Walk_Side;
    Guy_Walk_Back;
    Guy_Walk_Front;
    Guy_Dead_Side;
    Guy_Dead_Front;
    Guy_Dead_Back;

    // Frog Animations
    Frog_Idle_Side;
    Frog_Idle_Back;
    Frog_Idle_Front;
    Frog_Attacking_Side;
    Frog_Attacking_Back;
    Frog_Attacking_Front;
    Frog_Recovering_Side;
    Frog_Recovering_Back;
    Frog_Recovering_Front;

    // Goblin Animations
    Goblin_Idle_Side;
    Goblin_Idle_Back;
    Goblin_Idle_Front;
    Goblin_Attacking_Side;
    Goblin_Attacking_Back;
    Goblin_Attacking_Front;
    Goblin_Recovering_Side;
    Goblin_Recovering_Back;
    Goblin_Recovering_Front;
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
    None;

    Guy_Idle;
    Guy_Walk;
    Guy_Dead;

    Frog_Idle;
    Frog_Attacking;
    Frog_Recovering;

    Goblin_Idle;
    Goblin_Attacking;
    Goblin_Recovering;
}

Animation_Group :: struct {
    for_direction: [Direction.Count]Animation_Index;

#if DEVELOPER {
    encountered_in_file := false;
}
}



create_animation_data :: (client: *Client) -> bool {
#if BAKE_ASSETS {
    client.animations = BAKED_ANIMATIONS;
    return true;
} #else {
    return load_animation_file(client.animations, client.animation_groups, "data/animation-pack.txt");
}
}

load_animation_file :: (animations: []Animation, groups: []Animation_Group, filepath: string) -> bool {
    original_file_content, success := read_entire_file(Default_Allocator, filepath);
    if !success {
        logprint(.Error, "Failed to open the animation-pack file '%'!", filepath);
        return false;
    }

    defer free_file_content(Default_Allocator, *original_file_content);

    file_content := original_file_content;
    active_animation := Animation_Index.Count + 1;
    active_animation_group := Animation_Group_Index.Count + 1;
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

        args := string_split(line, #char " ", true, *temp);
        identifier := array_get(*args, 0);
        
        if identifier[0] == #char ":" {
            //
            // Declaration of a new animation
            //
            active_animation_group = .Count;
            active_animation = .Count;
            
            if args.count < 2 {
                logprint(.Error, "%:%: A declaration of an animation was expected here, in the syntax ':<name> <frame_time> <...flags>'.", filepath, line_number);
                success = false;
                continue;
            }

            name := substring_view(identifier, 1, identifier.count);
            active_animation = find_animation_index_from_name(name);

            if active_animation >= .Count {
                logprint(.Error, "%:%: '%' is not a known animation.", filepath, line_number, name);
                success = false;
                continue;
            }

            frame_time, valid_frame_time := string_to_float(array_get(*args, 1));
            if !valid_frame_time {
                logprint(.Error, "%:%: '%' is not a valid floating point number, the frame time was expected here.", filepath, line_number, array_get(*args, 1));
                success = false;
                continue;
            }

            flags: Animation_Flags = 0;

            for i := 2; i < args.count; ++i {
                flag := find_animation_flag_from_name(array_get(*args, i));
                flags |= flag;
                
                if flag == 0 {
                    logprint(.Error, "%:%: '%' is not a known animation flag.", filepath, line_number, array_get(*args, i));
                    success = false;
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
                success = false;
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
                success = false;
                continue;
            }

            animation := *animations[active_animation];
            
            name := array_get(*args, 0);
            sprite_index, valid_sprite_index := find_sprite_index_from_name(name);

            if !valid_sprite_index {
                logprint(.Error, "%:%: '%' is not a know sprite name.", filepath, line_number, name);
                success = false;
                continue;
            }
            
            if animation.frame_count == MAX_ANIMATION_FRAMES {
                logprint(.Error, "%:%: The animation '%' reached the maximum limit of % frames.", filepath, line_number, enum_names(Animation_Index)[active_animation], MAX_ANIMATION_FRAMES);
                success = false;
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
                success = false;
                continue;
            }

            direction := find_direction_from_name(array_get(*args, 0));
            if direction == .Count {
                logprint(.Error, "%:%: '%' is not a valid direction.", filepath, line_number, array_get(*args, 0));
                success = false;
                continue;
            }
            
            animation_index := find_animation_index_from_name(array_get(*args, 1));
            
            if animation_index >= .Count {
                logprint(.Error, "%:%: '%' is not a known animation.", filepath, line_number, array_get(*args, 1));
                success = false;
                continue;
            }

            groups[active_animation_group].for_direction[direction] = animation_index;
        } else if active_animation == Animation_Index.Count + 1 && active_animation_group == Animation_Group_Index.Count + 1 {
            logprint(.Error, "%:%: An animation or group declaration must come before the first frame.", filepath, line_number);
            success = false;
        }
    }

    return success;
}

get_animation_frame :: (animation: *Animation, rotation: Direction, t: f32) -> Sprite_Index, bool {
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
    
    return animation.frames[frame_index], flip;
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
