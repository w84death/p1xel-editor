// *************************************
// BOROWIK ENGINE
// by Krzysztof Krystian Jankowski
// github.com/w84death/borowik-engine
// *************************************

const build_options = @import("build_options");

pub const CONF = struct {
    pub const AppMode = enum { shareware, full };

    pub const VERSION = "2.9";
    pub const ENGINE = "1.2";
    pub const THE_NAME = "P1Xel Editor";
    pub const TAG_LINE = "";
    pub const APP_MODE: AppMode = if (build_options.full_version) .full else .shareware;
    pub const SHAREWARE_WAIT_SECONDS: i64 = 5;
    pub const BUY_URL = "https://w84death.itch.io/p1xel-editor";
    pub const SCREEN_W = 1280;
    pub const SCREEN_H = 800;
    pub const PIXEL_SCALE = 1;
    pub const FULLSCREEN = 1;
    pub const TARGET_FPS = 60.0;
    pub const FONT_WIDTH = 8;
    pub const FONT_HEIGHT = 8;

    pub const PROJECT_FILE = "art_data.p1x";
    pub const GBC_EXPORT_PROJECT_DIR = "EXAMPLE-GBC-PROJECT";
    pub const GBC_EXPORT_BINARY_PATH = GBC_EXPORT_PROJECT_DIR ++ "/engine_export.p1xb";
    pub const GBC_EXPORT_INC_DIR = GBC_EXPORT_PROJECT_DIR ++ "/SRC";
    pub const GBC_EXPORT_INC_PATH = GBC_EXPORT_INC_DIR ++ "/p1xel_export.inc";
    pub const TILE_SIDE = 8;
    pub const COLORS_PER_PALETTE = 4;
    pub const PALETTE_COUNT = 8;
    pub const MAX_TILES = 128;
    pub const EDITOR_CANVAS_X = 256;
    pub const EDITOR_CANVAS_Y = 64;
    pub const EDITOR_CANVAS_SCALE = 64;

    pub const SPRITE_MAX_FILE_BYTES = 16 * 1024 * 1024;
    pub const SPRITE_DEFAULT_TRANSPARENT_INDEX: u8 = 0;
    pub const BMP_FILE_HEADER_SIZE = 14;
    pub const BMP_DIB_HEADER_MIN_SIZE = 40;
    pub const BMP_PALETTE_ENTRY_SIZE = 4;
    pub const BMP_DEFAULT_PALETTE_COLORS = 256;
    pub const BMP_FILE_OFFSET_PIXEL_START = 10;
    pub const BMP_DIB_OFFSET_WIDTH = 18;
    pub const BMP_DIB_OFFSET_HEIGHT = 22;
    pub const BMP_DIB_OFFSET_PLANES = 26;
    pub const BMP_DIB_OFFSET_BITS_PER_PIXEL = 28;
    pub const BMP_DIB_OFFSET_COMPRESSION = 30;
    pub const BMP_DIB_OFFSET_COLORS_USED = 46;

    pub const BMP_SIGNATURE_B = 'B';
    pub const BMP_SIGNATURE_M = 'M';
    pub const BMP_REQUIRED_PLANES = 1;
    pub const BMP_REQUIRED_BPP = 8;
    pub const BMP_COMPRESSION_RGB = 0;
};
