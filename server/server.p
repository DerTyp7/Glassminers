#load "basic.p";

Shared_Server_Data :: struct {
    state: enum {
        Starting;
        Running;
        Closing;
        Closed;
    };

    requested_port: u16;
}

logprint :: (format: string, args: ..Any) {
    print(format, ..args);
    print("\n");
}

server_entry_point :: (data: *Shared_Server_Data) -> u32 #export {
    logprint("Starting server on port '%'.", data.requested_port);

    data.state = .Starting;
    
    data.state = .Closing;
    
    data.state = .Closed;

    logprint("Stopped server.");
    return 0;
}

main :: () -> u32 {
    data: Shared_Server_Data;
    data.requested_port = 9876;
    return server_entry_point(*data);
}