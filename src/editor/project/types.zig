const CONF = @import("../../engine/config.zig").CONF;

pub const Tool = enum { pixel, fill, line };
pub const ColorChannel = enum { r, g, b };
pub const ProjectMode = enum(u8) { tiles = 0, sprites = 1 };
pub const PaletteColor = [3]u8;

pub const MAX_MAP_W = 128;
pub const MAX_MAP_H = 32;
pub const MAX_MAP_CELLS = MAX_MAP_W * MAX_MAP_H;
pub const MAX_MAP_SPRITES = 256;

pub const MapSize = enum(u8) { size_32x32 = 0, size_64x16 = 1, size_128x16 = 2 };

pub const TILE_FLAG_TRAVERSABLE: u8 = 1 << 0;

pub const MapTileAttr = struct {
    palette: u8 = 0,
    hflip: bool = false,
    vflip: bool = false,

    pub fn encode(self: MapTileAttr) u8 {
        return (self.palette & 7) | (if (self.hflip) @as(u8, 1) << 5 else 0) | (if (self.vflip) @as(u8, 1) << 6 else 0);
    }

    pub fn decode(value: u8) MapTileAttr {
        return .{ .palette = value & 7, .hflip = (value & (1 << 5)) != 0, .vflip = (value & (1 << 6)) != 0 };
    }
};

pub const MapSprite = struct {
    x: u16 = 0,
    y: u16 = 0,
    sprite_id: u16 = 0,
    palette: u8 = 0,
    hflip: bool = false,
    vflip: bool = false,
};

pub const MapCell = struct {
    tile_id: u8,
    attr: MapTileAttr,
};

pub const Map = struct {
    width: u16 = 32,
    height: u16 = 32,
    tile_ids: [MAX_MAP_CELLS]u8 = [_]u8{0} ** MAX_MAP_CELLS,
    tile_attrs: [MAX_MAP_CELLS]u8 = [_]u8{0} ** MAX_MAP_CELLS,
    sprites: [MAX_MAP_SPRITES]MapSprite = [_]MapSprite{.{}} ** MAX_MAP_SPRITES,
    sprite_count: u16 = 0,
};

pub const Image = struct {
    palette_id: u8 = 0,
    pixels: [CONF.TILE_SIDE * CONF.TILE_SIDE]u8 = [_]u8{0} ** (CONF.TILE_SIDE * CONF.TILE_SIDE),

    pub fn is_empty(self: Image) bool {
        for (self.pixels) |px| if (px != 0) return false;
        return true;
    }
};

pub const Tile = Image;
