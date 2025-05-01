BAKE_ASSETS :: !DEVELOPER;

Baked_Texture :: struct {
    width: s32;
    height: s32;
    channels: u8;
    pixels: string;
}

#if BAKE_ASSETS {
    BAKED_SPRITE_ATLASES :: #run bake_all_sprite_atlases();
    BAKED_FONT :: #run bake_raw_file("run_tree/data/font.ttf");
}
    
#file_scope

bake_texture :: (file_path: string) -> Baked_Texture {
    file_content, success := read_entire_file(Default_Allocator, file_path);
    if !success {
        print("[ASSET BAKE]: Failed to bake the texture '%': The file does not exist.\n", file_path);
        return .{ };
    }

    width, height, channels_in_file: s32 = ---;
    buffer := stbi_load_from_memory(file_content.data, file_content.count, *width, *height, *channels_in_file, 0);
    buffer_size_in_bytes := width * height * channels_in_file;

    print("[ASSET BAKE]: Baked '%'.\n", file_path);
    
    return .{ width, height, channels_in_file, .{ buffer_size_in_bytes, buffer } };
}

bake_raw_file :: (file_path: string) -> string {
    file_content, success := read_entire_file(Default_Allocator, file_path);
    if !success {
        print("[ASSET BAKE]: Failed to bake the raw file '%': The file does not exist.\n", file_path);
        return "";
    }

    print("[ASSET BAKE]: Baked '%'.\n", file_path);

    return file_content;
}

bake_all_sprite_atlases :: () -> [SPRITE_ATLAS_COUNT]Baked_Texture {
    result: [SPRITE_ATLAS_COUNT]Baked_Texture = ---;

    for i := 0; i < SPRITE_ATLAS_COUNT; ++i {
        file_path := print_into_allocator(Default_Allocator, "run_tree/data/sprite_atlas_%.png", i);
        result[i] = bake_texture(file_path);
    }

    return result;
}
