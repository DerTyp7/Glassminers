// Aseprite stores some data in a zlib compressed format
#load "zlib.jai";

// -------------------------- Easy API  ---------------------------- //

// load_aseprite_layer_images_from_file   :: (allocator: *Allocator, path_to_file: string) -> Parsed_Aseprite_File, bool;
// load_aseprite_layer_images_from_memory :: (allocator: *Allocator, memory: string)       -> Parsed_Aseprite_File, bool;
// aseprite_print_file_structure :: (file_data: string);

// Returns in RGBA
Parsed_Aseprite_File :: struct {
    width:  u16;
    height: u16;

    layers: []Layer;
    Layer :: struct {
        name:     string;  // Actual string
        images: []string;  // String is image data
    }
}


// TODO(Felix): Ideally, this would take two separate allocators:
// - one for the temporary data, and
// - one for the "permanent" / result data.

load_aseprite_layer_images_from_file :: (allocator: *Allocator, path_to_file: string) -> Parsed_Aseprite_File, bool {
    file_content, success := read_entire_file(allocator, path_to_file);
    if !success { return .{}, false; }
    
    return load_aseprite_layer_images_from_memory(allocator, file_content);
}

load_aseprite_layer_images_from_memory :: (allocator: *Allocator, memory: string) -> Parsed_Aseprite_File, bool {
    result: Parsed_Aseprite_File;
    
    // File Header parsing & checks
    file_header: *Aseprite_File_Header = xx memory.data;
    if file_header.magic_number != ASEPRITE_MAGIC_NUMBER_FILE_HEADER { return .{}, false; }
    result.width  = file_header.width_in_pixels;
    result.height = file_header.height_in_pixels;
    frames_count := file_header.frames;
    
    
    // NOTE(Felix): I'm assuming that every layer has the same amount of frames.
    // Iterate over all layers of one frame once to determine the layer size
    layer_count: u16;
    {
        current_byte_location   := size_of(~file_header); 
        start_of_frame_location := current_byte_location;
        frame_header: *Aseprite_Frame_Header = xx pointer_after_struct(file_header);

        if frame_header.magic_number != ASEPRITE_MAGIC_NUMBER_FRAME_HEADER { return .{}, false; }
        current_byte_location += size_of(~frame_header);
        
        while current_byte_location < start_of_frame_location + frame_header.bytes_in_this_frame {
            chunk_header: *Aseprite_Chunk_Header = xx (memory.data + current_byte_location);
            if chunk_header.chunk_type == .Layer { 
                layer_count += 1;
            }
            
            current_byte_location += chunk_header.chunk_size;
        }
    }
    
    // Prepare memory
    {
        BYTES_PER_PIXEL :: 4;
        bytes_per_image := BYTES_PER_PIXEL * result.width * result.height;
        result.layers = allocate_array(allocator, Parsed_Aseprite_File.Layer, layer_count);
        for layer_index := 0; layer_index < layer_count; ++layer_index {
            layer: *Parsed_Aseprite_File.Layer = *result.layers[layer_index];
            layer.images = allocate_array(allocator, string, frames_count);
            for frame_index := 0; frame_index < frames_count; ++frame_index {
                image_data := allocate_string(allocator, bytes_per_image);
                clear_memory(image_data.data, image_data.count); // Ensure that the images are completely transparent at first
                layer.images[frame_index] = image_data;
            }
        }
    }
    
    
    // Second pass: Actually read pixel data and extract data
    {
        current_byte_location   := size_of(~file_header); 
        frame_index := 0;
        color_palette: []Palette_Entry; // I'm assuming that there will be just one big palette

        // for all frames
        while current_byte_location < file_header.file_size {
            start_of_frame_location := current_byte_location;
            frame_header: *Aseprite_Frame_Header = xx (memory.data + start_of_frame_location);
            current_byte_location += size_of(~frame_header);
            
            // Layers are stored in the first frame.
            // Now that we have layer array allocated, 
            // store the strings into into them as well
            layer_index := 0;

            while current_byte_location < start_of_frame_location + frame_header.bytes_in_this_frame {
                chunk_header: *Aseprite_Chunk_Header = xx (memory.data + current_byte_location);
                chunk_data: *void = xx pointer_after_struct(chunk_header);
                if chunk_header.chunk_type == {
                    case .Old_Palette_1;
                        old_palette: *Aseprite_Chunk_Palette_Old = xx chunk_data;
                        assert(color_palette.count == 0, "Color palette already exists, we are missing logic to extend it!");
                        color_palette = aseprite_get_flattened_palette_from_old_palette_chunk(allocator, old_palette);
                        
                    case .Palette;
                        palette: *Aseprite_Chunk_Palette = chunk_data;
                        assert(color_palette.count == 0, "Color palette already exists, we are missing logic to extend it!");
                        color_palette = aseprite_get_flattened_palette_from_palette_chunk(allocator, palette);
                        
                    case .Color_Profile;
                        color_profile: *Aseprite_Chunk_Color_Profile = xx chunk_data;
                        
                    case .Layer;
                        layer: *Aseprite_Chunk_Layer = xx chunk_data;

                        // Get string of layer
                        layer_name := aseprite_read_string(allocator, pointer_after_struct(layer));
                        result.layers[layer_index].name = layer_name;
                        layer_index += 1;
                        
                        
                    case .Cel;
                        cel: *Aseprite_Chunk_Cel = xx chunk_data;
                        image: *string = *result.layers[cel.layer_index].images[frame_index];
                        
                        // This is a very limited implementation at the moment
                        if #complete cel.cel_type == {
                            case .Raw_Image_Data;
                                aseprite_modify_image_from_raw_indexed_cel_chunk(image, color_palette, file_header.color_depth, 
                                                                                 result.width, result.height, cel);
                                
                            case .Compressed_Image;
                                content: *u8 = pointer_after_struct(cel);
                                width:  u16 = consume_and_move(*content, u16);
                                height: u16 = consume_and_move(*content, u16);
                                
                                bytes_per_aseprite_pixel := 0;
                                if #complete file_header.color_depth == {
                                    case .RGBA;      bytes_per_aseprite_pixel = 4;
                                    case .Grayscale; panic("Grayscale color depth not implemented.");
                                    case .Indexed;   bytes_per_aseprite_pixel = 1;
                                }
                                
                                bytes_read_within_chunk: s64 = cast(s64)(content - cast(*u8)cel);
                                compressed_content_size := chunk_header.chunk_size - bytes_read_within_chunk;
                                uncompressed_content_size := width * height * bytes_per_aseprite_pixel;
                                
                                compressed_content: string = .{compressed_content_size, content };
                                uncompressed_content: string = zlib_decode_known_output_size_into_allocator(allocator, compressed_content, uncompressed_content_size);
                                if uncompressed_content.count == 0 { panic("Aseprite zlib decoding failed!"); }
                                
                                aseprite_modify_image_pixels(image, color_palette, file_header.color_depth, cel, 
                                                             width, height, result.width, result.height,
                                                             uncompressed_content);
                                
                            case .Linked_Cel;
                                panic("Aseprite Cel Type \"Linked Cel\" is not implemented.");
                                return .{}, false;
                                
                            case .Compressed_Tilemap;
                                panic("Aseprite Cel Type \"Compressed Tilemap\" is not implemented.");
                                return .{}, false;
                        }
                        
                    case;
                        print("Chunk type % not implemented!\n", aseprite_chunk_type_to_name(chunk_header.chunk_type));
                        return .{}, false;

                }

                current_byte_location += chunk_header.chunk_size;
            }
            
            frame_index += 1;
        }
    }
    
    return result, true;
}


// Used for debugging / inspecting files which are not parsed properly
aseprite_print_file_structure :: (file_data: string) {
    file_header: *Aseprite_File_Header = xx file_data.data;
    if file_header.magic_number != ASEPRITE_MAGIC_NUMBER_FILE_HEADER {
        print("File content does not contain correct aseprite magic number (% vs %)!", file_header.magic_number, ASEPRITE_MAGIC_NUMBER_FILE_HEADER);
        return;
    }

    current_frame_index := 0;
    current_byte_location   := size_of(~file_header); 
    while current_byte_location < file_header.file_size {
        start_of_frame_location := current_byte_location;
        frame_header: *Aseprite_Frame_Header = xx (file_data.data + start_of_frame_location);
        current_byte_location += size_of(~frame_header);
        print("Frame % chunks: \n", current_frame_index);

        while current_byte_location < start_of_frame_location + frame_header.bytes_in_this_frame {
            chunk_header: *Aseprite_Chunk_Header = xx (file_data.data + current_byte_location);
            print("  %\n", aseprite_chunk_type_to_name(chunk_header.chunk_type));

            current_byte_location += chunk_header.chunk_size;
        }

        current_frame_index += 1;
        print("\n");
    }

    print("Done.\n");
}


#file_scope

// -------------------------- Start of internals ---------------------------- //

// File documentation
// https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md

// All aseprite bytes are stored in little endian.

ASEPRITE_MAGIC_NUMBER_FILE_HEADER  :: 0xA5E0;
ASEPRITE_MAGIC_NUMBER_FRAME_HEADER :: 0xF1FA;


// -------------------------- Types ---------------------------- //

Aseprite_Fixed_Type :: u32; // 32-bit fixed floating point (16.16). -_-
// STRING type: { string_length: u16, [string_length]u8 }

// These structs are representing the headers in memory,
// so don't shuffle the members around!

Aseprite_File_Header :: struct #packed {
    file_size:    u32;
    magic_number: u16; // Should be 0xA5E0
    frames:       u16;
    
    width_in_pixels:  u16;
    height_in_pixels: u16;
    color_depth:      Aseprite_Color_Depth;
    flags:            u32;
    speed:            u16; // milliseconds between frames
    
    __reserved_0: u32; // these two
    __reserved_1: u32; // should be 0
    
    palette_entry_index: u8;
    __reserved_2: [3]u8;
    number_of_colors:    u16;
    
    pixel_width:  u8;
    pixel_height: u8;
    x_position_of_grid: s16;
    y_position_of_grid: s16;
    grid_width:  u16;
    grid_height: u16;
    __reserved_3: [84]u8;
}

Aseprite_Frame_Header :: struct #packed {
    bytes_in_this_frame: u32;
    magic_number:        u16; // Should be 0xF1FA
    
    old_field_number_of_chunks: u16;
    frame_duration_in_ms:       u16; // milliseconds
    __reserved_0: [2]u8;
    new_field_number_of_chunks: u32;
}

Aseprite_Chunk_Header :: struct #packed {
    chunk_size: u32; // in bytes, >= 6 
    chunk_type: Aseprite_Chunk_Type;
    // chunk_size includes not only the size of the remaining bytes of the chunk,
    // but also the size of chunk_type and chunk_size itself
    
    // Afterwards the chunk_data follows:
    // [chunk_size - size_of(u32) - size_of(u16)]u8
}

Aseprite_Chunk_Type :: enum (u16) {
    Old_Palette_1 :: 0x0004; 
    Old_Palette_2 :: 0x0011;
    Layer         :: 0x2004;
    Cel           :: 0x2005;
    Cel_Extra     :: 0x2006;
    Color_Profile :: 0x2007;
    External_File :: 0x2008;
    Mask          :: 0x2016; // "Deprecated"
    Path          :: 0x2017; // "Unused"
    Tags          :: 0x2018; 
    Palette       :: 0x2019; // New version of Old_palette_...
    User_Data     :: 0x2020;
    Slice         :: 0x2022;
    Tileset       :: 0x2023;
}

// TODO(Felix): Chunk implementations
//  - Old_Palette_2
//  - Cel_Extra    
//  - External_File
//  - Mask         
//  - Path         
//  - Tags         
//  - User_Data    
//  - Slice        
//  - Tileset      


// -------------------------- Chunks ---------------------------- //


// Color profile

Aseprite_Color_Profile_Type :: enum(u16) {
    No_Color_Profile :: 0;
    SRGB             :: 1;
    Embedded_ICC     :: 2; 
}

Aseprite_Chunk_Color_Profile :: struct #packed {
    type:  Aseprite_Color_Profile_Type;
    flags: u16;
    gamma: Aseprite_Fixed_Type;
    
    __reserved_0: [8]u8;
    // If type == .Embedded_ICC, there is more data here
}



// Palette ("old")

Aseprite_Chunk_Palette_Old_Packet_Color :: struct #packed {
    red:   u8;
    green: u8;
    blue:  u8;
}

Aseprite_Chunk_Palette_Old_Packet :: struct #packed {
    to_skip_count:    u8; // "Number of palette entries to skip from the last packet (start from 0)"
    number_of_colors: u8; // "0 means 256"
    // For each packet: Aseprite_Chunk_Palette_Old_Packet_Color
}
 
Aseprite_Chunk_Palette_Old :: struct #packed {
    number_of_packets: u16;
    // Then there are Aseprite_Chunk_Palette_Old_Packet 
}



// Palette ("new")

Aseprite_Chunk_Palette_Entry_Flags :: enum(u16) {
    Has_Name :: 1;
}

Aseprite_Chunk_Palette_Entry :: struct #packed {
    flags: Aseprite_Chunk_Palette_Entry_Flags;
    
    red:   u8;
    green: u8;
    blue:  u8;
    alpha: u8;
    
    // If type & .HasName: ASEPRITE_STRING name here
}

Aseprite_Chunk_Palette :: struct #packed {
    palette_size:      u32;
    first_color_index: u32;
    last_color_index:  u32;
    
    __reserved_0: [8]u8;
}


// Layer

Aseprite_Chunk_Layer_Flags :: enum(u16) {
    // TODO
}

Aseprite_Chunk_Layer_Type :: enum(u16) {
    Normal  :: 0;
    Group   :: 1;
    Tilemap :: 2;
}

Aseprite_Chunk_Layer_Blend_Mode :: enum(u16) {
    Normal      ::  0;
    Multiply    ::  1;
    Screen      ::  2;
    Overlay     ::  3;
    Darken      ::  4;
    Lighten     ::  5;
    Color_Dodge ::  6;
    Color_Burn  ::  7;
    Hard_Light  ::  8;
    Soft_Light  ::  9;
    Difference  :: 10;
    Exclusion   :: 11;
    Hue         :: 12;
    Saturation  :: 13;
    Color       :: 14;
    Luminosity  :: 15;
    Addition    :: 16;
    Subtract    :: 17;
    Divide      :: 18;
}

Aseprite_Chunk_Layer :: struct #packed {
    flags: Aseprite_Chunk_Layer_Flags;
    type:  Aseprite_Chunk_Layer_Type;
    layer_child_level: u16;
    
    __ignored_default_layer_width:  u16;
    __ignored_default_layer_height: u16;
    
    blend_mode: Aseprite_Chunk_Layer_Blend_Mode;
    opacity: u8;
    
    __reserved_0: [3]u8;
    
    // ASEPRITE_STRING layer name
    // if type == .Tilemap:  tileset_index: u16
    // there is one more member here if some file_header flag is set
}



// Cel

Aseprite_Chunk_Cel_Type :: enum(u16) {
    Raw_Image_Data     :: 0;
    Linked_Cel         :: 1;
    Compressed_Image   :: 2;
    Compressed_Tilemap :: 3;
}

Aseprite_Chunk_Cel :: struct #packed {
    layer_index:   u16;
    x_position:    s16;
    y_position:    s16;
    opacity_level: u8;
    cel_type: Aseprite_Chunk_Cel_Type;
    z_index: s16;
    
    __reserved_0: [5]u8;
    // There is a bunch of stuff following depending on the cell type
}


// -------------------------- Helpers  ---------------------------- //

Palette_Entry :: GE_Color;

Aseprite_Color_Depth :: enum(u16) {
    RGBA      :: 32;
    Grayscale :: 16;
    Indexed   ::  8;
}

aseprite_get_flattened_palette_from_old_palette_chunk :: (allocator: *Allocator, chunk: *Aseprite_Chunk_Palette_Old) -> []Palette_Entry {
    SIZE_OF_COLOR_ENTRY   :: 3;
    
    // First pass: Count colors
    color_count: u32;
    {
        current_packet: *Aseprite_Chunk_Palette_Old_Packet = xx pointer_after_struct(chunk);
        for packet_index := 0; packet_index < chunk.number_of_packets; ++packet_index {
            colors_in_packet := ifx current_packet.number_of_colors == 0 then 256 else current_packet.number_of_colors;
            color_count += colors_in_packet;
            offset_to_next_packet := size_of(~current_packet) + (colors_in_packet * SIZE_OF_COLOR_ENTRY);
            current_packet = xx ((cast(*u8)current_packet) + offset_to_next_packet);
        }
    }
    
    // Prepare memory
    result: []Palette_Entry = allocate_array(allocator, Palette_Entry, color_count);
    
    // Second pass: Fill colors
    {
        current_color_index: u32 = 0;
        current_packet: *Aseprite_Chunk_Palette_Old_Packet = xx pointer_after_struct(chunk);
        assert(current_packet.to_skip_count == 0, "Skipping over palette indices not handled.");
        for packet_index := 0; packet_index < chunk.number_of_packets; ++packet_index {
            colors_in_packet := ifx current_packet.number_of_colors == 0 then 256 else current_packet.number_of_colors;
            offset_to_next_packet := size_of(~current_packet) + (colors_in_packet * SIZE_OF_COLOR_ENTRY);

            colors: *Aseprite_Chunk_Palette_Old_Packet_Color = xx pointer_after_struct(current_packet);
            for i := 0; i < colors_in_packet; ++i {
                to_fill: *Palette_Entry = *result[current_color_index];
                current_color_index += 1;
                
                to_fill.r = colors[i].red;
                to_fill.g = colors[i].green;
                to_fill.b = colors[i].blue;
                to_fill.a = 255;
            }
            
            current_packet = xx ((cast(*u8)current_packet) + offset_to_next_packet);
        }
    }
    
    // NOTE(Felix): There is a rare behavior, which is very weird:
    // Some files seem to have a dedicated "transparent" palette entry, 
    // which seems to be completely indistinguishable from a pitch-black color entry.
    // This is especially confusing because this old palette chunk is not storing transparency at all.
    // 
    // So far the only successfull strategy I found is
    //  - see if there are two pitch black palette entries
    //  - see if one of them is at index 0
    //  - If all of the above is true, the one at index 0 is actually completely transparent.
    {
        palette_entry_is_completely_black :: (entry: Palette_Entry) -> bool {
            return entry.r == 0 && entry.g == 0 && entry.b == 0;
        }

        pitch_black_index: s32 = 0;
        for i: s32 = 1; i < xx result.count; ++i {
            if palette_entry_is_completely_black(result[i]) {
                pitch_black_index = i;
                break;
            }
        }
        
        if palette_entry_is_completely_black(result[0]) && pitch_black_index != 0 {
            // The first color entry is completely transparent, actually.
            result[0].a = 0;
        }
    }
    
    return result;
}

aseprite_get_flattened_palette_from_palette_chunk :: (allocator: *Allocator, chunk: *Aseprite_Chunk_Palette) -> []Palette_Entry {
    // I think this is for combining multiple palettes - I'm not doing this for now
    assert(chunk.first_color_index == 0, "Unexpected first color index");
   
    content: *u8 = pointer_after_struct(chunk);
    color_count := chunk.palette_size;
    
    result: []Palette_Entry = allocate_array(allocator, Palette_Entry, color_count);
    
    for i := 0; i < result.count; ++i {
        to_fill: *Palette_Entry = *result[i];
        flags: u16 = consume_and_move(*content, u16);
        to_fill.r = consume_and_move(*content, u8);
        to_fill.g = consume_and_move(*content, u8);
        to_fill.b = consume_and_move(*content, u8);
        to_fill.a = consume_and_move(*content, u8);
        
        has_name := flags & 1;
        if has_name {
            string_length: u16 = consume_and_move(*content, u16);
            content += string_length;
        }    
    }
    
    return result;
}


aseprite_modify_image_from_raw_indexed_cel_chunk :: (image: *string, palette: []Palette_Entry, color_depth: Aseprite_Color_Depth, 
                                                     target_width, target_height: u16,
                                                     cel: *Aseprite_Chunk_Cel) {
    content: *u8 = pointer_after_struct(cel);
    width:  u16 = consume_and_move(*content, u16);
    height: u16 = consume_and_move(*content, u16);
    
    aseprite_pixel_size := color_depth / 8;
    aseprite_pixel_data: string = .{ width*height * aseprite_pixel_size, content };
    aseprite_modify_image_pixels(image, palette, color_depth, cel, width, height, target_width, target_height, aseprite_pixel_data);
}

aseprite_modify_image_pixels :: (image: *string, palette: []Palette_Entry, color_depth: Aseprite_Color_Depth,
                                 cel: *Aseprite_Chunk_Cel, 
                                 source_width, source_height: u16,
                                 target_width, target_height: u16,
                                 aseprite_pixel_data: string) {
    // NOTE(Felix): 
    // Some sprite frames only store part of the entire target texture (e.g. skipping out
    // an entire transparent row of pixels by setting cel.y_position & source_height accordingly).
    // 
    // Some sprite frames also store _more_ pixels than the target texture (??? why).
    // (so e.g. a cel with a larger height than the result image).
    // Sometimes the col.[]_position is also negative.
    // Maybe this is for compression purposes? Not quite sure, but simply ignoring those pixels
    // seems to be the way to go.
    target_out_of_bounds :: (x, y, target_width, target_height: s16) -> bool {
        return x < 0 || x >= target_width || y < 0 || y >= target_height;
    }


    BYTES_PER_RESULT_PIXEL :: 4;
    
    current_pixel_index: u32 = 0;
    if #complete color_depth == {
        case .RGBA;
            // Each pixel is [4]u8
            Aseprite_Pixel :: [4]u8; // Index into palette
            pixels: *Aseprite_Pixel = xx aseprite_pixel_data.data;
            for y := 0; y < source_height; ++y {
                for x := 0; x < source_width; ++x {
                    pixel: Aseprite_Pixel = pixels[y*source_width + x];

                    target_row    := y + cel.y_position;
                    target_column := x + cel.x_position;
                    if target_out_of_bounds(target_row, target_column, target_width, target_height) { continue; }
                    
                    destination_pixel: *u8 = *image.data[(target_row*target_height + target_column) * BYTES_PER_RESULT_PIXEL];
                    destination_pixel[0] = pixel[0];
                    destination_pixel[1] = pixel[1];
                    destination_pixel[2] = pixel[2];
                    destination_pixel[3] = pixel[3];
                }
            }


        case .Grayscale;
            panic("Grayscale color depth is not implemented!");
            
        case .Indexed;
            // Each pixel is just an u8 color palette index
            Aseprite_Pixel :: u8; // Index into palette
            pixels: *Aseprite_Pixel = xx aseprite_pixel_data.data;
            for y := 0; y < source_height; ++y {
                for x := 0; x < source_width; ++x {
                    palette_index := pixels[y*source_width + x];
                    assert(palette_index < palette.count, "Out of bounds palette index.");

                    target_row    := y + cel.y_position;
                    target_column := x + cel.x_position;
                    if target_out_of_bounds(target_row, target_column, target_width, target_height) { continue; }

                    destination_pixel: *u8 = *image.data[(target_row*target_height + target_column) * BYTES_PER_RESULT_PIXEL];
                    destination_pixel[0] = palette[palette_index].r;
                    destination_pixel[1] = palette[palette_index].g;
                    destination_pixel[2] = palette[palette_index].b;
                    destination_pixel[3] = palette[palette_index].a;
                }
            }
    }
}

aseprite_read_string :: (allocator: *Allocator, aseprite_string: *void) -> string {
    content: *u8 = aseprite_string;
    string_length:   u16 = consume_and_move(*content, u16);
    string_content: *u8  = content;
    
    result := allocate_string(allocator, string_length);
    copy_memory(result.data, string_content, string_length);
    
    return result;
}

aseprite_chunk_type_to_name :: (chunk_type: Aseprite_Chunk_Type) -> string {
    enum_info := cast(*Type_Info_Enum) type_info(Aseprite_Chunk_Type);
    for i := 0; i < enum_info.members.count; ++i {
        chunk_type_value := cast(s64) chunk_type;
        if chunk_type == enum_info.members[i].integral_value {
            return enum_info.members[i].display_name;
        } 
    }
    return "INVALID_CHUNK_TYPE";
}


// Pointer helpers

consume_and_move :: (pointer: **u8, $T: Type) -> T {
    value_pointer: *T = xx ~pointer;
    ~pointer += size_of(T);
    return ~value_pointer;
}

pointer_after_struct :: (pointer: *$T) -> *u8 {
    bytes_to_skip := size_of(~pointer);
    return (cast(*u8)pointer) + bytes_to_skip;
}
