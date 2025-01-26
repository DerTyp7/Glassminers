// Prometheus modules
#load "basic.p";
#load "virtual_connection.p";

// Shared
#load "../shared/messages.p";

Shared_Server_Data :: struct {
    state: enum {
        Starting;
        Running;
        Closing;
        Closed;
    };

    requested_port: u16;
}

Remote_Client :: struct {
    connection: Virtual_Connection;
}

Server :: struct {
    perm_pool: Memory_Pool;
    perm: Allocator;

    connection: Virtual_Connection;
    clients: [..]Remote_Client;
    incoming_messages: [..]Message;
    outgoing_messages: [..]Message;
}

logprint :: (format: string, args: ..Any) {
    print(format, ..args);
    print("\n");
}

server_entry_point :: (data: *Shared_Server_Data) -> u32 #export {
    //
    // Start up the server
    //
    data.state = .Starting;

    set_working_directory_to_executable_path();
    os_enable_high_resolution_timer();
    create_temp_allocator(128 * Memory_Unit.Megabytes);

    server: Server;
    create_memory_pool(*server.perm_pool, 32 * Memory_Unit.Megabytes, 128 * Memory_Unit.Kilobytes);
    server.perm = allocator_from_memory_pool(*server.perm_pool);
    server.clients.allocator = *server.perm;
    server.incoming_messages.allocator = *temp;
    server.outgoing_messages.allocator = *temp;

    if create_server_connection(*server.connection, .UDP, data.requested_port) == .Success {
        data.state = .Running;
    } else {
        data.state = .Closing;
    }
    
    logprint("Started the server.");
    
    while data.state == .Running {
        tick_start := os_get_hardware_time();

        //
        // Handle connection packets and read all messages from clients.
        //
        {
            array_clear_without_deallocation(*server.incoming_messages);
            
            while read_packet(*server.connection) {
                if server.connection.incoming_packet.header.packet_type == {
                  case Packet_Type.Connection_Request;
                    logprint("Connection request!");
                    
                  case Packet_Type.Connection_Closed;
                    logprint("Connection closed!");
                    
                  case Packet_Type.Ping;
                    logprint("Ping!"); 
                    
                  case Packet_Type.Message;
                    message := array_push(*server.incoming_messages);
                    read_message(*server.connection, message);
                }
            }
        }
        
        //
        // Update the internal state based on the received messages.
        //
        {
            
        }
        
        //
        // Send all updates to clients.
        //
        {
            for j := 0; j < server.clients.count; ++j {
                client := array_get_pointer(*server.clients, j);
                for i := 0; i < server.outgoing_messages.count; ++i {
                    send_reliable_message(*client.connection, array_get_pointer(*server.outgoing_messages, i));
                }
            }
        
            array_clear_without_deallocation(*server.outgoing_messages);
        }

        release_temp_allocator(0);
        
        tick_end := os_get_hardware_time();
        os_sleep_to_tick_rate(tick_start, tick_end, 60);
    }
    
    data.state = .Closing;
    
    destroy_connection(*server.connection);
    array_clear(*server.clients);
    destroy_temp_allocator();

    logprint("Stopped the server.");
    
    data.state = .Closed;

    return 0;
}

main :: () -> u32 {
    data: Shared_Server_Data;
    data.requested_port = 9876;
    return server_entry_point(*data);
}