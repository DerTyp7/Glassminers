SPRITES_PER_ATLAS      :: SPRITE_ATLAS_COLUMNS * SPRITE_ATLAS_ROWS;
SPRITE_ATLAS_WIDTH     :: 128;
SPRITE_ATLAS_HEIGHT    :: 128;
SPRITE_ATLAS_COLUMNS   :: 8;
SPRITE_ATLAS_ROWS      :: 8;
SPRITE_ATLAS_COUNT     :: 1;

BAKE_ASSETS :: !DEVELOPER;

Baked_Texture :: struct {
    width:    u32;
    height:   u32;
    channels: u32;
    pixels: string;
}

#if BAKE_ASSETS {
    BAKED_SPRITE_ATLASES :: #run bake_all_sprite_atlases("run_tree/data");
    BAKED_FONT :: #run bake_raw_file("run_tree/data/font.ttf");
}



#if DEVELOPER {
    reorder_sprite_atlases :: () {
        Old_Order :: enum { // A copy of the Sprite_Index enum
            Background;
            Bedrock;
            Crystal;
            Rock;
            Shard;
            Stone;
            Emitter;
            Receiver;
            Mirror;
            Player_Idle_0;
            Player_Idle_1;
            Dragon_Idle_0;
            Dragon_Idle_1;
            Dragon_Spitting_Fire;
            Dragon_Recovering_0;
            Dragon_Recovering_1;
        }

        New_Order: []Old_Order : .[
            .Background,
            .Bedrock,
            .Crystal,
            .Rock,
            .Shard,
            .Stone,
            .Emitter,
            .Receiver,
            .Mirror,
            .Player_Idle_0,
            .Player_Idle_1,
            .Count,
            .Count,
            .Count,
            .Count,
            .Dragon_Idle_0,
            .Dragon_Idle_1,
            .Dragon_Spitting_Fire,
            .Dragon_Recovering_0,
            .Dragon_Recovering_1,
        ];
        
        Sprite :: struct {
            width, height, channels: u32;
            pixels: string;
        }

        sprites: [Old_Order.Count]Sprite = ---;

        {
            old_atlases := bake_all_sprite_atlases("run_tree/data");

            for i := 0; i < sprites.Capacity; ++i {
                atlas_index := i / SPRITES_PER_ATLAS;
                index_in_atlas := i % SPRITES_PER_ATLAS;

                atlas := *old_atlases[atlas_index];
                
                sprite := *sprites[i];
                sprite.width    = atlas.width  / SPRITE_ATLAS_COLUMNS;
                sprite.height   = atlas.height / SPRITE_ATLAS_ROWS;
                sprite.channels = atlas.channels;
                sprite.pixels   = allocate_string(Default_Allocator, sprite.width * sprite.height * sprite.channels);

                row    := index_in_atlas / SPRITE_ATLAS_COLUMNS;
                column := index_in_atlas % SPRITE_ATLAS_COLUMNS;
                
                for h := 0; h < sprite.height; ++h {
                    y := row * sprite.height + h;
                    x := column * sprite.width;

                    copy_memory(*sprite.pixels[h * sprite.width * sprite.channels], *atlas.pixels[(y * atlas.width + x) * sprite.channels], sprite.width * sprite.channels);
                }
            }
        }

        {
            new_atlases := allocate_array(Default_Allocator, Baked_Texture, cast(s64) ceil(cast(f64) New_Order.count / cast(f64) SPRITES_PER_ATLAS));

            for i := 0; i < new_atlases.count; ++i {
                atlas := *new_atlases[i];
                atlas.width    = SPRITE_ATLAS_WIDTH;
                atlas.height   = SPRITE_ATLAS_HEIGHT;
                atlas.channels = 4;
                atlas.pixels   = allocate_string(Default_Allocator, atlas.width * atlas.height * atlas.channels);
                clear_memory(atlas.pixels.data, atlas.width * atlas.height * atlas.channels);
            }

            for i := 0; i < New_Order.count; ++i {
                if New_Order[i] == .Count continue;

                sprite := *sprites[New_Order[i]];

                atlas_index := i / SPRITES_PER_ATLAS;
                index_in_atlas := i % SPRITES_PER_ATLAS;

                row    := index_in_atlas / SPRITE_ATLAS_COLUMNS;
                column := index_in_atlas % SPRITE_ATLAS_COLUMNS;

                atlas := *new_atlases[atlas_index];

                for h := 0; h < sprite.height; ++h {
                    y := row * sprite.height + h;
                    x := column * sprite.width;

                    copy_memory(*atlas.pixels[(y * atlas.width + x) * sprite.channels], *sprite.pixels[h * sprite.width * sprite.channels], sprite.width * sprite.channels);
                }
            }

            for i := 0; i < new_atlases.count; ++i {
                atlas := *new_atlases[i];
                file_path := print_into_allocator(Default_Allocator, "run_tree/data/sprite_atlas_%.png", i);
                file_path_cstring := to_cstring(Default_Allocator, file_path);
                result := stbi_write_png(file_path_cstring, atlas.width, atlas.height, atlas.channels, atlas.pixels.data, atlas.width * atlas.channels);
                if result == 0 {
                    print("[ASSET CONVERT]: Failed to write back the converted sprite atlas '%'.\n", file_path);
                } else {
                    print("[ASSET CONVERT]: Converted to a new sprite atlas '%'.\n", file_path);
                }
            }
        }
    }
}
    
#file_scope

bake_texture :: (file_path: string) -> Baked_Texture {
    file_content, success := read_entire_file(Default_Allocator, file_path);
    if !success {
        print("[ASSET BAKE]: Failed to bake the texture '%': The file does not exist.\n", file_path);
        print("[ASSET BAKE]:    We are in the working directory: '%'.\n", get_working_directory(Default_Allocator));
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

bake_all_sprite_atlases :: (directory: string) -> [SPRITE_ATLAS_COUNT]Baked_Texture {
    result: [SPRITE_ATLAS_COUNT]Baked_Texture = ---;

    for i := 0; i < SPRITE_ATLAS_COUNT; ++i {
        file_path := print_into_allocator(Default_Allocator, "%/sprite_atlas_%.png", directory, i);
        result[i] = bake_texture(file_path);
    }

    return result;
}
