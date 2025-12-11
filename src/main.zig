// P1Xel Editor by Krzysztof Krystian Jankowski
//
const std = @import("std");
const rl = @import("raylib");
const math = @import("math.zig");
const DB16 = @import("palette.zig").DB16;

const THE_NAME = "P1Xel Editor";
const SCREEN_W = 1024;
const SCREEN_H = 768;

const PIVOT_TL_X = 8;
const PIVOT_TL_Y = 8;
const PIVOT_TR_X = SCREEN_W - 8;
const PIVOT_TR_Y = 8;
const PIVOT_BL_X = 8;
const PIVOT_BL_Y = SCREEN_H - 8;
const PIVOT_BR_X = SCREEN_W - 8;
const PIVOT_BR_Y = SCREEN_H - 8;

const SPRITE_SIZE = 16; // The actual sprite dimensions (16x16 pixels)
const GRID_SIZE = 32; // How large each pixel appears on screen (24x24 pixels)
const CANVAS_SIZE = SPRITE_SIZE * GRID_SIZE; // Total canvas size on screen (384x384)

const PREVIEW_SIZE = 128;
const PREVIEW_BIG = 256;
const SIDEBAR_X = 402;
const TOOLS_X = 402;
const TOOLS_Y = 300;
const SIDEBAR_W = SCREEN_W - SIDEBAR_X - 20;

var active_color: u8 = 1; // currently selected color index (0–15)
var current_palette = [4]u8{ 0, 1, 2, 3 }; // the 4 colors this sprite uses
var active_tool: u8 = 0; // TODO: Implement tool selection

fn getColorFromIndex(index: u8) rl.Color {
    return switch (index) {
        0 => DB16.BLACK, // Transparent if first color in palette
        1 => DB16.PURPLE,
        2 => DB16.RED,
        3 => DB16.BROWN,
        4 => DB16.DARK_GREEN,
        5 => DB16.DARK_GRAY,
        6 => DB16.GRAY,
        7 => DB16.WHITE,
        8 => DB16.LIGHT_RED,
        9 => DB16.ORANGE,
        10 => DB16.YELLOW,
        11 => DB16.GREEN,
        12 => DB16.CYAN,
        13 => DB16.BLUE,
        14 => DB16.LIGHT_BLUE,
        15 => DB16.PINK,
        else => DB16.BLACK, // Fallback for any index > 15
    };
}

pub fn main() !void {
    rl.initWindow(SCREEN_W, SCREEN_H, THE_NAME);
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    // Canvas should be 16x16 for the actual sprite data
    var canvas = [_][SPRITE_SIZE]u8{[_]u8{0} ** SPRITE_SIZE} ** SPRITE_SIZE;

    while (!rl.windowShouldClose()) {
        // ——————————————————————— INPUT ———————————————————————
        const mouse = rl.getMousePosition();
        // Calculate which sprite pixel the mouse is over
        const mouse_cell_x: i32 = @intFromFloat((mouse.x - PIVOT_TL_X) / @as(f32, @floatFromInt(GRID_SIZE)));
        const mouse_cell_y: i32 = @intFromFloat((mouse.y - PIVOT_TL_Y) / @as(f32, @floatFromInt(GRID_SIZE)));

        const in_canvas = mouse.x >= PIVOT_TL_X and mouse.x < PIVOT_TL_X + CANVAS_SIZE and
            mouse.y >= PIVOT_TL_Y and mouse.y < PIVOT_TL_Y + CANVAS_SIZE;

        if (in_canvas and ((rl.isMouseButtonDown(rl.MouseButton.left) or rl.isMouseButtonDown(rl.MouseButton.right)))) {
            var color: u8 = active_color;
            // Check bounds against SPRITE_SIZE, not GRID_SIZE
            if (mouse_cell_x >= 0 and mouse_cell_x < SPRITE_SIZE and
                mouse_cell_y >= 0 and mouse_cell_y < SPRITE_SIZE)
            {
                if (rl.isMouseButtonDown(rl.MouseButton.right)) color = 0;
                canvas[@intCast(mouse_cell_y)][@intCast(mouse_cell_x)] = color;
            }
        }

        const key = rl.getKeyPressed();
        switch (key) {
            rl.KeyboardKey.one => active_color = 0,
            rl.KeyboardKey.two => active_color = 1,
            rl.KeyboardKey.three => active_color = 2,
            rl.KeyboardKey.four => active_color = 3,
            else => {},
        }

        // ——————————————————————— DRAW ———————————————————————
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.getColor(0x1E1E1EFF));

        rl.drawText(THE_NAME, PIVOT_BL_X, PIVOT_BL_Y - 20, 20, DB16.LIGHT_BLUE);

        // ——— Canvas background (checkerboard) and sprite pixels ———
        for (0..SPRITE_SIZE) |y| {
            for (0..SPRITE_SIZE) |x| {
                // Draw checkerboard background
                const checker = (x + y) % 2 == 0;
                const col = if (checker) rl.getColor(0x333333FF) else rl.getColor(0x2D2D2DFF);

                rl.drawRectangle(
                    PIVOT_TL_X + @as(i32, @intCast(x * GRID_SIZE)),
                    PIVOT_TL_Y + @as(i32, @intCast(y * GRID_SIZE)),
                    GRID_SIZE,
                    GRID_SIZE,
                    col,
                );

                // Draw sprite pixel if not transparent
                const idx = canvas[y][x];
                if (idx != 0) { // 0 = transparent
                    const color = getColorFromIndex(idx);
                    rl.drawRectangle(
                        PIVOT_TL_X + @as(i32, @intCast(x * GRID_SIZE)),
                        PIVOT_TL_Y + @as(i32, @intCast(y * GRID_SIZE)),
                        GRID_SIZE,
                        GRID_SIZE,
                        color,
                    );
                }
            }
        }

        // ——— Canvas grid overlay ———
        // Draw grid lines for each sprite pixel (16 lines, not 24)
        for (0..SPRITE_SIZE + 1) |i| {
            const pos = @as(i32, @intCast(i * GRID_SIZE));
            rl.drawLine(PIVOT_TL_X + pos, PIVOT_TL_Y, PIVOT_TL_X + pos, PIVOT_TL_Y + CANVAS_SIZE, rl.getColor(0x44444488));
            rl.drawLine(PIVOT_TL_X, PIVOT_TL_Y + pos, PIVOT_TL_X + CANVAS_SIZE, PIVOT_TL_Y + pos, rl.getColor(0x44444488));
        }

        // ——— Canvas border ———
        rl.drawRectangleLines(PIVOT_TL_X - 1, PIVOT_TL_Y - 1, CANVAS_SIZE + 2, CANVAS_SIZE + 2, rl.Color.white);

        // ——— Right sidebar ———
        var sx: i32 = PIVOT_TR_X - SIDEBAR_X;
        var sy: i32 = PIVOT_TR_Y;

        rl.drawRectangleLines(sx, sy, PREVIEW_SIZE, PREVIEW_SIZE, rl.Color.ray_white);
        drawPreview(&canvas, sx + 4, sy + 4, PREVIEW_SIZE - 8);
        const next_prev: i32 = @intCast(PREVIEW_SIZE);
        rl.drawRectangleLines(sx + next_prev + 16, sy, PREVIEW_BIG, PREVIEW_BIG, rl.Color.ray_white);
        drawPreview(&canvas, sx + next_prev + 20, sy + 4, PREVIEW_BIG - 8);

        sx = PIVOT_BR_X - TOOLS_X;
        sy = PIVOT_BR_Y - TOOLS_Y;

        rl.drawText("ACTIVE PALETTE (DRAWING)", sx, sy, 10, DB16.BLUE);
        sy += 20;

        // 4-color sub-palette (the ones this sprite can use)
        inline for (0..4) |i| {
            const xoff: i32 = @intCast(i * 50);
            const index: u8 = @intCast(i);
            const color = current_palette[i];
            const pos: math.IVec2 = math.IVec2.init(sx + xoff, sy);
            rl.drawRectangle(pos.x, pos.y, 40, 40, getColorFromIndex(color));
            var buf: [2:0]u8 = undefined;
            buf[0] = '0' + index;
            buf[1] = 0;
            if (active_color == color) {
                const rx: i32 = pos.x - 1;
                const ry: i32 = pos.y - 1;
                rl.drawRectangleLines(rx, ry, 42, 42, DB16.WHITE);
                rl.drawText(&buf, pos.x + 2, pos.y + 42, 20, DB16.WHITE);
            } else rl.drawText(&buf, pos.x + 2, pos.y + 42, 20, DB16.LIGHT_BLUE);
        }
        sy += 70;

        // Tools
        rl.drawText("TOOLS", sx, sy, 10, DB16.BLUE);
        sy += 20;
        // _ = rl.GuiToggle(.{ .x = @floatFromInt(sx), .y = @floatFromInt(sy), .width = 40, .height = 40 }, rl.GuiIconText(rl.ICON_PENCIL, ""), active_tool == 0);
        // _ = rl.GuiToggle(.{ .x = @floatFromInt(sx + 50), .y = @floatFromInt(sy), .width = 40, .height = 40 }, rl.GuiIconText(rl.ICON_ERASER, ""), active_tool == 1);
        sy += 60;

        // Master 16-color palette
        rl.drawText("DB16 COLOR PALETTE", sx, sy, 10, DB16.BLUE);
        sy += 20;

        for (0..16) |i| {
            const x = @as(i32, @intCast(i % 8));
            const y = @as(i32, @intCast(i / 8));
            const rec = rl.Rectangle{
                .x = @floatFromInt(sx + x * 40),
                .y = @floatFromInt(sy + y * 40),
                .width = 36,
                .height = 36,
            };

            rl.drawRectangleRec(rec, getColorFromIndex(@intCast(i)));
            if (active_color == i) {
                rl.drawRectangleLinesEx(rec, 3, rl.Color.sky_blue);
            }
        }
    }
}

fn drawPreview(canvas: *const [SPRITE_SIZE][SPRITE_SIZE]u8, x: i32, y: i32, size: i32) void {
    const scale = @divFloor(size, SPRITE_SIZE); // Scale based on SPRITE_SIZE, not GRID_SIZE
    for (0..SPRITE_SIZE) |py| {
        for (0..SPRITE_SIZE) |px| {
            const idx = canvas[py][px];
            if (idx != 0) {
                rl.drawRectangle(
                    x + @as(i32, @intCast(px)) * scale,
                    y + @as(i32, @intCast(py)) * scale,
                    scale,
                    scale,
                    getColorFromIndex(idx),
                );
            }
        }
    }
}
