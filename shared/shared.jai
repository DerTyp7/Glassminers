#load "math/Vector.jai";

v2i :: Vector2_Base(s32);
v2f :: Vector2_Base(f32);

Pid :: u32;

INVALID_PID: Pid : -1;

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

NETWORK_TIMEOUT: f32 : 7;
NETWORK_PING_INTERVAL: f32 : 0.25;
