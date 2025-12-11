// P1Xel Editor by Krzysztof Krystian Jankowski
//
const std = @import("std");
const rl = @import("raylib");
const math = @import("math.zig");
const palette_mod = @import("palette.zig");
const DB16 = palette_mod.DB16;
const PALETTES = palette_mod.PALETTES;

const THE_NAME = "P1Xel Editor";
const SCREEN_W = 1024;
const SCREEN_H = 640;

const PIVOT_TL_X = 24;
const PIVOT_TL_Y = 24;
const PIVOT_TR_X = SCREEN_W - 24;
const PIVOT_TR_Y = 24;
const PIVOT_BL_X = 24;
const PIVOT_BL_Y = SCREEN_H - 24;
const PIVOT_BR_X = SCREEN_W - 24;
const PIVOT_BR_Y = SCREEN_H - 24;

const SPRITE_SIZE = 16; // The actual sprite dimensions (16x16 pixels)
const GRID_SIZE = 32; // How large each pixel appears on screen (24x24 pixels)
const CANVAS_SIZE = SPRITE_SIZE * GRID_SIZE; // Total canvas size on screen (384x384)

const PREVIEW_SIZE = 64;
const PREVIEW_BIG = 256;
const SIDEBAR_X = 402;
const TOOLS_X = 402;
const TOOLS_Y = 300;
const SIDEBAR_W = SCREEN_W - SIDEBAR_X - 20;

const Button = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    label: [:0]const u8,
    color: rl.Color,

    fn draw(self: Button) void {
        // Draw button background
        rl.drawRectangle(self.x, self.y, self.width, self.height, self.color);
        rl.drawRectangleLines(self.x, self.y, self.width, self.height, DB16.WHITE);

        // Draw centered text
        const text_width = rl.measureText(self.label, 20);
        const text_x = self.x + @divFloor(self.width - text_width, 2);
        const text_y = self.y + @divFloor(self.height - 20, 2);
        rl.drawText(self.label, text_x, text_y, 20, DB16.WHITE);
    }

    fn isClicked(self: Button, mouse: rl.Vector2) bool {
        return mouse.x >= @as(f32, @floatFromInt(self.x)) and
            mouse.x < @as(f32, @floatFromInt(self.x + self.width)) and
            mouse.y >= @as(f32, @floatFromInt(self.y)) and
            mouse.y < @as(f32, @floatFromInt(self.y + self.height));
    }
};

const MAX_CUSTOM_PALETTES = 20;
var custom_palettes: [MAX_CUSTOM_PALETTES][4]u8 = undefined;
var custom_palettes_count: usize = 0;

var active_color: u8 = 1; // currently selected color index (0–3) in current palette
var current_palette_index: usize = 0; // which palette is active from all_palettes
var current_palette = [4]u8{ 0, 3, 7, 15 }; // Mutable copy of current palette colors
var active_tool: u8 = 0; // TODO: Implement tool selection

fn savePalette() void {
    // Check if palette already exists in presets
    for (PALETTES) |pal| {
        if (std.mem.eql(u8, &pal, &current_palette)) {
            return; // Palette already exists
        }
    }

    // Check if palette already exists in custom
    for (0..custom_palettes_count) |i| {
        if (std.mem.eql(u8, &custom_palettes[i], &current_palette)) {
            return; // Palette already exists
        }
    }

    // Add to custom palettes if not at max
    if (custom_palettes_count < MAX_CUSTOM_PALETTES) {
        custom_palettes[custom_palettes_count] = current_palette;
        custom_palettes_count += 1;
        current_palette_index = PALETTES.len + custom_palettes_count - 1; // Select the new palette
    }
}

fn deletePalette() void {
    // Can't delete preset palettes
    if (current_palette_index < PALETTES.len) {
        return;
    }

    // Find and remove from custom palettes
    const custom_idx = current_palette_index - PALETTES.len;
    if (custom_idx < custom_palettes_count) {
        // Shift remaining palettes
        var i = custom_idx;
        while (i < custom_palettes_count - 1) : (i += 1) {
            custom_palettes[i] = custom_palettes[i + 1];
        }
        custom_palettes_count -= 1;

        // Adjust current palette index
        const total = PALETTES.len + custom_palettes_count;
        if (current_palette_index >= total) {
            current_palette_index = if (total > 0) total - 1 else 0;
        }

        // Update current palette
        current_palette = getPaletteAt(current_palette_index);
    }
}

fn getPaletteAt(index: usize) [4]u8 {
    if (index < PALETTES.len) {
        return PALETTES[index];
    } else if (index - PALETTES.len < custom_palettes_count) {
        return custom_palettes[index - PALETTES.len];
    }
    return [4]u8{ 0, 3, 7, 15 }; // Default palette
}

fn getColorFromIndex(index: u8) rl.Color {
    return switch (index) {
        0 => DB16.BLACK, // Transparent if first color in palette
        1 => DB16.DEEP_PURPLE,
        2 => DB16.NAVY_BLUE,
        3 => DB16.DARK_GRAY,
        4 => DB16.BROWN,
        5 => DB16.DARK_GREEN,
        6 => DB16.RED,
        7 => DB16.LIGHT_GRAY,
        8 => DB16.BLUE,
        9 => DB16.ORANGE,
        10 => DB16.STEEL_BLUE,
        11 => DB16.GREEN,
        12 => DB16.PINK_BEIGE,
        13 => DB16.CYAN,
        14 => DB16.YELLOW,
        15 => DB16.WHITE,
        else => DB16.BLACK, // Fallback for any index > 15
    };
}

pub fn main() !void {
    rl.initWindow(SCREEN_W, SCREEN_H, THE_NAME);
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    // Canvas should be 16x16 for the actual sprite data
    var canvas = [_][SPRITE_SIZE]u8{[_]u8{0} ** SPRITE_SIZE} ** SPRITE_SIZE;

    // Initialize current_palette from the first palette
    current_palette = PALETTES[current_palette_index];

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
                // Store the palette index, not the DB16 index
                canvas[@intCast(mouse_cell_y)][@intCast(mouse_cell_x)] = color;
            }
        }

        // Check for clicks on the 4-color palette
        const palette_x = PIVOT_BR_X - TOOLS_X;
        const palette_y = PIVOT_BR_Y - TOOLS_Y + 30; // Account for header text
        if (!in_canvas and rl.isMouseButtonPressed(rl.MouseButton.left)) {
            inline for (0..4) |i| {
                const xoff: i32 = @intCast(i * 50);
                const rect_x = palette_x + xoff;
                const rect_y = palette_y;
                if (mouse.x >= @as(f32, @floatFromInt(rect_x)) and
                    mouse.x < @as(f32, @floatFromInt(rect_x + 40)) and
                    mouse.y >= @as(f32, @floatFromInt(rect_y)) and
                    mouse.y < @as(f32, @floatFromInt(rect_y + 40)))
                {
                    active_color = @intCast(i);
                    break;
                }
            }
        }

        // Check for clicks on the global 16-color palette
        const global_palette_x = PIVOT_BR_X - TOOLS_X;
        const global_palette_y = PIVOT_BR_Y - TOOLS_Y + 118; // 24 (ACTIVE PALETTE) + 70 (after 4-color palette) + 24 (DB16 COLOR PALETTE)
        if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
            for (0..16) |i| {
                const x = @as(i32, @intCast(i % 8));
                const y = @as(i32, @intCast(i / 8));
                const rect_x = global_palette_x + x * 40;
                const rect_y = global_palette_y + y * 40;
                if (mouse.x >= @as(f32, @floatFromInt(rect_x)) and
                    mouse.x < @as(f32, @floatFromInt(rect_x + 36)) and
                    mouse.y >= @as(f32, @floatFromInt(rect_y)) and
                    mouse.y < @as(f32, @floatFromInt(rect_y + 36)))
                {
                    // Swap the clicked color into the current palette at active_color position
                    current_palette[active_color] = @intCast(i);
                    break;
                }
            }
        }

        const key = rl.getKeyPressed();
        switch (key) {
            rl.KeyboardKey.one => active_color = 0,
            rl.KeyboardKey.two => active_color = 1,
            rl.KeyboardKey.three => active_color = 2,
            rl.KeyboardKey.four => active_color = 3,
            rl.KeyboardKey.n => {
                // Clear canvas (start over)
                canvas = [_][SPRITE_SIZE]u8{[_]u8{0} ** SPRITE_SIZE} ** SPRITE_SIZE;
            },
            rl.KeyboardKey.tab => {
                // Cycle through palettes forward
                const total = PALETTES.len + custom_palettes_count;
                if (total > 0) {
                    current_palette_index = (current_palette_index + 1) % total;
                    current_palette = getPaletteAt(current_palette_index);
                    if (active_color > 0) active_color = 1; // Reset to second color if not on transparent
                }
            },
            rl.KeyboardKey.left_shift, rl.KeyboardKey.right_shift => {
                // Cycle through palettes backward with shift+tab
                const total = PALETTES.len + custom_palettes_count;
                if (rl.isKeyDown(rl.KeyboardKey.tab) and total > 0) {
                    if (current_palette_index == 0) {
                        current_palette_index = total - 1;
                    } else {
                        current_palette_index -= 1;
                    }
                    current_palette = getPaletteAt(current_palette_index);
                    if (active_color > 0) active_color = 1;
                }
            },
            else => {},
        }

        // ——————————————————————— DRAW ———————————————————————
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.getColor(0x1E1E1EFF));

        rl.drawText(THE_NAME, PIVOT_BL_X, PIVOT_BL_Y - 20, 20, DB16.CYAN);

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

                // Draw sprite pixel
                const idx = canvas[y][x];
                // Convert palette index to DB16 color index
                const db16_idx = current_palette[idx];

                // Only skip if it's index 0 AND the first palette color is black (transparent)
                if (idx == 0 and current_palette[0] == 0) {
                    // Skip transparent pixels
                } else {
                    const color = getColorFromIndex(db16_idx);
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
        // Draw grid lines for each sprite pixel (17 lines to complete the grid)
        for (0..SPRITE_SIZE + 1) |i| {
            const pos = @as(i32, @intCast(i * GRID_SIZE));
            const grid_color = if (i % 4 == 0) rl.getColor(0x66666688) else rl.getColor(0x44444488);
            rl.drawLine(PIVOT_TL_X + pos, PIVOT_TL_Y, PIVOT_TL_X + pos, PIVOT_TL_Y + CANVAS_SIZE, grid_color);
            rl.drawLine(PIVOT_TL_X, PIVOT_TL_Y + pos, PIVOT_TL_X + CANVAS_SIZE, PIVOT_TL_Y + pos, grid_color);
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

        var idx_buf: [32:0]u8 = undefined;
        const is_custom = current_palette_index >= PALETTES.len;
        const display_idx = if (is_custom) current_palette_index - PALETTES.len + 1 else current_palette_index + 1;
        const palette_type = if (is_custom) "CUSTOM" else "PRESET";
        const total = PALETTES.len + custom_palettes_count;
        _ = std.fmt.bufPrintZ(&idx_buf, "{s} {d}/{d}", .{ palette_type, display_idx, total }) catch {};
        rl.drawText(&idx_buf, sx, sy, 20, DB16.BLUE);

        // Add Save and Delete buttons
        const save_btn = Button{
            .x = sx + 240,
            .y = sy,
            .width = 96,
            .height = 28,
            .label = "Save",
            .color = DB16.DARK_GREEN,
        };

        const delete_btn = Button{
            .x = sx + 240,
            .y = sy + 34,
            .width = 96,
            .height = 28,
            .label = "Delete",
            .color = if (current_palette_index >= PALETTES.len) DB16.RED else DB16.DARK_GRAY,
        };

        save_btn.draw();
        delete_btn.draw();

        // Handle button clicks
        if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
            if (save_btn.isClicked(mouse)) {
                savePalette();
            } else if (delete_btn.isClicked(mouse) and current_palette_index >= PALETTES.len) {
                deletePalette();
            }
        }

        sy += 24;

        // 4-color sub-palette (the ones this sprite can use)
        inline for (0..4) |i| {
            const xoff: i32 = @intCast(i * 50);
            const index: u8 = @intCast(i);
            const db16_idx = current_palette[i];
            const pos: math.IVec2 = math.IVec2.init(sx + xoff, sy);

            // Draw shadow for depth
            rl.drawRectangle(pos.x + 2, pos.y + 2, 40, 40, rl.getColor(0x00000044));

            // Draw the color
            rl.drawRectangle(pos.x, pos.y, 40, 40, getColorFromIndex(db16_idx));

            // Draw border - thicker for selected
            if (active_color == index) {
                rl.drawRectangleLines(pos.x - 2, pos.y - 2, 44, 44, DB16.WHITE);
                rl.drawRectangleLines(pos.x - 1, pos.y - 1, 42, 42, DB16.WHITE);
            } else {
                rl.drawRectangleLines(pos.x, pos.y, 40, 40, rl.getColor(0x44444488));
            }

            // Draw key hint
            var buf: [2:0]u8 = undefined;
            buf[0] = '1' + index;
            buf[1] = 0;
            if (i == 0 and current_palette[0] == 0) {
                // Special label for transparent (only if first color is black)
                rl.drawText("TRANS", pos.x + 2, pos.y + 42, 8, if (active_color == index) DB16.WHITE else DB16.LIGHT_GRAY);
            } else {
                rl.drawText(&buf, pos.x + 2, pos.y + 42, 20, if (active_color == index) DB16.WHITE else DB16.LIGHT_GRAY);
            }
        }
        sy += 70;

        // Master 16-color palette
        rl.drawText("DB16 COLOR PALETTE", sx, sy, 20, DB16.BLUE);
        sy += 24;

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
            // Check if this DB16 color is in current palette
            var is_in_palette = false;
            for (current_palette) |palette_color| {
                if (palette_color == i) {
                    is_in_palette = true;
                    break;
                }
            }
            if (is_in_palette) {
                rl.drawRectangleLinesEx(rec, 3, rl.Color.sky_blue);
            }
        }

        rl.drawText("[TAB] = cycle palette, [N] = clear, [1-4] = color", PIVOT_BL_X + 160, PIVOT_BL_Y - 20, 20, DB16.LIGHT_GRAY);
    }
}

fn drawPreview(canvas: *const [SPRITE_SIZE][SPRITE_SIZE]u8, x: i32, y: i32, size: i32) void {
    const scale = @divFloor(size, SPRITE_SIZE); // Scale based on SPRITE_SIZE, not GRID_SIZE
    for (0..SPRITE_SIZE) |py| {
        for (0..SPRITE_SIZE) |px| {
            const idx = canvas[py][px];
            // Convert palette index to DB16 color index for preview
            const db16_idx = current_palette[idx];

            // Only skip if it's index 0 AND the first palette color is black (transparent)
            if (!(idx == 0 and current_palette[0] == 0)) {
                rl.drawRectangle(
                    x + @as(i32, @intCast(px)) * scale,
                    y + @as(i32, @intCast(py)) * scale,
                    scale,
                    scale,
                    getColorFromIndex(db16_idx),
                );
            }
        }
    }
}
