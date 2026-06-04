const std = @import("std");
const CONF = @import("../engine/config.zig").CONF;
const Render = @import("../engine/render.zig").Render;
const Mouse = @import("../engine/mouse.zig").Mouse;
const Project = @import("project.zig").Project;
const MainEditor = @import("main_editor.zig").MainEditor;
const views = @import("views.zig");

const UI = struct {
    const bg = 0x121619;
    const panel = 0x1B2026;
    const panel_hi = 0x2B323A;
    const border = 0x3B434C;
    const border_dark = 0x090B0D;
    const text = 0xF0F0F0;
    const muted = 0xB7BBC0;
    const accent = 0x7EDB1E;
    const accent_dark = 0x486E10;
    const danger = 0xFF4040;

    const side_x: i32 = 14;
    const top_y: i32 = 24;
    const top_h: i32 = 82;
    const left_x: i32 = 30;
    const left_w: i32 = 246;
    const grid_x: i32 = 290;
    const grid_y: i32 = 124;
    const grid_w: i32 = CONF.SCREEN_W - grid_x - 24;
    const grid_h: i32 = 656;
    const bottom_y: i32 = 802;
};

pub const TileLibrary = struct {
    page: u16 = 0,
    pending_delete: bool = false,
    pending_delete_id: u16 = 0,

    pub fn draw(self: *TileLibrary, fui: anytype, renderer: *Render, project: *Project, editor: *MainEditor, mouse: Mouse, sm: anytype) void {
        drawBackground(renderer);
        drawTopPanel(fui, renderer, project);
        drawLeftInfo(fui, renderer, project);

        const cols: u16 = 16;
        const rows: u16 = 8;
        const per_page = cols * rows;
        const count = project.imageCount();
        const max_page = if (count == 0) 0 else (count - 1) / per_page;
        if (self.page > max_page) self.page = max_page;

        drawGrid(self, fui, renderer, project, editor, mouse, sm, cols, rows, per_page, count);
        drawBottomNav(self, fui, renderer, project, mouse, sm, max_page);
    }

    fn drawGrid(self: *TileLibrary, fui: anytype, renderer: *Render, project: *Project, editor: *MainEditor, mouse: Mouse, sm: anytype, cols: u16, rows: u16, per_page: u16, count: u16) void {
        panel(renderer, UI.grid_x, UI.grid_y, UI.grid_w, UI.grid_h);

        const label_w: i32 = 42;
        const head_h: i32 = 40;
        const cell_w: i32 = @divFloor(UI.grid_w - label_w - 12, cols);
        const row_h: i32 = @divFloor(UI.grid_h - head_h - 12, rows);
        const tile_size: i32 = 56;
        const tile_scale: i32 = @divFloor(tile_size, CONF.TILE_SIDE);
        const start = self.page * per_page;
        const col_labels = [_][:0]const u8{ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F" };

        for (0..cols) |c| {
            const x = UI.grid_x + label_w + @as(i32, @intCast(c)) * cell_w + @divFloor(cell_w - 8, 2);
            drawText(fui, renderer, col_labels[c], x, UI.grid_y + 30, 1, if (c == project.selectedImageId() % cols) UI.accent else UI.muted);
        }

        var row: u16 = 0;
        while (row < rows) : (row += 1) {
            const row_base = start + row * cols;
            const y = UI.grid_y + head_h + @as(i32, @intCast(row)) * row_h;
            var row_buf: [8]u8 = undefined;
            const row_text = std.fmt.bufPrint(&row_buf, "{X}", .{row_base}) catch "?";
            drawText(fui, renderer, row_text, UI.grid_x + 12, y + 28, 2, UI.text);
            renderer.draw_rect(UI.grid_x + label_w, y + 4, UI.grid_w - label_w - 8, row_h - 8, 0x181D22);

            var col: u16 = 0;
            while (col < cols) : (col += 1) {
                const tile_id = row_base + col;
                const cell_x = UI.grid_x + label_w + @as(i32, @intCast(col)) * cell_w;
                const cell_y = y;
                const x = cell_x + @divFloor(cell_w - tile_size, 2);
                const tile_y = cell_y + @divFloor(row_h - tile_size, 2) + 4;
                const hovered = views.hover(mouse, x, tile_y, tile_size, tile_size);
                const selected = tile_id == project.selectedImageId();

                renderer.draw_rect(x - 6, tile_y - 6, tile_size + 12, tile_size + 12, if (hovered) UI.panel_hi else 0x20262B);
                renderer.draw_rect(x, tile_y, tile_size, tile_size, 0x9FA4A6);
                if (tile_id < count) {
                    views.drawTile(renderer, project, tile_id, x, tile_y, tile_scale);
                }

                if (selected) {
                    renderer.draw_rect_lines(x - 4, tile_y - 4, tile_size + 8, tile_size + 8, UI.accent);
                    renderer.draw_rect_lines(x - 2, tile_y - 2, tile_size + 4, tile_size + 4, UI.accent_dark);
                } else if (hovered) {
                    renderer.draw_rect_lines(x - 3, tile_y - 3, tile_size + 6, tile_size + 6, UI.text);
                }
                if (self.pending_delete and self.pending_delete_id == tile_id) renderer.draw_rect_lines(x - 5, tile_y - 5, tile_size + 10, tile_size + 10, UI.danger);

                if (hovered and mouse.just_pressed and tile_id < count) {
                    if (tile_id != project.selectedImageId()) self.cancelDelete();
                    choose(project, editor, tile_id, sm);
                }
            }
        }
    }

    fn drawBottomNav(self: *TileLibrary, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, sm: anytype, max_page: u16) void {
        if (button(fui, renderer, mouse, 34, UI.bottom_y, 112, 42, "< BACK", false)) {
            self.cancelDelete();
            sm.go_to(.editor);
        }
        if (button(fui, renderer, mouse, 172, UI.bottom_y, 112, 42, "+ ADD", false)) {
            self.cancelDelete();
            _ = project.createTile();
            views.saveIfDirty(project);
        }
        if (button(fui, renderer, mouse, 294, UI.bottom_y, 172, 42, "DUPLICATE", false)) {
            self.cancelDelete();
            _ = project.duplicateTile(project.selectedImageId());
            views.saveIfDirty(project);
        }

        const delete_label: [:0]const u8 = if (self.pending_delete and self.pending_delete_id == project.selectedImageId()) "CONFIRM" else "DELETE";
        if (button(fui, renderer, mouse, 486, UI.bottom_y, 136, 42, delete_label, self.pending_delete)) {
            const selected = project.selectedImageId();
            if (self.pending_delete and self.pending_delete_id == selected) {
                project.deleteTile(selected);
                views.saveIfDirty(project);
                self.cancelDelete();
            } else {
                self.pending_delete = true;
                self.pending_delete_id = selected;
            }
        }

        const page_center = UI.grid_x + @divFloor(UI.grid_w, 2);
        if (button(fui, renderer, mouse, page_center - 134, UI.bottom_y, 42, 42, "<", false) and self.page > 0) {
            self.cancelDelete();
            self.page -= 1;
        }
        if (button(fui, renderer, mouse, page_center + 92, UI.bottom_y, 42, 42, ">", false) and self.page < max_page) {
            self.cancelDelete();
            self.page += 1;
        }
        var page_buf: [24]u8 = undefined;
        const page_text = std.fmt.bufPrint(&page_buf, "PAGE {d} / {d}", .{ self.page + 1, max_page + 1 }) catch "PAGE";
        drawText(fui, renderer, page_text, page_center - 54, UI.bottom_y + 14, 1, UI.text);
    }

    fn choose(project: *Project, editor: *MainEditor, tile_id: u16, sm: anytype) void {
        const had_request = editor.library_request != null;
        if (editor.library_request) |request| {
            switch (request.mode) {
                .choose_slot => project.setVisibleSlot(request.slot_index, tile_id),
                .swap_tile => {
                    project.setVisibleSlot(request.slot_index, tile_id);
                    project.selectTile(tile_id);
                },
            }
            editor.library_request = null;
        }
        if (!had_request) project.selectTile(tile_id);
        editor.suppress_canvas_paint_until_mouse_up = true;
        views.saveIfDirty(project);
        sm.go_to(.editor);
    }

    fn cancelDelete(self: *TileLibrary) void {
        self.pending_delete = false;
        self.pending_delete_id = 0;
    }
};

fn drawBackground(renderer: *Render) void {
    renderer.draw_rect(0, 0, CONF.SCREEN_W, CONF.SCREEN_H, UI.bg);
}

fn drawTopPanel(fui: anytype, renderer: *Render, project: *const Project) void {
    panel(renderer, UI.side_x, UI.top_y, CONF.SCREEN_W - UI.side_x * 2, UI.top_h);
    const title = if (project.mode == .tiles) "TILES LIBRARY" else "SPRITES LIBRARY";
    drawText(fui, renderer, title, 38, 42, 3, UI.text);
    drawText(fui, renderer, "L: SELECT TILE", 38, 78, 1, UI.muted);
}

fn drawLeftInfo(fui: anytype, renderer: *Render, project: *const Project) void {
    const x = UI.left_x;
    panel(renderer, x, UI.grid_y, UI.left_w, 260);
    drawText(fui, renderer, "TILE INFO", x + 16, UI.grid_y + 22, 2, UI.text);

    const selected = project.selectedImageId();
    var id_buf: [8]u8 = undefined;
    const id_text = std.fmt.bufPrint(&id_buf, "{d}", .{selected}) catch "?";
    drawText(fui, renderer, "INDEX:", x + 16, UI.grid_y + 72, 1, UI.muted);
    drawText(fui, renderer, id_text, x + 16, UI.grid_y + 94, 2, UI.accent);

    var coord_buf: [24]u8 = undefined;
    const coord_text = std.fmt.bufPrint(&coord_buf, "0x{X} ({d}, {d})", .{ selected, selected % 16, selected / 16 }) catch "?";
    drawText(fui, renderer, "COORDINATES:", x + 16, UI.grid_y + 132, 1, UI.muted);
    drawText(fui, renderer, coord_text, x + 16, UI.grid_y + 154, 1, UI.accent);

    const tile = project.currentImage();
    drawText(fui, renderer, "PALETTE:", x + 16, UI.grid_y + 194, 1, UI.muted);
    for (0..CONF.COLORS_PER_PALETTE) |i| {
        const sx = x + 16 + @as(i32, @intCast(i)) * 30;
        renderer.draw_rect(sx, UI.grid_y + 216, 24, 24, if (project.isTransparentColor(@intCast(i))) 0x303030 else project.color32(tile.palette_id, @intCast(i)));
        renderer.draw_rect_lines(sx, UI.grid_y + 216, 24, 24, UI.border_dark);
    }
    var palette_buf: [16]u8 = undefined;
    const palette_text = std.fmt.bufPrint(&palette_buf, "{d} (P{d})", .{ tile.palette_id, tile.palette_id }) catch "?";
    drawText(fui, renderer, palette_text, x + 140, UI.grid_y + 222, 1, UI.accent);

    panel(renderer, x, UI.grid_y + 280, UI.left_w, 190);
    drawText(fui, renderer, "SELECTION", x + 16, UI.grid_y + 304, 2, UI.text);
    drawText(fui, renderer, "Click tile to select", x + 16, UI.grid_y + 356, 1, UI.muted);
    drawText(fui, renderer, "Right click from preview", x + 16, UI.grid_y + 378, 1, UI.muted);
    drawText(fui, renderer, "opens swap mode", x + 16, UI.grid_y + 400, 1, UI.muted);
}

fn panel(renderer: *Render, x: i32, y: i32, w: i32, h: i32) void {
    renderer.draw_rect(x + 3, y + 3, w, h, 0x07090B);
    renderer.draw_rect(x, y, w, h, UI.panel);
    renderer.draw_rect_lines(x, y, w, h, UI.border_dark);
    renderer.draw_rect_lines(x + 1, y + 1, w - 2, h - 2, UI.border);
}

fn button(fui: anytype, renderer: *Render, mouse: Mouse, x: i32, y: i32, w: i32, h: i32, label: [:0]const u8, active: bool) bool {
    const over = views.hover(mouse, x, y, w, h);
    const bg: u32 = if (active) UI.danger else if (over) lighten(UI.panel_hi) else UI.panel_hi;
    renderer.draw_rect(x + 2, y + 2, w, h, 0x07090B);
    renderer.draw_rect(x, y, w, h, bg);
    renderer.draw_rect_lines(x, y, w, h, if (active) UI.danger else UI.border_dark);
    renderer.draw_rect_lines(x + 1, y + 1, w - 2, h - 2, if (active) 0xFF8080 else UI.border);
    const tw = fui.text_length(label, 1);
    drawText(fui, renderer, label, x + @divFloor(w - tw, 2), y + @divFloor(h - CONF.FONT_HEIGHT, 2), 1, UI.text);
    return over and mouse.just_pressed;
}

fn drawText(fui: anytype, renderer: *Render, text: []const u8, x: i32, y: i32, scale: i32, color: u32) void {
    fui.draw_text(renderer, text, x, y, scale, color);
}

fn lighten(color: u32) u32 {
    const r: u32 = @min(255, ((color >> 16) & 0xFF) + 28);
    const g: u32 = @min(255, ((color >> 8) & 0xFF) + 28);
    const b: u32 = @min(255, (color & 0xFF) + 28);
    return (r << 16) | (g << 8) | b;
}
