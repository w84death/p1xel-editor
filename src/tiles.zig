const std = @import("std");
const CONF = @import("config.zig").CONF;
const DB16 = @import("palette.zig").DB16;
const Palette = @import("palette.zig").Palette;
const Fui = @import("fui.zig").Fui;
const PIVOTS = @import("fui.zig").PIVOTS;
const Vec2 = @import("math.zig").Vec2;
const Mouse = @import("math.zig").Mouse;

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
    updated: bool = false,
    hot: bool = false,
    pub fn init(fui: Fui, palette: *Palette) Tiles {
        return Tiles{
            .db = undefined,
            .selected = 0,
            .fui = fui,
            .palette = palette,
            .count = 1,
            .updated = false,
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
    pub fn update_pal32(self: *Tiles, index: usize) void {
        const pal = self.db[index].pal;
        self.db[index].pal32 = [_]u32{
            self.palette.get_rgba_from_index(self.palette.db[pal][0]),
            self.palette.get_rgba_from_index(self.palette.db[pal][1]),
            self.palette.get_rgba_from_index(self.palette.db[pal][2]),
            self.palette.get_rgba_from_index(self.palette.db[pal][3]),
        };
    }
    pub fn draw(self: *Tiles, index: usize, x: i32, y: i32) void {
        var base_index: usize = @intCast(y * CONF.SCREEN_W + x);
        for (0..CONF.SPRITE_SIZE) |py| {
            for (0..CONF.SPRITE_SIZE) |px| {
                const idx = self.db[index].data[py][px];
                const color = self.db[index].pal32[idx];
                if (idx == 0 and color == DB16.BLACK) {
                    base_index += CONF.PREVIEW_SCALE;
                    continue;
                }
                inline for (0..CONF.PREVIEW_SCALE) |dy| {
                    inline for (0..CONF.PREVIEW_SCALE) |dx| {
                        self.fui.buf[base_index + dy * CONF.SCREEN_W + dx] = color;
                    }
                }
                base_index += CONF.PREVIEW_SCALE;
            }
            base_index += CONF.SCREEN_W * CONF.PREVIEW_SCALE - CONF.SPRITE_SIZE * CONF.PREVIEW_SCALE;
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
    pub fn shift_tile_left(self: *Tiles, index: usize) void {
        if (index > 0 and index < self.count) {
            const temp = self.db[index];
            self.db[index] = self.db[index - 1];
            self.db[index - 1] = temp;
            self.updated = true;
        }
    }
    pub fn shift_tile_right(self: *Tiles, index: usize) void {
        if (index >= 0 and index < self.count - 1) {
            const temp = self.db[index];
            self.db[index] = self.db[index + 1];
            self.db[index + 1] = temp;
            self.updated = true;
        }
    }
    pub fn show_tiles_selector(self: *Tiles, mouse: Mouse) ?bool {
        if (self.hot and !mouse.pressed) {
            self.hot = false;
        } else if (self.hot) {
            return null;
        }
        const tiles_in_row: i32 = 8;
        const size: i32 = CONF.SPRITE_SIZE * CONF.PREVIEW_SCALE + 4;
        const tiles_first: usize = 0;
        const tiles_last: usize = CONF.MAX_TILES / 2;
        const t_pos = Vec2.init(
            self.fui.pivots[PIVOTS.CENTER].x - (tiles_in_row * size) / 2,
            self.fui.pivots[PIVOTS.CENTER].y - (tiles_in_row * size) / 2,
        );
        self.fui.draw_rect(t_pos.x, t_pos.y, (tiles_in_row * size), (tiles_in_row * size), CONF.COLOR_POPUP);
        for (tiles_first..tiles_last) |i| {
            const x_shift: i32 = @intCast(@mod(i, tiles_in_row) * size);
            const x: i32 = t_pos.x + x_shift;
            const ii: i32 = @intCast(i);
            const y: i32 = @divFloor(ii, tiles_in_row) * size;
            if (i < self.count) {
                if (self.fui.button(x, t_pos.y + y, size, size, "", DB16.BLACK, mouse)) {
                    self.selected = @intCast(ii);
                    return true;
                }
                self.draw(i, x + 1, t_pos.y + y + 1);
                if (self.selected == i) {
                    self.fui.draw_rect_lines(x + 5, y + t_pos.y + 5, size - 8, size - 8, DB16.BLACK);
                    self.fui.draw_rect_lines(x + 4, y + t_pos.y + 4, size - 8, size - 8, DB16.WHITE);
                }
            } else {
                self.fui.draw_rect_lines(x, t_pos.y + y, size, size, DB16.LIGHT_GRAY);
            }
        }
        if (self.fui.button(self.fui.pivots[PIVOTS.TOP_LEFT].x, self.fui.pivots[PIVOTS.TOP_LEFT].y, 80, 32, "Close", CONF.COLOR_MENU_NORMAL, mouse)) {
            return true;
        }
        return null;
    }
};
