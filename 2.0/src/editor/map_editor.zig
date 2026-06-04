const std = @import("std");
const CONF = @import("../engine/config.zig").CONF;
const Render = @import("../engine/render.zig").Render;
const Mouse = @import("../engine/mouse.zig").Mouse;
const project_mod = @import("project.zig");
const Project = project_mod.Project;
const ProjectMode = project_mod.ProjectMode;
const MapTileAttr = project_mod.MapTileAttr;
const MainEditor = @import("main_editor.zig").MainEditor;
const views = @import("views.zig");

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
    const warn = 0xDAD45E;

    const side_x: i32 = 14;
    const top_y: i32 = 24;
    const top_h: i32 = 82;
    const left_x: i32 = 14;
    const left_w: i32 = 304;
    const gap: i32 = 10;
    const canvas_x: i32 = left_x + left_w + gap;
    const canvas_y: i32 = 110;
    const canvas_w: i32 = CONF.SCREEN_W - canvas_x - 14;
    const canvas_h: i32 = CONF.SCREEN_H - canvas_y - 22;
};

const Tool = enum { bg_stamp, bg_fill, sprite_stamp };
const PendingSize = enum { none, s32x32, s64x16, s128x16 };

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

    pub fn draw(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, main_editor: *MainEditor, mouse: Mouse, sm: anytype) void {
        renderer.draw_rect(0, 0, CONF.SCREEN_W, CONF.SCREEN_H, UI.bg);
        self.drawTopBar(fui, renderer, project, mouse, sm);
        self.drawLeftPanel(fui, renderer, project, main_editor, mouse, sm);
        self.handleCanvas(project, mouse);
        self.drawCanvas(fui, renderer, project, mouse);
    }

    fn drawTopBar(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, sm: anytype) void {
        panel(renderer, UI.side_x, UI.top_y, CONF.SCREEN_W - UI.side_x * 2, UI.top_h);
        drawText(fui, renderer, "MAP EDITOR", 38, 44, 3, UI.text);

        if (button(fui, renderer, mouse, 396, 43, 144, 46, "EDITOR", false)) sm.go_to(.editor);
        if (button(fui, renderer, mouse, 548, 43, 156, 46, "SPRITES", false)) {
            project.setMode(.sprites);
            sm.go_to(.editor);
        }
        _ = button(fui, renderer, mouse, 712, 43, 190, 46, "MAP EDITOR", true);

        if (button(fui, renderer, mouse, 1260, 43, 86, 46, "SAVE", project.dirty)) {
            project.save() catch {
                self.setInfo("Save failed", UI.danger);
                return;
            };
            self.setInfo("File saved", UI.accent);
        }
        if (button(fui, renderer, mouse, 1354, 43, 52, 46, "X", false)) sm.go_to(.quit);
    }

    fn drawLeftPanel(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, main_editor: *MainEditor, mouse: Mouse, sm: anytype) void {
        panel(renderer, UI.left_x, UI.canvas_y, UI.left_w, UI.canvas_h);
        drawText(fui, renderer, "BG TILES", UI.left_x + 20, UI.canvas_y + 18, 2, UI.text);
        self.drawSelector(fui, renderer, project, main_editor, mouse, sm, .tiles, UI.left_x + 54, UI.canvas_y + 48, 56);

        drawText(fui, renderer, "SPRITES", UI.left_x + 20, UI.canvas_y + 240, 2, UI.text);
        self.drawSelector(fui, renderer, project, main_editor, mouse, sm, .sprites, UI.left_x + 54, UI.canvas_y + 270, 56);

        const tool_y = UI.canvas_y + 474;
        drawText(fui, renderer, "TOOLS", UI.left_x + 20, tool_y, 2, UI.text);
        if (button(fui, renderer, mouse, UI.left_x + 20, tool_y + 34, 126, 38, "STAMP", self.tool == .bg_stamp)) self.tool = .bg_stamp;
        if (button(fui, renderer, mouse, UI.left_x + 156, tool_y + 34, 126, 38, "FILL", self.tool == .bg_fill)) self.tool = .bg_fill;
        if (button(fui, renderer, mouse, UI.left_x + 20, tool_y + 82, 262, 38, "PLACE SPRITE", self.tool == .sprite_stamp)) self.tool = .sprite_stamp;

        const attr_y = UI.canvas_y + 616;
        drawText(fui, renderer, "SELECTED TILE", UI.left_x + 20, attr_y, 2, UI.text);
        self.drawAttrEditor(fui, renderer, project, mouse, attr_y + 36);
        drawText(fui, renderer, self.info_text, UI.left_x + 20, UI.canvas_y + UI.canvas_h - 30, 1, self.info_color);
    }

    fn drawSelector(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, main_editor: *MainEditor, mouse: Mouse, sm: anytype, mode: ProjectMode, x0: i32, y0: i32, slot: i32) void {
        _ = fui;
        const scale = @divFloor(slot - 8, CONF.TILE_SIDE);
        for (0..9) |i| {
            const cx: i32 = @intCast(i % 3);
            const cy: i32 = @intCast(i / 3);
            const x = x0 + cx * (slot + 10);
            const y = y0 + cy * (slot + 10);
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

    fn drawAttrEditor(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, y: i32) void {
        drawText(fui, renderer, "PALETTE", UI.left_x + 20, y, 1, UI.muted);
        for (0..8) |p| {
            const x = UI.left_x + 20 + @as(i32, @intCast(p)) * 34;
            var label_buf: [2]u8 = undefined;
            const label = std.fmt.bufPrint(&label_buf, "{d}", .{p}) catch "?";
            if (button(fui, renderer, mouse, x, y + 22, 28, 28, label, self.bg_attr.palette == p)) {
                self.bg_attr.palette = @intCast(p);
                self.sprite_attr.palette = @intCast(p);
                self.applySelectedCellAttr(project);
                self.setInfo("Palette assigned", UI.accent);
            }
        }
        if (button(fui, renderer, mouse, UI.left_x + 20, y + 64, 126, 36, "H FLIP", self.bg_attr.hflip)) {
            self.bg_attr.hflip = !self.bg_attr.hflip;
            self.sprite_attr.hflip = self.bg_attr.hflip;
            self.applySelectedCellAttr(project);
            self.setInfo("Horizontal flip toggled", UI.accent);
        }
        if (button(fui, renderer, mouse, UI.left_x + 156, y + 64, 126, 36, "V FLIP", self.bg_attr.vflip)) {
            self.bg_attr.vflip = !self.bg_attr.vflip;
            self.sprite_attr.vflip = self.bg_attr.vflip;
            self.applySelectedCellAttr(project);
            self.setInfo("Vertical flip toggled", UI.accent);
        }

        drawText(fui, renderer, "SIZE - DOUBLE CLICK TO CROP", UI.left_x + 20, y + 124, 1, UI.muted);
        self.sizeButton(fui, renderer, project, mouse, UI.left_x + 20, y + 146, 82, 34, "32x32", .s32x32, 32, 32);
        self.sizeButton(fui, renderer, project, mouse, UI.left_x + 110, y + 146, 82, 34, "64x16", .s64x16, 64, 16);
        self.sizeButton(fui, renderer, project, mouse, UI.left_x + 200, y + 146, 82, 34, "128x16", .s128x16, 128, 16);
    }

    fn sizeButton(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, x: i32, y: i32, w: i32, h: i32, label: []const u8, pending: PendingSize, width: u16, height: u16) void {
        const active = project.map.width == width and project.map.height == height;
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

    fn handleCanvas(self: *MapEditor, project: *Project, mouse: Mouse) void {
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
                .sprite_stamp => _ = project.addOrUpdateMapSprite(cell[0], cell[1], self.selected_sprite, self.sprite_attr),
            }
        }
    }

    fn drawCanvas(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse) void {
        panel(renderer, UI.canvas_x, UI.canvas_y, UI.canvas_w, UI.canvas_h);
        self.drawCanvasHeader(fui, renderer, project, mouse);
        const scale = self.canvasScale(project);
        const cell_px = @as(i32, CONF.TILE_SIDE) * scale;
        const origin = self.canvasOrigin(project);
        const map_w = @as(i32, project.map.width) * cell_px;
        const map_h = @as(i32, project.map.height) * cell_px;

        self.ensureMapCache(renderer, project, origin, scale, cell_px, map_w, map_h);
        copyTerrainRectToFrame(renderer, origin[0], origin[1], map_w, map_h);

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
    }

    fn ensureMapCache(self: *MapEditor, renderer: *Render, project: *Project, origin: [2]i32, scale: i32, cell_px: i32, map_w: i32, map_h: i32) void {
        const revision = project.visualRevision();
        if (self.cached_map_revision == revision and self.cached_map_scale == scale and self.cached_map_width == project.map.width and self.cached_map_height == project.map.height) return;

        const previous_target = renderer.target;
        renderer.set_target(.terrain);
        renderer.draw_rect(origin[0], origin[1], map_w, map_h, 0x101418);

        var y: u16 = 0;
        while (y < project.map.height) : (y += 1) {
            var x: u16 = 0;
            while (x < project.map.width) : (x += 1) {
                const idx = @as(usize, y) * @as(usize, project.map.width) + x;
                const attr = MapTileAttr.decode(project.map.tile_attrs[idx]);
                views.drawImageWithAttrs(renderer, project, .tiles, project.map.tile_ids[idx], attr.palette, attr.hflip, attr.vflip, origin[0] + @as(i32, x) * cell_px, origin[1] + @as(i32, y) * cell_px, scale);
            }
        }

        var si: usize = 0;
        while (si < project.map.sprite_count) : (si += 1) {
            const sprite = project.map.sprites[si];
            if (sprite.x < project.map.width and sprite.y < project.map.height) {
                views.drawImageWithAttrs(renderer, project, .sprites, sprite.sprite_id, sprite.palette, sprite.hflip, sprite.vflip, origin[0] + @as(i32, sprite.x) * cell_px, origin[1] + @as(i32, sprite.y) * cell_px, scale);
            }
        }

        var gx: u16 = 0;
        while (gx <= project.map.width) : (gx += 1) {
            const x = origin[0] + @as(i32, gx) * cell_px;
            renderer.draw_line(x, origin[1], x, origin[1] + map_h, 0x2B323A);
        }
        var gy: u16 = 0;
        while (gy <= project.map.height) : (gy += 1) {
            const yline = origin[1] + @as(i32, gy) * cell_px;
            renderer.draw_line(origin[0], yline, origin[0] + map_w, yline, 0x2B323A);
        }

        renderer.set_target(previous_target);
        self.cached_map_revision = revision;
        self.cached_map_scale = scale;
        self.cached_map_width = project.map.width;
        self.cached_map_height = project.map.height;
    }

    fn drawCanvasHeader(self: *MapEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse) void {
        _ = self;
        _ = mouse;
        var buf: [80]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "MAP CANVAS  {d} x {d}   L: DRAW   R: PICK", .{ project.map.width, project.map.height }) catch "MAP CANVAS";
        drawText(fui, renderer, text, UI.canvas_x + 18, UI.canvas_y + 18, 2, UI.text);
    }

    fn canvasScale(self: *MapEditor, project: *const Project) i32 {
        _ = self;
        const available_w = UI.canvas_w - 40;
        const available_h = UI.canvas_h - 86;
        const map_px_w = @as(i32, project.map.width) * CONF.TILE_SIDE;
        const map_px_h = @as(i32, project.map.height) * CONF.TILE_SIDE;
        return @max(1, @min(@divFloor(available_w, map_px_w), @divFloor(available_h, map_px_h)));
    }

    fn canvasOrigin(self: *MapEditor, project: *const Project) [2]i32 {
        const scale = self.canvasScale(project);
        const map_w = @as(i32, project.map.width) * CONF.TILE_SIDE * scale;
        const map_h = @as(i32, project.map.height) * CONF.TILE_SIDE * scale;
        return .{ UI.canvas_x + @divFloor(UI.canvas_w - map_w, 2), UI.canvas_y + 64 + @divFloor(UI.canvas_h - 78 - map_h, 2) };
    }

    fn canvasCell(self: *MapEditor, project: *const Project, mx: i32, my: i32) ?[2]u16 {
        const scale = self.canvasScale(project);
        const cell_px = @as(i32, CONF.TILE_SIDE) * scale;
        const origin = self.canvasOrigin(project);
        const map_w = @as(i32, project.map.width) * cell_px;
        const map_h = @as(i32, project.map.height) * cell_px;
        if (mx < origin[0] or my < origin[1] or mx >= origin[0] + map_w or my >= origin[1] + map_h) return null;
        return .{ @intCast(@divFloor(mx - origin[0], cell_px)), @intCast(@divFloor(my - origin[1], cell_px)) };
    }

    fn applySelectedCellAttr(self: *MapEditor, project: *Project) void {
        if (self.selected_cell) |cell| {
            _ = project.paintMapTile(cell[0], cell[1], self.selected_tile, self.bg_attr);
        }
    }

    fn setInfo(self: *MapEditor, text: []const u8, color: u32) void {
        self.info_text = text;
        self.info_color = color;
    }
};

fn copyTerrainRectToFrame(renderer: *Render, x: i32, y: i32, w: i32, h: i32) void {
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
    const hovered = views.hover(mouse, x, y, w, h);
    const bg: u32 = if (active) UI.accent_dark else if (hovered) UI.panel_hi else UI.panel_dark;
    renderer.draw_rect(x + 2, y + 2, w, h, 0x050607);
    renderer.draw_rect(x, y, w, h, bg);
    renderer.draw_rect_lines(x, y, w, h, if (active) UI.accent else UI.border);
    const tw = fui.text_length(label, 1);
    drawText(fui, renderer, label, x + @divFloor(w - tw, 2), y + @divFloor(h - CONF.FONT_HEIGHT, 2), 1, if (active) UI.text else UI.muted);
    return hovered and mouse.just_pressed;
}

fn panel(renderer: *Render, x: i32, y: i32, w: i32, h: i32) void {
    renderer.draw_rect(x + 3, y + 3, w, h, UI.border_dark);
    renderer.draw_rect(x, y, w, h, UI.panel);
    renderer.draw_rect_lines(x, y, w, h, UI.border);
}

fn drawText(fui: anytype, renderer: *Render, text: []const u8, x: i32, y: i32, scale: i32, color: u32) void {
    fui.draw_text(renderer, text, x, y, scale, color);
}
