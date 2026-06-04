const std = @import("std");
const CONF = @import("../engine/config.zig").CONF;
const render_mod = @import("../engine/render.zig");
const Render = render_mod.Render;
const Mouse = @import("../engine/mouse.zig").Mouse;
const Project = @import("project.zig").Project;
const Tool = @import("project.zig").Tool;
const ColorChannel = @import("project.zig").ColorChannel;
const views = @import("views.zig");

pub const State = enum { splash, editor, tile_library, quit };

pub const LibraryMode = enum { choose_slot, swap_tile };

pub const LibraryRequest = struct {
    mode: LibraryMode,
    slot_index: u8,
    tile_id: u16,
};

const UI = struct {
    const bg = 0x121619;
    const panel = 0x1B2026;
    const panel_dark = 0x14191E;
    const panel_hi = 0x2B323A;
    const border = 0x3B434C;
    const border_dark = 0x090B0D;
    const text = 0xF0F0F0;
    const muted = 0xB7BBC0;
    const accent = 0x7EDB1E;
    const accent_dark = 0x486E10;
    const danger = 0xFF4040;
    const blue = 0x5EA8FF;

    const margin: i32 = 8;
    const top_h: i32 = 82;
    const status_h: i32 = 0;
    const side_x: i32 = 14;
    const gap: i32 = 8;
    const left_w: i32 = 298;
    const right_w: i32 = 312;
    const content_y: i32 = 110;
    const draw_mode_y: i32 = 110;
    const palette_y: i32 = 224;
    const preview_y: i32 = 370;
    const info_y: i32 = 570;
    const file_y: i32 = 706;
    const center_info_h: i32 = 136;

    fn leftX() i32 {
        return side_x;
    }
    fn rightX() i32 {
        return CONF.SCREEN_W - side_x - right_w;
    }
    fn centerX() i32 {
        return leftX() + left_w + gap;
    }
    fn centerW() i32 {
        return rightX() - centerX() - gap;
    }
    fn contentH() i32 {
        return 580;
    }
    fn centerInfoY() i32 {
        return UI.content_y + contentH() + 12;
    }
    fn statusY() i32 {
        return CONF.SCREEN_H - status_h - 8;
    }
};

pub const MainEditor = struct {
    tool: Tool = .pixel,
    line_start: ?[2]i32 = null,
    library_request: ?LibraryRequest = null,
    save_error: bool = false,
    export_notice: bool = false,
    suppress_canvas_paint_until_mouse_up: bool = false,
    info_text: []const u8 = "Ready",
    info_color: u32 = UI.muted,
    ui_cache_dirty: bool = true,

    pub fn draw(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, sm: anytype) void {
        self.handleCanvas(fui, project, mouse);
        if (self.ui_cache_dirty) {
            const previous_target = renderer.target;
            renderer.set_target(.terrain);
            drawStaticUi(fui, renderer);
            renderer.set_target(previous_target);
            self.ui_cache_dirty = false;
        }
        renderer.copy_buffer(.terrain, .frame);
        self.drawTopBar(fui, renderer, project, mouse, sm);
        self.drawLeftPanel(fui, renderer, project, mouse, sm);
        self.drawCenterPanel(fui, renderer, project, mouse, sm);
        self.drawRightPanel(fui, renderer, project, mouse);
    }

    fn handleCanvas(self: *MainEditor, fui: anytype, project: *Project, mouse: Mouse) void {
        if (self.suppress_canvas_paint_until_mouse_up) {
            if (!mouse.left_down and !mouse.right_down) self.suppress_canvas_paint_until_mouse_up = false;
            return;
        }
        const cell = canvasCell(fui, mouse.x, mouse.y) orelse return;
        const paint_color = if (mouse.right_down) project.rightColor() else project.leftColor();
        if (mouse.left_down or mouse.right_down) {
            switch (self.tool) {
                .pixel => project.paintPixel(@intCast(cell[0]), @intCast(cell[1]), paint_color),
                .fill => if (mouse.just_pressed or mouse.just_right_pressed) project.fill(@intCast(cell[0]), @intCast(cell[1]), paint_color),
                .line => if (mouse.just_pressed or mouse.just_right_pressed) {
                    if (self.line_start) |start| {
                        project.drawLine(start[0], start[1], cell[0], cell[1], paint_color);
                        self.line_start = null;
                    } else {
                        self.line_start = cell;
                    }
                },
            }
        }
    }

    fn drawTopBar(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, sm: anytype) void {
        drawPixelText(fui, renderer, CONF.THE_NAME, UI.leftX() + 26, 52, 3, UI.text);

        if (tabButton(fui, renderer, mouse, 396, 43, 144, 46, "EDITOR", project.mode == .tiles)) project.setMode(.tiles);
        if (tabButton(fui, renderer, mouse, 548, 43, 156, 46, "SPRITES", project.mode == .sprites)) project.setMode(.sprites);
        if (tabButton(fui, renderer, mouse, 712, 43, 190, 46, "MAP EDITOR", false)) {}

        const tx: i32 = UI.rightX() + UI.right_w - 192;
        if (pillButton(fui, renderer, mouse, tx, 43, 86, 46, "SAVE", project.dirty)) {
            project.save() catch {
                self.setInfo("Save failed", UI.danger);
                return;
            };
            self.save_error = false;
            self.export_notice = false;
            self.setInfo("File saved", UI.accent);
        }
        if (pillButton(fui, renderer, mouse, tx + 98, 43, 86, 46, "QUIT", false)) sm.go_to(.quit);
    }

    fn drawLeftPanel(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, sm: anytype) void {
        const x = UI.leftX();
        if (pillButton(fui, renderer, mouse, x + 22, UI.draw_mode_y + 52, 76, 36, "PIXEL", self.tool == .pixel)) self.tool = .pixel;
        if (pillButton(fui, renderer, mouse, x + 112, UI.draw_mode_y + 52, 76, 36, "FILL", self.tool == .fill)) self.tool = .fill;
        if (pillButton(fui, renderer, mouse, x + 202, UI.draw_mode_y + 52, 76, 36, "LINE", self.tool == .line)) self.tool = .line;

        drawCurrentPalette(fui, renderer, project, mouse, x + 24, UI.palette_y + 56, self);

        drawPixelText(fui, renderer, "TILE PREVIEW", x + 22, UI.preview_y + 22, 2, UI.text);
        drawTileSlots(self, fui, renderer, project, mouse, sm, x + 88, UI.preview_y + 60, 40);

        drawPixelText(fui, renderer, "EDITED TILE ID:", x + 24, UI.info_y + 54, 1, UI.muted);
        drawNumber(fui, renderer, project.selectedImageId(), x + 24, UI.info_y + 78, 0xD5F8A5);
        drawPixelText(fui, renderer, "NON-EMPTY TILES:", x + 124, UI.info_y + 54, 1, UI.muted);
        drawCount(fui, renderer, project.nonEmptyTiles(), project.imageCount(), x + 124, UI.info_y + 78);

        if (pillButton(fui, renderer, mouse, x + 24, UI.file_y + 54, 112, 36, "SAVE", project.dirty)) {
            project.save() catch {
                self.save_error = true;
                self.setInfo("Save failed", UI.danger);
                return;
            };
            self.save_error = false;
            self.export_notice = false;
            self.setInfo("File saved", UI.accent);
        }
        if (pillButton(fui, renderer, mouse, x + 150, UI.file_y + 54, 112, 36, "EXPORT", false)) {
            self.export_notice = true;
            self.setInfo("Export not implemented", 0xDAD45E);
        }
    }

    fn drawCenterPanel(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, sm: anytype) void {
        _ = sm;
        var title_buf: [8]u8 = undefined;
        const id_text = std.fmt.bufPrint(&title_buf, "{d}", .{project.selectedImageId()}) catch "?";
        const title_x = UI.centerX() + @divFloor(UI.centerW() - fui.text_length("TILE ID: 000", 2), 2);
        drawPixelText(fui, renderer, "TILE ID:", title_x, 134, 2, UI.text);
        drawPixelText(fui, renderer, id_text, title_x + 142, 134, 2, UI.accent);

        drawCanvas(self, fui, renderer, project, mouse);

        drawInfoPanel(fui, renderer, self);
    }

    fn drawRightPanel(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse) void {
        drawPalettes(fui, renderer, project, mouse, UI.rightX() + 72, 162, self);
        drawColorEditor(fui, renderer, project, mouse, UI.rightX() + 22, 596, self);
    }

    fn setInfo(self: *MainEditor, text: []const u8, color: u32) void {
        self.info_text = text;
        self.info_color = color;
    }
};

fn drawStaticUi(fui: anytype, renderer: *Render) void {
    renderer.clear_background(UI.bg);
    panel(renderer, UI.leftX(), 24, CONF.SCREEN_W - UI.leftX() * 2, UI.top_h);
    drawStaticPanelFrames(fui, renderer);
}

fn drawStaticPanelFrames(fui: anytype, renderer: *Render) void {
    const x = UI.leftX();
    sectionPanel(renderer, x, UI.draw_mode_y, UI.left_w, 104, "DRAW MODE", fui);
    sectionPanel(renderer, x, UI.palette_y, UI.left_w, 134, "CURRENT PALETTE", fui);
    sectionPanel(renderer, x, UI.preview_y, UI.left_w, 186, "", fui);
    sectionPanel(renderer, x, UI.info_y, UI.left_w, 116, "TILE INFO", fui);
    sectionPanel(renderer, x, UI.file_y, UI.left_w, 110, "FILE", fui);

    panel(renderer, UI.centerX(), UI.content_y, UI.centerW(), UI.contentH());
    sectionPanel(renderer, UI.centerX(), UI.centerInfoY(), UI.centerW(), UI.center_info_h, "INFO", fui);

    sectionPanel(renderer, UI.rightX(), 110, UI.right_w, 430, "PALETTE BROWSER", fui);
    sectionPanel(renderer, UI.rightX(), 544, UI.right_w, 256, "EDITED COLOURS", fui);
}

fn panel(renderer: *Render, x: i32, y: i32, w: i32, h: i32) void {
    if (w <= 0 or h <= 0) return;
    renderer.draw_rect(x + 3, y + 3, w, h, 0x07090B);
    renderer.draw_rect(x, y, w, h, UI.panel);
    renderer.draw_rect_lines(x, y, w, h, UI.border_dark);
    renderer.draw_rect_lines(x + 1, y + 1, w - 2, h - 2, UI.border);
}

fn sectionPanel(renderer: *Render, x: i32, y: i32, w: i32, h: i32, title: []const u8, fui: anytype) void {
    panel(renderer, x, y, w, h);
    if (title.len > 0) drawPixelText(fui, renderer, title, x + 22, y + 22, 2, UI.text);
}

fn drawInfoPanel(fui: anytype, renderer: *Render, editor: *const MainEditor) void {
    drawPixelText(fui, renderer, editor.info_text, UI.centerX() + 24, UI.centerInfoY() + 56, 1, editor.info_color);
}

fn drawPixelText(fui: anytype, renderer: *Render, text: []const u8, x: i32, y: i32, scale: i32, color: u32) void {
    fui.draw_text(renderer, text, x, y, scale, color);
}

fn tabButton(fui: anytype, renderer: *Render, mouse: Mouse, x: i32, y: i32, w: i32, h: i32, label: [:0]const u8, active: bool) bool {
    const over = views.hover(mouse, x, y, w, h);
    const bg: u32 = if (active) UI.accent_dark else UI.panel_hi;
    renderer.draw_rect(x + 2, y + 2, w, h, 0x080A0C);
    renderer.draw_rect(x, y, w, h, if (over) lighten(bg) else bg);
    renderer.draw_rect_lines(x, y, w, h, if (active) UI.accent else UI.border_dark);
    renderer.draw_rect_lines(x + 1, y + 1, w - 2, h - 2, if (active) 0xC7FF5B else UI.border);
    const tw = fui.text_length(label, 2);
    fui.draw_text(renderer, label, x + @divFloor(w - tw, 2), y + 14, 2, if (active) 0xD9F99A else UI.muted);
    return over and mouse.just_pressed;
}

fn pillButton(fui: anytype, renderer: *Render, mouse: Mouse, x: i32, y: i32, w: i32, h: i32, label: [:0]const u8, active: bool) bool {
    const over = views.hover(mouse, x, y, w, h);
    const bg: u32 = if (active) UI.accent_dark else UI.panel_hi;
    renderer.draw_rect(x + 2, y + 2, w, h, 0x090B0D);
    renderer.draw_rect(x, y, w, h, if (over) lighten(bg) else bg);
    renderer.draw_rect_lines(x, y, w, h, if (active) UI.accent else UI.border_dark);
    renderer.draw_rect_lines(x + 1, y + 1, w - 2, h - 2, if (active) 0xC7FF5B else UI.border);
    const tw = fui.text_length(label, 1);
    fui.draw_text(renderer, label, x + @divFloor(w - tw, 2), y + @divFloor(h - CONF.FONT_HEIGHT, 2), 1, if (active) 0xE8FFD2 else UI.text);
    return over and mouse.just_pressed;
}

fn iconButton(renderer: *Render, mouse: Mouse, x: i32, y: i32, label: [:0]const u8, active: bool) bool {
    const size: i32 = 44;
    const over = views.hover(mouse, x, y, size, size);
    const bg: u32 = if (active) UI.accent_dark else UI.panel_hi;
    renderer.draw_rect(x + 2, y + 2, size, size, 0x07090B);
    renderer.draw_rect(x, y, size, size, if (over) lighten(bg) else bg);
    renderer.draw_rect_lines(x, y, size, size, if (active) UI.accent else UI.border_dark);
    renderer.draw_rect_lines(x + 1, y + 1, size - 2, size - 2, UI.border);
    drawDummyIcon(renderer, x + 11, y + 11, label, if (active) UI.accent else UI.text);
    return over and mouse.just_pressed;
}

fn miniButton(renderer: *Render, mouse: Mouse, x: i32, y: i32, label: [:0]const u8) bool {
    _ = label;
    const w: i32 = 30;
    const h: i32 = 24;
    const over = views.hover(mouse, x, y, w, h);
    renderer.draw_rect(x + 2, y + 2, w, h, 0x07090B);
    renderer.draw_rect(x, y, w, h, if (over) lighten(UI.panel_hi) else UI.panel_hi);
    renderer.draw_rect_lines(x, y, w, h, UI.border_dark);
    renderer.draw_rect(x + 10, y + 11, 10, 2, UI.text);
    renderer.draw_rect(x + 14, y + 7, 2, 10, UI.text);
    return over and mouse.just_pressed;
}

fn drawDummyIcon(renderer: *Render, x: i32, y: i32, label: [:0]const u8, color: u32) void {
    _ = label;
    renderer.draw_rect(x + 8, y, 8, 20, color);
    renderer.draw_rect(x, y + 8, 24, 8, color);
    renderer.draw_rect(x + 4, y + 4, 16, 16, 0x000000);
    renderer.draw_rect(x + 8, y + 8, 8, 8, color);
}

fn drawCurrentPalette(fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, x: i32, y: i32, editor: *MainEditor) void {
    for (0..CONF.COLORS_PER_PALETTE) |i| {
        const sx = x + @as(i32, @intCast(i)) * 48;
        renderer.draw_rect(sx, y, 44, 44, if (project.isTransparentColor(@intCast(i))) 0x303030 else project.currentColor32(@intCast(i)));
        renderer.draw_rect_lines(sx, y, 44, 44, UI.border_dark);
        if (project.isTransparentColor(@intCast(i))) renderer.draw_line(sx, y + 43, sx + 43, y, UI.text);
        if (views.hover(mouse, sx, y, 44, 44)) {
            if (mouse.just_pressed) {
                project.setLeftColor(@intCast(i));
                editor.setInfo("Left color selected", UI.accent);
            }
            if (mouse.just_right_pressed) {
                project.setRightColor(@intCast(i));
                editor.setInfo("Right color selected", UI.accent);
            }
        }
        if (project.leftColor() == i) renderer.draw_rect_lines(sx + 3, y + 3, 38, 38, UI.accent);
        if (project.rightColor() == i) renderer.draw_rect_lines(sx + 7, y + 7, 30, 30, UI.text);
    }

    const left_x = x + @as(i32, @intCast(project.leftColor())) * 48;
    const right_x = x + @as(i32, @intCast(project.rightColor())) * 48;
    if (project.leftColor() == project.rightColor()) {
        _ = pillButton(fui, renderer, mouse, left_x, y + 52, 44, 24, "LR", false);
    } else {
        _ = pillButton(fui, renderer, mouse, left_x, y + 52, 44, 24, "L", false);
        _ = pillButton(fui, renderer, mouse, right_x, y + 52, 44, 24, "R", false);
    }
}

fn drawCanvas(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse) void {
    const tile = project.currentImage();
    const origin = canvasOrigin(fui);
    renderer.draw_rect(origin[0] - 2, origin[1] - 2, CONF.TILE_SIDE * CONF.EDITOR_CANVAS_SCALE + 4, CONF.TILE_SIDE * CONF.EDITOR_CANVAS_SCALE + 4, 0xE6F5D8);
    var py: usize = 0;
    while (py < CONF.TILE_SIDE) : (py += 1) {
        var px: usize = 0;
        while (px < CONF.TILE_SIDE) : (px += 1) {
            const idx = tile.pixels[py * CONF.TILE_SIDE + px];
            const color = if (project.isTransparentColor(idx)) checker(px, py) else project.currentColor32(idx);
            const x = origin[0] + @as(i32, @intCast(px)) * CONF.EDITOR_CANVAS_SCALE;
            const y = origin[1] + @as(i32, @intCast(py)) * CONF.EDITOR_CANVAS_SCALE;
            renderer.draw_rect(x, y, CONF.EDITOR_CANVAS_SCALE, CONF.EDITOR_CANVAS_SCALE, color);
            renderer.draw_rect_lines(x, y, CONF.EDITOR_CANVAS_SCALE, CONF.EDITOR_CANVAS_SCALE, 0xD7EBCB);
        }
    }
    if (self.tool == .line) if (self.line_start) |start| if (canvasCell(fui, mouse.x, mouse.y)) |end| {
        const half = @divFloor(CONF.EDITOR_CANVAS_SCALE, 2);
        renderer.draw_line(origin[0] + start[0] * CONF.EDITOR_CANVAS_SCALE + half, origin[1] + start[1] * CONF.EDITOR_CANVAS_SCALE + half, origin[0] + end[0] * CONF.EDITOR_CANVAS_SCALE + half, origin[1] + end[1] * CONF.EDITOR_CANVAS_SCALE + half, 0x202020);
    };
    renderer.draw_rect_lines(origin[0], origin[1], CONF.TILE_SIDE * CONF.EDITOR_CANVAS_SCALE, CONF.TILE_SIDE * CONF.EDITOR_CANVAS_SCALE, UI.border_dark);
}

fn drawTileSlots(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, sm: anytype, x0: i32, y0: i32, slot: i32) void {
    _ = fui;
    const tile_scale = @divFloor(slot, CONF.TILE_SIDE);
    for (0..9) |i| {
        const cx: i32 = @intCast(i % 3);
        const cy: i32 = @intCast(i / 3);
        const x = x0 + cx * slot;
        const y = y0 + cy * slot;
        const tile_id = project.visibleSlot(i);
        renderer.draw_rect(x, y, slot, slot, UI.panel_hi);
        if (tile_id < project.imageCount()) views.drawTile(renderer, project, tile_id, x, y, tile_scale);
        if (views.hover(mouse, x, y, slot, slot)) {
            renderer.draw_rect_lines(x, y, slot, slot, UI.text);
            renderer.draw_rect_lines(x + 1, y + 1, slot - 2, slot - 2, UI.accent);
            if (mouse.just_pressed and tile_id < project.imageCount()) project.selectTile(tile_id);
            if (mouse.just_right_pressed) {
                self.library_request = .{ .mode = .swap_tile, .slot_index = @intCast(i), .tile_id = tile_id };
                sm.go_to(.tile_library);
            }
        }
    }
}

fn drawPalettes(fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, x0: i32, y0: i32, editor: *MainEditor) void {
    const sw: i32 = 50;
    const sh: i32 = 36;
    const row_h: i32 = 46;
    for (0..CONF.PALETTE_COUNT) |p| {
        const y = y0 + @as(i32, @intCast(p)) * row_h;
        var label_buf: [4]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buf, "{d}", .{p}) catch "?";
        if (project.selectedPalette() == p) drawPixelText(fui, renderer, ">", x0 - 64, y + 10, 2, UI.text);
        drawPixelText(fui, renderer, label, x0 - 40, y + 12, 2, UI.text);
        renderer.draw_rect(x0 - 2, y - 2, sw * CONF.COLORS_PER_PALETTE + 4, sh + 4, UI.border_dark);
        for (0..CONF.COLORS_PER_PALETTE) |color_slot| {
            const x = x0 + @as(i32, @intCast(color_slot)) * sw;
            renderer.draw_rect(x, y, sw, sh, if (project.isTransparentColor(@intCast(color_slot))) 0x303030 else project.color32(@intCast(p), @intCast(color_slot)));
            renderer.draw_rect_lines(x, y, sw, sh, UI.border_dark);
            if (project.isTransparentColor(@intCast(color_slot))) renderer.draw_line(x, y + sh - 1, x + sw - 1, y, UI.text);
            if (project.selectedPalette() == p and project.selectedColor() == color_slot) {
                renderer.draw_rect_lines(x + 4, y + 4, sw - 8, sh - 8, UI.accent);
                renderer.draw_rect_lines(x + 8, y + 8, sw - 16, sh - 16, UI.text);
            }
            if (views.hover(mouse, x, y, sw, sh) and (mouse.just_pressed or mouse.just_right_pressed)) {
                project.setPaletteSelection(@intCast(p), @intCast(color_slot));
                editor.setInfo("Palette color selected", UI.accent);
            }
        }
    }
}

fn drawColorEditor(fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, x: i32, y: i32, editor: *MainEditor) void {
    const selected_color = project.color32(project.selectedPalette(), project.selectedColor());
    renderer.draw_rect(x, y, 72, 48, selected_color);
    renderer.draw_rect_lines(x, y, 72, 48, UI.text);

    var title_buf: [32]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buf, "P{d} C{d}", .{ project.selectedPalette(), project.selectedColor() }) catch "P? C?";
    drawPixelText(fui, renderer, title, x + 86, y + 12, 2, UI.text);

    const rgb = selectedRgb(project);
    drawChannelEditor(fui, renderer, project, mouse, .r, "R", rgb[0], x, y + 54, UI.danger, editor);
    drawChannelEditor(fui, renderer, project, mouse, .g, "G", rgb[1], x, y + 82, UI.accent, editor);
    drawChannelEditor(fui, renderer, project, mouse, .b, "B", rgb[2], x, y + 110, UI.blue, editor);
}

fn drawChannelEditor(fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, channel: ColorChannel, label: [:0]const u8, value: u8, x: i32, y: i32, color: u32, editor: *MainEditor) void {
    drawPixelText(fui, renderer, label, x, y + 8, 2, color);
    renderer.draw_rect(x + 32, y + 15, 144, 6, UI.border);
    renderer.draw_rect(x + 32, y + 15, @divFloor(@as(i32, value) * 144, 255), 6, color);
    const knob_x = x + 32 + @divFloor(@as(i32, value) * 144, 255) - 5;
    renderer.draw_rect(knob_x, y + 10, 10, 16, UI.text);
    if (views.hover(mouse, x + 32, y + 4, 144, 28) and (mouse.left_down or mouse.right_down)) {
        const rel = @max(0, @min(143, mouse.x - (x + 32)));
        const target = @divFloor(rel * 255, 143);
        const delta: i16 = @as(i16, @intCast(target)) - @as(i16, @intCast(value));
        if (delta != 0) {
            project.adjustSelectedRgb(channel, delta);
            editor.setInfo("Color updated", UI.accent);
        }
    }
    var buf: [4]u8 = undefined;
    const value_text = std.fmt.bufPrint(&buf, "{d}", .{value}) catch "?";
    drawPixelText(fui, renderer, value_text, x + 188, y + 8, 2, UI.text);
    if (miniButton(renderer, mouse, x + 246, y + 4, "+")) {
        project.adjustSelectedRgb(channel, 1);
        editor.setInfo("Color updated", UI.accent);
    }
}

fn drawBottomStatus(fui: anytype, renderer: *Render, project: *const Project, save_error: bool, export_notice: bool) void {
    const y = UI.statusY();
    renderer.draw_rect(30, y, CONF.SCREEN_W - 60, UI.status_h, UI.panel_dark);
    renderer.draw_rect_lines(30, y, CONF.SCREEN_W - 60, UI.status_h, UI.border_dark);
    drawPixelText(fui, renderer, "ROM: GAME.ROM", 40, y + 11, 1, UI.text);
    drawPixelText(fui, renderer, "MODE:", 292, y + 11, 1, UI.text);
    renderer.draw_circle(362, y + 15, 5, UI.accent);
    drawPixelText(fui, renderer, if (project.mode == .tiles) "TILES" else "SPRITES", 382, y + 11, 1, UI.accent);
    drawPixelText(fui, renderer, "TILESET: 0x4000", 526, y + 11, 1, UI.text);
    const status = if (save_error) "SAVE FAILED" else if (export_notice) "EXPORT TODO" else if (project.dirty) "UNSAVED" else "READY";
    const status_color: u32 = if (save_error) UI.danger else if (project.dirty) 0xDAD45E else UI.accent;
    const sx = CONF.SCREEN_W - 42 - fui.text_length(status, 1);
    drawPixelText(fui, renderer, status, sx, y + 11, 1, status_color);
}

fn selectedRgb(project: *const Project) [3]u8 {
    return project.selectedRgb();
}

fn canvasCell(fui: anytype, x: i32, y: i32) ?[2]i32 {
    const origin = canvasOrigin(fui);
    const size = CONF.TILE_SIDE * CONF.EDITOR_CANVAS_SCALE;
    if (!views.hover(.{ .x = x, .y = y, .left_down = false, .right_down = false, .just_pressed = false, .just_right_pressed = false }, origin[0], origin[1], size, size)) return null;
    return .{ @divFloor(x - origin[0], CONF.EDITOR_CANVAS_SCALE), @divFloor(y - origin[1], CONF.EDITOR_CANVAS_SCALE) };
}

fn canvasOrigin(fui: anytype) [2]i32 {
    _ = fui;
    const size = CONF.TILE_SIDE * CONF.EDITOR_CANVAS_SCALE;
    return .{ UI.centerX() + @divFloor(UI.centerW() - size, 2), 170 };
}

fn checker(x: usize, y: usize) u32 {
    return if ((x + y) % 2 == 0) 0xF0F0F0 else 0xFFFFFF;
}

fn drawNumber(fui: anytype, renderer: *Render, n: anytype, x: i32, y: i32, color: u32) void {
    var buf: [8]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{n}) catch "?";
    fui.draw_text(renderer, text, x, y, 3, color);
}

fn drawCount(fui: anytype, renderer: *Render, n: u16, total: u16, x: i32, y: i32) void {
    var buf: [24]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d} / {d}", .{ n, total }) catch "?";
    fui.draw_text(renderer, text, x, y, 3, 0xD5F8A5);
}

fn lighten(color: u32) u32 {
    const r: u32 = @min(255, ((color >> 16) & 0xFF) + 28);
    const g: u32 = @min(255, ((color >> 8) & 0xFF) + 28);
    const b: u32 = @min(255, (color & 0xFF) + 28);
    return (r << 16) | (g << 8) | b;
}
