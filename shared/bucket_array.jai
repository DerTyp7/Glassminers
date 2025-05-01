Bucket_Array :: struct (T: Type) {
    INITIAL_BUCKET_COUNT: u64 : 8;
    BUCKET_SIZE : u64 : 64;
    BUCKET_FULL : u64 : 0;
    BUCKET_EMPTY: u64 : 0xffffffffffffffff;
    
    GENERATION_SHIFT: u64 : 32;
    GENERATION_MASK:  u64 : 0xffffffffffffffff << GENERATION_SHIFT;
    INDEX_MASK:       u64 : 0xffffffffffffffff & ^GENERATION_MASK;
    
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

push_bucket_array :: (array: *Bucket_Array($T)) -> Pid, *T {
    if array.first_free_bucket_index == MAX_U64 {
        grow_bucket_array(array, 0);
    }

    bucket_index := array.first_free_bucket_index;
    bucket := maybe_initialize_bucket(array, bucket_index);
    
    assert(bucket.free_mask != array.BUCKET_FULL, "The pushed bucket is somehow full!");
    index_in_bucket := transmute(u64) lowest_bit_set(bucket.free_mask);

    pointer := *bucket.content[index_in_bucket];
    ~pointer = .{ };
    
    bucket.free_mask &= ^(1 << index_in_bucket);
    ++bucket.generations[index_in_bucket];
    
    if bucket.free_mask == array.BUCKET_FULL {
        array.first_free_bucket_index = find_next_free_bucket(array, array.first_free_bucket_index + 1);
    }

    ++array.alive_count;
    
    index_in_array := bucket_index * array.BUCKET_SIZE + index_in_bucket;
    pid := index_in_array | (bucket.generations[index_in_bucket] << array.GENERATION_SHIFT);
    
    return pid, pointer;
}

push_bucket_array_with_pid :: (array: *Bucket_Array($T), pid: Pid) -> *T {
    assert(!bucket_array_contains(array, pid), "Tried to push an existing pid into the bucket array.");

    index_in_array := pid & array.INDEX_MASK;
    bucket_index    := index_in_array / array.BUCKET_SIZE;
    index_in_bucket := index_in_array % array.BUCKET_SIZE;

    if bucket_index >= array.buckets.count {
        grow_bucket_array(array, bucket_index);
    }

    bucket := maybe_initialize_bucket(array, bucket_index);
    
    assert(!!(bucket.free_mask & (1 << index_in_bucket)), "The index in the bucket is already taken while trying to push a pid into the bucket array.");

    pointer := *bucket.content[index_in_bucket];
    ~pointer = .{ };

    bucket.free_mask &= ^(1 << index_in_bucket);
    bucket.generations[index_in_bucket] = (pid & array.GENERATION_MASK) >> array.GENERATION_SHIFT;
    
    if bucket.free_mask == array.BUCKET_FULL {
        array.first_free_bucket_index = find_next_free_bucket(array, array.first_free_bucket_index + 1);
    }

    ++array.alive_count;
    
    return pointer;
}

query_bucket_array :: (array: *Bucket_Array($T), pid: Pid) -> *T, bool {
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

bucket_array_contains :: (array: *Bucket_Array($T), pid: Pid) -> bool {
    bucket_index, index_in_bucket, occupied := resolve_pid(array, pid);
    return occupied;
}

remove_index_from_bucket_array :: (array: *Bucket_Array($T), slot_index: u64) {
    bucket_index    := slot_index / array.BUCKET_SIZE;
    index_in_bucket := slot_index % array.BUCKET_SIZE;
    bucket := *array.buckets[bucket_index];
    bucket.free_mask |= 1 << index_in_bucket;
    maybe_shrink_bucket_array(array, bucket_index);
    --array.alive_count;
}

remove_pid_from_bucket_array :: (array: *Bucket_Array($T), pid: Pid) {
    bucket_index, index_in_bucket, occupied := resolve_pid(array, pid);

    assert(occupied == true, "Tried to remove a non-existent pid from a bucket array.");

    bucket := *array.buckets[bucket_index];
    bucket.free_mask |= 1 << index_in_bucket;
    maybe_shrink_bucket_array(array, bucket_index);
    --array.alive_count;
}



#file_scope

find_next_free_bucket :: (array: *Bucket_Array($T), index: u64) -> u64 {
    while index < array.buckets.count && array.buckets[index].free_mask == array.BUCKET_FULL {
        ++index;
    }
    return ifx index < array.buckets.count then index else MAX_U64;
}

resolve_pid :: (array: *Bucket_Array($T), pid: Pid) -> u64, u64, bool {
    generation := (pid & array.GENERATION_MASK) >> array.GENERATION_SHIFT;
    slot_index := pid & array.INDEX_MASK;
    
    bucket_index    := slot_index / array.BUCKET_SIZE;
    index_in_bucket := slot_index % array.BUCKET_SIZE;
    if bucket_index < 0 || bucket_index >= array.buckets.count return 0, 0, false;

    bucket := *array.buckets[bucket_index];
    return bucket_index, index_in_bucket, !(bucket.free_mask & (1 << index_in_bucket)) && bucket.generations[index_in_bucket] == generation;
}

maybe_initialize_bucket :: (array: *Bucket_Array($T), bucket_index: u64) -> *array.Bucket {
    bucket := *array.buckets[bucket_index];

    if !bucket.used {
        bucket.used        = true;
        bucket.free_mask   = array.BUCKET_EMPTY;
        bucket.generations = allocate_array(array.allocator, u8, array.BUCKET_SIZE);
        bucket.content     = allocate_array(array.allocator, T, array.BUCKET_SIZE);
        array.slot_count   = max(array.slot_count, (bucket_index + 1) * array.BUCKET_SIZE);
    }

    return bucket;
}

grow_bucket_array :: (array: *Bucket_Array($T), reserved_bucket_count: s64) {
    previous_bucket_count := array.buckets.count;
    new_bucket_count := array.buckets.count * 2;

    while new_bucket_count < reserved_bucket_count new_bucket_count *= 2;
    
    array.buckets = reallocate_array(array.allocator, array.buckets, new_bucket_count);
    for i := previous_bucket_count; i < array.buckets.count; ++i array.buckets[i] = array.Bucket.{};

    if array.first_free_bucket_index == MAX_U64 then array.first_free_bucket_index = array.buckets.count;
}

maybe_shrink_bucket_array :: (array: *Bucket_Array($T), bucket_index: u64) {
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
            array.slot_count = array.buckets.count * array.BUCKET_SIZE;
        }
    }
}
