const rl = @import("raylib");
const DB16 = @import("palette.zig").DB16;

pub const CONF = struct {
    pub const VERSION = "alpha1";
    pub const THE_NAME = "P1Xel Editor";
    pub const SCREEN_W = 1280;
    pub const SCREEN_H = 800;
    pub const PALETTES_FILE = "palettes.dat";
    pub const MAX_PALETTES = 100;
    pub const MAX_TILES = 128;
    pub const DEFAULT_FONT_SIZE = 20;
    pub const CORNER_RADIUS = 0.1;
    pub const CORNER_QUALITY = 2;
    pub const SHADOW = 4;
    pub const FRAME = 2;
    pub const SPRITE_SIZE = 16; // The actual sprite dimensions (16x16 pixels)
    pub const GRID_SIZE = 32; // How large each pixel appears on screen (24x24 pixels)
    pub const CANVAS_SIZE = SPRITE_SIZE * GRID_SIZE; // Total canvas size on screen (384x384)
    pub const CANVAS_FRAME_SIZE = 16;
    pub const CANVAS_X = 0;
    pub const CANVAS_Y = 64;
};
