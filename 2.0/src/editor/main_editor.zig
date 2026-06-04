const std = @import("std");
const CONF = @import("../engine/config.zig").CONF;
const Render = @import("../engine/render.zig").Render;
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

pub const MainEditor = struct {
    tool: Tool = .pixel,
    line_start: ?[2]i32 = null,
    library_request: ?LibraryRequest = null,
    save_error: bool = false,
    export_notice: bool = false,

    pub fn draw(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, sm: anytype) void {
        self.handleCanvas(fui, project, mouse);
        drawLeftPanel(self, fui, renderer, project, mouse, sm);
        drawCanvas(self, fui, renderer, project, mouse);
        drawTileSlots(self, fui, renderer, project, mouse, sm);
        drawPalettes(self, fui, renderer, project, mouse);
        drawColorEditor(fui, renderer, project, mouse);
        drawStatus(fui, renderer, project, self.save_error, self.export_notice);
    }

    fn handleCanvas(self: *MainEditor, fui: anytype, project: *Project, mouse: Mouse) void {
        const cell = canvasCell(fui, mouse.x, mouse.y) orelse return;
        const paint_color = if (mouse.right_down) project.right_color else project.left_color;
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
};

fn drawLeftPanel(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, sm: anytype) void {
    const x: i32 = 40;
    var y: i32 = 44;

    fui.draw_text(renderer, "Mode", x, y, 2, 0xE6E6E6);
    y += 26;
    if (views.smallButton(fui, renderer, mouse, x, y, 78, 34, "Tiles", project.mode == .tiles)) project.setMode(.tiles);
    if (views.smallButton(fui, renderer, mouse, x + 82, y, 78, 34, "Sprites", project.mode == .sprites)) project.setMode(.sprites);

    y += 58;
    if (views.smallButton(fui, renderer, mouse, x, y, 160, 36, "Pixel", self.tool == .pixel)) self.tool = .pixel;
    y += 38;
    if (views.smallButton(fui, renderer, mouse, x, y, 160, 36, "Fill", self.tool == .fill)) self.tool = .fill;
    y += 38;
    if (views.smallButton(fui, renderer, mouse, x, y, 160, 36, "Line", self.tool == .line)) self.tool = .line;

    y += 42;
    fui.draw_text(renderer, "Current Palette", x, y, 2, 0xE6E6E6);
    y += 30;
    for (0..CONF.COLORS_PER_PALETTE) |i| {
        const sx = x + @as(i32, @intCast(i)) * 40;
        renderer.draw_rect(sx, y, 40, 40, if (project.isTransparentColor(@intCast(i))) 0x303030 else project.currentColor32(@intCast(i)));
        renderer.draw_rect_lines(sx, y, 40, 40, 0x000000);
        if (project.isTransparentColor(@intCast(i))) renderer.draw_line(sx, y + 39, sx + 39, y, 0xFFFFFF);
        if (views.hover(mouse, sx, y, 40, 40)) {
            if (mouse.just_pressed) project.left_color = @intCast(i);
            if (mouse.just_right_pressed) project.right_color = @intCast(i);
        }
        if (project.left_color == i) renderer.draw_rect_lines(sx + 3, y + 3, 34, 34, 0xFFFFFF);
        if (project.right_color == i) renderer.draw_rect_lines(sx + 7, y + 7, 26, 26, 0x000000);
    }
    y += 50;
    fui.draw_text(renderer, "L", x + 12, y, 2, project.currentColor32(project.left_color));
    fui.draw_text(renderer, "R", x + 72, y, 2, project.currentColor32(project.right_color));

    y += 62;
    fui.draw_text(renderer, "Edited Tile ID:", x, y, 2, 0xE6E6E6);
    y += 30;
    drawNumber(fui, renderer, project.selected_tile, x + 60, y, 0xFFFFFF);
    y += 62;
    fui.draw_text(renderer, "Non-empty Tiles:", x, y, 2, 0xE6E6E6);
    y += 30;
    drawNumber(fui, renderer, project.nonEmptyTiles(), x + 60, y, 0xFFFFFF);

    y = 610;
    if (views.smallButton(fui, renderer, mouse, x, y, 160, 36, "Save", project.dirty)) {
        project.save() catch {
            self.save_error = true;
            return;
        };
        self.save_error = false;
        self.export_notice = false;
    }
    y += 42;
    if (views.smallButton(fui, renderer, mouse, x, y, 160, 36, "Export", false)) {
        self.export_notice = true;
    }
    y += 42;
    if (views.smallButton(fui, renderer, mouse, x, y, 160, 36, "Quit", false)) {
        project.save() catch {};
        sm.go_to(.quit);
    }
}

fn drawCanvas(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse) void {
    const tile = project.tiles[project.selected_tile];
    const origin = canvasOrigin(fui);
    var py: usize = 0;
    while (py < CONF.TILE_SIDE) : (py += 1) {
        var px: usize = 0;
        while (px < CONF.TILE_SIDE) : (px += 1) {
            const idx = tile.pixels[py * CONF.TILE_SIDE + px];
            const color = if (project.isTransparentColor(idx)) checker(px, py) else project.currentColor32(idx);
            renderer.draw_rect(origin[0] + @as(i32, @intCast(px)) * CONF.EDITOR_CANVAS_SCALE, origin[1] + @as(i32, @intCast(py)) * CONF.EDITOR_CANVAS_SCALE, CONF.EDITOR_CANVAS_SCALE, CONF.EDITOR_CANVAS_SCALE, color);
            renderer.draw_rect_lines(origin[0] + @as(i32, @intCast(px)) * CONF.EDITOR_CANVAS_SCALE, origin[1] + @as(i32, @intCast(py)) * CONF.EDITOR_CANVAS_SCALE, CONF.EDITOR_CANVAS_SCALE, CONF.EDITOR_CANVAS_SCALE, 0xD0D0D0);
        }
    }
    if (self.tool == .line) if (self.line_start) |start| if (canvasCell(fui, mouse.x, mouse.y)) |end| {
        const half = @divFloor(CONF.EDITOR_CANVAS_SCALE, 2);
        renderer.draw_line(origin[0] + start[0] * CONF.EDITOR_CANVAS_SCALE + half, origin[1] + start[1] * CONF.EDITOR_CANVAS_SCALE + half, origin[0] + end[0] * CONF.EDITOR_CANVAS_SCALE + half, origin[1] + end[1] * CONF.EDITOR_CANVAS_SCALE + half, 0x202020);
    };
    renderer.draw_rect_lines(origin[0], origin[1], CONF.TILE_SIDE * CONF.EDITOR_CANVAS_SCALE, CONF.TILE_SIDE * CONF.EDITOR_CANVAS_SCALE, 0x000000);
}

fn drawTileSlots(self: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, sm: anytype) void {
    const slot: i32 = 64;
    const origin = canvasOrigin(fui);
    const x0: i32 = origin[0] + @divFloor(CONF.TILE_SIDE * CONF.EDITOR_CANVAS_SCALE - slot * 3, 2);
    const y0: i32 = origin[1] + CONF.TILE_SIDE * CONF.EDITOR_CANVAS_SCALE + 24;
    for (0..9) |i| {
        const cx: i32 = @intCast(i % 3);
        const cy: i32 = @intCast(i / 3);
        const x = x0 + cx * slot;
        const y = y0 + cy * slot;
        renderer.draw_rect(x, y, slot, slot, 0x858585);
        const tile_id = project.visible_slots[i];
        if (tile_id < project.tile_count) views.drawTile(renderer, project, tile_id, x + 4, y + 4, 7);
        renderer.draw_rect_lines(x, y, slot, slot, 0x000000);
        if (project.selected_tile == tile_id) renderer.draw_rect_lines(x + 4, y + 4, slot - 8, slot - 8, 0xFFFFFF);
        if (views.hover(mouse, x, y, slot, slot)) {
            if (mouse.just_pressed and tile_id < project.tile_count) project.selectTile(tile_id);
            if (mouse.just_right_pressed) {
                self.library_request = .{ .mode = .swap_tile, .slot_index = @intCast(i), .tile_id = tile_id };
                sm.go_to(.tile_library);
            }
        }
    }
    fui.draw_text(renderer, "L to edit   R to swap", x0 - 2, y0 + slot * 3 + 6, 2, 0xFFFFFF);
}

fn drawPalettes(_: *MainEditor, fui: anytype, renderer: *Render, project: *Project, mouse: Mouse) void {
    const x0: i32 = fui.pivotX(.top_right) - 190;
    const y0: i32 = fui.pivotY(.top_right) + 60;
    const sw: i32 = 38;
    const row_h: i32 = 52;
    const title = if (project.mode == .tiles) "Tile Palettes" else "Sprite Palettes";
    fui.draw_text(renderer, title, x0 - 22, y0 - 32, 2, 0xFFFFFF);

    for (0..CONF.PALETTE_COUNT) |p| {
        const y = y0 + @as(i32, @intCast(p)) * row_h;
        var label_buf: [4]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buf, "{d}", .{p}) catch "?";
        if (project.selected_palette == p) fui.draw_text(renderer, ">", x0 - 32, y + 11, 2, 0xFFFFFF);
        fui.draw_text(renderer, label, x0 - 18, y + 11, 2, 0xE6E6E6);
        for (0..CONF.COLORS_PER_PALETTE) |color_slot| {
            const x = x0 + @as(i32, @intCast(color_slot)) * sw;
            renderer.draw_rect(x, y, sw, 40, if (project.isTransparentColor(@intCast(color_slot))) 0x303030 else project.color32(@intCast(p), @intCast(color_slot)));
            renderer.draw_rect_lines(x, y, sw, 40, 0x000000);
            if (project.isTransparentColor(@intCast(color_slot))) renderer.draw_line(x, y + 39, x + sw - 1, y, 0xFFFFFF);
            if (project.selected_palette == p and project.selected_color == color_slot) {
                renderer.draw_rect_lines(x + 4, y + 4, sw - 8, 32, 0xFFFFFF);
                renderer.draw_rect_lines(x + 7, y + 7, sw - 14, 26, 0x000000);
            }
            if (views.hover(mouse, x, y, sw, 40) and (mouse.just_pressed or mouse.just_right_pressed)) {
                project.selected_palette = @intCast(p);
                project.selected_color = @intCast(color_slot);
                project.tiles[project.selected_tile].palette_id = project.selected_palette;
                project.dirty = true;
            }
        }
    }
}

fn drawColorEditor(fui: anytype, renderer: *Render, project: *Project, mouse: Mouse) void {
    const x: i32 = fui.pivotX(.top_right) - 222;
    const y: i32 = fui.pivotY(.top_right) + 506;
    const selected_color = project.color32(project.selected_palette, project.selected_color);

    fui.draw_text(renderer, "Edit selected color", x, y, 2, 0xFFFFFF);
    renderer.draw_rect(x, y + 34, 64, 64, selected_color);
    renderer.draw_rect_lines(x, y + 34, 64, 64, 0xFFFFFF);

    var title_buf: [32]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buf, "P{d} C{d}", .{ project.selected_palette, project.selected_color }) catch "P? C?";
    fui.draw_text(renderer, title, x + 78, y + 40, 2, 0xE6E6E6);

    const rgb = selectedRgb(project);
    drawChannelEditor(fui, renderer, project, mouse, .r, "R", rgb[0], x, y + 116, 0xFF4040);
    drawChannelEditor(fui, renderer, project, mouse, .g, "G", rgb[1], x, y + 162, 0x80FF40);
    drawChannelEditor(fui, renderer, project, mouse, .b, "B", rgb[2], x, y + 208, 0x70A8FF);
}

fn drawChannelEditor(fui: anytype, renderer: *Render, project: *Project, mouse: Mouse, channel: ColorChannel, label: [:0]const u8, value: u8, x: i32, y: i32, color: u32) void {
    fui.draw_text(renderer, label, x, y + 8, 2, color);
    if (views.smallButton(fui, renderer, mouse, x + 34, y, 44, 32, "-", false)) project.adjustSelectedRgb(channel, -1);
    var buf: [4]u8 = undefined;
    const value_text = std.fmt.bufPrint(&buf, "{d}", .{value}) catch "?";
    fui.draw_text(renderer, value_text, x + 92, y + 8, 2, 0xFFFFFF);
    if (views.smallButton(fui, renderer, mouse, x + 142, y, 44, 32, "+", false)) project.adjustSelectedRgb(channel, 1);
}

fn drawStatus(fui: anytype, renderer: *Render, project: *const Project, save_error: bool, export_notice: bool) void {
    if (save_error) fui.draw_text(renderer, "Save failed", 40, 18, 2, 0xFF4040);
    if (export_notice) fui.draw_text(renderer, "GBC export TODO", 40, 18, 2, 0x80C8FF);
    if (!save_error and !export_notice and project.dirty) fui.draw_text(renderer, "Unsaved edits", 40, 18, 2, 0xAAAAAA);
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
    const size = CONF.TILE_SIDE * CONF.EDITOR_CANVAS_SCALE;
    return .{ fui.pivotX(.center) - @divFloor(size, 2), 40 };
}

fn checker(x: usize, y: usize) u32 {
    return if ((x + y) % 2 == 0) 0xF0F0F0 else 0xFFFFFF;
}

fn drawNumber(fui: anytype, renderer: *Render, n: anytype, x: i32, y: i32, color: u32) void {
    var buf: [8]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{n}) catch "?";
    fui.draw_text(renderer, text, x, y, 3, color);
}
