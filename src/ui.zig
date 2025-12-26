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
    pivots: [5]rl.Vector2,
    pub fn init(
        title: [:0]const u8,
    ) UI {
        return UI{
            .app_name = title,
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

    pub fn button(
        self: UI,
        x: f32,
        y: f32,
        width: i32,
        height: i32,
        label: [:0]const u8,
        color: rl.Color,
        mouse: rl.Vector2,
    ) bool {
        _ = self;
        const ix: i32 = @intFromFloat(x);
        const iy: i32 = @intFromFloat(y);
        const fw: f32 = @floatFromInt(width);
        const fh: f32 = @floatFromInt(height);
        const rec = rl.Rectangle.init(x, y, fw, fh);
        const hover = rl.checkCollisionPointRec(mouse, rec);
        const c = if (hover) DB16.YELLOW else DB16.WHITE;
        const text_x: i32 = ix + @divFloor(width - rl.measureText(label, CONF.FONT_DEFAULT_SIZE), 2);
        const text_y: i32 = iy + @divFloor(height - CONF.FONT_DEFAULT_SIZE, 2);

        rl.drawRectangle(ix + CONF.SHADOW, iy + CONF.SHADOW, width, height, DB16.BLACK);
        rl.drawRectangle(ix, iy, width, height, color);
        rl.drawRectangleLines(ix, iy, width, height, c);
        rl.drawText(label, text_x, text_y, CONF.FONT_DEFAULT_SIZE, c);

        return rl.isMouseButtonPressed(rl.MouseButton.left) and hover;
    }

    fn drawBasePopup(
        self: UI,
        message: [:0]const u8,
        bg_color: rl.Color,
    ) rl.Vector4 {
        const text_width: f32 = @floatFromInt(rl.measureText(message, CONF.FONT_DEFAULT_SIZE));
        const popup_size = rl.Vector2.init(text_width + 128, 128);
        const center = rl.Vector2.init(self.pivots[PIVOTS.CENTER].x, self.pivots[PIVOTS.CENTER].y);
        const popup_corner = rl.Vector2.init(center.x - @divFloor(popup_size.x, 2), center.y - @divFloor(popup_size.y, 2));
        const rec = rl.Rectangle.init(popup_corner.x, popup_corner.y, popup_size.x, popup_size.y);
        const rec_shadow = rl.Rectangle.init(popup_corner.x + 8, popup_corner.y + 8, popup_size.x, popup_size.y);
        const text_x = popup_corner.x + @divFloor(popup_size.x - text_width, 2);
        const text_y = popup_corner.y + 24.0;

        rl.drawRectangleRounded(rec_shadow, CONF.CORNER_RADIUS, CONF.CORNER_QUALITY, CONF.COLOR_SHADOW);
        rl.drawRectangleRounded(rec, CONF.CORNER_RADIUS, CONF.CORNER_QUALITY, bg_color);
        rl.drawRectangleRoundedLines(rec, CONF.CORNER_RADIUS, CONF.CORNER_QUALITY, CONF.COLOR_LIGHT);
        rl.drawText(message, @intFromFloat(text_x), @intFromFloat(text_y), CONF.FONT_DEFAULT_SIZE, CONF.COLOR_POPUP_MSG);
        return rl.Vector4.init(
            popup_corner.x,
            popup_corner.y,
            popup_size.x,
            popup_size.y,
        );
    }

    pub fn infoPopup(
        self: UI,
        message: [:0]const u8,
        mouse: rl.Vector2,
        bg_color: rl.Color,
    ) ?bool {
        // Popup
        const popupv4 = self.drawBasePopup(message, bg_color);
        const popup_corner = rl.Vector2.init(popupv4.x, popupv4.y);
        const popup_height = popupv4.w;

        // Button
        const button_height = 32;
        const button_width = 80;
        const button_x = self.pivots[PIVOTS.CENTER].x - @divFloor(button_width, 2);
        const button_y = popup_corner.y + popup_height - 50.0;
        const ok_clicked = self.button(
            button_x,
            button_y,
            button_width,
            button_height,
            "OK",
            CONF.COLOR_OK,
            mouse,
        );
        if (ok_clicked) return true;
        return null;
    }

    pub fn yesNoPopup(
        self: UI,
        message: [:0]const u8,
        mouse: rl.Vector2,
    ) ?bool {
        // Popup
        const popupv4 = self.drawBasePopup(message, CONF.COLOR_POPUP);
        const popup_corner = rl.Vector2.init(popupv4.x, popupv4.y);
        const popup_size = rl.Vector2.init(popupv4.z, popupv4.w);

        // buttons
        const button_y = popup_corner.y + popup_size.y - 50.0;
        const button_height = 32;
        const button_width = 80;
        const no_x = popup_corner.x + 24;
        const yes_x = popup_corner.x + popup_size.x - 80 - 24;

        const yes_clicked = self.button(
            yes_x,
            button_y,
            button_width,
            button_height,
            "Yes",
            CONF.COLOR_YES,
            mouse,
        );
        if (yes_clicked) return true;

        const no_clicked = self.button(
            no_x,
            button_y,
            button_width,
            button_height,
            "No",
            CONF.COLOR_NO,
            mouse,
        );
        if (no_clicked) return false;

        return null;
    }
    pub fn drawVersion(self: UI) void {
        const ver_x: i32 = @intFromFloat(self.pivots[PIVOTS.BOTTOM_RIGHT].x);
        const ver_y: i32 = @intFromFloat(self.pivots[PIVOTS.BOTTOM_RIGHT].y);

        rl.drawText(
            CONF.VERSION,
            ver_x - rl.measureText(CONF.VERSION, CONF.FONT_DEFAULT_SIZE),
            ver_y - CONF.FONT_DEFAULT_SIZE,
            CONF.FONT_DEFAULT_SIZE,
            CONF.COLOR_SECONDARY,
        );
    }
    pub fn drawCursorLines(self: UI, mouse: rl.Vector2) void {
        _ = self;
        rl.drawLine(@intFromFloat(mouse.x), 0, @intFromFloat(mouse.x), @intFromFloat(CONF.SCREEN_H), CONF.COLOR_CROSSHAIR);
        rl.drawLine(0, @intFromFloat(mouse.y), @intFromFloat(CONF.SCREEN_W), @intFromFloat(mouse.y), CONF.COLOR_CROSSHAIR);
    }
};
