Config :: struct {
    // Window
    window_width: s32;
    window_height: s32;
    window_x: s32;
    window_y: s32;
    window_fullscreen: bool;
    window_maximized: bool;
    
    // General
    desired_fps: f32;
    ui_scale: UI_Scale;
    master_volume: f32;
    display_gamma: f32;
    gamepad_vibration: bool;
    tutorial_panels: bool;

    // Game Settings
    account_name: string;
    network_host: string;
    network_port: s64;

    // Tweak file
    tweak_file: Tweak_File;
}

create_config :: (config: *Config, allocator: *Allocator) {
    create_tweak_file(*config.tweak_file, allocator, TWEAK_FILE_PATH);

    // Set the default values
    {
        config.window_width      = 1280;
        config.window_height     = 720;
        config.window_x          = WINDOW_DONT_CARE;
        config.window_y          = WINDOW_DONT_CARE;
        config.window_fullscreen = !DEVELOPER;
        config.window_maximized  = !DEVELOPER;

        config.desired_fps       = 144;
        config.ui_scale          = .Normal;
        config.master_volume     = 1;
        config.display_gamma     = 1;
        config.gamepad_vibration = true;
        config.tutorial_panels   = true;

        config.account_name = os_get_user_name(allocator);
        config.network_host = copy_string(allocator, ifx DEVELOPER then "localhost" else "tealfire.de");
        config.network_port = 9876;
    }

    // Register all tweak variables
    {
        tf := *config.tweak_file;
        register_tweak_variable(tf, "/window/width", *config.window_width);
        register_tweak_variable(tf, "/window/height", *config.window_height);
        register_tweak_variable(tf, "/window/x", *config.window_x);
        register_tweak_variable(tf, "/window/y", *config.window_y);
        register_tweak_variable(tf, "/window/fullscreen", *config.window_fullscreen);
        register_tweak_variable(tf, "/window/maximized", *config.window_maximized);

        register_tweak_variable(tf, "/general/fps", *config.desired_fps);
        register_tweak_variable(tf, "/general/ui_scale", *config.ui_scale);
        register_tweak_variable(tf, "/general/master_volume", *config.master_volume);
        register_tweak_variable(tf, "/general/display_gamma", *config.display_gamma);
        register_tweak_variable(tf, "/general/gamepad_vibration", *config.gamepad_vibration);
        register_tweak_variable(tf, "/general/tutorial_panels", *config.tutorial_panels);
        
        register_tweak_variable(tf, "/account/name", *config.account_name);
        register_tweak_variable(tf, "/account/host", *config.network_host);
        register_tweak_variable(tf, "/account/port", *config.network_port);
    }

    // Read in existing values from disk
    {
        read_tweak_file(*config.tweak_file);
    }
}

save_config :: (config: *Config) {
    write_tweak_file(*config.tweak_file);
}

destroy_config :: (config: *Config) {
    destroy_tweak_file(*config.tweak_file);
}

#if DEVELOPER {
    maybe_reload_config :: (config: *Config) {
        maybe_reload_tweak_file(*config.tweak_file);
    }
}


#file_scope

#if DEVELOPER {
    TWEAK_FILE_PATH :: "dev.tweak";
} #else {
    TWEAK_FILE_PATH :: ".tweak";
}