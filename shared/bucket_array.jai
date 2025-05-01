Bucket_Array :: struct (T: Type) {
    INACTIVE_INDIRECTION: Indirection : -1;
    INACTIVE_PID: Pid : -1;

    BUCKET_SIZE          :: 64;
    MIN_INDIRECTION_SIZE :: 8;
    MIN_BUCKET_COUNT     :: 1;

    INDEX_BITS      :: 32;
    INDEX_MASK      :: 0xffffffffffffffff >> (size_of(Pid) * 8 - INDEX_BITS);
    GENERATION_BITS :: size_of(Pid) * 8 - INDEX_BITS;
    GENERATION_MASK :: 0xffffffffffffffff << (size_of(Pid) * 8 - GENERATION_BITS);
    
    Bucket :: struct {
        entries: [BUCKET_SIZE]T = ---;
        pid: [BUCKET_SIZE]Pid = .[ INACTIVE_PID ];
    }
    
    allocator: *Allocator;
    indirection: []Indirection;
    buckets: []*Bucket;
    generation: s64;
    count: s64;
}

create_bucket_array :: (array: *Bucket_Array($T), allocator: *Allocator) {
    array.allocator   = allocator;
    array.indirection = allocate_array(array.allocator, Indirection, array.MIN_INDIRECTION_SIZE);
    array.buckets     = allocate_array(array.allocator, *array.Bucket, array.MIN_BUCKET_COUNT);
    for i := 0; i < array.indirection.count; ++i array.indirection[i] = array.INACTIVE_INDIRECTION;
    for i := 0; i < array.buckets.count; ++i array.buckets[i] = null;
    array.generation  = 0;
    array.count       = 0;
}

destroy_bucket_array :: (array: *Bucket_Array($T)) {
    deallocate_array(array.allocator, *array.indirection);

    for i := 0; i < array.buckets.count; ++i {
        deallocate(array.allocator, array.buckets[i]);
    }

    deallocate_array(array.allocator, *array.indirection);
}

push_bucket_array :: (array: *Bucket_Array($T)) -> Pid, *T {
    //
    // Find the lowest available pid
    //
    pid: Pid = array.INACTIVE_PID;

    {
        for i := 0; i < array.indirection.count; ++i {
            if array.indirection[i] == array.INACTIVE_INDIRECTION {
                pid = make_pid(array, i);
                break;
            }
        }

        if pid == array.INACTIVE_PID {
            previous_count := array.indirection.count;
            array.indirection = reallocate_array(array.allocator, array.indirection, array.indirection.count * 2);
            for i := previous_count; i < array.indirection.count; ++i {
                array.indirection[i] = array.INACTIVE_INDIRECTION;
            }

            pid = make_pid(array, previous_count);
        }

        array.indirection[pid & array.INDEX_MASK] = array.count;
    }

    //
    // Allocate an entry in the buckets
    //
    entry: *T = null;
    
    {
        bucket_index, index_in_bucket := array.count / array.BUCKET_SIZE, array.count % array.BUCKET_SIZE;

        if bucket_index >= array.buckets.count {
            previous_count := array.buckets.count;
            array.buckets = reallocate_array(array.allocator, array.buckets, array.buckets.count * 2);
            for i := previous_count; i < array.buckets.count; ++i {
                array.buckets[i] = null;
            }
        }

        if array.buckets[bucket_index] == null {
            array.buckets[bucket_index] = new(array.allocator, array.Bucket);
        }

        entry = *array.buckets[bucket_index].entries[index_in_bucket];
        array.buckets[bucket_index].pid[index_in_bucket] = pid;

        ++array.count;
    }

    return pid, entry;
}

push_bucket_array_with_pid :: (array: *Bucket_Array($T), pid: Pid) -> *T {
    {
        new_indirection_size := array.indirection.count;
        while (pid & array.INDEX_MASK) >= new_indirection_size {
            new_indirection_size *= 2;
        }

        if new_indirection_size > array.indirection.count {
            previous_count := array.indirection.count;
            array.indirection = reallocate_array(array.allocator, array.indirection, array.indirection.count * 2);
            for i := previous_count; i < array.indirection.count; ++i {
                array.indirection[i] = array.INACTIVE_INDIRECTION;
            }
        }
    }
        
    entry: *T = null;
    
    bucket_index, index_in_bucket := array.count / array.BUCKET_SIZE, array.count % array.BUCKET_SIZE;

    if bucket_index >= array.buckets.count {
        array.buckets = reallocate_array(array.allocator, array.buckets, array.buckets.count * 2);
    }

    if array.buckets[bucket_index] == null {
        array.buckets[bucket_index] = new(array.allocator, array.Bucket);
    }

    entry = *array.buckets[bucket_index].entries[index_in_bucket];
    array.buckets[bucket_index].pid[index_in_bucket] = pid;
    array.indirection[pid & array.INDEX_MASK] = array.count;

    ++array.count;    

    return entry;
}

remove_index_from_bucket_array :: (array: *Bucket_Array($T), to_remove_index: Indirection) {
    assert(to_remove_index >= 0 && to_remove_index < array.count, "Bucket Array Index is out of bounds.");

    //
    // Clear out the occupation of the entry to-be-removed
    //
    to_remove_bucket_index    := to_remove_index / array.BUCKET_SIZE;
    to_remove_index_in_bucket := to_remove_index % array.BUCKET_SIZE;

    to_remove_pid := array.buckets[to_remove_bucket_index].pid[to_remove_index_in_bucket];
    array.indirection[to_remove_pid & array.INDEX_MASK] = array.INACTIVE_PID;
    array.buckets[to_remove_bucket_index].pid[to_remove_index_in_bucket] = array.INACTIVE_PID;

    //
    // Keep the array continuous by putting the last used entry into the now-free position
    //
    if to_remove_index + 1 < array.count {
        last_bucket_index    := (array.count - 1) / array.BUCKET_SIZE;
        last_index_in_bucket := (array.count - 1) % array.BUCKET_SIZE;

        last_pid := array.buckets[last_bucket_index].pid[last_index_in_bucket];
        
        last_pointer := *array.buckets[last_bucket_index].entries[last_index_in_bucket];
        to_remove_pointer := *array.buckets[to_remove_bucket_index].entries[to_remove_index_in_bucket];

        ~to_remove_pointer = ~last_pointer;
        array.indirection[last_pid & array.INDEX_MASK] = to_remove_index;
        array.buckets[last_bucket_index].pid[last_index_in_bucket] = array.INACTIVE_PID;
        array.buckets[to_remove_bucket_index].pid[to_remove_index_in_bucket] = last_pid;
    }

    --array.count;

    //
    // Shrink the array if possible
    //
    required_buckets := max(cast(s64) ceil(cast(f64) array.count / cast(f64) array.BUCKET_SIZE), array.MIN_BUCKET_COUNT);
    if required_buckets <= array.buckets.count / 2 {
        array.buckets = reallocate_array(array.allocator, array.buckets, array.buckets.count / 2);
    }

    highest_used_pid := array.indirection.count - 1;
    while highest_used_pid > array.MIN_INDIRECTION_SIZE && array.indirection[highest_used_pid] == array.INACTIVE_PID {
        --highest_used_pid;
    }
    
    if highest_used_pid < array.indirection.count / 2 {
        array.indirection = reallocate_array(array.allocator, array.indirection, array.indirection.count / 2);
    }
}

remove_pid_from_bucket_array :: (array: *Bucket_Array($T), pid: Pid) {
    assert(bucket_array_contains(array, pid), "Trying to remove non-existent pid from bucket array.");
    return remove_index_from_bucket_array(array, array.indirection[pid & array.INDEX_MASK]);
}

index_bucket_array :: (array: *Bucket_Array($T), index: Indirection) -> *T {
    assert(index < array.count, "Trying to get out-of-bounds index from bucket array.");
    bucket_index    := index / array.BUCKET_SIZE;
    index_in_bucket := index % array.BUCKET_SIZE;
    return *array.buckets[bucket_index].entries[index_in_bucket];
}

query_bucket_array :: (array: *Bucket_Array($T), pid: Pid) -> *T {
    assert(bucket_array_contains(array, pid), "Trying to query non-existent pid from bucket array.");
    return index_bucket_array(array, array.indirection[pid & array.INDEX_MASK]);
}

bucket_array_contains :: (array: *Bucket_Array($T), pid: Pid) -> bool {
    if pid & array.INDEX_MASK >= array.indirection.count return false;
    if array.indirection[pid & array.INDEX_MASK] == array.INACTIVE_INDIRECTION return false;

    index := array.indirection[pid & array.INDEX_MASK];
    
    bucket_index    := index / array.BUCKET_SIZE;
    index_in_bucket := index % array.BUCKET_SIZE;

    return array.buckets[bucket_index].pid[index_in_bucket] == pid; // Check the generation
}



#file_scope

Indirection :: u64;

make_pid :: (array: *Bucket_Array($T), index_into_indirection: s64) -> Pid {
#if array.GENERATION_BITS > 0 {
    pid: Pid = index_into_indirection | ((array.generation << array.INDEX_BITS) & array.GENERATION_MASK);
    ++array.generation;
    return pid;
} #else {
    return index_into_indirection;
}
}
