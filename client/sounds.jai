Sound_Pid :: u64;

Sound_Index :: enum {
    Pickup_0;
    Pickaxe_0;
}

create_all_sounds :: (client: *Client) {
    client.sounds[.Pickup_0] = load_sound("data/sounds/pickup-0.wav");
    client.sounds[.Pickaxe_0] = load_sound("data/sounds/pickaxe-0.wav");
}

destroy_all_sounds :: (client: *Client) {
    for i := 0; i < client.sounds.Capacity; ++i {
        destroy_sound_data(*client.sounds[i]);
    }
}

play_sound :: (client: *Client, sound_index: Sound_Index, looping: bool) -> Sound_Pid {
    sound := *client.sounds[sound_index];
    
    stream := get_unused_sound_stream(*client.mixer.player);
    if !stream {
        logprint(.Warning, "Failed to play a sound because no stream was available!");
        return INVALID_SOUND_PID;
    }

    play_sound_on_stream(stream, sound, SOUND_CATEGORY_MAP[sound_index], looping);

    return (stream.play_counter << 48) | (stream & 0xffffffffffff);
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



#file_scope

INVALID_SOUND_PID: Sound_Pid = 0;

SOUND_CATEGORY_MAP: [Sound_Index.Count]Sound_Category : .[
    .Sound_Effect,
];

load_sound :: (filepath: string) -> Sound_Data {
    sound_data, status := create_sound_data_from_file(filepath);
    if status != .Success logprint(.Error, "Failed to load the sound '%': %.", filepath, status);
    return sound_data;
}
