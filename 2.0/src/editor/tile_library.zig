const std = @import("std");
const CONF = @import("../engine/config.zig").CONF;
const Render = @import("../engine/render.zig").Render;
const Mouse = @import("../engine/mouse.zig").Mouse;
const Project = @import("project.zig").Project;
const MainEditor = @import("main_editor.zig").MainEditor;
const views = @import("views.zig");

pub const TileLibrary = struct {
    page: u16 = 0,

    pub fn draw(self: *TileLibrary, fui: anytype, renderer: *Render, project: *Project, editor: *MainEditor, mouse: Mouse, sm: anytype) void {
        fui.draw_text(renderer, "Tiles Library", 40, 28, 3, 0xFFFFFF);
        fui.draw_text(renderer, "L: select   R: delete", 40, 64, 2, 0xBEBEBE);

        if (views.smallButton(fui, renderer, mouse, 40, 704, 90, 40, "Back", false)) sm.go_to(.editor);
        if (views.smallButton(fui, renderer, mouse, 150, 704, 70, 40, "Add", false)) {
            _ = project.createTile();
            views.saveIfDirty(project);
        }
        if (views.smallButton(fui, renderer, mouse, 240, 704, 70, 40, "Dup", false)) {
            _ = project.duplicateTile(project.selected_tile);
            views.saveIfDirty(project);
        }
        if (views.smallButton(fui, renderer, mouse, 330, 704, 60, 40, "<", false)) {
            project.moveTileLeft(project.selected_tile);
            views.saveIfDirty(project);
        }
        if (views.smallButton(fui, renderer, mouse, 410, 704, 60, 40, ">", false)) {
            project.moveTileRight(project.selected_tile);
            views.saveIfDirty(project);
        }
        if (views.smallButton(fui, renderer, mouse, 490, 704, 70, 40, "Del", false)) {
            project.deleteTile(project.selected_tile);
            views.saveIfDirty(project);
        }

        const cols: u16 = 10;
        const rows: u16 = 5;
        const per_page = cols * rows;
        const max_page = if (project.tile_count == 0) 0 else (project.tile_count - 1) / per_page;
        if (self.page > max_page) self.page = max_page;
        if (views.smallButton(fui, renderer, mouse, 820, 704, 60, 40, "-", false) and self.page > 0) self.page -= 1;
        if (views.smallButton(fui, renderer, mouse, 900, 704, 60, 40, "+", false) and self.page < max_page) self.page += 1;

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
            renderer.draw_rect_lines(x, y, 72, 72, if (tile_id == project.selected_tile) 0xFFFFFF else 0x111111);
            if (tile_id < project.tile_count) {
                views.drawTile(renderer, project, tile_id, x + 4, y + 4, 8);
                var buf: [8]u8 = undefined;
                const id_text = std.fmt.bufPrint(&buf, "{d}", .{tile_id}) catch "?";
                fui.draw_text(renderer, id_text, x, y + 80, 2, 0xD8D8D8);
                if (views.hover(mouse, x, y, 72, 72)) {
                    if (mouse.just_pressed) choose(project, editor, tile_id, sm);
                    if (mouse.just_right_pressed) {
                        project.deleteTile(tile_id);
                        views.saveIfDirty(project);
                    }
                }
            } else if (tile_id == project.tile_count) {
                if (views.smallButton(fui, renderer, mouse, x, y, 72, 72, "+", false)) {
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
                .choose_slot => project.visible_slots[request.slot_index] = tile_id,
                .swap_tile => {
                    project.swapTileIds(request.tile_id, tile_id);
                    project.visible_slots[request.slot_index] = request.tile_id;
                    project.selectTile(request.tile_id);
                },
            }
            editor.library_request = null;
        }
        if (!had_request) project.selectTile(tile_id);
        views.saveIfDirty(project);
        sm.go_to(.editor);
    }
};
