Sound_Index :: enum {
    Pickup_0;
}

create_all_sounds :: (client: *Client) {
    client.sounds[.Pickup_0] = load_sound("data/sounds/pickup-0.wav");
}

destroy_all_sounds :: (client: *Client) {
    for i := 0; i < client.sounds.Capacity; ++i {
        destroy_sound_data(*client.sounds[i]);
    }
}

play_sound :: (client: *Client, sound_index: Sound_Index, looping: bool) {
    sound := *client.sounds[sound_index];
    
    stream := get_unused_sound_stream(*client.mixer.player);
    if !stream {
        logprint(.Warning, "Failed to play a sound because no stream was available!");
        return;
    }

    play_sound_on_stream(stream, sound, SOUND_CATEGORY_MAP[sound_index], looping);
}



#file_scope

SOUND_CATEGORY_MAP: [Sound_Index.Count]Sound_Category : .[
    .Sound_Effect,
];

load_sound :: (filepath: string) -> Sound_Data {
    sound_data, status := create_sound_data_from_file(filepath);
    if status != .Success logprint(.Error, "Failed to load the sound '%': %.", filepath, status);
    return sound_data;
}
