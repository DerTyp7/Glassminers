draw_ui_callbacks :: (client: *Client) -> UI_Callbacks {
    return .{ client, draw_ui_text, draw_ui_rect, set_ui_scissors, clear_ui_scissors };
}

draw_ui_text :: (client: *Client, font: *Font, text: string, position: UI_Vector2, foreground: UI_Color, background: UI_Color) {
    ge_draw_text(*client.graphics, font, text, position.x, position.y, .Left | .Bottom, .{ foreground.r, foreground.g, foreground.b, foreground.a });    
}

draw_ui_rect :: (client: *Client, rect: UI_Rect, rounding: f32, color: UI_Color) {
    ge_imm2d_colored_rect(*client.graphics, rect.x0, rect.y0, rect.x1, rect.y1, .{ color.r, color.g, color.b, color.a });
    ge_imm2d_flush(*client.graphics);
}

set_ui_scissors :: (client: *Client, rect: UI_Rect) {

}

clear_ui_scissors :: (client: *Client) {
    
}



draw_text :: (client: *Client, font: *Font, text: string, x: f32, y: f32, alignment: Text_Alignment, foreground: UI_Color) {
    ge_draw_text(*client.graphics, font, text, x, y, alignment, .{ foreground.r, foreground.g, foreground.b, foreground.a });
}


draw_game_tick :: (client: *Client) {
    
}