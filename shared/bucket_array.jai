Bucket_Array :: struct (T: Type) {
    BUCKET_SIZE          :: 64;
    MIN_INDIRECTION_SIZE :: 8;
    MIN_BUCKET_COUNT     :: 1;
    
    Bucket :: struct {
        entries: [BUCKET_SIZE]T = ---;
        pid: [BUCKET_SIZE]Pid = .[ INACTIVE_PID ];
    }
    
    allocator: *Allocator;
    indirection: []Indirection;
    buckets: []*Bucket;
    count: s64;
}

create_bucket_array :: (array: *Bucket_Array($T), allocator: *Allocator) {
    array.allocator   = allocator;
    array.indirection = allocate_array(array.allocator, Indirection, array.MIN_INDIRECTION_SIZE);
    array.buckets     = allocate_array(array.allocator, *array.Bucket, array.MIN_BUCKET_COUNT);
    for i := 0; i < array.buckets.count; ++i array.buckets[i] = null;
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
    pid: Pid = INACTIVE_PID;

    {
        for i := 0; i < array.indirection.count; ++i {
            if array.indirection[i] == INACTIVE_INDIRECTION {
                pid = i;
                break;
            }
        }

        if pid == INACTIVE_PID {
            previous_count := array.indirection.count;
            array.indirection = reallocate_array(array.allocator, array.indirection, array.indirection.count * 2);
            for i := previous_count; i < array.indirection.count; ++i {
                array.indirection[i] = INACTIVE_INDIRECTION;
            }

            pid = previous_count;
        }

        array.indirection[pid] = array.count;
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
        while pid >= new_indirection_size {
            new_indirection_size *= 2;
        }

        if new_indirection_size > array.indirections.count {
            previous_count := array.indirection.count;
            array.indirection = reallocate_array(array.allocator, Pid, array.indirection.count * 2);
            for i := previous_count; i < array.indirection.count; ++i {
                array.indirection[i] = INACTIVE_INDIRECTION;
            }
        }
    }
        
    entry: *T = null;
    
    bucket_index, index_in_bucket := count / array.BUCKET_SIZE, count % array.BUCKET_SIZE;

    if bucket_index >= array.buckets.count {
        array.buckets = reallocate_array(array.allocator, *Bucket, array.buckets.count * 2);
    }

    if array.buckets[bucket_index] == null {
        array.buckets[bucket_index] = new(array.allocator, Bucket);
    }

    entry = *array.buckets[bucket_index].entries[index_in_bucket];
    array.buckets[bucket_index].id[index_in_bucket] = pid;

    ++count;    

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
    array.indirection[to_remove_pid] = INACTIVE_PID;
    array.buckets[to_remove_bucket_index].pid[to_remove_index_in_bucket] = INACTIVE_PID;

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
        array.indirection[last_pid] = to_remove_index;
        array.buckets[last_bucket_index].pid[last_index_in_bucket] = INACTIVE_PID;
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
    while highest_used_pid > array.MIN_INDIRECTION_SIZE && array.indirection[highest_used_pid] == INACTIVE_PID {
        --highest_used_pid;
    }
    
    if highest_used_pid <= array.indirection.count / 2 {
        array.indirection = reallocate_array(array.allocator, array.indirection, array.indirection.count / 2);
    }
}

remove_pid_from_bucket_array :: (array: *Bucket_Array($T), pid: Pid) {
    assert(pid >= 0 && pid < array.indirection.count, "Bucket Array Pid is out of bounds.");
    assert(array.indirection[pid] != INACTIVE_INDIRECTION, "Bucket Array Pid is unused.");
    return remove_index_from_bucket_array(array, array.indirection[pid]);
}

index_bucket_array :: (array: *Bucket_Array($T), index: Indirection) -> *T {
    assert(index >= 0 && index < array.count, "Bucket Array Index is out of bounds.");
    bucket_index := index / array.BUCKET_SIZE;
    index_in_bucket := index % array.BUCKET_SIZE;
    return *array.buckets[bucket_index].entries[index_in_bucket];
}

query_bucket_array :: (array: *Bucket_Array($T), pid: Pid) -> *T {
    assert(pid >= 0 && pid < array.indirection.count, "Bucket Array Pid is out of bounds.");
    assert(array.indirection[pid] != INACTIVE_INDIRECTION, "Bucket Array Pid is unused.");
    return index_bucket_array(array, array.indirection[pid]);
}



test_bucket_array :: () {
    Thing :: struct {
        value: [8]u8;
    }
    
    array: Bucket_Array(Thing);

    create_bucket_array(*array, Default_Allocator);
    pids: [..]Pid;
    
    srand(cast(u32) os_get_hardware_time());
    
    for i := 0; i < 1_000_000; ++i {
        action := rand() % 2;

        if action == {
          case 0;
            pid, pointer := push_bucket_array(*array);
            index_bucket_array(*array, array.count - 1);
            query_bucket_array(*array, pid);
            array_add(*pids, pid);
            
          case 1;
            if pids.count == 0 break;
            index := rand() % pids.count;
            pid := array_get(*pids, index);
            remove_pid_from_bucket_array(*array, pid);
            array_remove_index(*pids, index);
        }
    }
    
    destroy_bucket_array(*array);

    print("Success!\n");
}



#file_scope

Indirection :: s64;

INACTIVE_INDIRECTION: Indirection = -1;
INACTIVE_PID: Pid = -1;
