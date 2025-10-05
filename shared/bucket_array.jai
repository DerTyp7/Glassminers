Bucket_Array_Slot :: u64;

Bucket_Array :: struct (T: Type) {
    BUCKET_SIZE : u64 : 64;
    BUCKET_FULL : u64 : 0;
    BUCKET_EMPTY: u64 : 0xffffffffffffffff;
    
    Bucket :: struct {
        content:   [64]T = ---;
        free_mask: u64   = BUCKET_EMPTY;
        used:      bool  = false;

        #assert(size_of(free_mask) * 8 >= BUCKET_SIZE);
    }
    
    allocator: *Allocator;
    buckets: []*Bucket;
    first_free_bucket_index: u64;
    alive_count: s64;
    slot_count: s64;
}

create_bucket_array :: (array: *Bucket_Array($T), allocator: *Allocator) {
    array.allocator = allocator;
    array.buckets = .[];
    array.first_free_bucket_index = MAX_U64;
    array.alive_count = 0;
    array.slot_count  = 0;
}

destroy_bucket_array :: (array: *Bucket_Array($T)) {
    deallocate_slice(array.allocator, *array.buckets);
    array.first_free_bucket_index = MAX_U64;
    array.alive_count = 0;
    array.slot_count  = 0;
}

push_bucket_array :: (array: *Bucket_Array($T)) -> *T {
    if array.first_free_bucket_index == MAX_U64 {
        grow_bucket_array(array, array.buckets.count + 1);
    }

    bucket_index := array.first_free_bucket_index;
    bucket := array.buckets[bucket_index];
    index_in_bucket := transmute(u64) lowest_bit_set(bucket.free_mask);

    pointer := *bucket.content[index_in_bucket];
    ~pointer = .{ };
    
    bucket.free_mask &= ^(1 << index_in_bucket);
    
    if bucket.free_mask == array.BUCKET_FULL {
        array.first_free_bucket_index = find_next_free_bucket(array, array.first_free_bucket_index + 1);
    }

    index_in_array := bucket_index * array.BUCKET_SIZE + index_in_bucket;
    array.slot_count = max(array.slot_count, index_in_array + 1);
    ++array.alive_count;
    
    return pointer;
}

index_bucket_array :: (array: *Bucket_Array($T), slot: Bucket_Array_Slot) -> *T, bool {
    bucket_index    := slot / array.BUCKET_SIZE;
    index_in_bucket := slot % array.BUCKET_SIZE;
    bucket := array.buckets[bucket_index];
    return *bucket.content[index_in_bucket], !(bucket.free_mask & (1 << index_in_bucket));
}

bucket_array_slot_occupied :: (array: *Bucket_Array($T), slot: Bucket_Array_Slot) -> bool {
    bucket_index    := slot / array.BUCKET_SIZE;
    index_in_bucket := slot % array.BUCKET_SIZE;
    if bucket_index >= array.buckets.count return false;

    bucket := array.buckets[bucket_index];
    return !(bucket.free_mask & (1 << index_in_bucket));
}

remove_index_from_bucket_array :: (array: *Bucket_Array($T), slot: Bucket_Array_Slot) {
    assert(bucket_array_slot_occupied(array, slot), "Attempted to remove a slot from the bucket array that was already free.");
    bucket_index    := slot / array.BUCKET_SIZE;
    index_in_bucket := slot % array.BUCKET_SIZE;
    bucket := array.buckets[bucket_index];
    bucket.free_mask |= 1 << index_in_bucket;
    --array.alive_count;
    maybe_shrink_bucket_array(array, bucket_index);
}



#file_scope

find_next_free_bucket :: (array: *Bucket_Array($T), index: u64) -> u64 {
    while index < array.buckets.count && array.buckets[index].free_mask == array.BUCKET_FULL {
        ++index;
    }
    return ifx index < array.buckets.count then index else MAX_U64;
}

grow_bucket_array :: (array: *Bucket_Array($T), reserved_bucket_count: s64) {
    previous_bucket_count := array.buckets.count;
    new_bucket_count      := ifx array.buckets.count > 0 then array.buckets.count * 2 else 1;

    while new_bucket_count < reserved_bucket_count new_bucket_count *= 2;
    
    array.buckets = reallocate_slice(array.allocator, array.buckets, new_bucket_count);
    for i := previous_bucket_count; i < array.buckets.count; ++i {
        array.buckets[i] = new(array.allocator, array.Bucket);
    }

    array.first_free_bucket_index = min(array.first_free_bucket_index, previous_bucket_count);
}

maybe_shrink_bucket_array :: (array: *Bucket_Array($T), bucket_index: u64) {
    bucket := array.buckets[bucket_index];

    if bucket.free_mask == Bucket_Array(T).BUCKET_EMPTY {
        first_shrink_index := array.buckets.count / 2;
        makes_sense_to_shrink := true;

        for i := first_shrink_index; i < array.buckets.count; ++i {
            makes_sense_to_shrink &= array.buckets[i].free_mask == array.BUCKET_EMPTY;
        }

        if makes_sense_to_shrink {
            for i := first_shrink_index; i < array.buckets.count; ++i {
                deallocate(array.allocator, array.buckets[i]);
            }

            array.buckets = reallocate_slice(array.allocator, array.buckets, first_shrink_index);
            array.slot_count = array.buckets.count * array.BUCKET_SIZE; // @Speed: This slot count can probably be set to something lower...
        }

        array.first_free_bucket_index = find_next_free_bucket(array, 0);
    }
}
