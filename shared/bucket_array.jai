Bucket_Array :: struct (T: Type) {
    INITIAL_BUCKET_COUNT: u64 : 8;
    BUCKET_SIZE : u64 : 64;
    BUCKET_FULL : u64 : 0;
    BUCKET_EMPTY: u64 : 0xffffffffffffffff;
    
    GENERATION_MASK:  u64 : 0xffffffff00000000;
    GENERATION_SHIFT: u64 : 32;

    Bucket :: struct {
        content:     []T  = ---; // Allocated to fit BUCKET_SIZE
        generations: []u8 = ---; // Allocated to fit BUCKET_SIZE
        free_mask:   u64  = BUCKET_EMPTY;
        used:        bool = false;
    }
    
    allocator: *Allocator;
    buckets: []Bucket;
    first_free_bucket_index: u64;
    alive_count: s64;
    slot_count: s64;
}

create_bucket_array :: (array: *Bucket_Array($T), allocator: *Allocator) {
    array.allocator = allocator;    
    array.buckets   = allocate_array(array.allocator, array.Bucket, array.INITIAL_BUCKET_COUNT);
    for i := 0; i < array.buckets.count; ++i array.buckets[i] = array.Bucket.{};
    array.first_free_bucket_index = 0;
    array.alive_count = 0;
    array.slot_count  = 0;
}

destroy_bucket_array :: (array: *Bucket_Array($T)) {
    for i := 0; i < array.buckets.count; ++i {
        if array.buckets[i].used {
            deallocate_array(array.allocator, *array.buckets[i].generations);
            deallocate_array(array.allocator, *array.buckets[i].content);
        }
    }

    deallocate_array(array.allocator, *array.buckets);
    array.first_free_bucket_index = MAX_U64;
    array.alive_count = 0;
    array.slot_count  = 0;
}

push_bucket_array :: (array: *Bucket_Array($T)) -> *T, u64 {
    if array.first_free_bucket_index == MAX_U64 {
        array.first_free_bucket_index = array.buckets.count;
        array.buckets = reallocate_array(array.allocator, array.buckets, array.buckets.count * 2);
        for i := array.first_free_bucket_index; i < array.buckets.count; ++i array.buckets[i] = array.Bucket.{};
    }

    bucket_index := array.first_free_bucket_index;
    bucket := *array.buckets[bucket_index];

    if !bucket.used {
        bucket.used        = true;
        bucket.free_mask   = array.BUCKET_EMPTY;
        bucket.generations = allocate_array(array.allocator, u8, array.BUCKET_SIZE);
        bucket.content     = allocate_array(array.allocator, T, array.BUCKET_SIZE);

        slot_count = (bucket_index + 1) * array.BUCKET_SIZE;
    }

    assert(bucket.free_mask != array.BUCKET_FULL, "The pushed bucket is somehow full!");
    index_in_bucket := transmute(u64) lowest_bit_set(bucket.free_mask);

    pointer := *bucket.content[index_in_bucket];
    ~pointer = .{ };
    
    ++bucket.generations[index_in_bucket];
    bucket.free_mask &= ^(1 << index_in_bucket);
    
    if bucket.free_mask == array.BUCKET_FULL {
        array.first_free_bucket_index = find_next_free_bucket(array, array.first_free_bucket_index + 1);
    }
    
    index_in_array := bucket_index * array.BUCKET_SIZE + index_in_bucket;
    assert(index_in_array < array.GENERATION_MASK, "The bucket array grew too large, cannot use generational indices anymore!");
    pid := index_in_array | (bucket.generations[index_in_bucket] << array.GENERATION_SHIFT);

    ++array.count;
    
    return pointer, pid;
}

query_bucket_array :: (array: *Bucket_Array($T), pid: u64) -> *T, bool {
    bucket_index, index_in_bucket, occupied := resolve_pid(array, pid);
    bucket := array.buckets[bucket_index];
    return *bucket.content[index_in_bucket], occupied;
}

index_bucket_array :: (array: *Bucket_Array($T), index: u64) -> *T, bool {
    bucket_index    := index / array.BUCKET_SIZE;
    index_in_bucket := index % array.BUCKET_SIZE;
    bucket := array.buckets[bucket_index];
    return *bucket.content[index_in_bucket], !(bucket.free_mask & (1 << index_in_bucket));
}

bucket_array_contains :: (array: *Bucket_Array($T), pid: u64) -> bool {
    bucket_index, index_in_bucket, occupied := resolve_pid(array, pid);
    return occupied;
}

remove_iterator_from_bucket_array :: (array: *Bucket_Array($T), it: *Bucket_Array_Iterator(T)) {
    bucket := *array.buckets[it.__bucket_index];
    bucket.free_mask |= 1 << it.__index_in_bucket;
    maybe_shrink_bucket_array(array, it.__bucket_index);
    --array.count;
}

remove_pid_from_bucket_array :: (array: *Bucket_Array($T), pid: u64) {
    bucket_index, index_in_bucket, occupied := resolve_pid(array, pid);

    assert(occupied == true, "Tried to remove a non-existent pid from a bucket array.");

    bucket := *array.buckets[bucket_index];
    bucket.free_mask |= 1 << index_in_bucket;
    maybe_shrink_bucket_array(array, bucket_index);
    --array.count;
}



#file_scope

find_next_free_bucket :: (array: *Bucket_Array($T), index: u64) -> u64 {
    while index < array.buckets.count && array.buckets[index].free_mask == array.BUCKET_FULL {
        ++index;
    }
    return ifx index < array.buckets.count then index else MAX_U64;
}

resolve_pid :: (array: *Bucket_Array($T), pid: u64) -> u64, u64, bool {
    generation := (pid & array.GENERATION_MASK) >> array.GENERATION_SHIFT;
    slot_index := pid & (^array.GENERATION_MASK);
    
    bucket_index    := slot_index / array.BUCKET_SIZE;
    index_in_bucket := slot_index % array.BUCKET_SIZE;
    if bucket_index < 0 || bucket_index >= array.buckets.count return 0, 0, false;

    return bucket_index, index_in_bucket, !(bucket.free_mask & (1 << index_in_bucket)) && bucket.generations[index_in_bucket] == generation;
}

maybe_shrink_bucket_array :: (array: *Bucket_Array($T), bucket_index: s64) {
    bucket := *array.buckets[bucket_index];

    if bucket.free_mask == Bucket_Array(T).BUCKET_EMPTY {
        array.first_free_bucket_index = min(array.first_free_bucket_index, bucket_index);

        first_shrink_index := array.buckets.count / 2;
        makes_sense_to_shrink := first_shrink_index > array.INITIAL_BUCKET_COUNT;

        for i := first_shrink_index; i < array.buckets.count; ++i {
            makes_sense_to_shrink &= array.buckets[i].free_mask == array.BUCKET_EMPTY;
        }

        if makes_sense_to_shrink {
            for i := first_shrink_index; i < array.buckets.count; ++i {
                array.buckets[i].used = false;
                deallocate_array(array.allocator, *array.buckets[i].generations);
                deallocate_array(array.allocator, *array.buckets[i].content);
            }
            
            array.buckets = reallocate_array(array.allocator, array.buckets, first_shrink_index);
            slot_count = array.buckets.count * array.BUCKET_SIZE;
        }
    }
}
