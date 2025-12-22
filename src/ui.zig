const std = @import("std");
const rl = @import("raylib");
const palette = @import("palette.zig");
const DB16 = palette.DB16;
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

    pub fn yesNoPopup(self: UI, message: [:0]const u8, mouse: rl.Vector2) ?bool {
        const text_width: f32 = @floatFromInt(rl.measureText(message, CONF.DEFAULT_FONT_SIZE));
        const popup_size = rl.Vector2.init(text_width + 128, 128);
        const center = rl.Vector2.init(self.pivots[PIVOTS.CENTER].x, self.pivots[PIVOTS.CENTER].y);
        const popup_corner = rl.Vector2.init(center.x - @divFloor(popup_size.x, 2), center.y - @divFloor(popup_size.y, 2));
        const rec = rl.Rectangle.init(popup_corner.x, popup_corner.y, popup_size.x, popup_size.y);
        const rec_shadow = rl.Rectangle.init(popup_corner.x + 8, popup_corner.y + 8, popup_size.x, popup_size.y);
        const text_x = popup_corner.x + @divFloor(popup_size.x - text_width, 2);
        const text_y = popup_corner.y + 24.0;

        rl.drawRectangleRounded(rec_shadow, CONF.CORNER_RADIUS, CONF.CORNER_QUALITY, DB16.BLACK);
        rl.drawRectangleRounded(rec, CONF.CORNER_RADIUS, CONF.CORNER_QUALITY, DB16.DARK_GRAY);
        rl.drawRectangleRoundedLines(rec, CONF.CORNER_RADIUS, CONF.CORNER_QUALITY, DB16.RED);
        rl.drawText(message, @intFromFloat(text_x), @intFromFloat(text_y), CONF.DEFAULT_FONT_SIZE, DB16.WHITE);

        const button_y = popup_corner.y + popup_size.y - 50.0;
        const button_height = 32;
        const button_width = 80;
        const no_x = popup_corner.x + 24;
        const yes_x = popup_corner.x + popup_size.x - 80 - 24;

        const yes_clicked = self.button(yes_x, button_y, button_width, button_height, "Yes", DB16.GREEN, mouse);
        if (yes_clicked) return true;

        const no_clicked = self.button(no_x, button_y, button_width, button_height, "No", DB16.RED, mouse);
        if (no_clicked) return false;

        return null;
    }
};
