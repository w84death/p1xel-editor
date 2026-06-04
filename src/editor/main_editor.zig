const std = @import("std");
const CONF = @import("../engine/config.zig").CONF;
const render_mod = @import("../engine/render.zig");
const Render = render_mod.Render;
const Mouse = @import("../engine/mouse.zig").Mouse;
const Project = @import("project.zig").Project;
const Tool = @import("project.zig").Tool;
const ColorChannel = @import("project.zig").ColorChannel;
const views = @import("views.zig");

pub const State = enum { splash, editor, tile_library, map_editor, quit };

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

    const top_y: i32 = 24;
    const top_h: i32 = 82;
    const status_h: i32 = 0;
    const side_x: i32 = 14;
    const gap: i32 = 10;
    const left_w: i32 = 276;
    const right_w: i32 = 220;
    const content_y: i32 = 110;
    const side_panel_h: i32 = CONF.SCREEN_H - content_y - 22;
    const draw_mode_y: i32 = content_y + 18;
    const palette_y: i33 = content_y + 138;
    const preview_y: i32 = content_y + 286;
    const info_y: i32 = content_y + 500;
    const file_y: i32 = content_y + 622;
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
        return side_panel_h - center_info_h - 12;
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
    library_return_state: State = .editor,
    save_error: bool = false,
    export_notice: bool = false,
    suppress_canvas_paint_until_mouse_up: bool = false,
    info_text: []const u8 = "Ready",
    info_color: u32 = UI.muted,
    ui_cache_dirty: bool = true,
    cached_canvas_revision: u64 = std.math.maxInt(u64),

    pub fn draw(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, sm: anytype) void {
        self.handleCanvas(fui, project, mouse);
        if (self.ui_cache_dirty) {
            const previous_target = renderer.target;
            renderer.set_target(.terrain);
            drawStaticUi(fui, renderer);
            renderer.set_target(previous_target);
            self.cached_canvas_revision = std.math.maxInt(u64);
            self.ui_cache_dirty = false;
        }
        if (self.cached_canvas_revision != project.visualRevision()) {
            const previous_target = renderer.target;
            renderer.set_target(.terrain);
            drawCanvasBase(fui, renderer, project);
            renderer.set_target(previous_target);
            self.cached_canvas_revision = project.visualRevision();
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
                .pixel => {
                    _ = project.paintPixel(@intCast(cell[0]), @intCast(cell[1]), paint_color);
                },
                .fill => {
                    if (mouse.just_pressed or mouse.just_right_pressed) _ = project.fill(@intCast(cell[0]), @intCast(cell[1]), paint_color);
                },
                .line => if (mouse.just_pressed or mouse.just_right_pressed) {
                    if (self.line_start) |start| {
                        _ = project.drawLine(start[0], start[1], cell[0], cell[1], paint_color);
                        self.line_start = null;
                    } else {
                        self.line_start = cell;
                    }
                },
            }
        }
    }

    fn drawTopBar(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, sm: anytype) void {
        drawPixelText(fui, renderer, CONF.THE_NAME, 38, 44, 3, UI.text);

        if (tabButton(fui, renderer, mouse, 396, 43, 144, 46, "TILES", project.mode == .tiles)) project.setMode(.tiles);
        if (tabButton(fui, renderer, mouse, 548, 43, 156, 46, "SPRITES", project.mode == .sprites)) project.setMode(.sprites);
        if (tabButton(fui, renderer, mouse, 712, 43, 190, 46, "MAP EDITOR", false)) sm.go_to(.map_editor);

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
        drawPixelText(fui, renderer, "DRAW MODE", x + 16, UI.draw_mode_y, 2, UI.text);
        if (pillButton(fui, renderer, mouse, x + 16, UI.draw_mode_y + 30, 74, 34, "PIXEL", self.tool == .pixel)) self.tool = .pixel;
        if (pillButton(fui, renderer, mouse, x + 100, UI.draw_mode_y + 30, 70, 34, "FILL", self.tool == .fill)) self.tool = .fill;
        if (pillButton(fui, renderer, mouse, x + 180, UI.draw_mode_y + 30, 74, 34, "LINE", self.tool == .line)) self.tool = .line;

        drawPixelText(fui, renderer, "CURRENT PALETTE", x + 16, UI.palette_y, 2, UI.text);
        drawCurrentPalette(fui, renderer, project, mouse, x + 24, UI.palette_y + 34, self);

        drawPixelText(fui, renderer, "TILES MAP", x + 16, UI.preview_y, 2, UI.text);
        drawTileSlots(self, fui, renderer, project, mouse, sm, x + 76, UI.preview_y + 38, 40);
        drawPixelText(fui, renderer, "LMB: SELECT", x + 20, UI.preview_y + 176, 1, UI.muted);
        drawPixelText(fui, renderer, "RMB: LIBRARY", x + 136, UI.preview_y + 176, 1, UI.muted);

        drawPixelText(fui, renderer, "TILE INFO", x + 16, UI.info_y, 2, UI.text);
        drawPixelText(fui, renderer, "EDITED TILE ID:", x + 20, UI.info_y + 42, 1, UI.muted);
        drawNumber(fui, renderer, project.selectedImageId(), x + 20, UI.info_y + 64, 0xD5F8A5);
        drawPixelText(fui, renderer, "NON-EMPTY TILES:", x + 124, UI.info_y + 42, 1, UI.muted);
        drawCount(fui, renderer, project.nonEmptyTiles(), project.imageCount(), x + 124, UI.info_y + 64);

        drawPixelText(fui, renderer, "FILE", x + 16, UI.file_y, 2, UI.text);
        if (pillButton(fui, renderer, mouse, x + 16, UI.file_y + 34, 112, 36, "SAVE", project.dirty)) {
            project.save() catch {
                self.save_error = true;
                self.setInfo("Save failed", UI.danger);
                return;
            };
            self.save_error = false;
            self.export_notice = false;
            self.setInfo("File saved", UI.accent);
        }
        if (pillButton(fui, renderer, mouse, x + 142, UI.file_y + 34, 112, 36, "EXPORT", false)) {
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

        drawCanvasOverlay(self, fui, renderer, mouse);

        drawInfoPanel(fui, renderer, self);
    }

    fn drawRightPanel(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse) void {
        const x = UI.rightX() + 16;
        drawPixelText(fui, renderer, "PALETTE BANK", x, UI.content_y + 18, 2, UI.text);
        for (0..Project.PALETTE_BANK_COUNT) |bank| {
            const bx = x + @as(i32, @intCast(bank)) * 48;
            const label: [:0]const u8 = switch (bank) {
                0 => "1",
                1 => "2",
                2 => "3",
                else => "4",
            };
            if (pillButton(fui, renderer, mouse, bx, UI.content_y + 52, 38, 34, label, project.activePaletteBank() == bank)) {
                project.setPaletteBank(@intCast(bank));
                self.setInfo("Palette bank selected", UI.accent);
            }
        }

        drawPixelText(fui, renderer, "PALETTES", x, UI.content_y + 100, 2, UI.text);
        drawPalettes(fui, renderer, project, mouse, x + 48, UI.content_y + 134, self);
        drawPixelText(fui, renderer, "EDIT COLOUR", x, UI.content_y + 548, 2, UI.text);
        drawColorEditor(fui, renderer, project, mouse, x, UI.content_y + 586, self);
    }

    fn setInfo(self: *MainEditor, text: []const u8, color: u32) void {
        self.info_text = text;
        self.info_color = color;
    }
};

fn drawStaticUi(fui: anytype, renderer: *Render) void {
    renderer.clear_background(UI.bg);
    panel(renderer, UI.leftX(), UI.top_y, CONF.SCREEN_W - UI.leftX() * 2, UI.top_h);
    drawStaticPanelFrames(fui, renderer);
}

fn drawStaticPanelFrames(fui: anytype, renderer: *Render) void {
    const x = UI.leftX();
    panel(renderer, x, UI.content_y, UI.left_w, UI.side_panel_h);

    panel(renderer, UI.centerX(), UI.content_y, UI.centerW(), UI.contentH());
    sectionPanel(renderer, UI.centerX(), UI.centerInfoY(), UI.centerW(), UI.center_info_h, "INFO", fui);

    panel(renderer, UI.rightX(), UI.content_y, UI.right_w, UI.side_panel_h);
}

fn panel(renderer: *Render, x: i32, y: i32, w: i32, h: i32) void {
    if (w <= 0 or h <= 0) return;
    renderer.draw_rect(x + 3, y + 3, w, h, UI.border_dark);
    renderer.draw_rect(x, y, w, h, UI.panel);
    renderer.draw_rect_lines(x, y, w, h, UI.border);
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
    const bg: u32 = if (active) UI.accent_dark else if (over) UI.panel_hi else UI.panel_dark;
    renderer.draw_rect(x + 2, y + 2, w, h, 0x050607);
    renderer.draw_rect(x, y, w, h, bg);
    renderer.draw_rect_lines(x, y, w, h, if (active) UI.accent else UI.border);
    const tw = fui.text_length(label, 1);
    fui.draw_text(renderer, label, x + @divFloor(w - tw, 2), y + @divFloor(h - CONF.FONT_HEIGHT, 2), 1, if (active) UI.text else UI.muted);
    return over and mouse.just_pressed;
}

fn pillButton(fui: anytype, renderer: *Render, mouse: Mouse, x: i32, y: i32, w: i32, h: i32, label: [:0]const u8, active: bool) bool {
    const over = views.hover(mouse, x, y, w, h);
    const bg: u32 = if (active) UI.accent_dark else if (over) UI.panel_hi else UI.panel_dark;
    renderer.draw_rect(x + 2, y + 2, w, h, 0x050607);
    renderer.draw_rect(x, y, w, h, bg);
    renderer.draw_rect_lines(x, y, w, h, if (active) UI.accent else UI.border);
    const tw = fui.text_length(label, 1);
    fui.draw_text(renderer, label, x + @divFloor(w - tw, 2), y + @divFloor(h - CONF.FONT_HEIGHT, 2), 1, if (active) UI.text else UI.muted);
    return over and mouse.just_pressed;
}

fn iconButton(renderer: *Render, mouse: Mouse, x: i32, y: i32, label: [:0]const u8, active: bool) bool {
    const size: i32 = 44;
    const over = views.hover(mouse, x, y, size, size);
    const bg: u32 = if (active) UI.accent_dark else if (over) UI.panel_hi else UI.panel_dark;
    renderer.draw_rect(x + 2, y + 2, size, size, 0x050607);
    renderer.draw_rect(x, y, size, size, bg);
    renderer.draw_rect_lines(x, y, size, size, if (active) UI.accent else UI.border);
    drawDummyIcon(renderer, x + 11, y + 11, label, if (active) UI.text else UI.muted);
    return over and mouse.just_pressed;
}

fn miniButton(renderer: *Render, mouse: Mouse, x: i32, y: i32, label: [:0]const u8) bool {
    _ = label;
    const w: i32 = 30;
    const h: i32 = 24;
    const over = views.hover(mouse, x, y, w, h);
    renderer.draw_rect(x + 2, y + 2, w, h, 0x050607);
    renderer.draw_rect(x, y, w, h, if (over) UI.panel_hi else UI.panel_dark);
    renderer.draw_rect_lines(x, y, w, h, UI.border);
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

fn drawCanvasBase(fui: anytype, renderer: *Render, project: *Project) void {
    const tile = project.currentImage();
    const origin = canvasOrigin(fui);
    const size = CONF.TILE_SIDE * CONF.EDITOR_CANVAS_SCALE;
    renderer.draw_rect(origin[0] - 2, origin[1] - 2, size + 4, size + 4, 0xE6F5D8);

    var py: usize = 0;
    while (py < CONF.TILE_SIDE) : (py += 1) {
        var px: usize = 0;
        while (px < CONF.TILE_SIDE) : (px += 1) {
            const idx = tile.pixels[py * CONF.TILE_SIDE + px];
            const color = if (project.isTransparentColor(idx)) checker(px, py) else project.currentColor32(idx);
            const x = origin[0] + @as(i32, @intCast(px)) * CONF.EDITOR_CANVAS_SCALE;
            const y = origin[1] + @as(i32, @intCast(py)) * CONF.EDITOR_CANVAS_SCALE;
            renderer.draw_rect(x, y, CONF.EDITOR_CANVAS_SCALE, CONF.EDITOR_CANVAS_SCALE, color);
        }
    }

    var grid: usize = 0;
    while (grid <= CONF.TILE_SIDE) : (grid += 1) {
        const offset = @as(i32, @intCast(grid)) * CONF.EDITOR_CANVAS_SCALE;
        renderer.draw_line(origin[0] + offset, origin[1], origin[0] + offset, origin[1] + size, 0xD7EBCB);
        renderer.draw_line(origin[0], origin[1] + offset, origin[0] + size, origin[1] + offset, 0xD7EBCB);
    }
    renderer.draw_rect_lines(origin[0], origin[1], size, size, UI.border_dark);
}

fn drawCanvasOverlay(self: *MainEditor, fui: anytype, renderer: *Render, mouse: Mouse) void {
    if (self.tool == .line) if (self.line_start) |start| if (canvasCell(fui, mouse.x, mouse.y)) |end| {
        const origin = canvasOrigin(fui);
        const half = @divFloor(CONF.EDITOR_CANVAS_SCALE, 2);
        renderer.draw_line(origin[0] + start[0] * CONF.EDITOR_CANVAS_SCALE + half, origin[1] + start[1] * CONF.EDITOR_CANVAS_SCALE + half, origin[0] + end[0] * CONF.EDITOR_CANVAS_SCALE + half, origin[1] + end[1] * CONF.EDITOR_CANVAS_SCALE + half, 0x202020);
    };
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
                self.library_return_state = .editor;
                sm.go_to(.tile_library);
            }
        }
    }
}

fn drawPalettes(fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, x0: i32, y0: i32, editor: *MainEditor) void {
    const sw: i32 = 38;
    const sh: i32 = 34;
    const row_h: i32 = 44;
    for (0..CONF.PALETTE_COUNT) |p| {
        const y = y0 + @as(i32, @intCast(p)) * row_h;
        var label_buf: [4]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buf, "{d}", .{p}) catch "?";
        if (project.selectedPalette() == p) drawPixelText(fui, renderer, ">", x0 - 34, y + 10, 1, UI.text);
        drawPixelText(fui, renderer, label, x0 - 18, y + 10, 1, UI.text);
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
    renderer.draw_rect(x, y, 54, 42, selected_color);
    renderer.draw_rect_lines(x, y, 54, 42, UI.text);

    var title_buf: [32]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buf, "P{d} C{d}", .{ project.selectedPalette(), project.selectedColor() }) catch "P? C?";
    drawPixelText(fui, renderer, title, x + 68, y + 12, 1, UI.text);

    const rgb = selectedRgb(project);
    drawChannelEditor(fui, renderer, project, mouse, .r, "R", rgb[0], x, y + 52, UI.danger, editor);
    drawChannelEditor(fui, renderer, project, mouse, .g, "G", rgb[1], x, y + 82, UI.accent, editor);
    drawChannelEditor(fui, renderer, project, mouse, .b, "B", rgb[2], x, y + 112, UI.blue, editor);
}

fn drawChannelEditor(fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, channel: ColorChannel, label: [:0]const u8, value: u8, x: i32, y: i32, color: u32, editor: *MainEditor) void {
    const slider_w: i32 = 108;
    drawPixelText(fui, renderer, label, x, y + 8, 2, color);
    renderer.draw_rect(x + 28, y + 15, slider_w, 6, UI.border);
    renderer.draw_rect(x + 28, y + 15, @divFloor(@as(i32, value) * slider_w, 255), 6, color);
    const knob_x = x + 28 + @divFloor(@as(i32, value) * slider_w, 255) - 5;
    renderer.draw_rect(knob_x, y + 10, 10, 16, UI.text);
    if (views.hover(mouse, x + 28, y + 4, slider_w, 28) and (mouse.left_down or mouse.right_down)) {
        const rel = @max(0, @min(slider_w - 1, mouse.x - (x + 28)));
        const target = @divFloor(rel * 255, slider_w - 1);
        const delta: i16 = @as(i16, @intCast(target)) - @as(i16, @intCast(value));
        if (delta != 0) {
            project.adjustSelectedRgb(channel, delta);
            editor.setInfo("Color updated", UI.accent);
        }
    }
    var buf: [4]u8 = undefined;
    const value_text = std.fmt.bufPrint(&buf, "{d}", .{value}) catch "?";
    drawPixelText(fui, renderer, value_text, x + 146, y + 8, 1, UI.text);
    if (miniButton(renderer, mouse, x + 174, y + 4, "+")) {
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
