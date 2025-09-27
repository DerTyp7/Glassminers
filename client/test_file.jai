Test_Struct :: struct { 
    field_a: u16;
    field_b: u16;
    field_c: Custom_Type;
    
    Custom_Type :: struct {
        field_c: u16;
    }
}

test_function :: (allocator: *Allocator) {
    // Das wollte ich machen
    //array := allocate_array(allocator, Test_Struct.Custom_Type, 5);
    
    // Ich habe aber   Test_Struct::Custom_Type  eingegeben, und das gibt probleme:
    array := allocate_array(allocator, Test_Struct::Custom_Type, 5);
}
