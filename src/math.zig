const std = @import("std");

pub const Vec2 = struct {
    x: i32,
    y: i32,
    pub fn init(x: i32, y: i32) Vec2 {
        return .{ .x = x, .y = y };
    }
};
