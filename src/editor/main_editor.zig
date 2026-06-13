const std = @import("std");
const CONF = @import("../engine/config.zig").CONF;
const render_mod = @import("../engine/render.zig");
const Render = render_mod.Render;
const Mouse = @import("../engine/mouse.zig").Mouse;
const Project = @import("project.zig").Project;
const Tool = @import("project.zig").Tool;
const ColorChannel = @import("project.zig").ColorChannel;
const views = @import("views.zig");
const editor_ui = @import("ui.zig");

pub const State = enum { splash, editor, tile_library, map_editor, quit };

pub const LibraryMode = enum { choose_slot, swap_tile };

pub const LibraryRequest = struct {
    mode: LibraryMode,
    slot_index: u8,
    tile_id: u16,
};

const DAWNBRINGER_32 = [_]u32{
    0x000000, 0x222034, 0x45283C, 0x663931, 0x8F563B, 0xDF7126, 0xD9A066, 0xEEC39A,
    0xFBF236, 0x99E550, 0x6ABE30, 0x37946E, 0x4B692F, 0x524B24, 0x323C39, 0x3F3F74,
    0x306082, 0x5B6EE1, 0x639BFF, 0x5FCDE4, 0xCBDBFC, 0xFFFFFF, 0x9BADB7, 0x847E87,
    0x696A6A, 0x595652, 0x76428A, 0xAC3232, 0xD95763, 0xD77BBA, 0x8F974A, 0x8A6F30,
};

const UI = struct {
    const bg = editor_ui.Theme.bg;
    const panel_dark = editor_ui.Theme.panel_dark;
    const panel_hi = editor_ui.Theme.panel_hi;
    const border = editor_ui.Theme.border;
    const border_dark = editor_ui.Theme.border_dark;
    const text = editor_ui.Theme.text;
    const muted = editor_ui.Theme.muted;
    const accent = editor_ui.Theme.accent;
    const accent_dark = editor_ui.Theme.accent_dark;
    const danger = editor_ui.Theme.danger;
    const blue = editor_ui.Theme.blue;
    const drawing_panel = 0x17252D;
    const drawing_panel_alt = 0x1B2F39;
    const drawing_header = 0x9FE3FF;
    const palette_panel = 0x2A2418;
    const palette_panel_alt = 0x362D1B;
    const palette_header = 0xFFE29A;

    const top_y: i32 = editor_ui.Layout.top_y;
    const top_h: i32 = editor_ui.Layout.top_h;
    const side_x: i32 = editor_ui.Layout.side_x;
    const gap: i32 = editor_ui.Layout.gap;
    const left_w: i32 = editor_ui.Layout.left_w;
    const right_w: i32 = editor_ui.Layout.right_w;
    const content_y: i32 = editor_ui.Layout.content_y;
    const side_panel_h: i32 = editor_ui.Layout.contentH();
    const draw_mode_y: i32 = content_y + 16;
    const palette_y: i32 = content_y + 124;
    const preview_y: i32 = content_y + 260;
    const center_info_h: i32 = 160;
    const canvas_scale: i32 = 56;
    const canvas_y: i32 = 154;

    fn leftX() i32 {
        return editor_ui.Layout.leftX();
    }
    fn rightX() i32 {
        return editor_ui.Layout.rightX();
    }
    fn centerX() i32 {
        return editor_ui.Layout.centerX();
    }
    fn centerW() i32 {
        return editor_ui.Layout.centerW();
    }
    fn contentH() i32 {
        return side_panel_h - center_info_h - 12;
    }
    fn centerInfoY() i32 {
        return UI.content_y + contentH() + 12;
    }
};

pub const MainEditor = struct {
    tool: Tool = .pixel,
    line_start: ?[2]i32 = null,
    library_request: ?LibraryRequest = null,
    library_return_state: State = .editor,
    suppress_canvas_paint_until_mouse_up: bool = false,
    info_text: []const u8 = "Ready",
    info_color: u32 = UI.muted,
    ui_cache_dirty: bool = true,
    cached_canvas_revision: u64 = std.math.maxInt(u64),
    copied_color: ?[3]u8 = null,

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
        const active_tab: editor_ui.TopTab = if (project.mode == .tiles) .tiles else .sprites;
        const action = editor_ui.drawTopBar(fui, renderer, mouse, CONF.THE_NAME, active_tab, project.dirty, UI.rightX()) orelse return;
        switch (action) {
            .tiles => project.setMode(.tiles),
            .sprites => project.setMode(.sprites),
            .map_editor => sm.go_to(.map_editor),
            .save => {
                project.save() catch {
                    self.setInfo("Save failed", UI.danger);
                    return;
                };
                self.setInfo("File saved", UI.accent);
            },
            .quit => sm.go_to(.quit),
        }
    }

    fn drawLeftPanel(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, sm: anytype) void {
        const x = UI.leftX();
        drawPixelText(fui, renderer, "DRAW MODE", x + 16, UI.draw_mode_y, 2, UI.drawing_header);
        if (pillButton(fui, renderer, mouse, x + 16, UI.draw_mode_y + 30, 74, 34, "PIXEL", self.tool == .pixel)) self.tool = .pixel;
        if (pillButton(fui, renderer, mouse, x + 100, UI.draw_mode_y + 30, 70, 34, "FILL", self.tool == .fill)) self.tool = .fill;
        if (pillButton(fui, renderer, mouse, x + 180, UI.draw_mode_y + 30, 74, 34, "LINE", self.tool == .line)) self.tool = .line;

        drawPixelText(fui, renderer, "CURRENT PALETTE", x + 16, UI.palette_y, 2, UI.drawing_header);
        drawCurrentPalette(fui, renderer, project, mouse, x + 24, UI.palette_y + 34, self);

        drawPixelText(fui, renderer, "TILES MAP", x + 16, UI.preview_y, 2, UI.drawing_header);
        drawTileSlots(self, fui, renderer, project, mouse, sm, x + 76, UI.preview_y + 38, 40);
        drawPixelText(fui, renderer, "LMB: SELECT", x + 20, UI.preview_y + 176, 1, UI.muted);
        drawPixelText(fui, renderer, "RMB: LIBRARY", x + 136, UI.preview_y + 176, 1, UI.muted);

        drawTileFlags(fui, renderer, project, mouse, x + 16, UI.preview_y + 200, self);
        drawPixelTransferButtons(fui, renderer, project, mouse, x + 16, UI.preview_y + 292, self);
        drawStatusInfo(fui, renderer, self, x + 16, UI.content_y + UI.side_panel_h - 44);
    }

    fn drawCenterPanel(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, sm: anytype) void {
        _ = sm;
        var title_buf: [8]u8 = undefined;
        const id_text = std.fmt.bufPrint(&title_buf, "{d}", .{project.selectedImageId()}) catch "?";
        const title_x = UI.centerX() + @divFloor(UI.centerW() - fui.text_length("TILE ID: 000", 2), 2);
        const title_y: i32 = 126;
        drawPixelText(fui, renderer, "TILE ID:", title_x, title_y, 2, UI.drawing_header);
        drawPixelText(fui, renderer, id_text, title_x + 142, title_y, 2, UI.accent);

        drawCanvasOverlay(self, fui, renderer, mouse);

        drawGlobalPalettePicker(fui, renderer, project, mouse, self);
    }

    fn drawRightPanel(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse) void {
        const x = UI.rightX() + 16;
        drawPixelText(fui, renderer, "PALETTE BANK", x, UI.content_y + 18, 2, UI.palette_header);
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

        drawPixelText(fui, renderer, "PALETTES", x, UI.content_y + 92, 2, UI.palette_header);
        drawPalettes(fui, renderer, project, mouse, x + 42, UI.content_y + 124, self);
        drawPixelText(fui, renderer, "EDIT COLOUR", x, UI.content_y + 444, 2, UI.palette_header);
        drawColorEditor(fui, renderer, project, mouse, x, UI.content_y + 478, self);
    }

    pub fn setInfo(self: *MainEditor, text: []const u8, color: u32) void {
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
    panelColored(renderer, x, UI.content_y, UI.left_w, UI.side_panel_h, UI.drawing_panel);

    panelColored(renderer, UI.centerX(), UI.content_y, UI.centerW(), UI.contentH(), UI.drawing_panel);
    sectionPanel(renderer, UI.centerX(), UI.centerInfoY(), UI.centerW(), UI.center_info_h, UI.palette_panel, "Palette by DawnBringer", UI.palette_header, fui);

    panelColored(renderer, UI.rightX(), UI.content_y, UI.right_w, UI.side_panel_h, UI.palette_panel);
}

fn panel(renderer: *Render, x: i32, y: i32, w: i32, h: i32) void {
    editor_ui.panel(renderer, x, y, w, h);
}

fn panelColored(renderer: *Render, x: i32, y: i32, w: i32, h: i32, color: u32) void {
    if (w <= 0 or h <= 0) return;
    renderer.draw_rect(x, y, w, h, color);
}

fn sectionPanel(renderer: *Render, x: i32, y: i32, w: i32, h: i32, color: u32, title: []const u8, title_color: u32, fui: anytype) void {
    panelColored(renderer, x, y, w, h, color);
    if (title.len > 0) drawPixelText(fui, renderer, title, x + 22, y + 22, 2, title_color);
}

fn drawStatusInfo(fui: anytype, renderer: *Render, editor: *const MainEditor, x: i32, y: i32) void {
    drawPixelText(fui, renderer, "INFO", x, y, 2, UI.drawing_header);
    drawPixelText(fui, renderer, editor.info_text, x, y + 34, 1, editor.info_color);
}

fn drawGlobalPalettePicker(fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, editor: *MainEditor) void {
    const cols: usize = 16;
    const sw: i32 = 30;
    const gap: i32 = 6;
    const x0 = UI.centerX() + 24;
    const y0 = UI.centerInfoY() + 54;
    const selected = rgbToU32(project.selectedRgb());

    for (DAWNBRINGER_32, 0..) |color, i| {
        const col: i32 = @intCast(i % cols);
        const row: i32 = @intCast(i / cols);
        const x = x0 + col * (sw + gap);
        const y = y0 + row * (sw + gap);
        const hovered = views.hover(mouse, x, y, sw, sw);

        renderer.draw_rect(x, y, sw, sw, color);
        renderer.draw_rect_lines(x, y, sw, sw, if (hovered) UI.text else UI.border_dark);
        if (color == selected) {
            renderer.draw_rect_lines(x + 3, y + 3, sw - 6, sw - 6, UI.accent);
            renderer.draw_rect_lines(x + 6, y + 6, sw - 12, sw - 12, UI.text);
        }

        if (hovered and (mouse.just_pressed or mouse.just_right_pressed)) {
            pasteSelectedRgb(project, colorToRgb(color));
            editor.setInfo("Global color applied", UI.accent);
        }
    }

    const grid_w = @as(i32, @intCast(cols)) * sw + @as(i32, @intCast(cols - 1)) * gap;
    const hint_x = x0 + grid_w + 18;
    drawPixelText(fui, renderer, "Click colour", hint_x, y0 + 2, 1, UI.muted);
    drawPixelText(fui, renderer, "to replace", hint_x, y0 + 18, 1, UI.muted);
    drawPixelText(fui, renderer, "selected slot", hint_x, y0 + 34, 1, UI.muted);
}

fn drawPixelText(fui: anytype, renderer: *Render, text: []const u8, x: i32, y: i32, scale: i32, color: u32) void {
    editor_ui.drawText(fui, renderer, text, x, y, scale, color);
}

fn pillButton(fui: anytype, renderer: *Render, mouse: Mouse, x: i32, y: i32, w: i32, h: i32, label: [:0]const u8, active: bool) bool {
    return editor_ui.button(fui, renderer, mouse, x, y, w, h, label, active);
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
    const size = CONF.TILE_SIDE * UI.canvas_scale;
    renderer.draw_rect(origin[0] - 3, origin[1] - 3, size + 6, size + 6, UI.drawing_panel_alt);
    renderer.draw_rect(origin[0] - 2, origin[1] - 2, size + 4, size + 4, UI.drawing_header);

    var py: usize = 0;
    while (py < CONF.TILE_SIDE) : (py += 1) {
        var px: usize = 0;
        while (px < CONF.TILE_SIDE) : (px += 1) {
            const idx = tile.pixels[py * CONF.TILE_SIDE + px];
            const color = if (project.isTransparentColor(idx)) checker(px, py) else project.currentColor32(idx);
            const x = origin[0] + @as(i32, @intCast(px)) * UI.canvas_scale;
            const y = origin[1] + @as(i32, @intCast(py)) * UI.canvas_scale;
            renderer.draw_rect(x, y, UI.canvas_scale, UI.canvas_scale, color);
        }
    }

    var grid: usize = 0;
    while (grid <= CONF.TILE_SIDE) : (grid += 1) {
        const offset = @as(i32, @intCast(grid)) * UI.canvas_scale;
        renderer.draw_line(origin[0] + offset, origin[1], origin[0] + offset, origin[1] + size, 0xD7EBCB);
        renderer.draw_line(origin[0], origin[1] + offset, origin[0] + size, origin[1] + offset, 0xD7EBCB);
    }
    renderer.draw_rect_lines(origin[0], origin[1], size, size, UI.border_dark);
}

fn drawCanvasOverlay(self: *MainEditor, fui: anytype, renderer: *Render, mouse: Mouse) void {
    if (self.tool == .line) if (self.line_start) |start| if (canvasCell(fui, mouse.x, mouse.y)) |end| {
        const origin = canvasOrigin(fui);
        const half = @divFloor(UI.canvas_scale, 2);
        renderer.draw_line(origin[0] + start[0] * UI.canvas_scale + half, origin[1] + start[1] * UI.canvas_scale + half, origin[0] + end[0] * UI.canvas_scale + half, origin[1] + end[1] * UI.canvas_scale + half, 0x202020);
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
    const sw: i32 = 34;
    const sh: i32 = 30;
    const row_h: i32 = 38;
    for (0..CONF.PALETTE_COUNT) |p| {
        const y = y0 + @as(i32, @intCast(p)) * row_h;
        var label_buf: [4]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buf, "{d}", .{p}) catch "?";
        if (project.selectedPalette() == p) drawPixelText(fui, renderer, ">", x0 - 34, y + 10, 1, UI.text);
        drawPixelText(fui, renderer, label, x0 - 18, y + 10, 1, UI.text);
        renderer.draw_rect(x0 - 2, y - 2, sw * CONF.COLORS_PER_PALETTE + 4, sh + 4, UI.palette_panel_alt);
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

fn drawTileFlags(fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, x: i32, y: i32, editor: *MainEditor) void {
    if (project.mode != .tiles) return;

    var title_buf: [24]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buf, "TILE FLAGS 0x{X}", .{project.selectedTileFlags()}) catch "TILE FLAGS";
    drawPixelText(fui, renderer, title, x, y, 2, UI.drawing_header);

    const named_flags = [_]struct { label: [:0]const u8, bit: u8, w: i32 }{
        .{ .label = "WALK", .bit = 0, .w = 74 },
        .{ .label = "SLOW", .bit = 1, .w = 74 },
    };
    var flag_x = x;
    for (named_flags) |flag| {
        const active = project.selectedTileFlagBit(flag.bit);
        if (pillButton(fui, renderer, mouse, flag_x, y + 24, flag.w, 28, flag.label, active)) {
            project.setSelectedTileFlagBit(flag.bit, !active);
            editor.setInfo("Tile flag toggled", UI.accent);
        }
        flag_x += flag.w + 6;
    }

    const extra_flags = [_]struct { label: [:0]const u8, bit: u8 }{
        .{ .label = "2", .bit = 2 },
        .{ .label = "3", .bit = 3 },
        .{ .label = "4", .bit = 4 },
        .{ .label = "5", .bit = 5 },
        .{ .label = "6", .bit = 6 },
        .{ .label = "7", .bit = 7 },
    };
    flag_x = x;
    for (extra_flags) |flag| {
        const active = project.selectedTileFlagBit(flag.bit);
        if (pillButton(fui, renderer, mouse, flag_x, y + 56, 26, 24, flag.label, active)) {
            project.setSelectedTileFlagBit(flag.bit, !active);
            editor.setInfo("Tile flag toggled", UI.accent);
        }
        flag_x += 30;
    }
}

fn drawPixelTransferButtons(fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, x: i32, y: i32, editor: *MainEditor) void {
    drawPixelText(fui, renderer, "PIXEL TRANSFER", x, y, 2, UI.drawing_header);
    if (pillButton(fui, renderer, mouse, x, y + 30, 112, 30, "COPY PIX", false)) {
        project.copyCurrentPixelsToTransferFile() catch {
            editor.setInfo("Copy pixels failed", UI.danger);
            return;
        };
        editor.setInfo("Pixels copied", UI.accent);
    }
    if (pillButton(fui, renderer, mouse, x + 124, y + 30, 112, 30, "PASTE PIX", false)) {
        project.pastePixelsFromTransferFile() catch {
            editor.setInfo("Paste pixels failed", UI.danger);
            return;
        };
        editor.setInfo("Pixels pasted", UI.accent);
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

    if (pillButton(fui, renderer, mouse, x, y + 148, 82, 32, "COPY", false)) {
        editor.copied_color = rgb;
        editor.setInfo("Color copied", UI.accent);
    }
    if (pillButton(fui, renderer, mouse, x + 96, y + 148, 82, 32, "PASTE", editor.copied_color != null)) {
        if (editor.copied_color) |copied| {
            pasteSelectedRgb(project, copied);
            editor.setInfo("Color pasted", UI.accent);
        } else {
            editor.setInfo("No copied color", UI.danger);
        }
    }
}

fn pasteSelectedRgb(project: *Project, rgb: [3]u8) void {
    const current = selectedRgb(project);
    const r_delta = @as(i16, @intCast(rgb[0])) - @as(i16, @intCast(current[0]));
    const g_delta = @as(i16, @intCast(rgb[1])) - @as(i16, @intCast(current[1]));
    const b_delta = @as(i16, @intCast(rgb[2])) - @as(i16, @intCast(current[2]));
    if (r_delta != 0) project.adjustSelectedRgb(.r, r_delta);
    if (g_delta != 0) project.adjustSelectedRgb(.g, g_delta);
    if (b_delta != 0) project.adjustSelectedRgb(.b, b_delta);
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
}

fn selectedRgb(project: *const Project) [3]u8 {
    return project.selectedRgb();
}

fn colorToRgb(color: u32) [3]u8 {
    return .{
        @intCast((color >> 16) & 0xFF),
        @intCast((color >> 8) & 0xFF),
        @intCast(color & 0xFF),
    };
}

fn rgbToU32(rgb: [3]u8) u32 {
    return (@as(u32, rgb[0]) << 16) | (@as(u32, rgb[1]) << 8) | @as(u32, rgb[2]);
}

fn canvasCell(fui: anytype, x: i32, y: i32) ?[2]i32 {
    const origin = canvasOrigin(fui);
    const size = CONF.TILE_SIDE * UI.canvas_scale;
    if (!views.hover(.{ .x = x, .y = y, .left_down = false, .right_down = false, .just_pressed = false, .just_right_pressed = false }, origin[0], origin[1], size, size)) return null;
    return .{ @divFloor(x - origin[0], UI.canvas_scale), @divFloor(y - origin[1], UI.canvas_scale) };
}

fn canvasOrigin(fui: anytype) [2]i32 {
    _ = fui;
    const size = CONF.TILE_SIDE * UI.canvas_scale;
    return .{ UI.centerX() + @divFloor(UI.centerW() - size, 2), UI.canvas_y };
}

fn checker(x: usize, y: usize) u32 {
    return if ((x + y) % 2 == 0) 0xF0F0F0 else 0xFFFFFF;
}
