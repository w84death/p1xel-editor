const CONF = @import("../engine/config.zig").CONF;
const Render = @import("../engine/render.zig").Render;
const Mouse = @import("../engine/mouse.zig").Mouse;
const views = @import("views.zig");

pub const TopTab = enum { tiles, sprites, map_editor };
pub const TopAction = enum { tiles, sprites, map_editor, save, quit };

pub const Theme = struct {
    pub const bg = 0x121619;
    pub const panel = 0x1B2026;
    pub const panel_dark = 0x14191E;
    pub const panel_hi = 0x2B323A;
    pub const border = 0x3B434C;
    pub const border_dark = 0x090B0D;
    pub const text = 0xF0F0F0;
    pub const muted = 0xB7BBC0;
    pub const accent = 0x7EDB1E;
    pub const accent_dark = 0x486E10;
    pub const danger = 0xFF4040;
    pub const warn = 0xDAD45E;
    pub const blue = 0x5EA8FF;
    pub const shadow = 0x050607;
};

pub const Layout = struct {
    pub const side_x: i32 = 14;
    pub const top_y: i32 = 24;
    pub const top_h: i32 = 82;
    pub const gap: i32 = 10;
    pub const left_w: i32 = 276;
    pub const right_w: i32 = 220;
    pub const content_y: i32 = 110;

    pub fn leftX() i32 {
        return side_x;
    }

    pub fn rightX() i32 {
        return CONF.SCREEN_W - side_x - right_w;
    }

    pub fn centerX() i32 {
        return leftX() + left_w + gap;
    }

    pub fn centerW() i32 {
        return rightX() - centerX() - gap;
    }

    pub fn contentH() i32 {
        return CONF.SCREEN_H - content_y - 22;
    }
};

pub fn drawText(fui: anytype, renderer: *Render, text: []const u8, x: i32, y: i32, scale: i32, color: u32) void {
    fui.draw_text(renderer, text, x, y, scale, color);
}

pub fn panel(renderer: *Render, x: i32, y: i32, w: i32, h: i32) void {
    if (w <= 0 or h <= 0) return;
    renderer.draw_rect(x + 3, y + 3, w, h, Theme.border_dark);
    renderer.draw_rect(x, y, w, h, Theme.panel);
    renderer.draw_rect_lines(x, y, w, h, Theme.border);
}

pub fn button(fui: anytype, renderer: *Render, mouse: Mouse, x: i32, y: i32, w: i32, h: i32, label: []const u8, active: bool) bool {
    return themedButton(fui, renderer, mouse, x, y, w, h, label, active, Theme.accent_dark, Theme.accent);
}

pub fn dangerButton(fui: anytype, renderer: *Render, mouse: Mouse, x: i32, y: i32, w: i32, h: i32, label: []const u8, active: bool) bool {
    return themedButton(fui, renderer, mouse, x, y, w, h, label, active, Theme.danger, Theme.danger);
}

pub fn drawTopBar(
    fui: anytype,
    renderer: *Render,
    mouse: Mouse,
    title: []const u8,
    active_tab: TopTab,
    dirty: bool,
    right_x: i32,
) ?TopAction {
    panel(renderer, 14, 24, CONF.SCREEN_W - 28, 82);
    drawText(fui, renderer, title, 38, 44, 3, Theme.text);

    if (button(fui, renderer, mouse, 396, 43, 144, 46, "TILES", active_tab == .tiles)) return .tiles;
    if (button(fui, renderer, mouse, 548, 43, 156, 46, "SPRITES", active_tab == .sprites)) return .sprites;
    if (button(fui, renderer, mouse, 712, 43, 190, 46, "MAP EDITOR", active_tab == .map_editor)) return .map_editor;

    const tx = right_x + 220 - 192;
    if (button(fui, renderer, mouse, tx, 43, 86, 46, "SAVE", dirty)) return .save;
    if (button(fui, renderer, mouse, tx + 98, 43, 86, 46, "QUIT", false)) return .quit;

    return null;
}

pub fn themedButton(
    fui: anytype,
    renderer: *Render,
    mouse: Mouse,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    label: []const u8,
    active: bool,
    active_bg: u32,
    active_border: u32,
) bool {
    const hovered = views.hover(mouse, x, y, w, h);
    const bg: u32 = if (active) active_bg else if (hovered) Theme.panel_hi else Theme.panel_dark;
    renderer.draw_rect(x + 2, y + 2, w, h, Theme.shadow);
    renderer.draw_rect(x, y, w, h, bg);
    renderer.draw_rect_lines(x, y, w, h, if (active) active_border else Theme.border);
    const tw = fui.text_length(label, 1);
    drawText(fui, renderer, label, x + @divFloor(w - tw, 2), y + @divFloor(h - CONF.FONT_HEIGHT, 2), 1, if (active) Theme.text else Theme.muted);
    return hovered and mouse.just_pressed;
}
