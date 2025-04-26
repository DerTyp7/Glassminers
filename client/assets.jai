BAKE_ASSETS :: !DEVELOPER;

Baked_Texture :: struct {
    width: s32;
    height: s32;
    channels: u8;
    pixels: string;
}

#if BAKE_ASSETS {
    BAKED_SPRITE_ATLAS :: #run bake_texture("run_tree/data/sprite_atlas.png");
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
