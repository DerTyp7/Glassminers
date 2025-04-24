
Shared_Server_Data :: struct {
    state: enum {
        Starting;
        Running;
        Closing;
        Closed;
    };

    requested_port: u16;
}
