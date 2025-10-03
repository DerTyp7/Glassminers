Config :: struct {
    // General
    desired_fps: f32;
    ui_scale: UI_Scale;
    gamepad_vibration: bool;
    tutorial_panels: bool;

    // Game Settings
    requested_game_mode: Game_Mode;
    account_name: string;
    network_host: string;
    network_port: s64;

    // Tweak file
    tweak_file: Tweak_File;
}

create_config :: (client: *Client) {
    config := *client.config; 
    allocator := *client.engine_allocator;

    create_tweak_file(*config.tweak_file, allocator, TWEAK_FILE_PATH);

    // Set the default values
    {
        client.window.w = 1280;
        client.window.h = 720;
        client.window.x = WINDOW_DONT_CARE;
        client.window.y = WINDOW_DONT_CARE;
        client.window.fullscreen = !DEVELOPER;
        client.window.maximized  = !DEVELOPER;

        config.desired_fps       = 144;
        config.ui_scale          = .Normal;
        config.gamepad_vibration = true;
        config.tutorial_panels   = !DEVELOPER;

        config.requested_game_mode = ifx DEVELOPER then .Developer else .Tutorial;
        config.account_name = os_get_user_name(allocator);
        config.network_host = copy_string(allocator, ifx DEVELOPER then "localhost" else "tealfire.de");
        config.network_port = 9876;
    }

    // Register all tweak variables
    {
        tf := *config.tweak_file;
        register_tweak_variable(tf, "/window/width", *client.window.w);
        register_tweak_variable(tf, "/window/height", *client.window.h);
        register_tweak_variable(tf, "/window/x", *client.window.x);
        register_tweak_variable(tf, "/window/y", *client.window.y);
        register_tweak_variable(tf, "/window/fullscreen", *client.window.fullscreen);
        register_tweak_variable(tf, "/window/maximized", *client.window.maximized);

        register_tweak_variable(tf, "/general/fps", *config.desired_fps);
        register_tweak_variable(tf, "/general/ui_scale", *config.ui_scale);
        register_tweak_variable(tf, "/general/master_volume", *client.mixer.volumes[.Master]);
        register_tweak_variable(tf, "/general/display_gamma", *client.lightmap.gamma);
        register_tweak_variable(tf, "/general/gamepad_vibration", *config.gamepad_vibration);
        register_tweak_variable(tf, "/general/tutorial_panels", *config.tutorial_panels);
        
        register_tweak_variable(tf, "/game/requested_game_mode", *config.requested_game_mode);
        register_tweak_variable(tf, "/game/name", *config.account_name);
        register_tweak_variable(tf, "/game/host", *config.network_host);
        register_tweak_variable(tf, "/game/port", *config.network_port);
    }

    // Read in existing values from disk
    {
        read_tweak_file(*config.tweak_file);
    }
}

save_config :: (client: *Client) {
    write_tweak_file(*client.config.tweak_file);
}

destroy_config :: (client: *Client) {
    destroy_tweak_file(*client.config.tweak_file);
}

#if DEVELOPER {
    maybe_reload_config :: (client: *Client) {
        if maybe_reload_tweak_file(*client.config.tweak_file) then apply_window_config(client);
    }
}

desired_window_style :: (client: *Client) -> Window_Style_Flags { 
    if client.window.fullscreen then return .Fullscreen | .Maximized;
    if client.window.maximized  then return .Maximized;
    return .Default;
}



#file_scope

#if DEVELOPER {
    TWEAK_FILE_PATH :: "dev.tweak";
} #else {
    TWEAK_FILE_PATH :: ".tweak";
}

apply_window_config :: (client: *Client) {
    set_window_position_and_size(*client.window, client.window.x, client.window.y, client.window.w, client.window.h, client.window.maximized);
    set_window_style(*client.window, desired_window_style(client));
}