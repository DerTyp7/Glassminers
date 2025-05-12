SPRITES_PER_ATLAS      :: SPRITE_ATLAS_COLUMNS * SPRITE_ATLAS_ROWS;
SPRITE_ATLAS_WIDTH     :: 128;
SPRITE_ATLAS_HEIGHT    :: 128;
SPRITE_ATLAS_CHANNELS  :: 4;
SPRITE_ATLAS_COLUMNS   :: 8;
SPRITE_ATLAS_ROWS      :: 8;
SPRITE_ATLAS_COUNT     :: 1;
SPRITE_WIDTH           :: SPRITE_ATLAS_WIDTH / SPRITE_ATLAS_COLUMNS;
SPRITE_HEIGHT          :: SPRITE_ATLAS_HEIGHT / SPRITE_ATLAS_ROWS;

Texture_Data :: struct {
    width:    u32;
    height:   u32;
    channels: u32;
    pixels: string;
}

#if BAKE_ASSETS {
    BAKED_SPRITE_ATLASES :: #run bake_all_sprite_atlases("run_tree/data");
    BAKED_SOUNDS :: #run bake_all_sounds("run_tree/data/sounds");
    BAKED_FONT :: #run bake_raw_file("run_tree/data/font.ttf");
}

pack_sprite_atlases :: (directory: string, filepaths: *[..]string) -> bool {
    find_sprite_index_from_name :: (name: string) -> s64, bool {
        enum_info := cast(*Type_Info_Enum) type_info(Sprite_Index);

        for i := 0; i < enum_info.members.count; ++i {
            member := *enum_info.members[i];

            if member.display_name == name {
                return member.integral_value, true;
            }
        }

        return 0, false;
    }
    
    Entry :: struct {
        ident: string;
        sprite_index: s64;
        filepath: string;
        texture: Texture_Data;
    }
    
    start := os_get_hardware_time();
    arena: Memory_Arena;
    create_memory_arena(*arena, 1 * Memory_Unit.Megabytes, 1 * Memory_Unit.Megabytes, false);
    allocator: Allocator = allocator_from_memory_arena(*arena);
    
    entries: [..]Entry;
    defer {
        for i := 0; i < entries.count; ++i free_texture_data(*array_get(*entries, i).texture);
        destroy_memory_arena(*arena);
    };

    filepath := print_into_allocator(*allocator, "%/sprite-pack.txt", directory);
    original_file_content, success := read_entire_file(*allocator, filepath);

    highest_sprite_index: s64 = 0;
    
    //
    // Parse the Sprite Pack file
    //
    {
        if !success {
            logprint(.Error, "Failed to open the sprite-pack file!");
            return false;
        }

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

            space_index, space_found := search_string(line, #char " ");
            if !space_found {
                logprint(.Error, "The sprite-pack file is erroneous on line %: A sprite name and a file path, with a space between them were expected.");
                success = false;
                continue;
            }

            entry := array_push(*entries);
            entry.ident    = trim_string_view(substring_view(line, 0, space_index));
            entry.filepath = print_into_allocator(*allocator, "%/%", directory, trim_string_view(substring_view(line, space_index + 1, line.count)));

            found_sprite_index: bool = ---;
            entry.sprite_index, found_sprite_index = find_sprite_index_from_name(entry.ident);
            if !found_sprite_index {
                logprint(.Error, "The sprite identifier '%' is not known in the system.", entry.ident);
                success = false;
                continue;
            }

            highest_sprite_index = max(entry.sprite_index, highest_sprite_index);

            if filepaths array_add(filepaths, copy_string(filepaths.allocator, entry.filepath));
        }
    }

    if !success return false;

    //
    // Load all required sprite images into memory
    //
    {
        for i := 0; i < entries.count; ++i {
            entry := array_get_pointer(*entries, i);

            found_sprite: bool = ---;
            entry.texture, found_sprite = load_texture_data(*allocator, entry.filepath);

            if !found_sprite {
                logprint(.Error, "The source sprite file '%' does not exist!", entry.filepath);
                success = false;
            } else if entry.texture.channels != SPRITE_ATLAS_CHANNELS || entry.texture.width != SPRITE_WIDTH || entry.texture.height != SPRITE_HEIGHT {
                logprint(.Error, "Each source sprite file was expected to be '%x%' with % channels, but '%' was '%x%' with % channels.", SPRITE_WIDTH, SPRITE_HEIGHT, SPRITE_ATLAS_CHANNELS, entry.filepath, entry.texture.width, entry.texture.height, entry.texture.channels);
                success = false;
            }
        }
    }

    if !success return false;

    //
    // Put all entries into the sprite atlases
    //
    {
        //
        // Prepare the atlases
        //
        atlas_count := cast(s64) ceil(cast(f64) highest_sprite_index / cast(f64) SPRITES_PER_ATLAS);

        if atlas_count != SPRITE_ATLAS_COUNT {
            logprint(.Error, "The SPRITE_ATLAS_COUNT constant is no longer correct... Victor needs to change it!");
            success = false;
        }

        atlases := allocate_array(*allocator, Texture_Data, atlas_count);

        for i := 0; i < atlases.count; ++i {
            atlas := *atlases[i];
            atlas.width    = SPRITE_ATLAS_WIDTH;
            atlas.height   = SPRITE_ATLAS_HEIGHT;
            atlas.channels = SPRITE_ATLAS_CHANNELS;
            atlas.pixels   = allocate_string(*allocator, atlas.width * atlas.height * atlas.channels);
        }

        //
        // Build the atlases
        //
        for i := 0; i < entries.count; ++i {
            entry := array_get_pointer(*entries, i);
            atlas_index := entry.sprite_index / SPRITES_PER_ATLAS;
            index_in_atlas := entry.sprite_index % SPRITES_PER_ATLAS;

            row    := index_in_atlas / SPRITE_ATLAS_COLUMNS;
            column := index_in_atlas % SPRITE_ATLAS_COLUMNS;

            atlas := *atlases[atlas_index];

            for h := 0; h < entry.texture.height; ++h {
                y := row * entry.texture.height + h;
                x := column * entry.texture.width;

                copy_memory(*atlas.pixels[(y * atlas.width + x) * entry.texture.channels], *entry.texture.pixels[h * entry.texture.width * entry.texture.channels], entry.texture.width * entry.texture.channels);
            }
        }
        
        //
        // Export each atlas
        //
        for i := 0; i < atlases.count; ++i {
            atlas := *atlases[i];

            filepath := print_into_allocator(*allocator, "%/sprite_atlas_%.png\0", directory, i);

            result := stbi_write_png(filepath.data, atlas.width, atlas.height, atlas.channels, atlas.pixels.data, atlas.width * atlas.channels);
            
            if result == 0 {
                logprint(.Error, "Failed to export the sprite atlas '%'.", filepath);
                success = false;
            } else {
                logprint(.Debug, "Packed sprite atlas '%'.", filepath);
            }
        }
    }

    if success {
        end := os_get_hardware_time();
        #if ALLOCATOR_STATISTICS {
            logprint(.Debug, "Sprite packing took %ms, %mb.", os_convert_hardware_time(end - start, .Milliseconds), cast(f64) allocator.stats.working_set / 1_000_000.0);
        }
    }
    
    return success;
}

#if DEVELOPER {
    pack_sprite_atlases_with_watchdog :: (client: *Client, directory: string) -> bool {
        filepaths: [..]string;
        filepaths.allocator = *temp;
        if !pack_sprite_atlases(directory, *filepaths) return false;

        destroy_file_watcher(*client.sprite_watchdog);
        create_file_watcher(*client.sprite_watchdog, *client.engine_allocator);
        add_files_to_watch(*client.sprite_watchdog, filepaths);
        return true;
    }
}

    
#file_scope

load_texture_data :: (allocator: *Allocator, filepath: string) -> Texture_Data, bool {
    file_content, success := read_entire_file(allocator, filepath);
    if !success {
        return .{ }, false;
    }
        
    width, height, channels_in_file: s32 = ---;
    buffer := stbi_load_from_memory(file_content.data, file_content.count, *width, *height, *channels_in_file, 0);
    buffer_size_in_bytes := width * height * channels_in_file;
    
    return .{ width, height, channels_in_file, .{ buffer_size_in_bytes, buffer } }, true;
}

free_texture_data :: (data: *Texture_Data) {
    stbi_image_free(data.pixels.data);
    ~data = .{};
}

bake_all_sprite_atlases :: (directory: string) -> [SPRITE_ATLAS_COUNT]Texture_Data {
    pack_sprite_atlases(directory, null);

    result: [SPRITE_ATLAS_COUNT]Texture_Data = ---;

    for i := 0; i < SPRITE_ATLAS_COUNT; ++i {
        filepath := print_into_allocator(Default_Allocator, "%/sprite_atlas_%.png", directory, i);

        success: bool = ---;
        result[i], success = load_texture_data(Default_Allocator, filepath);

        if !success {
            compiler_report_error(print_into_allocator(Default_Allocator, "[ASSET BAKE]: Failed to bake the texture '%': The file does not exist.\n", filepath));
            compiler_report_error(print_into_allocator(Default_Allocator, "[ASSET BAKE]:    We are in the working directory: '%'.\n", get_working_directory(Default_Allocator)));
        }
    }

    return result;
}

bake_all_sounds :: (directory: string) -> [Sound_Index.Count]Sound_Data {
    result: [Sound_Index.Count]Sound_Data = ---;

    for i := 0; i < Sound_Index.Count; ++i {
        filepath := print_into_allocator(Default_Allocator, "%/%", directory, SOUND_FILEPATH_MAP[i]);

        status: Sound_File_Status = ---;
        result[i], status = create_sound_data_from_file(filepath);
        
        if status != .Success {
            compiler_report_error(print_into_allocator(Default_Allocator, "[ASSET BAKE]: Failed to bake the sound '%': %.\n", filepath, status));
            compiler_report_error(print_into_allocator(Default_Allocator, "[ASSET BAKE]:    We are in the working directory: '%'.\n", get_working_directory(Default_Allocator)));            
        }
    }
    
    return result;
}

bake_raw_file :: (filepath: string) -> string {
    file_content, success := read_entire_file(Default_Allocator, filepath);
    if !success {
        compiler_report_error(print_into_allocator(Default_Allocator, "[ASSET BAKE]: Failed to bake the raw file '%': The file does not exist.\n", filepath));
        return "";
    }

    return file_content;
}
