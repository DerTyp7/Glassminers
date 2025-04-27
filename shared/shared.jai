Server_State :: enum {
    Starting;
    Running;
    Closing;
    Closed;
}

Shared_Server_Data :: struct {
    state: Server_State;
    requested_port: u16;
}
