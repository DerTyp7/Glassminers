SPRITE_WIDTH          :: 16;
SPRITE_HEIGHT         :: 16;
SPRITE_ATLAS_CHANNELS :: 4;

SPRITE_ATLAS_COLUMNS :: 16;
SPRITE_ATLAS_ROWS    :: 16;

SPRITE_ATLAS_WIDTH  :: SPRITE_WIDTH * SPRITE_ATLAS_COLUMNS;
SPRITE_ATLAS_HEIGHT :: SPRITE_HEIGHT * SPRITE_ATLAS_ROWS;
SPRITES_PER_ATLAS   :: SPRITE_ATLAS_COLUMNS * SPRITE_ATLAS_ROWS;
SPRITE_ATLAS_COUNT  :: cast(s64) ceil(cast(f64) Sprite_Index.Count / cast(f64) SPRITES_PER_ATLAS);

Texture_Data :: struct {
    width:    u32;
    height:   u32;
    channels: u32;
    pixels: string;
}

#if BAKE_ASSETS {
    BAKED_SPRITE_ATLASES :: #run bake_all_sprite_atlases(ASSET_FILE_PATH("run_tree/data"));
}

#if DEVELOPER {
    pack_sprite_atlases_with_watchdog :: (client: *Client, directory: string) -> Sprite_Packing_Result {
        filepaths: [..]string;
        filepaths.allocator = *temp;
        result := pack_sprite_atlases(directory, *filepaths);

        if result != .Complete_Failure {
            destroy_file_watcher(*client.sprite_watchdog);
            create_file_watcher(*client.sprite_watchdog, *client.engine_allocator);
            add_files_to_watch(*client.sprite_watchdog, filepaths);
        }
        
        return result;
    }
}

    
#file_scope

Sprite_Packing_Result :: enum {
    Success;
    Complete_Failure;
    Partial_Failure;
}

Sprite_Source :: enum {
    Png;
    Aseprite;
}

consume_whitespace_separated_string :: (to_process: *string) -> string {
    space_index, space_found := search_string(~to_process, #char " ");
    if !space_found { 
        result_string := ~to_process;
        ~to_process = .{};
        return result_string;
    }
    
    result_string := trim_string_view(substring_view(~to_process, 0, space_index));
    
    while space_index < to_process.count && to_process.data[space_index] == #char " " {
        space_index += 1;
    }
    
    to_process.data += space_index;
    to_process.count -= space_index;
    return result_string;
}

grab_texture_pixels_from_parsed_aseprite_file :: (file: Parsed_Aseprite_File, layer_name: string, frame_index: s64) -> string, bool {
    layer: Parsed_Aseprite_File.Layer;
    passed_checks: bool = true;
    
    if layer_name.count > 0 {
        found_match: bool = false;
        for i := 0; i < file.layers.count; ++i {
            if strings_equal_case_insensitive(layer_name, file.layers[i].name) {
                layer = file.layers[i];
                found_match = true;
                break;
            }
        }
        
        if !found_match {
            logprint(.Error, "Layer name % could not be found in aseprite file!", layer_name);
            passed_checks = false;
        }
    } else {
        // Default to first layer
        layer = file.layers[0];
    }
    
    if frame_index >= layer.images.count {
        logprint(.Error, "Access frame index %/% in aseprite file is out of bounds!", frame_index, layer.images.count);
        passed_checks = false;
    }
    
    result_image_data: string = ifx passed_checks then layer.images[frame_index] else .{};
    return result_image_data, passed_checks;
}

pack_sprite_atlases :: (directory: string, filepaths: *[..]string) -> Sprite_Packing_Result {
    Entry :: struct {
        ident: string;
        source_type: Sprite_Source;
        sprite_index: s64;
        filepath: string;
        texture: Texture_Data;
        
        // Optional (for aseprite)
        layer_name: string;
        frame_index: s64;
    }
    
    // TODO(Felix):
    // Especially the aseprite code is using more temporary memory than actually required.
    // If we want to optimize the memory usage we should probably use two temporary 
    // arenas to juggle the temporaries more efficiently.
    // (Parsed file in arena A, convert to raw images in arena B, which creates 
    // the atlas in arena A or permanent allocator).
    // But this is debug code, so that's fine for now.
    
    start := os_get_cpu_time();
    arena: Memory_Arena;
    create_memory_arena(*arena, 10 * Memory_Unit.Megabytes, 10 * Memory_Unit.Megabytes, false);
    allocator: Allocator = allocator_from_memory_arena(*arena);
    
    entries: [..]Entry;
    entries.allocator = *allocator;
    
    defer {
        for i := 0; i < entries.count; ++i { 
            source_type: Sprite_Source = array_get(*entries, i).source_type;
            if source_type == .Png {
                free_png_texture_data(*array_get(*entries, i).texture);
            } else if source_type == .Aseprite {
                // noop; is allocated on the arena
            }
        }
        destroy_memory_arena(*arena);
    };

    filepath := print_into_allocator(*allocator, "%/sprite-pack.txt", directory);
    original_file_content, file_found := read_entire_file(*allocator, filepath);
    
    highest_sprite_index: s64 = 0;
    result: Sprite_Packing_Result = .Success;
    
    //
    // Parse the Sprite Pack file
    //
    {
        if !file_found {
            logprint(.Error, "The sprite pack file '%' does not exist!", filepath);
            return .Complete_Failure;
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

            working_slice := line;
            identifier   := consume_whitespace_separated_string(*working_slice);
            path_to_file := consume_whitespace_separated_string(*working_slice);
            frame_index  := consume_whitespace_separated_string(*working_slice);
            layer_name   := consume_whitespace_separated_string(*working_slice);
            
            if identifier.count == 0 || path_to_file.count == 0 {
                logprint(.Error, "%:%: A mapping from a sprite identifier to a filepath was expected here, in the syntax '<identifier> <filepath> [frame [layer]]'.", filepath, line_number);
                result = .Complete_Failure;
                continue;
            }
            
            entry := array_push(*entries);
            entry.ident    = identifier;
            entry.filepath = print_into_allocator(*allocator, "%/%", directory, path_to_file);
            
            // fill optional frame_index & layer argument
            if frame_index.count > 0 {
                is_valid_number: bool;
                entry.frame_index, is_valid_number = string_to_int(frame_index);
                if !is_valid_number {
                    logprint(.Error, "%:%: The string % is not a valid frame index.", filepath, line_number, frame_index);
                    result = .Complete_Failure;
                    continue;
                }
                entry.layer_name = layer_name;
            }

            found_sprite_index: bool = ---;
            entry.sprite_index, found_sprite_index = find_sprite_index_from_name(entry.ident);
            if !found_sprite_index {
                logprint(.Error, "%: %: '%' is not known in the system.", filepath, line_number, entry.ident);
                entry.sprite_index = -1;
                result = .Complete_Failure;
                continue;
            }

            highest_sprite_index = max(entry.sprite_index, highest_sprite_index);

            if filepaths array_add(filepaths, copy_string(filepaths.allocator, entry.filepath));
        }
    }

    //
    // Check for missing entries and report errors on them
    //
    {
        for i: Sprite_Index = 0; i < Sprite_Index.Count; ++i {
            found := false;

            for j := 0; j < entries.count; ++j {
                entry := array_get_pointer(*entries, j);
                if entry.sprite_index == i {
                    found = true;
                    break;
                }
            }

            if !found {
                logprint(.Error, "The sprite '%' is missing in the sprite pack '%'.", i, filepath);
                result = .Partial_Failure;
            }
        }
    }
    
    
    //
    // Sort list so we only load each file once, even if it is used multiple times
    // 
    {
        compare_entries_by_path :: (a, b: *Entry) -> Sort_Comparison_Result {
            stringA := a.filepath;
            stringB := b.filepath;
            min_char_count := min(stringA.count, stringB.count);
            
            for i := 0; i < min_char_count; ++i {
                charA := to_lower_character(stringA[i]);
                charB := to_lower_character(stringB[i]);
                if charA != charB { return charA - charB; }
            }
            
            return stringA.count < stringB.count;
        }
        
        quick_sort([]Entry.{ entries.count, entries.data }, compare_entries_by_path);
    }
    
    //
    // Load all required sprite images into memory
    //
    {
        previous_path: string;
        previous_parsed_aseprite_file: Parsed_Aseprite_File;
        
        for i := 0; i < entries.count; ++i {
            entry := array_get_pointer(*entries, i);
            
            found_sprite: bool = false;
            if string_ends_with(entry.filepath, ".aseprite", .Case_Insensitive) {
                parsed_aseprite_file: Parsed_Aseprite_File;
                
                if strings_equal_case_insensitive(entry.filepath, previous_path) {
                    parsed_aseprite_file = previous_parsed_aseprite_file;
                } else {
                    file_content, success := read_entire_file(*allocator, entry.filepath);
                    found_sprite = success;
                    
                    if found_sprite {
                        parsed_aseprite_file, success = load_aseprite_layer_images_from_file(*allocator, entry.filepath);
                        assert(success, "Could not parse aseprite file during texture loading!");
                    }
                }

                if found_sprite {
                    pixel_data, passed_aseprite_checks := grab_texture_pixels_from_parsed_aseprite_file(parsed_aseprite_file, entry.layer_name, entry.frame_index);
                    entry.texture.width = parsed_aseprite_file.width;
                    entry.texture.height = parsed_aseprite_file.height;
                    entry.texture.channels = 4; // hardcoded RGBA
                    entry.texture.pixels = pixel_data;
                    entry.source_type = .Aseprite;
                    
                    if !passed_aseprite_checks {
                        logprint(.Error, "Problems detected with aseprite file %", entry.filepath);
                        result = .Complete_Failure;
                    }
                }
            } else if string_ends_with(entry.filepath, ".png", .Case_Insensitive) {
                entry.texture, found_sprite = load_texture_data(*allocator, entry.filepath);
                entry.source_type = .Png;
            }
            
            if !found_sprite {
                logprint(.Error, "The source sprite file '%' does not exist!", entry.filepath);
                result = .Complete_Failure;
            } else if entry.texture.channels != SPRITE_ATLAS_CHANNELS || entry.texture.width != SPRITE_WIDTH || entry.texture.height != SPRITE_HEIGHT {
                logprint(.Error, "Each source sprite file was expected to be %x% with % channels, but '%' was %x% with % channels.", SPRITE_WIDTH, SPRITE_HEIGHT, SPRITE_ATLAS_CHANNELS, entry.filepath, entry.texture.width, entry.texture.height, entry.texture.channels);
                result = .Complete_Failure;
            }
        }
    }

    //
    // Put all entries into the sprite atlases
    //
    {
        //
        // Prepare the atlases
        //
        atlas_count := cast(s64) ceil(cast(f64) (highest_sprite_index + 1) / cast(f64) SPRITES_PER_ATLAS);

        if atlas_count != SPRITE_ATLAS_COUNT {
            logprint(.Error, "The SPRITE_ATLAS_COUNT (%) constant is no longer correct... It should be % (we have a total of % sprites)!", SPRITE_ATLAS_COUNT, atlas_count, highest_sprite_index + 1);
            result = .Complete_Failure;
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

            file_written := stbi_write_png(filepath.data, atlas.width, atlas.height, atlas.channels, atlas.pixels.data, atlas.width * atlas.channels);
            
            if file_written == 0 {
                logprint(.Error, "The sprite atlas '%' could not be written to disk.", filepath);
                result = .Complete_Failure;
            } else {
                logprint(.Debug, "Packed the sprite atlas '%'.", filepath);
            }
        }
    }
    
    if result == .Success {
        end := os_get_cpu_time();
        #if ALLOCATOR_STATISTICS {
            logprint(.Debug, "Sprite packing took %ms, %mb.", os_convert_cpu_time(end - start, .Milliseconds), cast(f64) allocator.stats.working_set / 1_000_000.0);
        }
    }
    
    return result;
}

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

free_png_texture_data :: (data: *Texture_Data) {
    stbi_image_free(data.pixels.data);
    ~data = .{};
}

bake_all_sprite_atlases :: (directory: string) -> [SPRITE_ATLAS_COUNT]Texture_Data {
    sprites: [SPRITE_ATLAS_COUNT]Texture_Data;

    packing_result := pack_sprite_atlases(directory, null);
    if packing_result != .Success {
        compiler_report_error("Failed to pack the sprite atlases.");
        return sprites;
    }

    for i := 0; i < SPRITE_ATLAS_COUNT; ++i {
        filepath := print_into_allocator(Default_Allocator, "%/sprite_atlas_%.png", directory, i);

        success: bool = ---;
        sprites[i], success = load_texture_data(Default_Allocator, filepath);

        if !success {
            compiler_report_error(print_into_allocator(Default_Allocator, "[ASSET BAKE]: Failed to bake the texture '%': The file does not exist.\n", filepath));
            compiler_report_error(print_into_allocator(Default_Allocator, "[ASSET BAKE]:    We are in the working directory: '%'.\n", get_working_directory(Default_Allocator)));
        }
    }

    return sprites;
}
