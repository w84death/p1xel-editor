const std = @import("std");
const rl = @import("raylib");
const CONF = @import("../config.zig").CONF;
const DB16 = @import("../palette.zig").DB16;
const Palette = @import("../palette.zig").Palette;
const Ui = @import("../ui.zig").UI;
const PIVOTS = @import("../ui.zig").PIVOTS;
const State = @import("../state.zig").State;
const StateMachine = @import("../state.zig").StateMachine;
const Tiles = @import("../tiles.zig").Tiles;
const Tile = @import("../tiles.zig").Tile;
const Ppm = @import("../ppm.zig").Ppm;
const RGB = @import("../ppm.zig").RGB;
const Color = @import("../ppm.zig").Color;

const Canvas = struct {
    width: i32,
    height: i32,
    x: i32,
    y: i32,
    data: [CONF.SPRITE_SIZE][CONF.SPRITE_SIZE]u8,
};

const Popup = enum {
    none,
    info_not_implemented,
    confirm_clear,
    info_save_ppm_ok,
    info_save_ppm_fail,
    info_save_tileset,
};

pub const EditScreen = struct {
    ui: Ui,
    sm: *StateMachine,
    canvas: Canvas,
    palette: *Palette,
    tiles: *Tiles,
    tile_id: u8,
    locked: bool,
    popup: Popup,
    needs_saving: bool,
    status_buffer: [256]u8 = undefined,

    pub fn init(ui: Ui, sm: *StateMachine, pal: *Palette, tiles: *Tiles) EditScreen {
        const ix: i32 = @intFromFloat(ui.pivots[PIVOTS.TOP_LEFT].x + CONF.CANVAS_X);
        const iy: i32 = @intFromFloat(ui.pivots[PIVOTS.TOP_LEFT].y + CONF.CANVAS_Y);
        return EditScreen{
            .ui = ui,
            .sm = sm,
            .canvas = Canvas{
                .width = CONF.SPRITE_SIZE * CONF.GRID_SIZE,
                .height = CONF.SPRITE_SIZE * CONF.GRID_SIZE,
                .x = ix,
                .y = iy,
                .data = tiles.db[0].data,
            },
            .palette = pal,
            .tiles = tiles,
            .tile_id = 0,
            .locked = false,
            .popup = Popup.none,
            .needs_saving = false,
        };
    }
    pub fn handleKeyboard(self: *EditScreen) void {
        if (self.locked) return;
        const key = rl.getKeyPressed();
        switch (key) {
            rl.KeyboardKey.one => self.palette.swatch = 0,
            rl.KeyboardKey.two => self.palette.swatch = 1,
            rl.KeyboardKey.three => self.palette.swatch = 2,
            rl.KeyboardKey.four => self.palette.swatch = 3,
            rl.KeyboardKey.tab => {
                self.palette.cyclePalette();
            },
            else => {},
        }
    }
    pub fn handleMouse(self: *EditScreen, mouse: rl.Vector2) void {
        if (self.locked) return;

        if (self.sm.hot and rl.isMouseButtonReleased(rl.MouseButton.left)) {
            self.sm.hot = false;
        } else if (self.sm.hot) {
            return;
        }

        const mx: i32 = @intFromFloat(mouse.x);
        const my: i32 = @intFromFloat(mouse.y);
        const mouse_cell_x: i32 = @divFloor(mx - self.canvas.x, CONF.GRID_SIZE);
        const mouse_cell_y: i32 = @divFloor(my - self.canvas.y, CONF.GRID_SIZE);

        if ((rl.isMouseButtonDown(rl.MouseButton.left) or rl.isMouseButtonDown(rl.MouseButton.right))) {
            var color: u8 = self.palette.swatch;
            if (mouse_cell_x >= 0 and mouse_cell_x < CONF.SPRITE_SIZE and
                mouse_cell_y >= 0 and mouse_cell_y < CONF.SPRITE_SIZE)
            {
                if (rl.isMouseButtonDown(rl.MouseButton.right)) color = 0;
                self.canvas.data[@intCast(mouse_cell_y)][@intCast(mouse_cell_x)] = color;
                self.needs_saving = true;
            }
        }

        var status_buf: [64:0]u8 = undefined;
        if (mouse_cell_x >= 0 and mouse_cell_x < CONF.SPRITE_SIZE and
            mouse_cell_y >= 0 and mouse_cell_y < CONF.SPRITE_SIZE)
        {
            _ = std.fmt.bufPrintZ(&status_buf, "Pos: {d}, {d}", .{ mouse_cell_x, mouse_cell_y }) catch {};
            rl.drawText(&status_buf, self.canvas.x, self.canvas.y + CONF.SPRITE_SIZE * CONF.GRID_SIZE + 8, 20, DB16.WHITE);
        }
    }

    pub fn clearCanvas(self: *EditScreen) void {
        self.canvas.data = [_][CONF.SPRITE_SIZE]u8{[_]u8{0} ** CONF.SPRITE_SIZE} ** CONF.SPRITE_SIZE;
    }
    pub fn draw(self: *EditScreen, mouse: rl.Vector2) !void {
        // Navigation (top)
        const nav: rl.Vector2 = rl.Vector2.init(self.ui.pivots[PIVOTS.TOP_LEFT].x, self.ui.pivots[PIVOTS.TOP_LEFT].y);
        var nav_step = nav.x;
        if (self.ui.button(nav_step, nav.y, 80, 32, "< Menu", DB16.BLUE, mouse) and !self.locked) {
            self.sm.goTo(State.main_menu);
        }
        nav_step += 88;
        if (self.ui.button(nav_step, nav.y, 160, 32, "Select tile", DB16.BLUE, mouse) and !self.locked) {
            self.sm.goTo(State.tileset);
        }
        nav_step += 168;
        if (self.ui.button(nav_step, nav.y, 160, 32, "Save tile", if (self.needs_saving) DB16.GREEN else DB16.DARK_GREEN, mouse) and !self.locked) {
            self.tiles.db[self.tile_id].data = self.canvas.data;
            self.tiles.db[self.tile_id].pal = self.palette.index;
            self.tiles.saveTilesToFile();
            self.needs_saving = false;
        }
        nav_step += 168;
        if (self.ui.button(nav_step, nav.y, 240, 32, "Export Tile (PPM)", DB16.DARK_GREEN, mouse) and !self.locked) {
            self.locked = true;
            self.export_to_ppm() catch {
                self.popup = Popup.info_save_ppm_fail;
                return;
            };
            self.popup = Popup.info_save_ppm_ok;
        }

        // Canvas
        for (0..CONF.SPRITE_SIZE) |y| {
            for (0..CONF.SPRITE_SIZE) |x| {
                const idx = self.canvas.data[y][x];
                const db16_idx = self.palette.current[idx];
                const xx: i32 = @intCast(x * CONF.GRID_SIZE);
                const yy: i32 = @intCast(y * CONF.GRID_SIZE);
                var color: rl.Color = undefined;

                if (idx == 0 and self.palette.current[0] == 0) {
                    const checker = (x + y) % 2 == 0;
                    color = if (checker) rl.getColor(0x33333310) else rl.getColor(0xAAAAAA10);
                } else {
                    color = self.palette.getColorFromIndex(db16_idx);
                }
                rl.drawRectangle(
                    self.canvas.x + xx,
                    self.canvas.y + yy,
                    CONF.GRID_SIZE,
                    CONF.GRID_SIZE,
                    color,
                );
            }
        }
        rl.drawRectangleLines(
            self.canvas.x,
            self.canvas.y,
            self.canvas.width,
            self.canvas.height,
            DB16.STEEL_BLUE,
        );
        const clear_pos: rl.Vector2 = rl.Vector2.init(
            @floatFromInt(self.canvas.x + CONF.SPRITE_SIZE * CONF.GRID_SIZE - 160),
            @floatFromInt(self.canvas.y + CONF.SPRITE_SIZE * CONF.GRID_SIZE + 8),
        );
        if (self.ui.button(
            clear_pos.x,
            clear_pos.y,
            160,
            32,
            "Clear canvas",
            DB16.RED,
            mouse,
        ) and !self.locked) {
            self.locked = true;
            self.popup = Popup.confirm_clear;
        }

        // Previews
        const px = self.canvas.x + self.canvas.width + 24;
        const py = self.canvas.y;
        const dw: i32 = @divFloor(self.canvas.height, 4);
        self.draw_preview(px, py, 4, DB16.BLACK);
        self.draw_preview(px + dw + 8, py, 4, DB16.WHITE);

        // Swatches
        const swa_x: i32 = px;
        const swa_y: i32 = py + 160;
        const swa_size: i32 = 48;
        rl.drawText("ACTIVE SWATCHES", swa_x, swa_y, 20, rl.Color.ray_white);
        inline for (0..4) |i| {
            const x_shift: i32 = @intCast(i * (swa_size + 6));
            const index: u8 = @intCast(i);
            const db16_idx = self.palette.current[i];
            const fx: f32 = @floatFromInt(swa_x + x_shift);
            const fy: f32 = @floatFromInt(swa_y + 28);

            if (self.ui.button(fx, fy, swa_size, swa_size, "", self.palette.getColorFromIndex(db16_idx), mouse) and !self.locked) {
                self.palette.swatch = index;
            }

            if (self.palette.swatch == i) {
                rl.drawRectangleLines(swa_x + x_shift + 5, swa_y + 28 + 5, swa_size - 8, swa_size - 8, DB16.BLACK);
                rl.drawRectangleLines(swa_x + x_shift + 4, swa_y + 28 + 4, swa_size - 8, swa_size - 8, DB16.WHITE);
            }

            if (i == 0 and self.palette.current[0] == 0) {
                rl.drawText("TRANSPARENT", swa_x, swa_y + swa_size + 32, 10, DB16.WHITE);
            }
        }

        var fsx: f32 = @floatFromInt(swa_x + swa_size * 4 + 24);
        var fsy: f32 = @floatFromInt(swa_y + 28);
        var status_buf: [7:0]u8 = undefined;
        _ = std.fmt.bufPrintZ(&status_buf, "{d:0>2}/{d:0>2}", .{ self.palette.index + 1, self.palette.count }) catch {};
        rl.drawText(&status_buf, @intFromFloat(fsx), @intFromFloat(fsy), CONF.FONT_DEFAULT_SIZE, DB16.WHITE);
        if (self.palette.count > 1 and self.ui.button(fsx, fsy + 24, 64, 24, ">", DB16.BLUE, mouse) and !self.locked) {
            self.palette.cyclePalette();
            self.needs_saving = true;
        }
        fsx += 38;
        if (self.palette.count > 1 and self.ui.button(fsx + 64, fsy, 80, 32, "Delete", DB16.RED, mouse) and !self.locked) {
            self.palette.deletePalette();
        }

        fsx += 64;
        rl.drawText("OPTIONS:", @intFromFloat(fsx), swa_y, 20, rl.Color.ray_white);
        fsy += 40;
        if (self.palette.updated) {
            if (self.ui.button(fsx, fsy, 120, 32, "Update", DB16.BLUE, mouse) and !self.locked) {
                self.palette.updatePalette();
                self.needs_saving = true;
            }
            if (self.ui.button(fsx, fsy + 40, 120, 32, "Save new", DB16.GREEN, mouse) and !self.locked) {
                self.palette.newPalette();
                self.needs_saving = true;
            }
        }

        // Palette
        const pal_x: i32 = swa_x;
        const pal_y: i32 = swa_y + 100;
        const pal_size: i32 = 32;
        rl.drawText("DB16 PALETTE", pal_x, pal_y, 20, rl.Color.ray_white);
        const colors_in_row: usize = 4;
        inline for (0..16) |i| {
            const x_shift: i32 = @intCast(@mod(i, colors_in_row) * (pal_size + 6));
            const fx: f32 = @floatFromInt(pal_x + x_shift);
            const iy: i32 = @divFloor(i, colors_in_row) * (pal_size + 6);
            const fy: f32 = @floatFromInt(pal_y + iy + 28);

            if (self.ui.button(fx, fy, pal_size, pal_size, "", self.palette.getColorFromIndex(i), mouse) and !self.locked) {
                self.palette.swapCurrentSwatch(i);
            }
        }

        // Footer
        const foo_x: i32 = @intFromFloat(self.ui.pivots[PIVOTS.BOTTOM_LEFT].x);
        const foo_y: i32 = @intFromFloat(self.ui.pivots[PIVOTS.BOTTOM_LEFT].y);

        rl.drawText(
            "[TAB] cycle palette, [1-4] select swatch",
            foo_x,
            foo_y - CONF.FONT_DEFAULT_SIZE,
            CONF.FONT_DEFAULT_SIZE,
            CONF.COLOR_SECONDARY,
        );

        // Popups
        if (self.popup != Popup.none) {
            rl.drawRectangle(0, 0, CONF.SCREEN_W, CONF.SCREEN_H, rl.Color.init(0, 0, 0, 128));
            switch (self.popup) {
                Popup.info_not_implemented => {
                    if (self.ui.infoPopup("Not implemented yet...", mouse, DB16.DARK_GRAY)) |dismissed| {
                        if (dismissed) {
                            self.popup = Popup.none;
                            self.locked = false;
                            self.sm.hot = true;
                        }
                    }
                },
                Popup.confirm_clear => {
                    if (self.ui.yesNoPopup("Clear canvas?", mouse)) |confirmed| {
                        if (confirmed) {
                            self.clearCanvas();
                        }
                        self.popup = Popup.none;
                        self.locked = false;
                        self.sm.hot = true;
                    }
                },
                Popup.info_save_ppm_ok => {
                    if (self.ui.infoPopup("PPM file saved!", mouse, DB16.DARK_GREEN)) |dismissed| {
                        if (dismissed) {
                            self.popup = Popup.none;
                            self.locked = false;
                            self.sm.hot = true;
                        }
                    }
                },
                Popup.info_save_ppm_fail => {
                    if (self.ui.infoPopup("Failed", mouse, DB16.RED)) |dismissed| {
                        if (dismissed) {
                            self.popup = Popup.none;
                            self.locked = false;
                            self.sm.hot = true;
                        }
                    }
                },
                else => {},
            }
        }
    }

    fn draw_preview(self: EditScreen, x: i32, y: i32, down_scale: i32, background: rl.Color) void {
        const w: i32 = @divFloor(self.canvas.width, down_scale);
        const h: i32 = @divFloor(self.canvas.height, down_scale);
        rl.drawRectangle(x, y, w, h, background);

        for (0..CONF.SPRITE_SIZE) |py| {
            for (0..CONF.SPRITE_SIZE) |px| {
                const idx = self.canvas.data[py][px];
                const db16_idx = self.palette.current[idx];
                const scaled_grid_size: i32 = @divFloor(CONF.GRID_SIZE, down_scale);
                const xx: i32 = @intCast(px);
                const yy: i32 = @intCast(py);

                if (!(idx == 0 and self.palette.current[0] == 0)) {
                    rl.drawRectangle(
                        x + xx * scaled_grid_size,
                        y + yy * scaled_grid_size,
                        scaled_grid_size,
                        scaled_grid_size,
                        self.palette.getColorFromIndex(db16_idx),
                    );
                }
            }
        }

        rl.drawRectangleLines(x, y, w, h, DB16.STEEL_BLUE);
    }

    fn export_to_ppm(self: *EditScreen) !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var ppm = try Ppm.init(
            allocator,
            CONF.SPRITE_SIZE,
            CONF.SPRITE_SIZE,
        );
        defer ppm.deinit();

        for (0..ppm.height) |y| {
            for (0..ppm.width) |x| {
                const idx = self.canvas.data[y][x];
                const db16_idx = self.palette.current[idx];
                const color = self.palette.getColorFromIndex(db16_idx);
                ppm.data[y * ppm.width + x] = Color{ .data = RGB{ .r = color.r, .g = color.g, .b = color.b } };
            }
        }

        try ppm.save("tile.ppm");
    }
};
