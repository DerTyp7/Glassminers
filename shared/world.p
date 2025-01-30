#load "math/Vector.p";

WORLD_WIDTH  :: 32;
WORLD_HEIGHT :: 5;

v2i :: Vector2_Base(s32);
v2f :: Vector2_Base(f32);

Pid :: u32;

INVALID_PID: Pid : -1;

Entity_Kind :: enum {
    Inanimate;
    Player;
    Crystal;
    Stone;
}

Entity_Prototype :: struct {
    kind: Entity_Kind;
    position: v2i;
}

