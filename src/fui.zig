const std = @import("std");
const c = @cImport({
    @cInclude("fenster.h");
});
const Vec2 = @import("math.zig").Vec2;
const Mouse = @import("math.zig").Mouse;
const Rect = @import("math.zig").Rect;
const CONF = @import("config.zig").CONF;
const Palette = @import("palette.zig").Palette;
const DB16 = @import("palette.zig").DB16;
const Font = @import("font.zig").Font;
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
        self.buf[index] = color;
    }

    pub fn get_pixel(self: *Fui, x: i32, y: i32) u32 {
        const index: u32 = @intCast(y * CONF.SCREEN_W + x);
        return self.buf[index];
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
        if (w <= 0 or h <= 0) return;

        var rx = x;
        var ry = y;
        var rw = w;
        var rh = h;

        // Crop left
        if (rx < 0) {
            rw += rx;
            rx = 0;
        }
        // Crop top
        if (ry < 0) {
            rh += ry;
            ry = 0;
        }
        // Crop right
        if (rx + rw > CONF.SCREEN_W) {
            rw = CONF.SCREEN_W - rx;
        }
        // Crop bottom
        if (ry + rh > CONF.SCREEN_H) {
            rh = CONF.SCREEN_H - ry;
        }

        if (rw <= 0 or rh <= 0) return;

        const ix: u32 = @intCast(rx);
        const iy: u32 = @intCast(ry);
        const iw: u32 = @intCast(rw);
        const ih: u32 = @intCast(rh);

        for (iy..(iy + ih)) |row| {
            for (ix..(ix + iw)) |col| {
                self.put_pixel(@intCast(col), @intCast(row), color);
            }
        }
    }
    pub fn draw_rect_trans(self: *Fui, x: i32, y: i32, w: i32, h: i32, color: u32) void {
        if (w <= 0 or h <= 0) return;

        var rx = x;
        var ry = y;
        var rw = w;
        var rh = h;

        // Crop left
        if (rx < 0) {
            rw += rx;
            rx = 0;
        }
        // Crop top
        if (ry < 0) {
            rh += ry;
            ry = 0;
        }
        // Crop right
        if (rx + rw > CONF.SCREEN_W) {
            rw = CONF.SCREEN_W - rx;
        }
        // Crop bottom
        if (ry + rh > CONF.SCREEN_H) {
            rh = CONF.SCREEN_H - ry;
        }

        if (rw <= 0 or rh <= 0) return;

        const ix: u32 = @intCast(rx);
        const iy: u32 = @intCast(ry);
        const iw: u32 = @intCast(rw);
        const ih: u32 = @intCast(rh);

        for (iy..(iy + ih)) |row| {
            for (ix..(ix + iw)) |col| {
                const local_row = row - iy;
                const local_col = col - ix;
                if (local_row % 2 == local_col % 2) {
                    self.put_pixel(@intCast(col), @intCast(row), color);
                }
            }
        }
    }
    pub fn draw_rect_lines(self: *Fui, x: i32, y: i32, w: i32, h: i32, color: u32) void {
        if (w <= 0 or h <= 0) return;
        self.draw_line(x, y, x + w - 1, y, color);
        self.draw_line(x, y + h - 1, x + w - 1, y + h - 1, color);
        self.draw_line(x, y, x, y + h - 1, color);
        self.draw_line(x + w - 1, y, x + w - 1, y + h - 1, color);
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
    pub fn draw_text(self: *Fui, s: []const u8, x: i32, y: i32, scale: i32, color: u32) void {
        var px = x;
        for (s) |chr| {
            if (chr >= 32 and chr < 95 + 32) {
                const bmh = Font[chr - 32];
                var dy: i32 = 0;
                while (dy < 5) : (dy += 1) {
                    var dx: i32 = 0;
                    while (dx < 3) : (dx += 1) {
                        const bit: u4 = @intCast(dy * 3 + dx);
                        if ((bmh >> bit) & 1 != 0) {
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
    pub fn text_length(self: *Fui, s: []const u8, scale: i32) i32 {
        _ = self;
        const len: i32 = @intCast(s.len);
        return len * scale * CONF.FONT_WIDTH + (len - 2) * scale;
    }
    pub fn text_center(self: *Fui, s: []const u8, scale: i32) Vec2 {
        _ = self;
        const len: i32 = @intCast(s.len);
        return Vec2.init(@divFloor(len * scale * CONF.FONT_WIDTH + (len - 2) * scale, 2), @divFloor(scale * CONF.FONT_HEIGHT, 2));
    }
    pub fn draw_cursor_lines(self: *Fui, mouse: Vec2) void {
        self.draw_line(mouse.x, 0, mouse.x, CONF.SCREEN_H, CONF.COLOR_CROSSHAIR);
        self.draw_line(0, mouse.y, CONF.SCREEN_W, mouse.y, CONF.COLOR_CROSSHAIR);
    }
    pub fn button(self: *Fui, x: i32, y: i32, w: i32, h: i32, label: [:0]const u8, color: u32, mouse: Mouse) bool {
        const hover = self.check_hover(mouse, Rect.init(w, h, x, y));
        const hover_color = if (hover) CONF.COLOR_MENU_FRAME_HOVER else CONF.COLOR_MENU_FRAME;
        const text_cener = self.text_center(label, CONF.FONT_DEFAULT_SIZE);
        const text_x: i32 = x + @divFloor(w, 2) - text_cener.x;
        const text_y: i32 = y + @divFloor(h, 2) - text_cener.y;

        // self.draw_rect(x + CONF.SHADOW, y + CONF.SHADOW, w, h, CONF.COLOR_SHADOW);
        self.draw_rect(x, y, w, h, color);
        self.draw_rect_lines(x, y, w, h, hover_color);
        self.draw_text(label, text_x, text_y, CONF.FONT_DEFAULT_SIZE, if (hover) CONF.COLOR_MENU_FRAME_HOVER else CONF.COLOR_MENU_TEXT);

        return mouse.pressed and hover;
    }
    pub fn check_hover(self: *Fui, mouse: Mouse, target: Rect) bool {
        _ = self;
        return mouse.x >= target.x and mouse.x < target.x + target.w and
            mouse.y >= target.y and mouse.y < target.y + target.h;
    }
    pub fn draw_version(self: *Fui) void {
        const len = self.text_length(CONF.VERSION, CONF.FONT_DEFAULT_SIZE);
        const ver_x: i32 = self.pivots[PIVOTS.BOTTOM_RIGHT].x - len;
        const ver_y: i32 = self.pivots[PIVOTS.BOTTOM_RIGHT].y;
        self.draw_text(CONF.VERSION, ver_x, ver_y, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_SECONDARY);
    }
    fn draw_base_popup(self: *Fui, message: [:0]const u8, bg_color: u32) Rect {
        const text_width: i32 = self.text_length(message, CONF.FONT_DEFAULT_SIZE);
        const popup_size = Vec2.init(if (text_width < 256) 256 else text_width + 128, 128);
        const center = Vec2.init(self.pivots[PIVOTS.CENTER].x, self.pivots[PIVOTS.CENTER].y);
        const popup_corner = Vec2.init(center.x - @divFloor(popup_size.x, 2), center.y - @divFloor(popup_size.y, 2));

        const text_x: i32 = popup_corner.x + @divFloor(popup_size.x - text_width, 2);
        const text_y: i32 = popup_corner.y + 24;

        const x: i32 = popup_corner.x;
        const y: i32 = popup_corner.y;
        const w: i32 = popup_size.x;
        const h: i32 = popup_size.y;

        self.draw_rect(x + 8, y + 8, w, h, CONF.COLOR_SHADOW);
        self.draw_rect(x, y, w, h, bg_color);
        self.draw_rect_lines(x, y, w, h, CONF.COLOR_LIGHT);
        self.draw_text(message, text_x, text_y, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_POPUP_MSG);
        return Rect.init(popup_size.x, popup_size.y, popup_corner.x, popup_corner.y);
    }
    pub fn info_popup(self: *Fui, message: [:0]const u8, mouse: Mouse, bg_color: u32) ?bool {
        // Popup
        const popupv4: Rect = self.draw_base_popup(message, bg_color);
        const popup_corner = Vec2.init(popupv4.x, popupv4.y);
        const popup_height = popupv4.h;

        // Button
        const button_height = 32;
        const button_width = 80;
        const button_x = self.pivots[PIVOTS.CENTER].x - @divFloor(button_width, 2);
        const button_y = popup_corner.y + popup_height - 50;
        const ok_clicked = self.button(button_x, button_y, button_width, button_height, "OK", CONF.COLOR_OK, mouse);
        if (ok_clicked) return true;
        return null;
    }
    pub fn yes_no_popup(self: *Fui, message: [:0]const u8, mouse: Mouse) ?bool {
        // Popup
        const popupv4: Rect = self.draw_base_popup(message, CONF.COLOR_POPUP);
        const popup_corner = Vec2.init(popupv4.x, popupv4.y);
        const popup_size = Vec2.init(popupv4.w, popupv4.h);

        // buttons
        const button_y = popup_corner.y + popup_size.y - 50;
        const button_height = 32;
        const button_width = 80;
        const no_x = popup_corner.x + 24;
        const yes_x = popup_corner.x + popup_size.x - 80 - 24;

        const yes_clicked = self.button(yes_x, button_y, button_width, button_height, "Yes", CONF.COLOR_YES, mouse);
        if (yes_clicked) return true;

        const no_clicked = self.button(no_x, button_y, button_width, button_height, "No", CONF.COLOR_NO, mouse);
        if (no_clicked) return false;

        return null;
    }
};
