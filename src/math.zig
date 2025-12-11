const std = @import("std");

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }
    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }
    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }
    pub fn scale(v: Vec2, s: f32) Vec2 {
        return .{ .x = v.x * s, .y = v.y * s };
    }
    pub fn clamp(v: Vec2, min: f32, max: f32) Vec2 {
        return .{ .x = std.math.clamp(v.x, min, max), .y = std.math.clamp(v.y, min, max) };
    }
};

pub const IVec2 = struct {
    x: i32,
    y: i32,
    pub fn init(x: i32, y: i32) IVec2 {
        return .{ .x = x, .y = y };
    }
};
