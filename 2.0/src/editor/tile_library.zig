const std = @import("std");
const CONF = @import("../engine/config.zig").CONF;
const Render = @import("../engine/render.zig").Render;
const Mouse = @import("../engine/mouse.zig").Mouse;
const Project = @import("project.zig").Project;
const MainEditor = @import("main_editor.zig").MainEditor;
const views = @import("views.zig");

pub const TileLibrary = struct {
    page: u16 = 0,
    pending_delete: bool = false,
    pending_delete_id: u16 = 0,

    pub fn draw(self: *TileLibrary, fui: anytype, renderer: *Render, project: *Project, editor: *MainEditor, mouse: Mouse, sm: anytype) void {
        const title = if (project.mode == .tiles) "Tiles Library" else "Sprites Library";
        fui.draw_text(renderer, title, 40, 28, 3, 0xFFFFFF);
        fui.draw_text(renderer, "L: select", 40, 64, 2, 0xBEBEBE);

        if (views.smallButton(fui, renderer, mouse, 40, 704, 90, 40, "Back", false)) {
            self.cancelDelete();
            sm.go_to(.editor);
        }
        if (views.smallButton(fui, renderer, mouse, 150, 704, 70, 40, "Add", false)) {
            self.cancelDelete();
            _ = project.createTile();
            views.saveIfDirty(project);
        }
        if (views.smallButton(fui, renderer, mouse, 240, 704, 70, 40, "Dup", false)) {
            self.cancelDelete();
            _ = project.duplicateTile(project.selectedImageId());
            views.saveIfDirty(project);
        }
        if (views.smallButton(fui, renderer, mouse, 330, 704, 60, 40, "<", false)) {
            self.cancelDelete();
            project.moveTileLeft(project.selectedImageId());
            views.saveIfDirty(project);
        }
        if (views.smallButton(fui, renderer, mouse, 410, 704, 60, 40, ">", false)) {
            self.cancelDelete();
            project.moveTileRight(project.selectedImageId());
            views.saveIfDirty(project);
        }

        const delete_label: [:0]const u8 = if (self.pending_delete and self.pending_delete_id == project.selectedImageId()) "Confirm" else "Del";
        if (views.smallButton(fui, renderer, mouse, 490, 704, 92, 40, delete_label, self.pending_delete)) {
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

        const cols: u16 = 10;
        const rows: u16 = 5;
        const per_page = cols * rows;
        const count = project.imageCount();
        const max_page = if (count == 0) 0 else (count - 1) / per_page;
        if (self.page > max_page) self.page = max_page;
        if (views.smallButton(fui, renderer, mouse, 820, 704, 60, 40, "-", false) and self.page > 0) {
            self.cancelDelete();
            self.page -= 1;
        }
        if (views.smallButton(fui, renderer, mouse, 900, 704, 60, 40, "+", false) and self.page < max_page) {
            self.cancelDelete();
            self.page += 1;
        }

        var page_buf: [24]u8 = undefined;
        const page_text = std.fmt.bufPrint(&page_buf, "Page {d}/{d}", .{ self.page + 1, max_page + 1 }) catch "Page";
        fui.draw_text(renderer, page_text, 680, 714, 2, 0xFFFFFF);

        const start = self.page * per_page;
        var i: u16 = 0;
        while (i < per_page) : (i += 1) {
            const tile_id = start + i;
            const x = 40 + @as(i32, @intCast(i % cols)) * 94;
            const y = 108 + @as(i32, @intCast(i / cols)) * 112;
            renderer.draw_rect(x, y, 72, 72, 0x707070);
            renderer.draw_rect_lines(x, y, 72, 72, if (tile_id == project.selectedImageId()) 0xFFFFFF else 0x111111);
            if (self.pending_delete and self.pending_delete_id == tile_id) renderer.draw_rect_lines(x + 3, y + 3, 66, 66, 0xFF4040);
            if (tile_id < count) {
                views.drawTile(renderer, project, tile_id, x + 4, y + 4, 8);
                var buf: [8]u8 = undefined;
                const id_text = std.fmt.bufPrint(&buf, "{d}", .{tile_id}) catch "?";
                fui.draw_text(renderer, id_text, x, y + 80, 2, 0xD8D8D8);
                if (views.hover(mouse, x, y, 72, 72) and mouse.just_pressed) {
                    if (tile_id != project.selectedImageId()) self.cancelDelete();
                    choose(project, editor, tile_id, sm);
                }
            } else if (tile_id == count) {
                if (views.smallButton(fui, renderer, mouse, x, y, 72, 72, "+", false)) {
                    self.cancelDelete();
                    _ = project.createTile();
                    views.saveIfDirty(project);
                }
            }
        }
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
        views.saveIfDirty(project);
        sm.go_to(.editor);
    }

    fn cancelDelete(self: *TileLibrary) void {
        self.pending_delete = false;
        self.pending_delete_id = 0;
    }
};
