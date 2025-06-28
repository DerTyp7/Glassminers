Sound_Pid :: u64;
INVALID_SOUND_PID: Sound_Pid : 0;

SOUNDS_INNER_RADIUS: f32 : 3;
SOUNDS_OUTER_RADIUS: f32 : 18;

Play_Sound_Flags :: enum bitfield {
    Default;
    Looping;
    Once_Per_Frame;
}

Sound_Index :: enum {
    Hud_Pickup_0;
    Hud_Placedown_0;
    Hud_Success_0;
    Hud_Failure_0;
    
    Receiver_Charging;
    Guy_Digging_0;
    Guy_Walk_0;
    Guy_Walk_1;
    Rock_Sliding_0;
    Guy_Death_0;
    Frog_Attack_0;
    Frog_Hurt_0;
    Frog_Death_0;
    Goblin_Attack_0;
    Goblin_Hurt_0;
    Goblin_Death_0;
    Slime_Hurt_0;
    Slime_Death_0;
    Slime_Scared_0;
    Slime_Walk_0;
}

SOUND_FILEPATH_MAP: [Sound_Index.Count]string : .[
    "hud-pickup-0.wav",
    "hud-placedown-0.wav",
    "hud-success-0.wav",
    "hud-failure-0.wav",

    "receiver-charging.wav",
    "guy-digging-0.wav",
    "guy-walk-0.wav",
    "guy-walk-1.wav",
    "rock-sliding-0.wav",
    "guy-death-0.wav",
    "frog-attack-0.wav",
    "frog-hurt-0.wav",
    "frog-death-0.wav",
    "goblin-attack-0.wav",
    "goblin-hurt-0.wav",
    "goblin-death-0.wav",
    "slime-hurt-0.wav",
    "slime-death-0.wav",
    "slime-scared-0.wav",
    "slime-walk-0.wav",
];

create_sound_data :: (client: *Client) -> bool {
#if BAKE_ASSETS {
    for i := 0; i < client.sounds.Capacity; ++i {
        client.sounds[i] = BAKED_SOUNDS[i];
    }
    return true;
} #else {
    create_file_watcher(*client.sound_watchdog, *client.engine_allocator);

    for i := 0; i < client.sounds.Capacity; ++i {
        filepath := print_into_allocator(*temp, "data/sounds/%", SOUND_FILEPATH_MAP[i]);
        add_file_to_watch(*client.sound_watchdog, filepath);

        status: Sound_File_Status = ---;
        client.sounds[i], status = create_sound_data_from_file(filepath);
        
        if status != .Success logprint(.Error, "Failed to load the sound '%': %.", filepath, status);
    }
    
    return true;
}
}

destroy_all_sounds :: (client: *Client) {
#if !BAKE_ASSETS {
    for i := 0; i < client.sounds.Capacity; ++i {
        destroy_sound_data(*client.sounds[i]);
    }
}
}

stop_all_sounds :: (client: *Client) {
    for i := 0; i < client.mixer.streams.count; ++i {
        client.mixer.streams[i].state = .Stopped;
    }
}

play_sound :: (client: *Client, sound_index: Sound_Index, flags: Play_Sound_Flags) -> Sound_Pid {
    if flags & .Once_Per_Frame && client.sounds_played_this_frame[sound_index] return INVALID_SOUND_PID;

    sound := *client.sounds[sound_index];
    
    stream := get_unused_sound_stream(*client.mixer);
    if !stream {
        logprint(.Warning, "Failed to play a sound because no stream was available!");
        return INVALID_SOUND_PID;
    }

    play_sound_on_stream(stream, sound, SOUND_CATEGORY_MAP[sound_index], flags & .Looping);
    client.sounds_played_this_frame[sound_index] = true;

    return (stream.play_counter << 48) | (stream & 0xffffffffffff);
}

play_sound_on_entity :: (client: *Client, sound_index: Sound_Index, entity: *Entity, flags: Play_Sound_Flags) -> Sound_Pid {
    sound_pid := play_sound(client, sound_index, flags);

    if sound_pid != INVALID_SOUND_PID {
        stream: *Sound_Stream = xx (sound_pid & 0xffffffffffff);
        spatialize_sound_stream(stream, xx entity.physical_position.x, xx entity.physical_position.y, 0, SOUNDS_INNER_RADIUS, SOUNDS_OUTER_RADIUS);
    }
        
    return sound_pid;
}

set_sound_playback_position :: (client: *Client, sound_pid: Sound_Pid, percentage: f32) {
    if !sound_active(client, sound_pid) return;

    stream: *Sound_Stream = xx (sound_pid & 0xffffffffffff);
    stream.frame_offset = cast(u64) (cast(f32) stream.sound_data.available_frames * percentage);
}

update_sound_players :: (client: *Client) {
    forward :: [3]f32.[ 0, 1, 0 ];
    up :: [3]f32.[ 0, 0, 1 ];
    right :: [3]f32.[ 1, 0, 0 ];
    inner_radius: f32 : 2;

    if client.current_state == .Ingame {
        for i := 0; i < client.local_player_count; ++i {
            entity := get_entity(client, client.local_players[i].guy_pid);
            update_sound_listener(*client.mixer, i,
                                  entity.visual_position.x, entity.visual_position.y, 0,
                                  forward[0], forward[1], forward[2],
                                  up[0], up[1], up[2],
                                  right[0], right[1], right[2],
                                  inner_radius);
        }
    } else {
        set_sound_listener_count(*client.mixer, 1);
    }
}

stop_sound :: (client: *Client, sound_pid_pointer: *Sound_Pid) {
    sound_pid := ~sound_pid_pointer;

    if sound_pid == INVALID_SOUND_PID return;
    
    stream: *Sound_Stream = xx (sound_pid & 0xffffffffffff);
    play_counter := sound_pid >> 48;

    if stream.play_counter == play_counter {
        stream.state = .Stopped;
    }

    ~sound_pid_pointer = INVALID_SOUND_PID;
}

sound_active :: (client: *Client, sound_pid: Sound_Pid) -> bool {
    if sound_pid == INVALID_SOUND_PID return false;
    stream: *Sound_Stream = xx (sound_pid & 0xffffffffffff);
    play_counter := sound_pid >> 48;
    return stream.state != .Stopped && stream.play_counter == play_counter;
}

get_sound_length_in_seconds :: (client: *Client, sound_index: Sound_Index) -> f32 {
    sound_data := *client.sounds[sound_index];
    return cast(f32) sound_data.available_frames / cast(f32) sound_data.sample_rate;
}

toggle_all_game_sounds :: (client: *Client, pause: bool) {
    for i := 0; i < client.mixer.streams.count; ++i {
        stream := *client.mixer.streams[i];

        if stream.category == .Sound_Effect {
            if stream.state == .Playing && pause {
                stream.state = .Paused;
            } else if stream.state == .Paused && !pause {
                stream.state = .Playing;
            }
        }
    }
}


#if DEVELOPER {
    find_sound_index_from_filepath :: (filepath: string) -> Sound_Index {
        filename := cut_directories_from_path(filepath);

        for i := 0; i < Sound_Index.Count; ++i {
            if SOUND_FILEPATH_MAP[i] == filename return i;
        }

        return Sound_Index.Count;
    }
}


#file_scope

SOUND_CATEGORY_MAP: [Sound_Index.Count]Sound_Category : .[
    .Sound_Effect,
];
