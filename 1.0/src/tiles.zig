const std = @import("std");
const CONF = @import("config.zig").CONF;
const DB16 = @import("palette.zig").DB16;
const Palette = @import("palette.zig").Palette;
const Fui = @import("fui.zig").Fui;
const PIVOTS = @import("fui.zig").PIVOTS;
const Vec2 = @import("math.zig").Vec2;
const Mouse = @import("math.zig").Mouse;

pub const Layer = struct {
    data: [CONF.MAX_PREVIEW_H][CONF.MAX_PREVIEW_W]u8,
    visible: bool = false,
};

pub const Tile = struct {
    w: f32,
    h: f32,
    data: [CONF.SPRITE_SIZE][CONF.SPRITE_SIZE]u8,
    pal: u8,
    pal32: [4]u32,
    page: u8,
    pub fn init(data: [CONF.SPRITE_SIZE][CONF.SPRITE_SIZE]u8, pal: u8) Tile {
        const p32: [4]u32 = .{ 0, 0, 0, 0 };
        return Tile{
            .w = CONF.SPRITE_SIZE,
            .h = CONF.SPRITE_SIZE,
            .data = data,
            .pal = pal,
            .pal32 = p32,
            .page = 0,
        };
    }
};

pub const Tiles = struct {
    db: [CONF.MAX_TILES]Tile = undefined,
    selected: u8 = 0,
    count: u8 = 0,
    fui: Fui,
    palette: *Palette,
    layers: ?*[CONF.PREVIEW_LAYERS]Layer = null,
    updated: bool = false,
    hot: bool = false,
    page: usize = 0,
    pub fn init(fui: Fui, palette: *Palette, layers: ?*[CONF.PREVIEW_LAYERS]Layer) Tiles {
        return Tiles{
            .db = undefined,
            .selected = 0,
            .fui = fui,
            .palette = palette,
            .layers = layers,
            .count = 1,
            .updated = false,
            .page = 0,
        };
    }
    pub fn load_tileset_from_file(self: *Tiles) void {
        var example_data: [CONF.SPRITE_SIZE][CONF.SPRITE_SIZE]u8 = undefined;
        for (0..CONF.SPRITE_SIZE) |y| {
            for (0..CONF.SPRITE_SIZE) |x| {
                example_data[y][x] = 0;
            }
        }
        const file = std.fs.cwd().openFile(CONF.TILES_FILE, .{}) catch {
            self.db[0] = Tile.init(example_data, 0);
            self.count = 1;
            return;
        };
        defer file.close();

        const data = file.readToEndAlloc(std.heap.page_allocator, 1024 * 1024) catch {
            self.db[0] = Tile.init(example_data, 0);
            self.count = 1;
            return;
        };
        defer std.heap.page_allocator.free(data);

        const per_tile = CONF.SPRITE_SIZE * CONF.SPRITE_SIZE + 1;
        self.count = @min(data.len / per_tile, CONF.MAX_TILES);
        for (0..self.count) |i| {
            const offset = i * per_tile;
            const pal = data[offset];
            var tile_data: [CONF.SPRITE_SIZE][CONF.SPRITE_SIZE]u8 = undefined;
            for (0..CONF.SPRITE_SIZE) |y| {
                for (0..CONF.SPRITE_SIZE) |x| {
                    tile_data[y][x] = data[offset + 1 + y * CONF.SPRITE_SIZE + x];
                }
            }
            self.db[i] = Tile.init(tile_data, pal);
            self.update_pal32(i);
        }

        self.updated = false;
    }
    pub fn save_tileset_to_file(self: *Tiles) !void {
        const per_tile: usize = CONF.SPRITE_SIZE * CONF.SPRITE_SIZE + 1;
        const total_bytes = self.count * per_tile;
        var buf: [CONF.MAX_TILES * per_tile]u8 = undefined;
        for (0..self.count) |i| {
            const offset = i * per_tile;
            buf[offset] = self.db[i].pal;
            for (0..CONF.SPRITE_SIZE) |y| {
                for (0..CONF.SPRITE_SIZE) |x| {
                    buf[offset + 1 + y * CONF.SPRITE_SIZE + x] = self.db[i].data[y][x];
                }
            }
        }

        const file = try std.fs.cwd().createFile(CONF.TILES_FILE, .{});
        defer file.close();
        _ = try file.write(buf[0..total_bytes]);
        self.updated = false;
    }
    pub fn export_asm(self: *Tiles) !void {
        const file = try std.fs.cwd().createFile("tiles.asm", .{});
        defer file.close();
        var buf: [256]u8 = undefined;

        var issues: usize = 0;
        for (0..self.count) |i| {
            if (self.db[i].pal >= self.palette.count) {
                issues += 1;
            }
        }

        try file.writeAll("; Generated from P1Xel Editor\n");
        if (self.count > 0) {
            const s = try std.fmt.bufPrint(&buf, "; Total tiles: {d}\n", .{self.count});
            try file.writeAll(s);
        } else {
            try file.writeAll("; Total tiles: 0\n");
        }
        const s_issues = try std.fmt.bufPrint(&buf, "; Tiles with palette issues: {d}\n\n", .{issues});
        try file.writeAll(s_issues);

        try file.writeAll("; Palette definitions (mapped to DawnBringer 16 indices)\n");
        try file.writeAll("Palettes:\n");

        for (0..self.palette.count) |i| {
            const p = self.palette.db[i];
            const s = try std.fmt.bufPrint(&buf, "db 0x{X}, 0x{X}, 0x{X}, 0x{X} ; Palette {d}\n", .{ p[0], p[1], p[2], p[3], i });
            try file.writeAll(s);
        }

        try file.writeAll("\nTiles:\n");

        if (self.count == 0) return;

        for (0..self.count) |i| {
            const tile = self.db[i];
            const s_tile = try std.fmt.bufPrint(&buf, "; Tile {d}\n", .{i});
            try file.writeAll(s_tile);
            const s_pal = try std.fmt.bufPrint(&buf, "db 0x{X:0>2}\n", .{tile.pal});
            try file.writeAll(s_pal);

            for (0..CONF.SPRITE_SIZE) |y| {
                var w1: u16 = 0;
                var w2: u16 = 0;

                for (0..8) |x| {
                    const val: u16 = @intCast(tile.data[y][x] & 3);
                    w1 |= (val << @intCast((7 - x) * 2));
                }

                for (0..8) |x| {
                    const val: u16 = @intCast(tile.data[y][x + 8] & 3);
                    w2 |= (val << @intCast((7 - x) * 2));
                }

                const s_data = try std.fmt.bufPrint(&buf, "dw {b:0>16}b, {b:0>16}b\n", .{ w1, w2 });
                try file.writeAll(s_data);
            }
            try file.writeAll("\n");
        }
    }
    pub fn update_pal32(self: *Tiles, index: usize) void {
        const pal = self.db[index].pal;
        self.db[index].pal32 = [_]u32{
            self.palette.get_rgba_from_index(self.palette.db[pal][0]),
            self.palette.get_rgba_from_index(self.palette.db[pal][1]),
            self.palette.get_rgba_from_index(self.palette.db[pal][2]),
            self.palette.get_rgba_from_index(self.palette.db[pal][3]),
        };
    }

    // Unified function for updating tile palette indices
    // Supports deletion, insertion, and swap operations
    pub fn update_tile_palette_ids(self: *Tiles, old_id: u8, new_id: u8, operation: enum { delete, insert, swap }) void {
        for (0..self.count) |i| {
            const tile_pal = self.db[i].pal;

            switch (operation) {
                .delete => {
                    // Delete: shift all palettes after old_id left, assign deleted to first palette
                    if (tile_pal > old_id) {
                        self.db[i].pal = tile_pal - 1;
                        self.update_pal32(i);
                    } else if (tile_pal == old_id) {
                        self.db[i].pal = 0;
                        self.update_pal32(i);
                    }
                },
                .insert => {
                    // Insert: shift all palettes at/after old_id right
                    if (tile_pal >= old_id) {
                        self.db[i].pal = tile_pal + 1;
                        self.update_pal32(i);
                    }
                },
                .swap => {
                    // Swap: exchange old_id and new_id
                    if (tile_pal == old_id) {
                        self.db[i].pal = new_id;
                        self.update_pal32(i);
                    } else if (tile_pal == new_id) {
                        self.db[i].pal = old_id;
                        self.update_pal32(i);
                    }
                },
            }
        }

        self.updated = true;
    }

    // Legacy functions for backward compatibility
    pub fn update_palette_indices(self: *Tiles, old_index: u8, new_index: u8, shift: i8) void {
        _ = new_index;
        if (shift == -1) {
            self.update_tile_palette_ids(old_index, 0, .delete);
        } else if (shift == 1) {
            self.update_tile_palette_ids(old_index, 0, .insert);
        }
    }

    pub fn update_palette_indices_swap(self: *Tiles, index1: u8, index2: u8) void {
        self.update_tile_palette_ids(index1, index2, .swap);
    }
    pub fn draw(self: *Tiles, index: usize, x: i32, y: i32) void {
        for (0..CONF.SPRITE_SIZE) |py| {
            for (0..CONF.SPRITE_SIZE) |px| {
                const idx = self.db[index].data[py][px];
                const color = self.db[index].pal32[idx];
                if (idx == 0 and color == DB16.BLACK) {
                    continue;
                }
                const px_i32: i32 = @intCast(px);
                const py_i32: i32 = @intCast(py);
                inline for (0..CONF.PREVIEW_SCALE) |dy| {
                    inline for (0..CONF.PREVIEW_SCALE) |dx| {
                        const dx_i32: i32 = @intCast(dx);
                        const dy_i32: i32 = @intCast(dy);
                        const sx: i32 = x + px_i32 * CONF.PREVIEW_SCALE + dx_i32;
                        const sy: i32 = y + py_i32 * CONF.PREVIEW_SCALE + dy_i32;
                        if (sx >= 0 and sx < CONF.SCREEN_W and sy >= 0 and sy < CONF.SCREEN_H) {
                            const index_buf: usize = @intCast(sy * CONF.SCREEN_W + sx);
                            self.fui.buf[index_buf] = color;
                        }
                    }
                }
            }
        }
    }
    pub fn create_new(self: *Tiles) !void {
        var data: [CONF.SPRITE_SIZE][CONF.SPRITE_SIZE]u8 = undefined;
        for (0..CONF.SPRITE_SIZE) |y| {
            for (0..CONF.SPRITE_SIZE) |x| {
                data[y][x] = 0;
            }
        }
        self.db[self.count] = Tile.init(data, 0);
        self.update_pal32(self.count);
        self.count += 1;
        self.updated = true;
    }
    pub fn duplicate_tile(self: *Tiles, index: usize) void {
        const data: [CONF.SPRITE_SIZE][CONF.SPRITE_SIZE]u8 = self.db[index].data;
        self.db[self.count] = Tile.init(data, self.db[index].pal);
        self.update_pal32(self.count);
        self.count += 1;
        self.updated = true;
    }
    pub fn save_layers_to_file(self: *Tiles) void {
        if (self.layers) |layers| {
            var buf: [CONF.PREVIEW_LAYERS * CONF.MAX_PREVIEW_H * CONF.MAX_PREVIEW_W]u8 = undefined;
            const per_layer = CONF.MAX_PREVIEW_H * CONF.MAX_PREVIEW_W;
            for (0..CONF.PREVIEW_LAYERS) |l| {
                for (0..CONF.MAX_PREVIEW_H) |y| {
                    for (0..CONF.MAX_PREVIEW_W) |x| {
                        buf[l * per_layer + y * CONF.MAX_PREVIEW_W + x] = layers[l].data[y][x];
                    }
                }
            }
            const file = std.fs.cwd().createFile(CONF.PREVIEW_FILE, .{}) catch return;
            defer file.close();
            _ = file.write(&buf) catch return;
        }
    }
    pub fn delete(self: *Tiles, index: usize) void {
        if (self.count <= 1) {
            return;
        }
        var i = index;
        while (i < self.count - 1) : (i += 1) {
            self.db[i] = self.db[i + 1];
        }
        if (self.layers != null) {
            for (0..CONF.PREVIEW_LAYERS) |l| {
                for (0..CONF.MAX_PREVIEW_H) |y| {
                    for (0..CONF.MAX_PREVIEW_W) |x| {
                        const val = self.layers.?[l].data[y][x];
                        if (val > index and val < 255) {
                            self.layers.?[l].data[y][x] = @intCast(val - 1);
                        } else if (val == index) {
                            self.layers.?[l].data[y][x] = 255;
                        }
                    }
                }
            }
        }
        self.count -= 1;
        self.updated = true;
        self.save_layers_to_file();
        self.save_tileset_to_file() catch {};
        return;
    }
    pub fn shift_tile_left(self: *Tiles, index: usize) void {
        if (index > 0 and index < self.count) {
            const temp = self.db[index];
            self.db[index] = self.db[index - 1];
            self.db[index - 1] = temp;
            if (self.layers != null) {
                for (0..CONF.PREVIEW_LAYERS) |l| {
                    for (0..CONF.MAX_PREVIEW_H) |y| {
                        for (0..CONF.MAX_PREVIEW_W) |x| {
                            const val = self.layers.?[l].data[y][x];
                            if (val == index) {
                                self.layers.?[l].data[y][x] = @intCast(index - 1);
                            } else if (val == index - 1) {
                                self.layers.?[l].data[y][x] = @intCast(index);
                            }
                        }
                    }
                }
            }
            self.updated = true;
            self.save_layers_to_file();
            self.save_tileset_to_file() catch {};
        }
    }
    pub fn shift_tile_right(self: *Tiles, index: usize) void {
        if (index >= 0 and index < self.count - 1) {
            const temp = self.db[index];
            self.db[index] = self.db[index + 1];
            self.db[index + 1] = temp;
            if (self.layers != null) {
                for (0..CONF.PREVIEW_LAYERS) |l| {
                    for (0..CONF.MAX_PREVIEW_H) |y| {
                        for (0..CONF.MAX_PREVIEW_W) |x| {
                            const val = self.layers.?[l].data[y][x];
                            if (val == index) {
                                self.layers.?[l].data[y][x] = @intCast(index + 1);
                            } else if (val == index + 1) {
                                self.layers.?[l].data[y][x] = @intCast(index);
                            }
                        }
                    }
                }
            }
            self.updated = true;
            self.save_layers_to_file();
            self.save_tileset_to_file() catch {};
        }
    }
    pub fn show_tiles_selector(self: *Tiles, mouse: Mouse) ?bool {
        if (self.hot and !mouse.pressed) {
            self.hot = false;
        } else if (self.hot) {
            return null;
        }
        const tiles_in_row: i32 = 8;
        const tiles_rows: i32 = 8;
        const tiles_per_page: usize = @intCast(tiles_in_row * tiles_rows);
        const max_pages: usize = (CONF.MAX_TILES + tiles_per_page - 1) / tiles_per_page;

        const size: i32 = CONF.SPRITE_SIZE * CONF.PREVIEW_SCALE + 4;
        const start_index = self.page * tiles_per_page;

        const t_pos = Vec2.init(
            self.fui.pivots[PIVOTS.CENTER].x - (tiles_in_row * size) / 2,
            self.fui.pivots[PIVOTS.CENTER].y - (tiles_in_row * size) / 2,
        );

        self.fui.draw_rect(t_pos.x, t_pos.y, (tiles_in_row * size), (tiles_rows * size), CONF.COLOR_POPUP);

        for (0..tiles_per_page) |i| {
            const index = start_index + i;
            if (index >= CONF.MAX_TILES) break;

            const x_shift: i32 = @intCast(@mod(i, @as(usize, @intCast(tiles_in_row))) * @as(usize, @intCast(size)));
            const x: i32 = t_pos.x + x_shift;
            const row: i32 = @intCast(i / @as(usize, @intCast(tiles_in_row)));
            const y: i32 = row * size;

            if (index < self.count) {
                if (self.fui.button(x, t_pos.y + y, size, size, "", DB16.BLACK, mouse)) {
                    self.selected = @intCast(index);
                    return true;
                }
                self.draw(index, x + 1, t_pos.y + y + 1);
                if (self.selected == index) {
                    self.fui.draw_rect_lines(x + 5, y + t_pos.y + 5, size - 8, size - 8, DB16.BLACK);
                    self.fui.draw_rect_lines(x + 4, y + t_pos.y + 4, size - 8, size - 8, DB16.WHITE);
                }
            } else {
                self.fui.draw_rect_lines(x, t_pos.y + y, size, size, DB16.LIGHT_GRAY);
            }
        }

        // Controls
        const control_panel_x = t_pos.x - 148;
        self.fui.draw_rect(control_panel_x, t_pos.y, 140, 260, CONF.COLOR_MENU_NORMAL);

        var btn_y = t_pos.y + 8;
        if (self.fui.button(control_panel_x + 10, btn_y, 120, 64, "Close", CONF.COLOR_MENU_NORMAL, mouse)) {
            return true;
        }

        btn_y += 72;
        if (self.page > 0) {
            if (self.fui.button(control_panel_x + 10, btn_y, 120, 64, "Prev", CONF.COLOR_MENU_NORMAL, mouse)) {
                self.page -= 1;
            }
        }

        btn_y += 72;
        if (self.page < max_pages - 1) {
            if (self.fui.button(control_panel_x + 10, btn_y, 120, 64, "Next", CONF.COLOR_MENU_NORMAL, mouse)) {
                self.page += 1;
            }
        }

        var status_buf: [32:0]u8 = undefined;
        _ = std.fmt.bufPrintZ(&status_buf, "{d}/{d}", .{ self.page + 1, max_pages }) catch {};
        self.fui.draw_text(&status_buf, control_panel_x + 40, btn_y + 80, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);

        return null;
    }
};
