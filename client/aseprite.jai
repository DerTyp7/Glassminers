// TODO(Felix): This should probably be a compiler module or something

#load "zlib.jai";

ASEPRITE_MAGIC_NUMBER_FILE_HEADER  :: 0xA5E0;
ASEPRITE_MAGIC_NUMBER_FRAME_HEADER :: 0xF1FA;
ASEPRITE_OFFSET_FROM_CHUNK_HEADER_TO_CHUNK_CONTENT :: size_of(u32) + size_of(u16);

// Easy api

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
// Too bad!

// TODO(Felix): Need to implement zlib because aseprite files are compressed >:(

// DEBUG
#run {
    SIMPLE_FILE_PATH      :: "/home/void/Software/Victor/Glassminers/aseprite/inanimates/bedrock.aseprite";
    COMPLICATED_FILE_PATH :: "/home/void/Software/Victor/Glassminers/aseprite/guy/guy-walking.aseprite";
    EXAMPLE_FILE_PATH     :: COMPLICATED_FILE_PATH;
    
    // TODO(Felix)
    //load_aseprite_layer_images_from_file(Default_Allocator, EXAMPLE_FILE_PATH);
    
    file_content, success := read_entire_file(Default_Allocator, EXAMPLE_FILE_PATH);
    aseprite_print_file_structure(file_content);
}

#run { assert(size_of(Aseprite_File_Header) == 128, "File Header size bad"); }
#run { assert(size_of(Aseprite_Frame_Header) == 16, "Frame Header Size bad"); }

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
        frame_header: *Aseprite_Frame_Header = xx (memory.data + current_byte_location);

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
                chunk_data: *void = xx (memory.data + current_byte_location + ASEPRITE_OFFSET_FROM_CHUNK_HEADER_TO_CHUNK_CONTENT);
                if chunk_header.chunk_type == {
                    case .Old_Palette_1;
                        old_palette: *Aseprite_Chunk_Palette_Old = xx chunk_data;
                        assert(color_palette.count == 0, "Color palette already exists, we are missing logic to extend it!");
                        color_palette = aseprite_get_flattened_palette_from_old_palette_chunk(allocator, old_palette);
                        
                    case .Color_Profile;
                        color_profile: *Aseprite_Chunk_Color_Profile = xx chunk_data;
                        
                    case .Layer;
                        layer: *Aseprite_Chunk_Layer = xx chunk_data;

                        // Get string of layer
                        layer_name := aseprite_read_string(allocator, *layer.__reserved_0[2] + 1);
                        result.layers[layer_index].name = layer_name;
                        layer_index += 1;
                        
                        
                    case .Cel;
                        assert(file_header.color_depth == .Indexed, "Only indexed colors are implemented.");
                        
                        cel: *Aseprite_Chunk_Cel = xx chunk_data;
                        image: *string = *result.layers[cel.layer_index].images[frame_index];
                        
                        // This is a very limited implementation at the moment
                        if #complete cel.cel_type == {
                            case .Raw_Image_Data;
                                aseprite_modify_image_from_raw_indexed_cel_chunk(image, color_palette, cel);
                                
                            case .Compressed_Image;
                                assert(false, "Aseprite Cel Type \"Compressed Image\" is not implemented.");
                                return .{}, false;
                                
                            case .Linked_Cel;
                                assert(false, "Aseprite Cel Type \"Linked Cel\" is not implemented.");
                                return .{}, false;
                                
                            case .Compressed_Tilemap;
                                assert(false, "Aseprite Cel Type \"Compressed Tilemap\" is not implemented.");
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
    
    // TODO
    return .{}, false;
}

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


// File documentation
// https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md

// All aseprite bytes are stored in little endian.

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
    // TODO: there is one more member here if some file_header flag is set
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
    // TODO(Felix): There is a bunch of stuff following depending on the cell type
}

// TODO(Felix): This is temporary code to see which chunks 
// we actually need to implement for parsing Glassminers Aseprite files.
// Ideally we'd implement everything, but I'll implement stuff
// as needed.


// -------------------------- Helpers  ---------------------------- //

Palette_Entry :: GE_Color;

Aseprite_Color_Depth :: enum(u16) {
    RGBA      :: 32;
    Grayscale :: 16;
    Indexed   ::  8;
}

aseprite_get_flattened_palette_from_old_palette_chunk :: (allocator: *Allocator, chunk: *Aseprite_Chunk_Palette_Old) -> []Palette_Entry {
    SIZE_OF_COLOR_ENTRY   :: 3;
    SIZE_OF_PACKET_HEADER :: 2;
    
    // First pass: Count colors
    color_count: u32;
    {
        current_packet: *Aseprite_Chunk_Palette_Old_Packet = xx ((cast(*u8)chunk) + size_of(~chunk));
        for packet_index := 0; packet_index < chunk.number_of_packets; ++packet_index {
            colors_in_packet := ifx current_packet.number_of_colors == 0 then 256 else current_packet.number_of_colors;
            color_count += colors_in_packet;
            offset_to_next_packet := SIZE_OF_PACKET_HEADER + (colors_in_packet * SIZE_OF_COLOR_ENTRY);
            current_packet = xx ((cast(*u8)current_packet) + offset_to_next_packet);
        }
    }
    
    // Prepare memory
    result: []Palette_Entry = allocate_array(allocator, Palette_Entry, color_count);
    
    // Second pass: Fill colors
    {
        current_color_index: u32 = 0;
        current_packet: *Aseprite_Chunk_Palette_Old_Packet = xx ((cast(*u8)chunk) + size_of(~chunk));
        assert(current_packet.to_skip_count == 0, "Skipping over palette indices not handled.");
        for packet_index := 0; packet_index < chunk.number_of_packets; ++packet_index {
            colors_in_packet := ifx current_packet.number_of_colors == 0 then 256 else current_packet.number_of_colors;
            offset_to_next_packet := SIZE_OF_PACKET_HEADER + (colors_in_packet * SIZE_OF_COLOR_ENTRY);

            colors: *Aseprite_Chunk_Palette_Old_Packet_Color = xx ((cast(*u8)current_packet) + SIZE_OF_PACKET_HEADER);
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
    
    return result;
}

aseprite_modify_image_from_raw_indexed_cel_chunk :: (image: *string, palette: []Palette_Entry, cel: *Aseprite_Chunk_Cel) {
    start_of_content: *u8 = (*cel.__reserved_0[4] + 1);
    width:  u16 = ~cast(*u16)(start_of_content + 0);
    height: u16 = ~cast(*u16)(start_of_content + 2);
    
    BYTES_PER_PIXEL :: 4;

    Aseprite_Pixel :: u8; // Index into palette
    pixels: *Aseprite_Pixel = xx (start_of_content + 4);
    current_pixel_index: u32 = 0;
    for y := 0; y < height; ++y {
        for x := 0; x < width; ++x {
            palette_index := pixels[y*width + x];
            print("% ", palette_index);
            assert(palette_index < palette.count, "Out of bounds palette index.");

            destination_pixel: *u8 = *image.data[y*width + x];
            destination_pixel[0] = palette[palette_index].r;
            destination_pixel[1] = palette[palette_index].g;
            destination_pixel[2] = palette[palette_index].b;
            destination_pixel[3] = cel.opacity_level;
        }
        print("\n");
    }
}

aseprite_read_string :: (allocator: *Allocator, aseprite_string: *void) -> string {
    string_length:   u16 = ~cast(*u16)aseprite_string;
    string_content: *u8  = xx (aseprite_string + 2);
    
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

