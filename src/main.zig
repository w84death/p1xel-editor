const std = @import("std");
const rl = @import("raylib");
const math = @import("math.zig");
const UI = @import("ui.zig").UI;

const palette_mod = @import("palette.zig");
const DB16 = palette_mod.DB16;
const PALETTES_FILE = "palettes.dat";

const THE_NAME = "P1Xel Editor";

const MAX_PALETTES = 100;
const SPRITE_SIZE = 16; // The actual sprite dimensions (16x16 pixels)
const GRID_SIZE = 32; // How large each pixel appears on screen (24x24 pixels)
const CANVAS_SIZE = SPRITE_SIZE * GRID_SIZE; // Total canvas size on screen (384x384)

pub fn main() !void {
    const ui = UI.init(THE_NAME, DB16.NAVY_BLUE, DB16.YELLOW);
    ui.createWindow();
    defer ui.closeWindow();

    rl.setTargetFPS(60);

    // var canvas_main = [_][SPRITE_SIZE]u8{[_]u8{0} ** SPRITE_SIZE} ** SPRITE_SIZE;
    // const mouse = rl.getMousePosition();

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        ui.demo();
    }
}
