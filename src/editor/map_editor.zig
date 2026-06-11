const std = @import("std");
const CONF = @import("../engine/config.zig").CONF;
const Render = @import("../engine/render.zig").Render;
const Mouse = @import("../engine/mouse.zig").Mouse;
const project_mod = @import("project.zig");
const Project = project_mod.Project;
const ProjectMode = project_mod.ProjectMode;
const MapTileAttr = project_mod.MapTileAttr;
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

const Tool = enum { bg_stamp, bg_fill, bg_random_row, sprite_stamp, sprite_remove };
const PendingSize = enum { none, s32x32, s64x16, s128x16 };
const GBC_SCREEN_W_TILES: i32 = 20;
const GBC_SCREEN_H_TILES: i32 = 18;

pub const MapEditor = struct {
    tool: Tool = .bg_stamp,
    selected_tile: u8 = 0,
    selected_sprite: u16 = 0,
    bg_attr: MapTileAttr = .{},
    sprite_attr: MapTileAttr = .{},
    selected_cell: ?[2]u16 = null,
    pending_size: PendingSize = .none,
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
        if (button(fui, renderer, mouse, UI.left_x + 16, tool_y + 30, 74, 34, "STAMP", self.tool == .bg_stamp)) self.tool = .bg_stamp;
        if (button(fui, renderer, mouse, UI.left_x + 98, tool_y + 30, 62, 34, "FILL", self.tool == .bg_fill)) self.tool = .bg_fill;
        if (button(fui, renderer, mouse, UI.left_x + 168, tool_y + 30, 86, 34, "RND ROW", self.tool == .bg_random_row)) self.tool = .bg_random_row;
        if (button(fui, renderer, mouse, UI.left_x + 16, tool_y + 72, 116, 34, "PLACE SPR", self.tool == .sprite_stamp)) self.tool = .sprite_stamp;
        if (button(fui, renderer, mouse, UI.left_x + 142, tool_y + 72, 110, 34, "REM SPR", self.tool == .sprite_remove)) self.tool = .sprite_remove;

        drawText(fui, renderer, "BG TILES", UI.left_x + 16, UI.canvas_y + 132, 2, UI.text);
        self.drawSelector(fui, renderer, project, main_editor, mouse, sm, .tiles, UI.left_x + 50, UI.canvas_y + 160, 40);

        drawText(fui, renderer, "SPRITES", UI.left_x + 16, UI.canvas_y + 310, 2, UI.text);
        self.drawSelector(fui, renderer, project, main_editor, mouse, sm, .sprites, UI.left_x + 50, UI.canvas_y + 338, 40);
        drawText(fui, renderer, "LMB: SELECT", UI.left_x + 20, UI.canvas_y + 496, 1, UI.muted);
        drawText(fui, renderer, "RMB: LIBRARY", UI.left_x + 136, UI.canvas_y + 496, 1, UI.muted);

        const attr_y = UI.canvas_y + 516;
        drawText(fui, renderer, "SELECTED TILE", UI.left_x + 20, attr_y, 2, UI.text);
        self.drawAttrEditor(fui, renderer, mouse, attr_y + 36);
        drawText(fui, renderer, self.info_text, UI.left_x + 20, UI.canvas_y + UI.canvas_h - 14, 1, self.info_color);
    }

    fn drawRightPanel(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse) void {
        panel(renderer, UI.right_x, UI.canvas_y, UI.right_w, UI.canvas_h);
        const x = UI.right_x + 16;
        const bank_y = UI.canvas_y + 16;
        const size_y = UI.canvas_y + 94;
        const zoom_y = UI.canvas_y + 226;
        const pan_y = UI.canvas_y + 342;
        const view_y = UI.canvas_y + 500;
        const file_y = UI.canvas_y + 590;

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

        drawText(fui, renderer, "ZOOM", x, zoom_y, 2, UI.text);
        if (button(fui, renderer, mouse, x, zoom_y + 32, 54, 34, "-", false) and self.zoom_extra > 0) {
            self.zoom_extra -= 1;
            self.setInfo("Zoom out", UI.accent);
        }
        var zoom_buf: [16]u8 = undefined;
        const zoom_text = std.fmt.bufPrint(&zoom_buf, "+{d}", .{self.zoom_extra}) catch "+?";
        drawText(fui, renderer, zoom_text, x + 78, zoom_y + 44, 1, UI.accent);
        if (button(fui, renderer, mouse, x + 134, zoom_y + 32, 54, 34, "+", false) and self.zoom_extra < 6) {
            self.zoom_extra += 1;
            self.setInfo("Zoom in", UI.accent);
        }
        if (button(fui, renderer, mouse, x, zoom_y + 74, 188, 32, "RESET VIEW", false)) {
            self.zoom_extra = 0;
            self.pan_x = 0;
            self.pan_y = 0;
            self.setInfo("View reset", UI.accent);
        }

        drawText(fui, renderer, "PAN", x, pan_y, 2, UI.text);
        const step = @as(i32, CONF.TILE_SIDE) * self.canvasScale(project) * 4;
        if (button(fui, renderer, mouse, x + 67, pan_y + 30, 54, 34, "UP", false)) self.pan_y += step;
        if (button(fui, renderer, mouse, x, pan_y + 72, 54, 34, "<", false)) self.pan_x += step;
        if (button(fui, renderer, mouse, x + 67, pan_y + 72, 54, 34, "0", false)) {
            self.pan_x = 0;
            self.pan_y = 0;
        }
        if (button(fui, renderer, mouse, x + 134, pan_y + 72, 54, 34, ">", false)) self.pan_x -= step;
        if (button(fui, renderer, mouse, x + 67, pan_y + 114, 54, 34, "DN", false)) self.pan_y -= step;

        drawText(fui, renderer, "VIEW", x, view_y, 2, UI.text);
        if (button(fui, renderer, mouse, x, view_y + 32, 86, 34, "GRID", self.show_grid)) {
            self.show_grid = !self.show_grid;
            self.setInfo(if (self.show_grid) "Grid on" else "Grid off", UI.accent);
        }
        if (button(fui, renderer, mouse, x + 102, view_y + 32, 86, 34, "GBC VIEW", self.show_gbc_screen)) {
            self.show_gbc_screen = !self.show_gbc_screen;
            self.setInfo(if (self.show_gbc_screen) "GBC screen on" else "GBC screen off", UI.accent);
        }

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
                self.selected_cell = null;
                self.setInfo("Map resized and cropped", UI.warn);
            } else {
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
        if (!mouse.left_down) self.random_last_cell = null;

        const cell = self.canvasCell(project, mouse.x, mouse.y) orelse return;
        if (mouse.just_right_pressed) {
            if (project.mapCellAt(cell[0], cell[1])) |map_cell| {
                self.selected_tile = map_cell.tile_id;
                self.bg_attr = map_cell.attr;
                self.selected_cell = cell;
                self.setInfo("Picked map cell", UI.accent);
            }
            return;
        }
        if (mouse.left_down) {
            self.selected_cell = cell;
            switch (self.tool) {
                .bg_stamp => _ = project.paintMapTile(cell[0], cell[1], self.selected_tile, self.bg_attr),
                .bg_fill => {
                    if (mouse.just_pressed) _ = project.fillMapTile(cell[0], cell[1], self.selected_tile, self.bg_attr);
                },
                .bg_random_row => self.paintRandomTopRowTile(project, cell),
                .sprite_stamp => _ = project.addOrUpdateMapSprite(cell[0], cell[1], self.selected_sprite, self.sprite_attr),
                .sprite_remove => {
                    if (project.removeMapSpriteAt(cell[0], cell[1])) self.setInfo("Sprite removed", UI.accent);
                },
            }
        }
    }

    fn paintRandomTopRowTile(self: *MapEditor, project: *Project, cell: [2]u16) void {
        if (self.random_last_cell) |last| {
            if (last[0] == cell[0] and last[1] == cell[1]) return;
        }
        self.random_last_cell = cell;
        const tile_id = self.randomTopRowTile(project);
        _ = project.paintMapTile(cell[0], cell[1], tile_id, self.bg_attr);
    }

    fn randomTopRowTile(self: *MapEditor, project: *const Project) u8 {
        self.random_state = self.random_state *% 1664525 +% 1013904223;
        const slot: usize = @intCast(self.random_state % 3);
        return @intCast(@min(project.visibleSlotMode(.tiles, slot), 255));
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

        if (self.canvasCell(project, mouse.x, mouse.y)) |cell| {
            const hx = origin[0] + @as(i32, cell[0]) * cell_px;
            const hy = origin[1] + @as(i32, cell[1]) * cell_px;
            renderer.draw_rect_lines(hx, hy, cell_px, cell_px, UI.text);
        }
        if (self.selected_cell) |cell| {
            const sx = origin[0] + @as(i32, cell[0]) * cell_px;
            const sy = origin[1] + @as(i32, cell[1]) * cell_px;
            renderer.draw_rect_lines(sx + 1, sy + 1, cell_px - 2, cell_px - 2, UI.accent);
        }

        self.drawCanvasHeader(fui, renderer, project, mouse);
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

        const focus = self.selected_cell orelse self.canvasCell(project, mouse.x, mouse.y);
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
        _ = self;
        _ = mouse;
        const map = project.activeMap();
        renderer.draw_rect(UI.canvas_x + 1, UI.canvas_y + 1, UI.canvas_w - 2, 56, UI.panel);
        var buf: [80]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "MAP {d}  {d} x {d}   L: DRAW   R: PICK   ARROWS: PAN", .{ project.activeMapBank() + 1, map.width, map.height }) catch "MAP CANVAS";
        drawText(fui, renderer, text, UI.canvas_x + 18, UI.canvas_y + 18, 2, UI.text);
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

    fn setInfo(self: *MapEditor, text: []const u8, color: u32) void {
        self.info_text = text;
        self.info_color = color;
    }
};

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
