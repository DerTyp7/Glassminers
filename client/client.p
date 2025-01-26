// Prometheus modules
#load "basic.p";
#load "window.p";
#load "ui.p";
#load "mixer.p";
#load "threads.p";
#load "virtual_connection.p";
#load "graphics_engine/graphics_engine.p";

// Client files
#load "draw.p";

// @Volatile: Must be in sync with server/server.p
Shared_Server_Data :: struct {
    state: enum {
        Starting;
        Running;
        Closing;
        Closed;
    };

    requested_port: u16;
}

Client_State :: enum {
    Main_Menu;
    Connecting;
}

Client :: struct {
    //
    // Engine structure
    //
    window: Window;
    graphics: Graphics_Engine;
    ui: UI;
    mixer: Mixer;

    perm_pool: Memory_Pool;
    perm: Allocator;

    ui_font, title_font: Font;
    state: Client_State;

    //
    // Networking
    //
    server_data: Shared_Server_Data = .{ .Closed, 0 };
    server_thread: Thread;
    connection: Virtual_Connection;
    
    //
    // Game Data
    //
}

logprint :: (format: string, args: ..Any) {
    print(format, ..args);
    print("\n");
}

host_server :: (client: *Client, port: u16) {
    server_entry_point :: (data: *Shared_Server_Data) -> u32 #foreign;

    client.server_data.state = .Starting;
    client.server_data.requested_port = port;
    client.server_thread = create_thread(server_entry_point, *client.server_data, false);
    while client.server_data.state == .Starting {}
}

join_server :: (client: *Client, name: string, host: string, port: u16) {
    if create_client_connection(*client.connection, .UDP, host, port) == .Success {
        send_connection_request_packet(*client.connection, 5);
        client.state = .Connecting;
    } else {
        maybe_shutdown_server(client);
    }
}

disconnect_from_server :: (client: *Client) {
    maybe_shutdown_server(client);
    client.state = .Main_Menu;
}

maybe_shutdown_server :: (client: *Client) {
    if client.server_data.state != .Closed {
        client.server_data.state = .Closing;
        join_thread(*client.server_thread);
    }
}

do_main_menu :: (client: *Client) {
    ui :: *client.ui;
    
    ui_push_width(ui, .Pixels, 256, 1);

    // Host Window
    {
        ui_push_window(ui, "Host", .Default, .{ 0.33, 0.4 });
        ui_label(ui, false, "Name:");
        name := ui_text_input(ui, "Enter your name", .Everything);
        ui_divider(ui, true);
        ui_label(ui, false, "Port");
        port := ui_text_input(ui, "Enter the port", .Integer);
        ui_divider(ui, true);
        
        if ui_button(ui, "Host!") && name.valid && port.valid {
            host_server(client, port._int);
            join_server(client, name._string, "localhost", port._int);
        }
        
        ui_pop_window(ui);
    }

    // Join Window
    {
        ui_push_window(ui, "Join", .Default, .{ 0.66, 0.4 });
        ui_label(ui, false, "Name:");
        name := ui_text_input(ui, "Enter your name", .Everything);
        ui_divider(ui, true);
        ui_label(ui, false, "Host");
        host := ui_text_input(ui, "Enter the address", .Everything);
        ui_label(ui, false, "Port");
        port := ui_text_input(ui, "Enter the port", .Integer);
        ui_divider(ui, true);
        
        if ui_button(ui, "Join!") && name.valid && host.valid && port.valid {
            join_server(client, name._string, host._string, port._int);
        }
        
        ui_pop_window(ui);
    }
        
    ui_pop_width(ui);
}

do_connecting_screen :: (client: *Client) {
    ui :: *client.ui;

    ui_push_width(ui, .Pixels, 256, 1);
    ui_push_window(ui, "Connecting...", .Default, .{ .5, .5 });
    ui_label(ui, false, "...");
    ui_divider(ui, true);
    if ui_button(ui, "Cancel!") {
        disconnect_from_server(client);
    }
    ui_pop_window(ui);
    ui_pop_width(ui);
}

main :: () -> s32 {
    //
    // Start up the engine
    //
    set_working_directory_to_executable_path();
    os_enable_high_resolution_timer();
    create_temp_allocator(128 * Memory_Unit.Megabytes);
    
    client: Client;
    create_memory_pool(*client.perm_pool, 32 * Memory_Unit.Megabytes, 128 * Memory_Unit.Kilobytes);
    client.perm = allocator_from_memory_pool(*client.perm_pool);

    create_window(*client.window, "Glassminers", WINDOW_DONT_CARE, WINDOW_DONT_CARE, WINDOW_DONT_CARE, WINDOW_DONT_CARE, .Default);
    ge_create(*client.graphics, *client.window, *client.perm);
    ge_create_font_from_file(*client.graphics, *client.ui_font, "data/font.ttf", 12, .Ascii);
    ge_create_font_from_file(*client.graphics, *client.title_font, "data/font.ttf", 45, .Ascii);
    create_ui(*client.ui, draw_ui_callbacks(*client), UI_Dark_Theme, *client.window, *client.ui_font);
    create_mixer(*client.mixer, 1);

    client.state = .Main_Menu;

    //
    // Main loop
    //
    while !client.window.should_close {
        frame_start := os_get_hardware_time();
        
        //
        // Do one frame
        //
        {
            update_window(*client.window);
            begin_ui_frame(*client.ui, .{ 128, 24 });
            
            if #complete client.state == {
              case .Main_Menu; do_main_menu(*client);
              case .Connecting; do_connecting_screen(*client);
            }
        }
        
        //
        // Draw one frame
        //
        {
            ge_clear_screen(*client.graphics, .{ 40, 40, 50, 255 });
            
            if #complete client.state == {
              case .Main_Menu, .Connecting;
                draw_text(*client, *client.title_font, "GlassMiners", xx client.window.w / 2, xx client.window.h / 4, .Center | .Median, .{ 255, 255, 255, 255 });
                draw_ui_frame(*client.ui);
            }
                        
            ge_swap_buffers(*client.graphics);
        }

        release_temp_allocator(0);
        
        frame_end := os_get_hardware_time();
        os_sleep_to_tick_rate(frame_start, frame_end, 144);
    }

    maybe_shutdown_server(*client);
        
    //
    // Destroy the engine
    //
    destroy_mixer(*client.mixer);
    destroy_ui(*client.ui);
    ge_destroy_font(*client.graphics, *client.ui_font);
    ge_destroy_font(*client.graphics, *client.title_font);
    ge_destroy(*client.graphics);
    destroy_window(*client.window);
    destroy_memory_pool(*client.perm_pool);
    destroy_temp_allocator();

    return 0;
}