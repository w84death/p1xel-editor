const rl = @import("raylib");

pub const DB16 = struct {
    pub const BLACK = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const DEEP_PURPLE = rl.Color{ .r = 68, .g = 32, .b = 52, .a = 255 };
    pub const NAVY_BLUE = rl.Color{ .r = 48, .g = 52, .b = 109, .a = 255 };
    pub const DARK_GRAY = rl.Color{ .r = 78, .g = 74, .b = 78, .a = 255 };
    pub const BROWN = rl.Color{ .r = 133, .g = 76, .b = 48, .a = 255 };
    pub const DARK_GREEN = rl.Color{ .r = 52, .g = 101, .b = 36, .a = 255 };
    pub const RED = rl.Color{ .r = 208, .g = 70, .b = 72, .a = 255 };
    pub const LIGHT_GRAY = rl.Color{ .r = 117, .g = 113, .b = 97, .a = 255 };
    pub const BLUE = rl.Color{ .r = 89, .g = 125, .b = 206, .a = 255 };
    pub const ORANGE = rl.Color{ .r = 210, .g = 125, .b = 44, .a = 255 };
    pub const STEEL_BLUE = rl.Color{ .r = 133, .g = 149, .b = 161, .a = 255 };
    pub const GREEN = rl.Color{ .r = 109, .g = 170, .b = 44, .a = 255 };
    pub const PINK_BEIGE = rl.Color{ .r = 210, .g = 170, .b = 153, .a = 255 };
    pub const CYAN = rl.Color{ .r = 109, .g = 194, .b = 202, .a = 255 };
    pub const YELLOW = rl.Color{ .r = 218, .g = 212, .b = 94, .a = 255 };
    pub const WHITE = rl.Color{ .r = 222, .g = 238, .b = 214, .a = 255 };
};

// Palette struct holds 4 color indices from DB16
pub const Palette = [4]u8;
