const std = @import("std");
const c = @cImport({
    @cInclude("fenster.h");
});
const Vec2 = @import("math.zig").Vec2;
const CONF = @import("config.zig").CONF;
const Palette = @import("palette.zig").Palette;
const DB16 = Palette.DB16;
pub const PIVOTS = struct {
    pub const PADDING = 24;
    pub const CENTER = 0;
    pub const TOP_LEFT = 1;
    pub const TOP_RIGHT = 2;
    pub const BOTTOM_LEFT = 3;
    pub const BOTTOM_RIGHT = 4;
};
pub const Fui = struct {
    app_name: [:0]const u8 = CONF.THE_NAME,
    pivots: [5]Vec2,
    buf: *[CONF.SCREEN_W * CONF.SCREEN_H]u32 = undefined,
    const font5x3: [95]u16 = [_]u16{ 0x0000, 0x2092, 0x002d, 0x5f7d, 0x279e, 0x52a5, 0x7ad6, 0x0012, 0x4494, 0x1491, 0x017a, 0x05d0, 0x1400, 0x01c0, 0x0400, 0x12a4, 0x2b6a, 0x749a, 0x752a, 0x38a3, 0x4f4a, 0x38cf, 0x3bce, 0x12a7, 0x3aae, 0x49ae, 0x0410, 0x1410, 0x4454, 0x0e38, 0x1511, 0x10e3, 0x73ee, 0x5f7a, 0x3beb, 0x624e, 0x3b6b, 0x73cf, 0x13cf, 0x6b4e, 0x5bed, 0x7497, 0x2b27, 0x5add, 0x7249, 0x5b7d, 0x5b6b, 0x3b6e, 0x12eb, 0x4f6b, 0x5aeb, 0x388e, 0x2497, 0x6b6d, 0x256d, 0x5f6d, 0x5aad, 0x24ad, 0x72a7, 0x6496, 0x4889, 0x3493, 0x002a, 0xf000, 0x0011, 0x6b98, 0x3b79, 0x7270, 0x7b74, 0x6750, 0x95d6, 0xb9ee, 0x5b59, 0x6410, 0xb482, 0x56e8, 0x6492, 0x5be8, 0x5b58, 0x3b70, 0x976a, 0xcd6a, 0x1370, 0x38f0, 0x64ba, 0x3b68, 0x2568, 0x5f68, 0x54a8, 0xb9ad, 0x73b8, 0x64d6, 0x2492, 0x3593, 0x03e0 };
    pub fn init(buf: *[CONF.SCREEN_W * CONF.SCREEN_H]u32) Fui {
        return Fui{
            .buf = buf,
            .pivots = .{
                Vec2.init(CONF.SCREEN_W / 2, CONF.SCREEN_H / 2),
                Vec2.init(PIVOTS.PADDING, PIVOTS.PADDING),
                Vec2.init(CONF.SCREEN_W - PIVOTS.PADDING, PIVOTS.PADDING),
                Vec2.init(PIVOTS.PADDING, CONF.SCREEN_H - PIVOTS.PADDING),
                Vec2.init(CONF.SCREEN_W - PIVOTS.PADDING, CONF.SCREEN_H - PIVOTS.PADDING),
            },
        };
    }
    pub fn put_pixel(self: *Fui, x: i32, y: i32, color: u32) void {
        const index: usize = @intCast(y * CONF.SCREEN_W + x);
        if (index > 0 and index < self.buf.len) {
            self.buf[index] = color;
        }
    }
    pub fn get_pixel(self: *Fui, x: i32, y: i32) u32 {
        const index: u32 = @intCast(y * CONF.SCREEN_W + x);
        if (index > 0 and index < self.buf.len) {
            return self.buf[index];
        }
        return 0;
    }
    pub fn clear_background(self: *Fui, color: u32) void {
        for (self.buf, 0..) |_, i| {
            self.buf[i] = color;
        }
    }
    pub fn draw_line(self: *Fui, x0: i32, y0: i32, x1: i32, y1: i32, color: u32) void {
        var x = x0;
        var y = y0;
        const dx: i32 = @intCast(@abs(x1 - x0));
        const dy: i32 = @intCast(@abs(y1 - y0));
        const sx: i32 = if (x0 < x1) 1 else -1;
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err: i32 = if (dx > dy) dx else -dy;
        err = @divFloor(err, 2);
        while (true) {
            if (x >= 0 and x < CONF.SCREEN_W and y >= 0 and y < CONF.SCREEN_H) {
                self.put_pixel(x, y, color);
            }
            if (x == x1 and y == y1) break;
            const e2 = err;
            if (e2 > -dx) {
                err -= dy;
                x += sx;
            }
            if (e2 < dy) {
                err += dx;
                y += sy;
            }
        }
    }
    pub fn draw_rect(self: *Fui, x: i32, y: i32, w: i32, h: i32, color: u32) void {
        const ix: u32 = @intCast(x);
        const iy: u32 = @intCast(y);
        const iw: u32 = @intCast(w);
        const ih: u32 = @intCast(h);

        for (iy..(iy + ih)) |row| {
            for (ix..(ix + iw)) |col| {
                self.put_pixel(@intCast(col), @intCast(row), color);
            }
        }
    }
    pub fn draw_rect_lines(self: *Fui, x: i32, y: i32, w: i32, h: i32, color: u32) void {
        const ix: u32 = @intCast(x);
        const iy: u32 = @intCast(y);
        const iw: u32 = @intCast(w);
        const ih: u32 = @intCast(h);

        for (iy..(iy + ih)) |row| {
            for (ix..(ix + iw)) |col| {
                self.put_pixel(@intCast(col), @intCast(row), color);
            }
        }
    }
    pub fn draw_circle(self: *Fui, x: i32, y: i32, r: u32, color: u32) void {
        const rr = @as(i64, r) * r;
        const ir: i32 = @intCast(r);
        var dy: i32 = -ir;
        while (dy <= ir) : (dy += 1) {
            var dx: i32 = -ir;
            while (dx <= ir) : (dx += 1) {
                const px = x + dx;
                const py = y + dy;
                if (px >= 0 and px < CONF.SCREEN_W and py >= 0 and py < CONF.SCREEN_H) {
                    const dist = @as(i64, dx) * dx + @as(i64, dy) * dy;
                    if (dist <= rr) {
                        const index = (@as(usize, @intCast(py)) * CONF.SCREEN_W) + @as(usize, @intCast(px));
                        self.buf[index] = color;
                    }
                }
            }
        }
    }
    pub fn fill(self: *Fui, x: i32, y: i32, old_color: u32, new_color: u32) void {
        if (x < 0 or y < 0 or x >= CONF.SCREEN_W or y >= CONF.SCREEN_H) {
            return;
        }
        if (self.get_pixel(x, y) == old_color) {
            self.put_pixel(x, y, new_color);
            self.fill(x - 1, y, old_color, new_color);
            self.fill(x + 1, y, old_color, new_color);
            self.fill(x, y - 1, old_color, new_color);
            self.fill(x, y + 1, old_color, new_color);
        }
    }
    pub fn draw_text(self: *Fui, x: i32, y: i32, s: []const u8, scale: i32, color: u32) void {
        var px = x;
        for (s) |chr| {
            if (chr >= 32) {
                const bmp = font5x3[chr - 32];
                var dy: i32 = 0;
                while (dy < 5) : (dy += 1) {
                    var dx: i32 = 0;
                    while (dx < 3) : (dx += 1) {
                        const bit: u4 = @intCast(dy * 3 + dx);
                        if ((bmp >> bit) & 1 != 0) {
                            const rx: i32 = @intCast(dx * scale);
                            const ry: i32 = @intCast(dy * scale);
                            if (x + rx >= 0 and ry >= 0) {
                                self.draw_rect(px + rx, y + ry, scale, scale, color);
                            }
                        }
                    }
                }
            }
            px += 4 * @as(i32, scale);
        }
    }
    pub fn textLength(self: *Fui, s: []const u8, scale: i32) i32 {
        _ = self;
        return s.len * scale * CONF.FONT_WIDTH;
    }
    pub fn textCenter(self: *Fui, s: []const u8, scale: i32) Vec2 {
        _ = self;
        const size: i32 = @intCast(s.len);
        return Vec2.init(@divFloor(size * scale * CONF.FONT_WIDTH, 2), @divFloor(scale * CONF.FONT_HEIGHT, 2));
    }
};
