const std = @import("std");
const rl = @import("raylib");
const CONF = @import("config.zig").CONF;
const DB16 = @import("palette.zig").DB16;
const Palette = @import("palette.zig").Palette;

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
    count: u8 = 0,
    palette: *Palette,
    pub fn init(palette: *Palette) Tiles {
        var example_data: [CONF.SPRITE_SIZE][CONF.SPRITE_SIZE]u8 = undefined;
        for (0..CONF.SPRITE_SIZE) |y| {
            for (0..CONF.SPRITE_SIZE) |x| {
                example_data[y][x] = if ((x + y) % 2 == 0) 1 else 2;
            }
        }
        var tiles: [CONF.MAX_TILES]Tile = undefined;
        tiles[0] = Tile.init(example_data, 0);
        return Tiles{
            .db = tiles,
            .palette = palette,
            .count = 1,
        };
    }
    pub fn draw_tile(self: *Tiles, index: usize, x: i32, y: i32, scale: i32) void {
        for (0..CONF.SPRITE_SIZE) |py| {
            for (0..CONF.SPRITE_SIZE) |px| {
                const pal = self.db[index].pal;
                const idx = self.db[index].data[py][px];
                const db16_idx = self.palette.db[pal][idx];
                const xx: i32 = @intCast(px);
                const yy: i32 = @intCast(py);

                if (!(idx == 0 and self.palette.current[0] == 0)) {
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
    }
};
