const std = @import("std");
const rl = @import("raylib");
// const raygui = @import("raylib").raygui;
const palette = @import("palette.zig");
const DB16 = palette.DB16;
const Math = @import("math.zig");
const IVec2 = Math.IVec2;

const SCREEN_W = 1024;
const SCREEN_H = 640;

const DEFAULT_FONT_SIZE = 20;
const CORNER_RADIUS = 0.1;
const CORNER_QUALITY = 2;

const PIVOT_PADDING = 24;
const P_CENTER = 0;
const P_TOPLEFT = 1;
const P_TOPRIGHT = 2;
const P_BOTTOMLEFT = 3;
const P_BOTTOMRIGHT = 4;

pub const UI = struct {
    app_name: [:0]const u8,
    bg_color: rl.Color,
    primary_color: rl.Color,
    pivots: [5]IVec2,
    pub fn init(title: [:0]const u8, bg_color: rl.Color, primary_color: rl.Color) UI {
        return UI{
            .app_name = title,
            .bg_color = bg_color,
            .primary_color = primary_color,
            .pivots = .{
                IVec2.init(SCREEN_W / 2, SCREEN_H / 2),
                IVec2.init(PIVOT_PADDING, PIVOT_PADDING),
                IVec2.init(SCREEN_W - PIVOT_PADDING, PIVOT_PADDING),
                IVec2.init(PIVOT_PADDING, SCREEN_H - PIVOT_PADDING),
                IVec2.init(SCREEN_W - PIVOT_PADDING, SCREEN_H - PIVOT_PADDING),
            },
        };
    }

    pub fn createWindow(self: UI) void {
        rl.initWindow(SCREEN_W, SCREEN_H, self.app_name);
    }

    pub fn closeWindow(self: UI) void {
        _ = self;
        rl.closeWindow();
    }

    pub fn button(x: i32, y: i32, width: i32, height: i32, label: [:0]const u8, color: rl.Color, mouse: rl.Vector2) bool {
        const fx: f32 = @floatFromInt(x);
        const fy: f32 = @floatFromInt(y);
        const fw: f32 = @floatFromInt(width);
        const fh: f32 = @floatFromInt(height);
        const rec = rl.Rectangle.init(fx, fy, fw, fh);
        const rec_shadow = rl.Rectangle.init(fx + 3.0, fy + 3.0, fw, fh);
        const hover = rl.checkCollisionPointRec(mouse, rec);
        const c = if (hover) DB16.YELLOW else DB16.WHITE;
        const text_x: i32 = x + @divFloor(width - rl.measureText(label, DEFAULT_FONT_SIZE), 2);
        const text_y: i32 = y + @divFloor(height - DEFAULT_FONT_SIZE, 2);

        rl.drawRectangleRounded(rec_shadow, CORNER_RADIUS, CORNER_QUALITY, DB16.BLACK);
        rl.drawRectangleRounded(rec, CORNER_RADIUS, CORNER_QUALITY, color);
        rl.drawRectangleRoundedLinesEx(rec, CORNER_RADIUS, CORNER_QUALITY, 2, c);
        rl.drawText(label, text_x, text_y, DEFAULT_FONT_SIZE, c);

        return rl.isMouseButtonPressed(rl.MouseButton.left) and hover;
    }

    pub fn demo(self: UI) void {
        const mouse = rl.getMousePosition();
        rl.clearBackground(DB16.NAVY_BLUE);
        rl.drawText(self.app_name, self.pivots[P_CENTER].x - @divFloor(rl.measureText(self.app_name, DEFAULT_FONT_SIZE), 2), self.pivots[P_CENTER].y, DEFAULT_FONT_SIZE, self.primary_color);
        if (button(12, 12, 100, 32, "Red", DB16.RED, mouse)) {
            rl.drawText("Clicked Red", 120, 12, DEFAULT_FONT_SIZE, self.primary_color);
        }
        if (button(12, 56, 100, 32, "Blue", DB16.BLUE, mouse)) {
            rl.drawText("Clicked Blue", 120, 56, DEFAULT_FONT_SIZE, self.primary_color);
        }
    }
};
