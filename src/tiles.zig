const std = @import("std");
const rl = @import("raylib");
const CONF = @import("config.zig").CONF;
const DB16 = @import("palette.zig").DB16;
const Palette = @import("palette.zig").Palette;
const Ui = @import("ui.zig").UI;
const PIVOTS = @import("ui.zig").PIVOTS;

pub const Tile = struct {
    w: f32,
    h: f32,
    data: [CONF.SPRITE_SIZE][CONF.SPRITE_SIZE]u8,
    pal: u8,
    pub fn init(data: [CONF.SPRITE_SIZE][CONF.SPRITE_SIZE]u8, pal: u8) Tile {
        return Tile{
            .w = CONF.SPRITE_SIZE,
            .h = CONF.SPRITE_SIZE,
            .data = data,
            .pal = pal,
        };
    }
};

pub const Tiles = struct {
    db: [CONF.MAX_TILES]Tile = undefined,
    selected: u8 = 0,
    count: u8 = 0,
    ui: Ui,
    palette: *Palette,
    updated: bool = false,
    hot: bool = false,
    pub fn init(ui: Ui, palette: *Palette) Tiles {
        return Tiles{
            .db = undefined,
            .selected = 0,
            .ui = ui,
            .palette = palette,
            .count = 1,
            .updated = false,
        };
    }
    pub fn loadTilesFromFile(self: *Tiles) void {
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
        }

        self.updated = false;
    }
    pub fn saveTilesToFile(self: *Tiles) !void {
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

    pub fn draw(self: *Tiles, index: usize, x: i32, y: i32, scale: i32) void {
        for (0..CONF.SPRITE_SIZE) |py| {
            for (0..CONF.SPRITE_SIZE) |px| {
                const pal = self.db[index].pal;
                const idx = self.db[index].data[py][px];
                const db16_idx = self.palette.db[pal][idx];
                const xx: i32 = @intCast(px);
                const yy: i32 = @intCast(py);
                if (db16_idx == 0 and idx == 0) continue;
                rl.drawRectangle(
                    x + xx * scale,
                    y + yy * scale,
                    scale,
                    scale,
                    self.palette.getColorFromIndex(db16_idx),
                );
            }
        }
    }
    pub fn newTile(self: *Tiles) !void {
        var data: [CONF.SPRITE_SIZE][CONF.SPRITE_SIZE]u8 = undefined;
        for (0..CONF.SPRITE_SIZE) |y| {
            for (0..CONF.SPRITE_SIZE) |x| {
                data[y][x] = 0;
            }
        }
        self.db[self.count] = Tile.init(data, 0);
        self.count += 1;
        self.updated = true;
    }
    pub fn duplicateTile(self: *Tiles, index: usize) void {
        const data: [CONF.SPRITE_SIZE][CONF.SPRITE_SIZE]u8 = self.db[index].data;
        self.db[self.count] = Tile.init(data, self.db[index].pal);
        self.count += 1;
        self.updated = true;
    }
    pub fn delete(self: *Tiles, index: usize) void {
        if (self.count <= 1) {
            return;
        }
        var i = index;
        while (i < self.count - 1) : (i += 1) {
            self.db[i] = self.db[i + 1];
        }
        self.count -= 1;
        self.updated = true;
        return;
    }
    pub fn shiftLeft(self: *Tiles, index: usize) void {
        if (index > 0 and index < self.count) {
            const temp = self.db[index];
            self.db[index] = self.db[index - 1];
            self.db[index - 1] = temp;
            self.updated = true;
        }
    }
    pub fn shiftRight(self: *Tiles, index: usize) void {
        if (index >= 0 and index < self.count - 1) {
            const temp = self.db[index];
            self.db[index] = self.db[index + 1];
            self.db[index + 1] = temp;
            self.updated = true;
        }
    }
    pub fn showTilesSelector(self: *Tiles, mouse: rl.Vector2) ?bool {
        if (self.hot and rl.isMouseButtonReleased(rl.MouseButton.left)) {
            self.hot = false;
        } else if (self.hot) {
            return null;
        }

        const tiles_in_row: usize = 16;
        const scale: i32 = 4;
        const w: f32 = tiles_in_row * (CONF.SPRITE_SIZE * scale + 12);
        const h: f32 = @floatFromInt(@divFloor(CONF.MAX_TILES, tiles_in_row) * (CONF.SPRITE_SIZE * scale + 12));
        const t_pos = rl.Vector2.init(self.ui.pivots[PIVOTS.CENTER].x - w / 2, self.ui.pivots[PIVOTS.CENTER].y - h / 2);
        const tiles_x: i32 = @intFromFloat(t_pos.x);
        const tiles_y: i32 = @intFromFloat(t_pos.y);

        inline for (0..CONF.MAX_TILES) |i| {
            const x_shift: i32 = @intCast(@mod(i, tiles_in_row) * (CONF.SPRITE_SIZE * scale + 12));
            const x: i32 = tiles_x + x_shift;
            const y: i32 = @divFloor(i, tiles_in_row) * (CONF.SPRITE_SIZE * scale + 12);
            const size: i32 = CONF.SPRITE_SIZE * scale + 2;
            const fx: f32 = @floatFromInt(x);
            const fy: f32 = @floatFromInt(tiles_y + y);
            if (i < self.count) {
                if (self.ui.button(fx, fy, size, size, "", DB16.BLACK, mouse)) {
                    self.selected = i;
                    return true;
                }
                self.draw(i, x + 1, tiles_y + y + 1, scale);
                if (self.selected == i) {
                    rl.drawRectangleLines(x + 5, y + tiles_y + 5, size - 8, size - 8, DB16.BLACK);
                    rl.drawRectangleLines(x + 4, y + tiles_y + 4, size - 8, size - 8, DB16.WHITE);
                }
            } else {
                rl.drawRectangleLines(x, tiles_y + y, size, size, DB16.LIGHT_GRAY);
            }
        }
        return null;
    }
};
