pub const CONF = struct {
    pub const VERSION = "pre-alpha0";
    pub const THE_NAME = "P1Xel Editor";
    pub const SCREEN_W = 1024;
    pub const SCREEN_H = 768;
    pub const PALETTES_FILE = "palettes.dat";
    pub const MAX_PALETTES = 100;
    pub const DEFAULT_FONT_SIZE = 20;
    pub const CORNER_RADIUS = 0.1;
    pub const CORNER_QUALITY = 2;
    pub const SPRITE_SIZE = 16; // The actual sprite dimensions (16x16 pixels)
    pub const GRID_SIZE = 32; // How large each pixel appears on screen (24x24 pixels)
    pub const CANVAS_SIZE = SPRITE_SIZE * GRID_SIZE; // Total canvas size on screen (384x384)
};
