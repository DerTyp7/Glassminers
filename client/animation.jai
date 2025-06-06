MAX_ANIMATION_FRAMES :: 4;

Animation_Index :: enum {
    None;

    Guy_Walk_Side;
}

Animation :: struct {
    frames: [MAX_ANIMATION_FRAMES]Sprite_Index = ---;
    frame_count: s32;
    frame_time: f32;
    looping: bool;
}

create_animation_data :: (client: *Client) -> bool {
#if BAKE_ASSETS {
    client.animations = BAKED_ANIMATIONS;
    return true;
} #else {
    return load_animation_file(client.animations, "data/animation-pack.txt");
}
}

load_animation_file :: (animations: []Animation, filepath: string) -> bool {
    original_file_content, success := read_entire_file(Default_Allocator, filepath);
    if !success {
        logprint(.Error, "Failed to open the animation-pack file '%'!", filepath);
        return false;
    }

    defer free_file_content(Default_Allocator, *original_file_content);

    file_content := original_file_content;
    active_animation_index := Animation_Index.Count + 1;
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
        
        if array_get(*args, 0)[0] == #char ":" {
            //
            // Declaration of a new animation
            //
            active_animation_index = .Count;
            
            if args.count != 3 {
                logprint(.Error, "%:%: A declaration of an animation was expected here, in the syntax ':<name> <frame_time> <looping>'.", filepath, line_number);
                success = false;
                continue;
            }

            name := array_get(*args, 0);
            name = substring_view(name, 1, name.count);
            active_animation_index = find_animation_index_from_name(name);

            if active_animation_index >= .Count {
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

            looping, looping_valid := string_to_bool(array_get(*args, 2));
            if !looping_valid {
                logprint(.Error, "%:%: '%' is not a valid bool, the looping property was expected here.", filepath, line_number, array_get(*args, 2));
                success = false;
                continue;
            }

            animations[active_animation_index].frame_count = 0;
            animations[active_animation_index].frame_time  = xx frame_time;
            animations[active_animation_index].looping     = looping;
        } else if active_animation_index < .Count {
            //
            // Append a new frame to the current animation
            //
            if args.count != 1 {
                logprint(.Error, "%:%: A single animation frame was expected here.", filepath, line_number);
                success = false;
                continue;
            }

            animation := *animations[active_animation_index];
            
            name := array_get(*args, 0);
            sprite_index, valid_sprite_index := find_sprite_index_from_name(name);

            if !valid_sprite_index {
                logprint(.Error, "%:%: '%' is not a know sprite name.", filepath, line_number, name);
                success = false;
                continue;
            }
            
            if animation.frame_count == MAX_ANIMATION_FRAMES {
                logprint(.Error, "%:%: The animation '%' reached the maximum limit of % frames.", filepath, line_number, enum_names(Animation_Index)[active_animation_index], MAX_ANIMATION_FRAMES);
                success = false;
                continue;
            }

            
            animation.frames[animation.frame_count] = sprite_index;
            ++animation.frame_count;
        } else if active_animation_index == Animation_Index.Count + 1 {
            logprint(.Error, "%:%: An animation declaration must come before the first frame.", filepath, line_number);
            success = false;
        }
    }

    return success;
}



#file_scope

find_animation_index_from_name :: (name: string) -> Animation_Index {
    names :: enum_names(Animation_Index);
    
    for i := 0; i < Animation_Index.Count; ++i {
        if strings_equal(names[i], name, .Case_Insensitive) {
            return i;
        }
    }

    return .Count;
}
