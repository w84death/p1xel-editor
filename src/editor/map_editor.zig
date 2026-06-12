const std = @import("std");
const CONF = @import("../engine/config.zig").CONF;
const Render = @import("../engine/render.zig").Render;
const Mouse = @import("../engine/mouse.zig").Mouse;
const project_mod = @import("project.zig");
const Project = project_mod.Project;
const ProjectMode = project_mod.ProjectMode;
const MapTileAttr = project_mod.MapTileAttr;
const MapSprite = project_mod.MapSprite;
const MainEditor = @import("main_editor.zig").MainEditor;
const exporter = @import("exporter.zig");
const views = @import("views.zig");
const editor_ui = @import("ui.zig");

const UI = struct {
    const bg = editor_ui.Theme.bg;
    const panel = editor_ui.Theme.panel;
    const panel_hi = editor_ui.Theme.panel_hi;
    const border_dark = editor_ui.Theme.border_dark;
    const text = editor_ui.Theme.text;
    const muted = editor_ui.Theme.muted;
    const accent = editor_ui.Theme.accent;
    const accent_dark = editor_ui.Theme.accent_dark;
    const danger = editor_ui.Theme.danger;
    const warn = editor_ui.Theme.warn;

    const side_x: i32 = editor_ui.Layout.side_x;
    const top_y: i32 = editor_ui.Layout.top_y;
    const top_h: i32 = editor_ui.Layout.top_h;
    const left_x: i32 = editor_ui.Layout.leftX();
    const left_w: i32 = editor_ui.Layout.left_w;
    const right_w: i32 = editor_ui.Layout.right_w;
    const gap: i32 = editor_ui.Layout.gap;
    const canvas_x: i32 = editor_ui.Layout.centerX();
    const canvas_y: i32 = editor_ui.Layout.content_y;
    const right_x: i32 = editor_ui.Layout.rightX();
    const canvas_w: i32 = editor_ui.Layout.centerW();
    const canvas_h: i32 = editor_ui.Layout.contentH();
};

pub const ArrowKeys = struct {
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,
};

const Tool = enum { bg_stamp, bg_fill, bg_random_row, bg_path9, sprite_stamp, sprite_remove, select };
const PendingSize = enum { none, s32x32, s64x16, s128x16 };
const GBC_SCREEN_W_TILES: i32 = 20;
const GBC_SCREEN_H_TILES: i32 = 18;

const MapSelectionRect = struct {
    x: u16 = 0,
    y: u16 = 0,
    w: u16 = 1,
    h: u16 = 1,
};

const Path9Placement = struct {
    tile_id: u16,
    attr: MapTileAttr,
};

const Path9Slots = struct {
    const top_left_corner: usize = 0; // row 1 col 1, hflip for top-right
    const top_edge: usize = 1; // row 1 col 2
    const top_inner_corner: usize = 2; // row 1 col 3, hflip for opposite top inner corner
    const left_edge: usize = 3; // row 2 col 1, hflip for right edge
    const filler_a: usize = 4; // row 2 col 2
    const filler_b: usize = 5; // row 2 col 3
    const bottom_left_corner: usize = 6; // row 3 col 1, hflip for bottom-right
    const bottom_edge: usize = 7; // row 3 col 2
    const bottom_inner_corner: usize = 8; // row 3 col 3, hflip for opposite bottom inner corner
};

pub const MapEditor = struct {
    tool: Tool = .bg_stamp,
    selected_tile: u8 = 0,
    selected_sprite: u16 = 0,
    bg_attr: MapTileAttr = .{},
    sprite_attr: MapTileAttr = .{},
    brush_size: u8 = 1,
    pending_size: PendingSize = .none,
    pending_clear_map: bool = false,
    info_text: []const u8 = "Ready",
    info_color: u32 = UI.muted,
    cached_map_revision: u64 = std.math.maxInt(u64),
    cached_map_scale: i32 = 0,
    cached_map_width: u16 = 0,
    cached_map_height: u16 = 0,
    cached_origin_x: i32 = std.math.minInt(i32),
    cached_origin_y: i32 = std.math.minInt(i32),
    cache_dirty: bool = true,
    zoom_extra: i32 = 0,
    pan_x: i32 = 0,
    pan_y: i32 = 0,
    random_state: u32 = 0xA53C_9E27,
    random_last_cell: ?[2]u16 = null,
    selection: ?MapSelectionRect = null,
    selection_drag_anchor: ?[2]u16 = null,
    clipboard_tile_ids: [project_mod.MAX_MAP_CELLS]u8 = [_]u8{0} ** project_mod.MAX_MAP_CELLS,
    clipboard_tile_attrs: [project_mod.MAX_MAP_CELLS]u8 = [_]u8{0} ** project_mod.MAX_MAP_CELLS,
    clipboard_w: u16 = 0,
    clipboard_h: u16 = 0,
    clipboard_sprites: [project_mod.MAX_MAP_SPRITES]MapSprite = [_]MapSprite{.{}} ** project_mod.MAX_MAP_SPRITES,
    clipboard_sprite_count: u16 = 0,
    pending_paste: bool = false,
    suppress_canvas_until_mouse_up: bool = false,
    show_grid: bool = true,
    show_gbc_screen: bool = false,

    pub fn invalidateCache(self: *MapEditor) void {
        self.cache_dirty = true;
    }

    pub fn syncLibrarySelection(self: *MapEditor, project: *const Project) void {
        const image_id = project.selectedImageId();
        const image = project.imageAtMode(project.mode, image_id);
        const default_palette = image.palette_id;
        if (project.mode == .tiles) {
            self.selected_tile = @intCast(@min(image_id, 255));
            self.bg_attr.palette = default_palette;
            self.tool = .bg_stamp;
            self.setInfo("BG tile selected", UI.accent);
        } else {
            self.selected_sprite = image_id;
            self.sprite_attr.palette = default_palette;
            self.tool = .sprite_stamp;
            self.setInfo("Sprite selected", UI.accent);
        }
    }

    pub fn draw(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, main_editor: *MainEditor, mouse: Mouse, arrows: ArrowKeys, sm: anytype) void {
        const previous_target = renderer.target;
        renderer.set_target(.frame);
        defer renderer.set_target(previous_target);

        self.handleArrowPan(project, arrows);

        renderer.draw_rect(0, 0, CONF.SCREEN_W, CONF.SCREEN_H, UI.bg);
        self.drawTopBar(fui, renderer, project, main_editor, mouse, sm);
        self.drawLeftPanel(fui, renderer, project, main_editor, mouse, sm);
        self.drawRightPanel(fui, renderer, project, mouse);
        self.handleCanvas(project, mouse);
        self.drawCanvas(fui, renderer, project, mouse);
    }

    fn drawTopBar(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, main_editor: *MainEditor, mouse: Mouse, sm: anytype) void {
        const action = editor_ui.drawTopBar(fui, renderer, mouse, CONF.THE_NAME, .map_editor, project.dirty, UI.right_x) orelse return;
        switch (action) {
            .tiles => {
                project.setMode(.tiles);
                main_editor.ui_cache_dirty = true;
                sm.go_to(.editor);
            },
            .sprites => {
                project.setMode(.sprites);
                main_editor.ui_cache_dirty = true;
                sm.go_to(.editor);
            },
            .map_editor => {},
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

    fn drawLeftPanel(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, main_editor: *MainEditor, mouse: Mouse, sm: anytype) void {
        panel(renderer, UI.left_x, UI.canvas_y, UI.left_w, UI.canvas_h);
        const tool_y = UI.canvas_y + 18;
        drawText(fui, renderer, "TOOLS", UI.left_x + 16, tool_y, 2, UI.text);
        if (button(fui, renderer, mouse, UI.left_x + 16, tool_y + 30, 70, 34, "STAMP", self.tool == .bg_stamp)) self.tool = .bg_stamp;
        if (button(fui, renderer, mouse, UI.left_x + 94, tool_y + 30, 58, 34, "FILL", self.tool == .bg_fill)) self.tool = .bg_fill;
        if (button(fui, renderer, mouse, UI.left_x + 160, tool_y + 30, 94, 34, "PATH9", self.tool == .bg_path9)) self.tool = .bg_path9;
        if (button(fui, renderer, mouse, UI.left_x + 16, tool_y + 72, 62, 34, "RND", self.tool == .bg_random_row)) self.tool = .bg_random_row;
        if (button(fui, renderer, mouse, UI.left_x + 86, tool_y + 72, 58, 34, "SPR", self.tool == .sprite_stamp)) self.tool = .sprite_stamp;
        if (button(fui, renderer, mouse, UI.left_x + 152, tool_y + 72, 50, 34, "REM", self.tool == .sprite_remove)) self.tool = .sprite_remove;
        if (button(fui, renderer, mouse, UI.left_x + 210, tool_y + 72, 52, 34, "SEL", self.tool == .select)) self.tool = .select;

        drawText(fui, renderer, "BG TILES", UI.left_x + 16, UI.canvas_y + 132, 2, UI.text);
        self.drawSelector(fui, renderer, project, main_editor, mouse, sm, .tiles, UI.left_x + 50, UI.canvas_y + 160, 40);

        drawText(fui, renderer, "SPRITES", UI.left_x + 16, UI.canvas_y + 310, 2, UI.text);
        self.drawSelector(fui, renderer, project, main_editor, mouse, sm, .sprites, UI.left_x + 50, UI.canvas_y + 338, 40);
        drawText(fui, renderer, "LMB: SELECT", UI.left_x + 20, UI.canvas_y + 496, 1, UI.muted);
        drawText(fui, renderer, "RMB: LIBRARY", UI.left_x + 136, UI.canvas_y + 496, 1, UI.muted);

        const attr_y = UI.canvas_y + 516;
        drawText(fui, renderer, "SELECTED TILE", UI.left_x + 20, attr_y, 2, UI.text);
        self.drawAttrEditor(fui, renderer, mouse, attr_y + 36);
    }

    fn drawRightPanel(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse) void {
        panel(renderer, UI.right_x, UI.canvas_y, UI.right_w, UI.canvas_h);
        const x = UI.right_x + 16;
        const bank_y = UI.canvas_y + 16;
        const size_y = UI.canvas_y + 94;
        const brush_y = UI.canvas_y + 226;
        const pan_y = UI.canvas_y + 334;
        const selection_y = UI.canvas_y + 394;
        const file_y = UI.canvas_y + 486;
        const info_y = UI.canvas_y + 614;

        drawText(fui, renderer, "MAP BANK", x, bank_y, 2, UI.text);
        for (0..Project.MAP_BANK_COUNT) |bank| {
            const bx = x + @as(i32, @intCast(bank)) * 48;
            var label_buf: [2]u8 = undefined;
            const label = std.fmt.bufPrint(&label_buf, "{d}", .{bank + 1}) catch "?";
            if (button(fui, renderer, mouse, bx, bank_y + 32, 38, 32, label, project.activeMapBank() == bank)) {
                project.setMapBank(@intCast(bank));
                self.invalidateCache();
                self.setInfo("Map bank selected", UI.accent);
            }
        }

        drawText(fui, renderer, "MAP SIZE", x, size_y, 2, UI.text);
        drawText(fui, renderer, "DOUBLE CLICK TO CROP", x, size_y + 26, 1, UI.muted);
        self.sizeButton(fui, renderer, project, mouse, x, size_y + 48, 86, 32, "32x32", .s32x32, 32, 32);
        self.sizeButton(fui, renderer, project, mouse, x + 102, size_y + 48, 86, 32, "64x16", .s64x16, 64, 16);
        self.sizeButton(fui, renderer, project, mouse, x, size_y + 88, 188, 32, "128x16", .s128x16, 128, 16);

        drawText(fui, renderer, "BRUSH SIZE", x, brush_y, 2, UI.text);
        self.brushSizeButton(fui, renderer, mouse, x, brush_y + 32, "1x1", 1);
        self.brushSizeButton(fui, renderer, mouse, x + 66, brush_y + 32, "2x2", 2);
        self.brushSizeButton(fui, renderer, mouse, x + 132, brush_y + 32, "3x3", 3);
        drawText(fui, renderer, "PATH9: 9-PIECE", x, brush_y + 84, 1, UI.muted);

        drawText(fui, renderer, "PAN", x, pan_y, 2, UI.text);
        drawText(fui, renderer, "ARROWS: PAN MAP", x, pan_y + 32, 1, UI.muted);

        self.drawSelectionControls(fui, renderer, project, mouse, x, selection_y);

        drawText(fui, renderer, "FILE", x, file_y, 2, UI.text);
        if (button(fui, renderer, mouse, x, file_y + 32, 86, 34, "SAVE", project.dirty)) {
            project.save() catch {
                self.setInfo("Save failed", UI.danger);
                return;
            };
            self.setInfo("File saved", UI.accent);
        }
        if (button(fui, renderer, mouse, x + 102, file_y + 32, 86, 34, "EXPORT", false)) {
            exporter.exportGameBoyEngine(project) catch |err| {
                std.debug.print("[export] map editor export failed: {s}\n", .{@errorName(err)});
                self.setInfo(exporter.errorMessage(err), UI.danger);
                return;
            };
            self.setInfo("Engine data exported", UI.accent);
        }
        const clear_label: [:0]const u8 = if (self.pending_clear_map) "CONFIRM CLEAR" else "CLEAR MAP";
        if (button(fui, renderer, mouse, x, file_y + 74, 188, 34, clear_label, self.pending_clear_map)) self.clearMapButton(project);

        drawText(fui, renderer, "INFO", x, info_y, 2, UI.text);
        renderer.draw_rect(x, info_y + 30, UI.right_w - 32, 58, UI.panel_hi);
        renderer.draw_rect_lines(x, info_y + 30, UI.right_w - 32, 58, UI.border_dark);
        drawText(fui, renderer, self.info_text, x + 10, info_y + 52, 1, self.info_color);
    }

    fn clearMapButton(self: *MapEditor, project: *Project) void {
        if (!self.pending_clear_map) {
            self.pending_clear_map = true;
            self.pending_size = .none;
            self.pending_paste = false;
            self.setInfo("Click clear again to confirm", UI.warn);
            return;
        }
        self.pending_clear_map = false;
        self.pending_paste = false;
        self.selection = null;
        self.selection_drag_anchor = null;
        if (project.clearActiveMap()) {
            self.invalidateCache();
            self.setInfo("Map cleared", UI.warn);
        } else {
            self.setInfo("Map already clear", UI.muted);
        }
    }

    fn drawSelectionControls(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, x: i32, y: i32) void {
        drawText(fui, renderer, "SELECTION", x, y, 2, UI.text);
        if (button(fui, renderer, mouse, x, y + 28, 86, 30, "COPY", self.selection != null)) self.copySelection(project);
        if (button(fui, renderer, mouse, x + 102, y + 28, 86, 30, "PASTE", self.hasClipboard())) self.armPasteSelection();
    }

    fn drawSelector(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, main_editor: *MainEditor, mouse: Mouse, sm: anytype, mode: ProjectMode, x0: i32, y0: i32, slot: i32) void {
        _ = fui;
        const scale = @divFloor(slot - 8, CONF.TILE_SIDE);
        for (0..9) |i| {
            const cx: i32 = @intCast(i % 3);
            const cy: i32 = @intCast(i / 3);
            const x = x0 + cx * (slot + 6);
            const y = y0 + cy * (slot + 6);
            const image_id = project.visibleSlotMode(mode, i);
            const selected = if (mode == .tiles) image_id == self.selected_tile else image_id == self.selected_sprite;
            renderer.draw_rect(x, y, slot, slot, if (selected) UI.accent_dark else UI.panel_hi);
            renderer.draw_rect_lines(x, y, slot, slot, UI.border_dark);
            const image = project.imageAtMode(mode, image_id);
            views.drawImageWithAttrs(renderer, project, mode, image_id, image.palette_id, false, false, x + 4, y + 4, scale);
            if (views.hover(mouse, x, y, slot, slot)) {
                renderer.draw_rect_lines(x + 1, y + 1, slot - 2, slot - 2, UI.text);
                if (mouse.just_pressed) {
                    const default_palette = image.palette_id;
                    if (mode == .tiles) {
                        self.selected_tile = @intCast(@min(image_id, 255));
                        self.bg_attr.palette = default_palette;
                        self.tool = .bg_stamp;
                        self.setInfo("BG tile selected", UI.accent);
                    } else {
                        self.selected_sprite = image_id;
                        self.sprite_attr.palette = default_palette;
                        self.tool = .sprite_stamp;
                        self.setInfo("Sprite selected", UI.accent);
                    }
                }
                if (mouse.just_right_pressed) {
                    project.setMode(mode);
                    main_editor.library_request = .{ .mode = .swap_tile, .slot_index = @intCast(i), .tile_id = image_id };
                    main_editor.library_return_state = .map_editor;
                    main_editor.suppress_canvas_paint_until_mouse_up = true;
                    sm.go_to(.tile_library);
                }
            }
        }
    }

    fn brushSizeButton(self: *MapEditor, fui: anytype, renderer: *Render, mouse: Mouse, x: i32, y: i32, label: []const u8, size: u8) void {
        if (button(fui, renderer, mouse, x, y, 54, 30, label, self.brush_size == size)) {
            self.brush_size = size;
            self.setInfo("Brush size changed", UI.accent);
        }
    }

    fn drawAttrEditor(self: *MapEditor, fui: anytype, renderer: *Render, mouse: Mouse, y: i32) void {
        const editing_sprite = self.tool == .sprite_stamp;
        const active_attr = if (editing_sprite) self.sprite_attr else self.bg_attr;

        drawText(fui, renderer, "PALETTE", UI.left_x + 20, y, 1, UI.muted);
        for (0..8) |p| {
            const x = UI.left_x + 20 + @as(i32, @intCast(p)) * 30;
            var label_buf: [2]u8 = undefined;
            const label = std.fmt.bufPrint(&label_buf, "{d}", .{p}) catch "?";
            if (button(fui, renderer, mouse, x, y + 22, 28, 28, label, active_attr.palette == p)) {
                if (editing_sprite) {
                    self.sprite_attr.palette = @intCast(p);
                } else {
                    self.bg_attr.palette = @intCast(p);
                }
                self.setInfo("Palette assigned", UI.accent);
            }
        }
        if (button(fui, renderer, mouse, UI.left_x + 20, y + 64, 112, 36, "H FLIP", active_attr.hflip)) {
            if (editing_sprite) {
                self.sprite_attr.hflip = !self.sprite_attr.hflip;
            } else {
                self.bg_attr.hflip = !self.bg_attr.hflip;
            }
            self.setInfo("Horizontal flip toggled", UI.accent);
        }
        if (button(fui, renderer, mouse, UI.left_x + 142, y + 64, 112, 36, "V FLIP", active_attr.vflip)) {
            if (editing_sprite) {
                self.sprite_attr.vflip = !self.sprite_attr.vflip;
            } else {
                self.bg_attr.vflip = !self.bg_attr.vflip;
            }
            self.setInfo("Vertical flip toggled", UI.accent);
        }
    }

    fn sizeButton(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, x: i32, y: i32, w: i32, h: i32, label: []const u8, pending: PendingSize, width: u16, height: u16) void {
        const map = project.activeMap();
        const active = map.width == width and map.height == height;
        const confirm = self.pending_size == pending;
        if (button(fui, renderer, mouse, x, y, w, h, label, active or confirm)) {
            if (active) {
                self.pending_size = .none;
                return;
            }
            if (confirm) {
                _ = project.resizeMap(width, height);
                self.pending_size = .none;
                self.pending_clear_map = false;
                self.setInfo("Map resized and cropped", UI.warn);
            } else {
                self.pending_clear_map = false;
                self.pending_size = pending;
                self.setInfo("Click same size again to confirm crop", UI.warn);
            }
        }
    }

    fn handleArrowPan(self: *MapEditor, project: *const Project, arrows: ArrowKeys) void {
        const cell_px = @as(i32, CONF.TILE_SIDE) * self.canvasScale(project);
        const step = @max(4, @divFloor(cell_px, 2));
        if (arrows.left) self.pan_x += step;
        if (arrows.right) self.pan_x -= step;
        if (arrows.up) self.pan_y += step;
        if (arrows.down) self.pan_y -= step;
    }

    fn handleCanvas(self: *MapEditor, project: *Project, mouse: Mouse) void {
        if (!mouse.left_down and !mouse.right_down) {
            self.random_last_cell = null;
            self.selection_drag_anchor = null;
            self.suppress_canvas_until_mouse_up = false;
        }
        if (self.suppress_canvas_until_mouse_up) return;

        const cell = self.canvasCell(project, mouse.x, mouse.y) orelse return;
        if (self.pending_paste) {
            if (mouse.just_right_pressed) {
                self.pending_paste = false;
                self.suppress_canvas_until_mouse_up = true;
                self.setInfo("Paste cancelled", UI.muted);
                return;
            }
            if (mouse.just_pressed) {
                self.pasteSelectionAt(project, cell);
                self.pending_paste = false;
                self.suppress_canvas_until_mouse_up = true;
                return;
            }
            return;
        }
        if (self.tool == .bg_path9 and mouse.right_down) {
            self.erasePath9Brush(project, cell);
            return;
        }
        if (mouse.just_right_pressed) {
            if (project.mapCellAt(cell[0], cell[1])) |map_cell| {
                self.selected_tile = map_cell.tile_id;
                self.bg_attr = map_cell.attr;
                self.setInfo("Picked map cell", UI.accent);
            }
            return;
        }
        if (mouse.left_down) {
            switch (self.tool) {
                .bg_stamp => self.paintStampBrush(project, cell),
                .bg_fill => {
                    if (mouse.just_pressed) _ = project.fillMapTile(cell[0], cell[1], self.selected_tile, self.bg_attr);
                },
                .bg_random_row => self.paintRandomSelectedRowBrush(project, cell),
                .bg_path9 => self.paintPath9Brush(project, cell),
                .sprite_stamp => _ = project.addOrUpdateMapSprite(cell[0], cell[1], self.selected_sprite, self.sprite_attr),
                .sprite_remove => {
                    if (project.removeMapSpriteAt(cell[0], cell[1])) self.setInfo("Sprite removed", UI.accent);
                },
                .select => self.updateSelectionDrag(cell, mouse),
            }
        }
    }

    fn updateSelectionDrag(self: *MapEditor, cell: [2]u16, mouse: Mouse) void {
        if (mouse.just_pressed or self.selection_drag_anchor == null) {
            self.selection_drag_anchor = cell;
        }
        const anchor = self.selection_drag_anchor orelse cell;
        self.selection = rectFromCells(anchor, cell);
        self.setInfo("Map area selected", UI.accent);
    }

    fn copySelection(self: *MapEditor, project: *const Project) void {
        const rect = self.clampedSelection(project) orelse {
            self.setInfo("No map selection", UI.warn);
            return;
        };
        const map = project.activeMap();
        self.clipboard_w = rect.w;
        self.clipboard_h = rect.h;
        self.pending_paste = false;

        var y: u16 = 0;
        while (y < rect.h) : (y += 1) {
            var x: u16 = 0;
            while (x < rect.w) : (x += 1) {
                const src = @as(usize, rect.y + y) * @as(usize, map.width) + @as(usize, rect.x + x);
                const dst = @as(usize, y) * @as(usize, rect.w) + x;
                self.clipboard_tile_ids[dst] = map.tile_ids[src];
                self.clipboard_tile_attrs[dst] = map.tile_attrs[src];
            }
        }

        self.clipboard_sprite_count = 0;
        var sprite_index: usize = 0;
        while (sprite_index < map.sprite_count and self.clipboard_sprite_count < project_mod.MAX_MAP_SPRITES) : (sprite_index += 1) {
            const sprite = map.sprites[sprite_index];
            if (sprite.x >= rect.x and sprite.x < rect.x + rect.w and sprite.y >= rect.y and sprite.y < rect.y + rect.h) {
                var relative = sprite;
                relative.x -= rect.x;
                relative.y -= rect.y;
                self.clipboard_sprites[self.clipboard_sprite_count] = relative;
                self.clipboard_sprite_count += 1;
            }
        }

        self.setInfo("Map selection copied", UI.accent);
    }

    fn armPasteSelection(self: *MapEditor) void {
        if (!self.hasClipboard()) {
            self.pending_paste = false;
            self.setInfo("Clipboard empty", UI.warn);
            return;
        }
        self.pending_paste = true;
        self.selection_drag_anchor = null;
        self.setInfo("Click map to paste, RMB cancels", UI.accent);
    }

    fn pasteSelectionAt(self: *MapEditor, project: *Project, cell: [2]u16) void {
        if (!self.hasClipboard()) {
            self.setInfo("Clipboard empty", UI.warn);
            return;
        }
        const dest = self.pasteRectForCell(project, cell);
        const map = project.activeMap();
        var changed = false;

        var y: u16 = 0;
        while (y < self.clipboard_h and dest.y + y < map.height) : (y += 1) {
            var x: u16 = 0;
            while (x < self.clipboard_w and dest.x + x < map.width) : (x += 1) {
                const src = @as(usize, y) * @as(usize, self.clipboard_w) + x;
                changed = project.paintMapTile(dest.x + x, dest.y + y, self.clipboard_tile_ids[src], MapTileAttr.decode(self.clipboard_tile_attrs[src])) or changed;
            }
        }

        var sprite_index: usize = 0;
        while (sprite_index < self.clipboard_sprite_count) : (sprite_index += 1) {
            const sprite = self.clipboard_sprites[sprite_index];
            const px = dest.x + sprite.x;
            const py = dest.y + sprite.y;
            if (px < map.width and py < map.height) {
                changed = project.addOrUpdateMapSprite(px, py, sprite.sprite_id, .{ .palette = sprite.palette, .hflip = sprite.hflip, .vflip = sprite.vflip }) or changed;
            }
        }

        if (changed) self.invalidateCache();
        self.setInfo(if (changed) "Map selection pasted" else "Paste unchanged", if (changed) UI.accent else UI.muted);
    }

    fn pasteRectForCell(self: *const MapEditor, project: *const Project, cell: [2]u16) MapSelectionRect {
        const map = project.activeMap();
        const max_x: u16 = if (self.clipboard_w >= map.width) 0 else map.width - self.clipboard_w;
        const max_y: u16 = if (self.clipboard_h >= map.height) 0 else map.height - self.clipboard_h;
        return .{
            .x = @min(cell[0], max_x),
            .y = @min(cell[1], max_y),
            .w = @min(self.clipboard_w, map.width),
            .h = @min(self.clipboard_h, map.height),
        };
    }

    fn hasClipboard(self: *const MapEditor) bool {
        return self.clipboard_w > 0 and self.clipboard_h > 0;
    }

    fn clampedSelection(self: *const MapEditor, project: *const Project) ?MapSelectionRect {
        const rect = self.selection orelse return null;
        const map = project.activeMap();
        if (rect.x >= map.width or rect.y >= map.height) return null;
        return .{
            .x = rect.x,
            .y = rect.y,
            .w = @min(rect.w, map.width - rect.x),
            .h = @min(rect.h, map.height - rect.y),
        };
    }

    fn paintStampBrush(self: *MapEditor, project: *Project, cell: [2]u16) void {
        const origin = self.brushOrigin(cell);
        self.paintBrushCells(project, origin, false);
    }

    fn paintRandomSelectedRowBrush(self: *MapEditor, project: *Project, cell: [2]u16) void {
        if (self.random_last_cell) |last| {
            if (last[0] == cell[0] and last[1] == cell[1]) return;
        }
        self.random_last_cell = cell;
        const origin = self.brushOrigin(cell);
        self.paintBrushCells(project, origin, true);
    }

    fn paintPath9Brush(self: *MapEditor, project: *Project, cell: [2]u16) void {
        const origin = self.brushOrigin(cell);
        self.paintPath9Cells(project, origin, true);
    }

    fn erasePath9Brush(self: *MapEditor, project: *Project, cell: [2]u16) void {
        const origin = self.brushOrigin(cell);
        self.paintPath9Cells(project, origin, false);
    }

    fn paintPath9Cells(self: *MapEditor, project: *Project, origin: [2]i32, add: bool) void {
        const map = project.activeMap();
        var changed = false;

        var by: u8 = 0;
        while (by < self.brush_size) : (by += 1) {
            const y = origin[1] + by;
            if (y < 0 or y >= map.height) continue;
            var bx: u8 = 0;
            while (bx < self.brush_size) : (bx += 1) {
                const x = origin[0] + bx;
                if (x < 0 or x >= map.width) continue;
                if (add) {
                    const seed = self.path9PlacementForSlot(project, self.randomPath9FillerSlot(), false);
                    changed = project.paintMapTile(@intCast(x), @intCast(y), @intCast(@min(seed.tile_id, 255)), seed.attr) or changed;
                } else if (self.isPath9Tile(project, map.tile_ids[@as(usize, @intCast(y)) * @as(usize, map.width) + @as(usize, @intCast(x))])) {
                    changed = project.paintMapTile(@intCast(x), @intCast(y), 0, .{}) or changed;
                }
            }
        }

        changed = self.refreshPath9Region(project, origin[0] - 1, origin[1] - 1, @as(i32, self.brush_size) + 2, @as(i32, self.brush_size) + 2) or changed;
        if (changed) self.setInfo(if (add) "Path9 painted" else "Path9 erased", UI.accent);
    }

    fn refreshPath9Region(self: *MapEditor, project: *Project, x0: i32, y0: i32, w: i32, h: i32) bool {
        const map = project.activeMap();
        var changed = false;
        const min_x = @max(0, x0);
        const min_y = @max(0, y0);
        const max_x = @min(@as(i32, map.width), x0 + w);
        const max_y = @min(@as(i32, map.height), y0 + h);

        var y = min_y;
        while (y < max_y) : (y += 1) {
            var x = min_x;
            while (x < max_x) : (x += 1) {
                const idx = @as(usize, @intCast(y)) * @as(usize, map.width) + @as(usize, @intCast(x));
                if (!self.isPath9Tile(project, map.tile_ids[idx])) continue;
                const placement = self.path9PlacementForCell(project, @intCast(x), @intCast(y));
                changed = project.paintMapTile(@intCast(x), @intCast(y), @intCast(@min(placement.tile_id, 255)), placement.attr) or changed;
            }
        }
        return changed;
    }

    fn path9PlacementForCell(self: *MapEditor, project: *const Project, x: u16, y: u16) Path9Placement {
        const north = self.path9Neighbor(project, x, y, 0, -1);
        const south = self.path9Neighbor(project, x, y, 0, 1);
        const west = self.path9Neighbor(project, x, y, -1, 0);
        const east = self.path9Neighbor(project, x, y, 1, 0);

        if (!north) {
            if (!west) return self.path9PlacementForSlot(project, Path9Slots.top_left_corner, false);
            if (!east) return self.path9PlacementForSlot(project, Path9Slots.top_left_corner, true);
            return self.path9PlacementForSlot(project, Path9Slots.top_edge, false);
        }
        if (!south) {
            if (!west) return self.path9PlacementForSlot(project, Path9Slots.bottom_left_corner, false);
            if (!east) return self.path9PlacementForSlot(project, Path9Slots.bottom_left_corner, true);
            return self.path9PlacementForSlot(project, Path9Slots.bottom_edge, false);
        }
        if (!west) return self.path9PlacementForSlot(project, Path9Slots.left_edge, false);
        if (!east) return self.path9PlacementForSlot(project, Path9Slots.left_edge, true);

        if (!self.path9Neighbor(project, x, y, -1, -1)) return self.path9PlacementForSlot(project, Path9Slots.top_inner_corner, false);
        if (!self.path9Neighbor(project, x, y, 1, -1)) return self.path9PlacementForSlot(project, Path9Slots.top_inner_corner, true);
        if (!self.path9Neighbor(project, x, y, -1, 1)) return self.path9PlacementForSlot(project, Path9Slots.bottom_inner_corner, false);
        if (!self.path9Neighbor(project, x, y, 1, 1)) return self.path9PlacementForSlot(project, Path9Slots.bottom_inner_corner, true);

        return self.path9InteriorPlacement(project, x, y);
    }

    fn path9InteriorPlacement(self: *MapEditor, project: *const Project, x: u16, y: u16) Path9Placement {
        const slot = self.existingPath9FillerSlot(project, x, y) orelse self.randomPath9FillerSlot();
        return self.path9PlacementForSlot(project, slot, false);
    }

    fn existingPath9FillerSlot(self: *const MapEditor, project: *const Project, x: u16, y: u16) ?usize {
        _ = self;
        const map = project.activeMap();
        const idx = @as(usize, y) * @as(usize, map.width) + x;
        const current_id = map.tile_ids[idx];
        if (current_id == project.visibleSlotMode(.tiles, Path9Slots.filler_a)) return Path9Slots.filler_a;
        if (current_id == project.visibleSlotMode(.tiles, Path9Slots.filler_b)) return Path9Slots.filler_b;
        return null;
    }

    fn randomPath9FillerSlot(self: *MapEditor) usize {
        const filler_slots = [_]usize{ Path9Slots.filler_a, Path9Slots.filler_b };
        self.random_state = self.random_state *% 1664525 +% 1013904223;
        const choice: usize = @intCast(self.random_state % @as(u32, @intCast(filler_slots.len)));
        return filler_slots[choice];
    }

    fn path9PlacementForSlot(self: *const MapEditor, project: *const Project, slot: usize, hflip: bool) Path9Placement {
        _ = self;
        const tile_id = project.visibleSlotMode(.tiles, slot);
        var attr = path9AttrForTile(project, tile_id);
        attr.hflip = hflip;
        return .{ .tile_id = tile_id, .attr = attr };
    }

    fn path9Neighbor(self: *const MapEditor, project: *const Project, x: u16, y: u16, dx: i32, dy: i32) bool {
        const map = project.activeMap();
        const nx = @as(i32, x) + dx;
        const ny = @as(i32, y) + dy;
        if (nx < 0 or ny < 0 or nx >= map.width or ny >= map.height) return false;
        const idx = @as(usize, @intCast(ny)) * @as(usize, map.width) + @as(usize, @intCast(nx));
        return self.isPath9Tile(project, map.tile_ids[idx]);
    }

    fn isPath9Tile(self: *const MapEditor, project: *const Project, tile_id: u8) bool {
        _ = self;
        for (0..9) |slot| {
            if (project.visibleSlotMode(.tiles, slot) == tile_id) return true;
        }
        return false;
    }

    fn paintBrushCells(self: *MapEditor, project: *Project, origin: [2]i32, randomize: bool) void {
        const map = project.activeMap();
        var by: u8 = 0;
        while (by < self.brush_size) : (by += 1) {
            const y = origin[1] + by;
            if (y < 0 or y >= map.height) continue;
            var bx: u8 = 0;
            while (bx < self.brush_size) : (bx += 1) {
                const x = origin[0] + bx;
                if (x < 0 or x >= map.width) continue;

                var tile_id: u16 = self.selected_tile;
                var attr = self.bg_attr;
                if (randomize) {
                    tile_id = self.randomSelectedRowTile(project);
                    attr.palette = project.imageAtMode(.tiles, tile_id).palette_id;
                }
                _ = project.paintMapTile(@intCast(x), @intCast(y), @intCast(@min(tile_id, 255)), attr);
            }
        }
    }

    fn randomSelectedRowTile(self: *MapEditor, project: *const Project) u16 {
        self.random_state = self.random_state *% 1664525 +% 1013904223;
        const row = self.selectedTileRow(project);
        const slot = row * 3 + @as(usize, @intCast(self.random_state % 3));
        return project.visibleSlotMode(.tiles, slot);
    }

    fn selectedTileRow(self: *const MapEditor, project: *const Project) usize {
        for (0..9) |slot| {
            if (project.visibleSlotMode(.tiles, slot) == @as(u16, self.selected_tile)) return slot / 3;
        }
        return 0;
    }

    fn brushOrigin(self: *const MapEditor, cell: [2]u16) [2]i32 {
        const offset = @divFloor(@as(i32, self.effectiveBrushSize()) - 1, 2);
        return .{ @as(i32, cell[0]) - offset, @as(i32, cell[1]) - offset };
    }

    fn effectiveBrushSize(self: *const MapEditor) u8 {
        return switch (self.tool) {
            .bg_stamp, .bg_random_row, .bg_path9 => self.brush_size,
            else => 1,
        };
    }

    fn drawCanvas(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse) void {
        panel(renderer, UI.canvas_x, UI.canvas_y, UI.canvas_w, UI.canvas_h);
        const scale = self.canvasScale(project);
        const cell_px = @as(i32, CONF.TILE_SIDE) * scale;
        const origin = self.canvasOrigin(project);
        const map = project.activeMap();
        const map_w = @as(i32, map.width) * cell_px;
        const map_h = @as(i32, map.height) * cell_px;

        self.ensureMapCache(renderer, project, origin, scale, cell_px, map_w, map_h);
        copyTerrainRectToFrame(renderer, origin[0], origin[1], map_w, map_h, UI.canvas_x + 1, UI.canvas_y + 1, UI.canvas_w - 2, UI.canvas_h - 2);

        if (self.show_grid) self.drawGridOverlay(renderer, project, origin, cell_px, map_w, map_h);
        if (self.show_gbc_screen) self.drawGameBoyScreenOverlay(renderer, project, mouse, origin, cell_px);
        self.drawSelectionOverlay(renderer, project, origin, cell_px);

        if (self.pending_paste) {
            self.drawPastePreview(renderer, project, mouse, origin, cell_px);
        } else if (self.tool != .select) {
            if (self.canvasCell(project, mouse.x, mouse.y)) |cell| {
                const brush_origin = self.brushOrigin(cell);
                const hx = origin[0] + brush_origin[0] * cell_px;
                const hy = origin[1] + brush_origin[1] * cell_px;
                const brush_px = @as(i32, self.effectiveBrushSize()) * cell_px;
                drawClippedRectLines(renderer, hx, hy, brush_px, brush_px, canvasContentClip(), UI.text);
            }
        }
        self.drawCanvasHeader(fui, renderer, project, mouse);
    }

    fn drawSelectionOverlay(self: *MapEditor, renderer: *Render, project: *const Project, origin: [2]i32, cell_px: i32) void {
        const rect = self.clampedSelection(project) orelse return;
        const x = origin[0] + @as(i32, rect.x) * cell_px;
        const y = origin[1] + @as(i32, rect.y) * cell_px;
        const w = @as(i32, rect.w) * cell_px;
        const h = @as(i32, rect.h) * cell_px;
        const clip = canvasContentClip();
        drawClippedRectLines(renderer, x, y, w, h, clip, UI.accent);
        drawClippedRectLines(renderer, x + 1, y + 1, w - 2, h - 2, clip, UI.text);
    }

    fn drawPastePreview(self: *MapEditor, renderer: *Render, project: *const Project, mouse: Mouse, origin: [2]i32, cell_px: i32) void {
        if (!self.hasClipboard()) return;
        const cell = self.canvasCell(project, mouse.x, mouse.y) orelse return;
        const rect = self.pasteRectForCell(project, cell);
        const x = origin[0] + @as(i32, rect.x) * cell_px;
        const y = origin[1] + @as(i32, rect.y) * cell_px;
        const w = @as(i32, rect.w) * cell_px;
        const h = @as(i32, rect.h) * cell_px;
        const clip = canvasContentClip();
        drawClippedRectLines(renderer, x, y, w, h, clip, UI.warn);
        drawClippedRectLines(renderer, x + 1, y + 1, w - 2, h - 2, clip, UI.text);
    }

    fn ensureMapCache(self: *MapEditor, renderer: *Render, project: *Project, origin: [2]i32, scale: i32, cell_px: i32, map_w: i32, map_h: i32) void {
        const revision = project.visualRevision();
        const map = project.activeMap();
        if (!self.cache_dirty and self.cached_map_revision == revision and self.cached_map_scale == scale and self.cached_map_width == map.width and self.cached_map_height == map.height and self.cached_origin_x == origin[0] and self.cached_origin_y == origin[1]) return;

        const previous_target = renderer.target;
        renderer.set_target(.terrain);
        renderer.draw_rect(origin[0], origin[1], map_w, map_h, 0x101418);

        var y: u16 = 0;
        while (y < map.height) : (y += 1) {
            var x: u16 = 0;
            while (x < map.width) : (x += 1) {
                const idx = @as(usize, y) * @as(usize, map.width) + x;
                const attr = MapTileAttr.decode(map.tile_attrs[idx]);
                views.drawImageWithAttrs(renderer, project, .tiles, map.tile_ids[idx], attr.palette, attr.hflip, attr.vflip, origin[0] + @as(i32, x) * cell_px, origin[1] + @as(i32, y) * cell_px, scale);
            }
        }

        var si: usize = 0;
        while (si < map.sprite_count) : (si += 1) {
            const sprite = map.sprites[si];
            if (sprite.x < map.width and sprite.y < map.height) {
                views.drawImageWithAttrs(renderer, project, .sprites, sprite.sprite_id, sprite.palette, sprite.hflip, sprite.vflip, origin[0] + @as(i32, sprite.x) * cell_px, origin[1] + @as(i32, sprite.y) * cell_px, scale);
            }
        }

        renderer.set_target(previous_target);
        self.cached_map_revision = revision;
        self.cached_map_scale = scale;
        self.cached_map_width = map.width;
        self.cached_map_height = map.height;
        self.cached_origin_x = origin[0];
        self.cached_origin_y = origin[1];
        self.cache_dirty = false;
    }

    fn drawGridOverlay(self: *MapEditor, renderer: *Render, project: *const Project, origin: [2]i32, cell_px: i32, map_w: i32, map_h: i32) void {
        _ = self;
        const map = project.activeMap();
        const clip = canvasContentClip();
        var gx: u16 = 0;
        while (gx <= map.width) : (gx += 1) {
            const x = origin[0] + @as(i32, gx) * cell_px;
            drawClippedVLine(renderer, x, origin[1], map_h, clip, 0x2B323A);
        }
        var gy: u16 = 0;
        while (gy <= map.height) : (gy += 1) {
            const yline = origin[1] + @as(i32, gy) * cell_px;
            drawClippedHLine(renderer, origin[0], yline, map_w, clip, 0x2B323A);
        }
    }

    fn drawGameBoyScreenOverlay(self: *MapEditor, renderer: *Render, project: *const Project, mouse: Mouse, origin: [2]i32, cell_px: i32) void {
        const map = project.activeMap();
        const view_w_cells = @min(GBC_SCREEN_W_TILES, @as(i32, map.width));
        const view_h_cells = @min(GBC_SCREEN_H_TILES, @as(i32, map.height));
        if (view_w_cells <= 0 or view_h_cells <= 0) return;

        const focus = self.canvasCell(project, mouse.x, mouse.y);
        const max_x = @as(i32, map.width) - view_w_cells;
        const max_y = @as(i32, map.height) - view_h_cells;
        const left_cell = if (focus) |cell| @max(0, @min(max_x, @as(i32, cell[0]) - @divFloor(view_w_cells, 2))) else @divFloor(max_x, 2);
        const top_cell = if (focus) |cell| @max(0, @min(max_y, @as(i32, cell[1]) - @divFloor(view_h_cells, 2))) else @divFloor(max_y, 2);

        const x = origin[0] + left_cell * cell_px;
        const y = origin[1] + top_cell * cell_px;
        const w = view_w_cells * cell_px;
        const h = view_h_cells * cell_px;
        const clip = canvasContentClip();

        drawClippedRectLines(renderer, x, y, w, h, clip, UI.warn);
        drawClippedRectLines(renderer, x + 1, y + 1, w - 2, h - 2, clip, UI.text);
    }

    fn drawCanvasHeader(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse) void {
        renderer.draw_rect(UI.canvas_x + 1, UI.canvas_y + 1, UI.canvas_w - 2, 56, UI.panel);

        const y = UI.canvas_y + 13;
        const x = UI.canvas_x + 18;
        drawText(fui, renderer, "ZOOM", x, y + 10, 1, UI.muted);
        if (button(fui, renderer, mouse, x + 54, y, 38, 32, "-", false) and self.zoom_extra > 0) {
            self.zoom_extra -= 1;
            self.setInfo("Zoom out", UI.accent);
        }
        var zoom_buf: [16]u8 = undefined;
        const zoom_text = std.fmt.bufPrint(&zoom_buf, "+{d}", .{self.zoom_extra}) catch "+?";
        drawText(fui, renderer, zoom_text, x + 106, y + 12, 1, UI.accent);
        if (button(fui, renderer, mouse, x + 144, y, 38, 32, "+", false) and self.zoom_extra < 6) {
            self.zoom_extra += 1;
            self.setInfo("Zoom in", UI.accent);
        }
        if (button(fui, renderer, mouse, x + 202, y, 112, 32, "RESET VIEW", false)) {
            self.zoom_extra = 0;
            self.pan_x = 0;
            self.pan_y = 0;
            self.setInfo("View reset", UI.accent);
        }
        if (button(fui, renderer, mouse, x + 334, y, 74, 32, "GRID", self.show_grid)) {
            self.show_grid = !self.show_grid;
            self.setInfo(if (self.show_grid) "Grid on" else "Grid off", UI.accent);
        }
        if (button(fui, renderer, mouse, x + 424, y, 104, 32, "GBC VIEW", self.show_gbc_screen)) {
            self.show_gbc_screen = !self.show_gbc_screen;
            self.setInfo(if (self.show_gbc_screen) "GBC screen on" else "GBC screen off", UI.accent);
        }
        self.drawSelectionHeader(fui, renderer, project, x + 550, y + 12);
    }

    fn drawSelectionHeader(self: *MapEditor, fui: anytype, renderer: *Render, project: *const Project, x: i32, y: i32) void {
        var size_buf: [32]u8 = undefined;
        if (self.pending_paste and self.hasClipboard()) {
            const label = std.fmt.bufPrint(&size_buf, "PASTE {d}x{d}", .{ self.clipboard_w, self.clipboard_h }) catch "PASTE ?x?";
            drawText(fui, renderer, label, x, y, 1, UI.warn);
            return;
        }
        const label = if (self.clampedSelection(project)) |rect|
            std.fmt.bufPrint(&size_buf, "SEL {d}x{d}", .{ rect.w, rect.h }) catch "SEL ?x?"
        else
            "SEL NONE";
        drawText(fui, renderer, label, x, y, 1, if (self.selection != null) UI.accent else UI.muted);
    }

    fn canvasScale(self: *MapEditor, project: *const Project) i32 {
        const map = project.activeMap();
        const available_w = UI.canvas_w - 40;
        const available_h = UI.canvas_h - 86;
        const map_px_w = @as(i32, map.width) * CONF.TILE_SIDE;
        const map_px_h = @as(i32, map.height) * CONF.TILE_SIDE;
        const fit = @max(1, @min(@divFloor(available_w, map_px_w), @divFloor(available_h, map_px_h)));
        return fit + self.zoom_extra;
    }

    fn canvasOrigin(self: *MapEditor, project: *const Project) [2]i32 {
        const map = project.activeMap();
        const scale = self.canvasScale(project);
        const map_w = @as(i32, map.width) * CONF.TILE_SIDE * scale;
        const map_h = @as(i32, map.height) * CONF.TILE_SIDE * scale;
        return .{ UI.canvas_x + @divFloor(UI.canvas_w - map_w, 2) + self.pan_x, UI.canvas_y + 64 + @divFloor(UI.canvas_h - 78 - map_h, 2) + self.pan_y };
    }

    fn canvasCell(self: *MapEditor, project: *const Project, mx: i32, my: i32) ?[2]u16 {
        const scale = self.canvasScale(project);
        const cell_px = @as(i32, CONF.TILE_SIDE) * scale;
        const origin = self.canvasOrigin(project);
        const map = project.activeMap();
        const map_w = @as(i32, map.width) * cell_px;
        const map_h = @as(i32, map.height) * cell_px;
        if (mx < UI.canvas_x + 1 or my < UI.canvas_y + 58 or mx >= UI.canvas_x + UI.canvas_w - 1 or my >= UI.canvas_y + UI.canvas_h - 1) return null;
        if (mx < origin[0] or my < origin[1] or mx >= origin[0] + map_w or my >= origin[1] + map_h) return null;
        return .{ @intCast(@divFloor(mx - origin[0], cell_px)), @intCast(@divFloor(my - origin[1], cell_px)) };
    }

    pub fn setInfo(self: *MapEditor, text: []const u8, color: u32) void {
        self.info_text = text;
        self.info_color = color;
    }
};

fn path9AttrForTile(project: *const Project, tile_id: u16) MapTileAttr {
    return .{ .palette = project.imageAtMode(.tiles, @min(tile_id, project.imageCountMode(.tiles) - 1)).palette_id };
}

fn rectFromCells(a: [2]u16, b: [2]u16) MapSelectionRect {
    const x0 = @min(a[0], b[0]);
    const y0 = @min(a[1], b[1]);
    const x1 = @max(a[0], b[0]);
    const y1 = @max(a[1], b[1]);
    return .{ .x = x0, .y = y0, .w = x1 - x0 + 1, .h = y1 - y0 + 1 };
}

const ClipRect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
};

fn canvasContentClip() ClipRect {
    return .{
        .x = UI.canvas_x + 1,
        .y = UI.canvas_y + 58,
        .w = UI.canvas_w - 2,
        .h = UI.canvas_h - 59,
    };
}

fn drawClippedHLine(renderer: *Render, x: i32, y: i32, w: i32, clip: ClipRect, color: u32) void {
    if (w <= 0 or y < clip.y or y >= clip.y + clip.h) return;
    const x0 = @max(x, clip.x);
    const x1 = @min(x + w, clip.x + clip.w);
    if (x0 >= x1) return;
    renderer.draw_hline(x0, y, x1 - x0, color);
}

fn drawClippedVLine(renderer: *Render, x: i32, y: i32, h: i32, clip: ClipRect, color: u32) void {
    if (h <= 0 or x < clip.x or x >= clip.x + clip.w) return;
    const y0 = @max(y, clip.y);
    const y1 = @min(y + h, clip.y + clip.h);
    if (y0 >= y1) return;
    renderer.draw_vline(x, y0, y1 - y0, color);
}

fn drawClippedRectLines(renderer: *Render, x: i32, y: i32, w: i32, h: i32, clip: ClipRect, color: u32) void {
    if (w <= 0 or h <= 0) return;
    drawClippedHLine(renderer, x, y, w, clip, color);
    if (h > 1) drawClippedHLine(renderer, x, y + h - 1, w, clip, color);
    if (h > 2) {
        drawClippedVLine(renderer, x, y + 1, h - 2, clip, color);
        if (w > 1) drawClippedVLine(renderer, x + w - 1, y + 1, h - 2, clip, color);
    }
}

fn copyTerrainRectToFrame(renderer: *Render, x: i32, y: i32, w: i32, h: i32, clip_x: i32, clip_y: i32, clip_w: i32, clip_h: i32) void {
    if (w <= 0 or h <= 0) return;
    var rx = x;
    var ry = y;
    var rw = w;
    var rh = h;
    if (rx < 0) {
        rw += rx;
        rx = 0;
    }
    if (ry < 0) {
        rh += ry;
        ry = 0;
    }
    if (rx < clip_x) {
        rw -= clip_x - rx;
        rx = clip_x;
    }
    if (ry < clip_y) {
        rh -= clip_y - ry;
        ry = clip_y;
    }
    if (rx + rw > clip_x + clip_w) rw = clip_x + clip_w - rx;
    if (ry + rh > clip_y + clip_h) rh = clip_y + clip_h - ry;
    if (rx + rw > renderer.width) rw = renderer.width - rx;
    if (ry + rh > renderer.height) rh = renderer.height - ry;
    if (rw <= 0 or rh <= 0) return;

    const screen_w: usize = @intCast(renderer.width);
    const sx: usize = @intCast(rx);
    const sy: usize = @intCast(ry);
    const sw: usize = @intCast(rw);
    const sh: usize = @intCast(rh);
    var row: usize = 0;
    while (row < sh) : (row += 1) {
        const start = (sy + row) * screen_w + sx;
        @memcpy(renderer.frame_buf[start .. start + sw], renderer.terrain_buf[start .. start + sw]);
    }
}

fn button(fui: anytype, renderer: *Render, mouse: Mouse, x: i32, y: i32, w: i32, h: i32, label: []const u8, active: bool) bool {
    return editor_ui.button(fui, renderer, mouse, x, y, w, h, label, active);
}

fn panel(renderer: *Render, x: i32, y: i32, w: i32, h: i32) void {
    editor_ui.panel(renderer, x, y, w, h);
}

fn drawText(fui: anytype, renderer: *Render, text: []const u8, x: i32, y: i32, scale: i32, color: u32) void {
    editor_ui.drawText(fui, renderer, text, x, y, scale, color);
}
