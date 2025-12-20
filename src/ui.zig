const std = @import("std");
const rl = @import("raylib");
const palette = @import("palette.zig");
const DB16 = palette.DB16;
const Math = @import("math.zig");
const CONF = @import("config.zig").CONF;

pub const PIVOTS = struct {
    pub const PADDING = 24;
    pub const CENTER = 0;
    pub const TOP_LEFT = 1;
    pub const TOP_RIGHT = 2;
    pub const BOTTOM_LEFT = 3;
    pub const BOTTOM_RIGHT = 4;
};

pub const UI = struct {
    app_name: [:0]const u8,
    bg_color: rl.Color,
    primary_color: rl.Color,
    secondary_color: rl.Color,
    pivots: [5]rl.Vector2,
    pub fn init(title: [:0]const u8, bg_color: rl.Color, primary_color: rl.Color, secondary_color: rl.Color) UI {
        return UI{
            .app_name = title,
            .bg_color = bg_color,
            .primary_color = primary_color,
            .secondary_color = secondary_color,
            .pivots = .{
                rl.Vector2.init(CONF.SCREEN_W / 2, CONF.SCREEN_H / 2),
                rl.Vector2.init(PIVOTS.PADDING, PIVOTS.PADDING),
                rl.Vector2.init(CONF.SCREEN_W - PIVOTS.PADDING, PIVOTS.PADDING),
                rl.Vector2.init(PIVOTS.PADDING, CONF.SCREEN_H - PIVOTS.PADDING),
                rl.Vector2.init(CONF.SCREEN_W - PIVOTS.PADDING, CONF.SCREEN_H - PIVOTS.PADDING),
            },
        };
    }

    pub fn createWindow(self: UI) void {
        rl.initWindow(CONF.SCREEN_W, CONF.SCREEN_H, self.app_name);
    }

    pub fn closeWindow(self: UI) void {
        _ = self;
        rl.closeWindow();
    }

    pub fn button(self: UI, x: f32, y: f32, width: i32, height: i32, label: [:0]const u8, color: rl.Color, mouse: rl.Vector2) bool {
        _ = self;
        const ix: i32 = @intFromFloat(x);
        const iy: i32 = @intFromFloat(y);
        const fw: f32 = @floatFromInt(width);
        const fh: f32 = @floatFromInt(height);
        const rec = rl.Rectangle.init(x, y, fw, fh);
        const rec_shadow = rl.Rectangle.init(x + 3.0, y + 3.0, fw, fh);
        const hover = rl.checkCollisionPointRec(mouse, rec);
        const c = if (hover) DB16.YELLOW else DB16.WHITE;
        const text_x: i32 = ix + @divFloor(width - rl.measureText(label, CONF.DEFAULT_FONT_SIZE), 2);
        const text_y: i32 = iy + @divFloor(height - CONF.DEFAULT_FONT_SIZE, 2);

        rl.drawRectangleRounded(rec_shadow, CONF.CORNER_RADIUS, CONF.CORNER_QUALITY, DB16.BLACK);
        rl.drawRectangleRounded(rec, CONF.CORNER_RADIUS, CONF.CORNER_QUALITY, color);
        rl.drawRectangleRoundedLinesEx(rec, CONF.CORNER_RADIUS, CONF.CORNER_QUALITY, 2, c);
        rl.drawText(label, text_x, text_y, CONF.DEFAULT_FONT_SIZE, c);

        return rl.isMouseButtonPressed(rl.MouseButton.left) and hover;
    }
};
