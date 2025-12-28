const std = @import("std");

pub const Vec2 = struct {
    x: i32,
    y: i32,
    pub fn init(x: i32, y: i32) Vec2 {
        return .{ .x = x, .y = y };
    }
};
pub const Mouse = struct {
    x: i32,
    y: i32,
    pressed: bool,
    pub fn init(x: i32, y: i32, pressed: bool) Mouse {
        return .{ .x = x, .y = y, .pressed = pressed };
    }
};
pub const Rect = struct {
    w: i32,
    h: i32,
    x: i32,
    y: i32,
    pub fn init(w: i32, h: i32, x: i32, y: i32) Rect {
        return .{ .w = w, .h = h, .x = x, .y = y };
    }
};
