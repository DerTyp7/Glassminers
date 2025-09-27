
// TODO(Felix): This should probably be a compiler module or something

// File documentation
// https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md

// All aseprite bytes are stored in little endian.

// -------------------------- Types ---------------------------- //

Aseprite_Fixed_Type :: u32; // 32-bit fixed floating point (16.16). -_-
// STRING type: { string_length: u16, [string_length]u8 }

// These structs are representing the headers in memory,
// so don't shuffle the members around!

Aseprite_File_Header :: struct {
    file_size:    u32;
    magic_number: u16; // Should be 0xA5E0
    frames:       u16;
    
    width_in_pixels:  u16;
    height_in_pixels: u16;
    color_depth:      u16; // Bits per pixel
    flags:            u32;
    speed:            u16; // milliseconds between frames
    
    __reserved_0: u16; // these two
    __reserved_1: u16; // should be 0
    
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

Aseprite_Frame_Header :: struct {
    bytes_in_this_frame: u32;
    magic_number:        u16; // Should be 0xF1FA
    
    old_field_number_of_chunks: u16;
    frame_duration_in_ms:       u16; // milliseconds
    __reserved_0: [2]u8;
    new_field_number_of_chunks: u16;
}

Aseprite_Chunk_Header :: struct {
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
//  - Old_Palette_1
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

Aseprite_Chunk_Color_Profile :: struct {
    type:  Aseprite_Color_Profile_Type;
    flags: u16;
    gamma: Aseprite_Fixed_Type;
    
    __reserved_0: [8]u8;
    // If type == .Embedded_ICC, there is more data here
}



// Palette ("new")

Aseprite_Chunk_Pallete_Entry_Flags :: enum(u16) {
    Has_Name :: 1;
}

Aseprite_Chunk_Palette_Entry :: struct {
    flags: Aseprite_Chunk_Pallete_Entry_Flags;
    
    red:   u8;
    green: u8;
    blue:  u8;
    alpha: u8;
    
    // If type & .HasName: ASEPRITE_STRING name here
}

Aseprite_Chunk_Palette :: struct {
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

Aseprite_Chunk_Layer :: struct {
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

Aseprite_Chunk_Cel :: struct {
    layer_index:   u16;
    x_position:    s16;
    y_position:    s16;
    opacity_level: u8;
    cel_type: Aseprite_Chunk_Cel_Type;
    z_index: s16;
    
    __reserved_0: [5]u8;
    // TODO(Felix): There is a bunch of stuff following depending on the cell type
}



ASEPRITE_MAGIC_NUMBER_FILE_HEADER  :: 0xA5E0;
ASEPRITE_MAGIC_NUMBER_FRAME_HEADER :: 0xF1FA;


// TODO(Felix): This is temporary code to see which chunks 
// we actually need to implement for parsing Glassminers Aseprite files.
// Ideally we'd implement everything, but I'll implement stuff
// as needed.

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

#run {
    // TODO(Felix): find and parse all files
    //set_working_directory_to_executable_path();
    
    SIMPLE_FILE_PATH :: "/home/void/Software/Victor/Glassminers/aseprite/inanimates/bedrock.aseprite";
    EXAMPLE_FILE_PATH :: SIMPLE_FILE_PATH;
    
    file_content, success := read_entire_file(Default_Allocator, EXAMPLE_FILE_PATH);
    assert(success, "File could not be loaded!");

    
    
    // Begin of parsing code
    file_header: *Aseprite_File_Header = xx file_content.data;
    assert(file_header.magic_number == ASEPRITE_MAGIC_NUMBER_FILE_HEADER, "Unexpected magic number for aseprite file header!");
    print("File Header:  %\n", ~file_header);
    
    current_byte_location := size_of(~file_header);
    
    frame_header: *Aseprite_Frame_Header = xx (file_content.data + current_byte_location);
    assert(frame_header.magic_number == ASEPRITE_MAGIC_NUMBER_FRAME_HEADER, "Unexpected magic number for aseprite file header!");
    print("Frame Header: %\n", ~frame_header);
    
    // Iterate over chunks
    print("Iterating over chunks:\n");
    current_byte_location += size_of(~frame_header);
    while current_byte_location < file_content.count {
        chunk_header: *Aseprite_Chunk_Header = xx (file_content.data + current_byte_location);
        print("  %: ", aseprite_chunk_type_to_name(chunk_header.chunk_type));
        
        OFFSET_FROM_CHUNK_HEADER_TO_CHUNK_CONTENT :: size_of(Aseprite_Chunk_Header);
        chunk_data: *void = (file_content.data + current_byte_location + OFFSET_FROM_CHUNK_HEADER_TO_CHUNK_CONTENT);
        
        if chunk_header.chunk_type == {
            case .Palette;
                palette: *Aseprite_Chunk_Palette = xx chunk_data;
                print("%", ~palette);
                break;
                
            case .Layer;
                layer: *Aseprite_Chunk_Layer = xx chunk_data;
                print("%", ~layer);
                break;
                
            case .Cel;
                cel: *Aseprite_Chunk_Cel = xx chunk_data;
                print("%", ~cel);
                break;
            
            case .Color_Profile;
                color_profile: *Aseprite_Chunk_Color_Profile = xx chunk_data;
                print("%", ~color_profile);
                break;
            
            case;
                print("  Chunk type % not implemented.\n", format_int(chunk_header.chunk_type, .Hexadecimal, false, true, 4));
        }
        //print("  Type: %\n", format_int(chunk_header.chunk_type, .Hexadecimal, false, true, 4));
        
        print("\n");
        current_byte_location += chunk_header.chunk_size;
    }
}



// DEBUG Code below 

ASEPRITE_FILE_HEADER_EXPECTED_SIZE  :: 128;
ASEPRITE_FRAME_HEADER_EXPECTED_SIZE :: 16;


// TODO(Felix): This is debug code, remove this
#run {
    assert(size_of(Aseprite_File_Header)  == ASEPRITE_FILE_HEADER_EXPECTED_SIZE, "Unexpected aseprite file header struct size");
    assert(size_of(Aseprite_Frame_Header) == ASEPRITE_FRAME_HEADER_EXPECTED_SIZE, "Unexpected aseprite frame header struct size");
}

#run {
    ACTUAL_HEADER_SIZE :: size_of(Aseprite_File_Header);
    EXPECTED_HEADER_SIZE :: 128;
    if ACTUAL_HEADER_SIZE != EXPECTED_HEADER_SIZE {
        print("Big problem: % vs expected %\n", ACTUAL_HEADER_SIZE, EXPECTED_HEADER_SIZE);
    }
    assert(ACTUAL_HEADER_SIZE == 128, "Unexpected aseprite file header size");
}
