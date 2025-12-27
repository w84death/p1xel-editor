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
    confirm_del,
    info_save_ok,
    info_save_fail,
};

const Tools = enum {
    pixel,
    fill,
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
    tool: Tools = Tools.pixel,
    status_buffer: [256]u8 = undefined,

    pub fn init(ui: Ui, sm: *StateMachine, pal: *Palette, tiles: *Tiles) EditScreen {
        const ix: i32 = @intFromFloat(ui.pivots[PIVOTS.TOP_LEFT].x + CONF.CANVAS_X + 128);
        const iy: i32 = @intFromFloat(ui.pivots[PIVOTS.TOP_LEFT].y + CONF.CANVAS_Y);
        const p: *Palette = pal;
        p.index = tiles.db[0].pal;
        p.current = p.db[p.index];
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
            .palette = p,
            .tiles = tiles,
            .tile_id = 0,
            .locked = false,
            .popup = Popup.none,
            .needs_saving = false,
            .tool = Tools.pixel,
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
            rl.KeyboardKey.tab => self.palette.cyclePalette(),
            rl.KeyboardKey.q => self.palette.prevPalette(),
            rl.KeyboardKey.w => self.palette.nextPalette(),
            rl.KeyboardKey.e => self.tool = Tools.pixel,
            rl.KeyboardKey.r => self.tool = Tools.fill,
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
                switch (self.tool) {
                    Tools.pixel => {
                        if (rl.isMouseButtonDown(rl.MouseButton.right)) color = 0;
                        self.canvas.data[@intCast(mouse_cell_y)][@intCast(mouse_cell_x)] = color;
                    },
                    Tools.fill => {
                        if (rl.isMouseButtonDown(rl.MouseButton.right)) color = 0;
                        const start_x: usize = @intCast(mouse_cell_x);
                        const start_y: usize = @intCast(mouse_cell_y);
                        const old_color = self.canvas.data[start_y][start_x];
                        if (old_color == color) return; // No change needed
                        const floodFill = struct {
                            fn flood(data: *[CONF.SPRITE_SIZE][CONF.SPRITE_SIZE]u8, x: usize, y: usize, old: u8, new: u8) void {
                                if (x >= CONF.SPRITE_SIZE or y >= CONF.SPRITE_SIZE) return;
                                if (data[y][x] != old) return;
                                data[y][x] = new;
                                if (x > 0) flood(data, x - 1, y, old, new);
                                if (x < CONF.SPRITE_SIZE - 1) flood(data, x + 1, y, old, new);
                                if (y > 0) flood(data, x, y - 1, old, new);
                                if (y < CONF.SPRITE_SIZE - 1) flood(data, x, y + 1, old, new);
                            }
                        }.flood;
                        floodFill(&self.canvas.data, start_x, start_y, old_color, color);
                    },
                }
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
        if (self.ui.button(nav_step, nav.y, 120, 32, "< Menu", CONF.COLOR_MENU_SECONDARY, mouse) and !self.locked) {
            self.sm.goTo(State.main_menu);
        }
        nav_step += 128 + 32;
        if (self.ui.button(nav_step, nav.y, 160, 32, "Change tile", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.sm.goTo(State.tileset);
        }
        nav_step += 168 + 32;
        if (self.ui.button(nav_step, nav.y, 160, 32, "Save tile", if (self.needs_saving) CONF.COLOR_MENU_HIGHLIGHT else CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.tiles.db[self.tile_id].data = self.canvas.data;
            self.tiles.db[self.tile_id].pal = self.palette.index;
            self.locked = true;
            self.tiles.saveTilesToFile() catch {
                self.popup = Popup.info_save_fail;
                return;
            };
            self.popup = Popup.info_save_ok;
            self.needs_saving = false;
        }
        nav_step += 168;
        if (self.ui.button(nav_step, nav.y, 240, 32, "Export Tile (PPM)", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.export_to_ppm() catch {
                self.popup = Popup.info_save_fail;
                return;
            };
            self.popup = Popup.info_save_ok;
        }
        // Tools
        const tx: i32 = self.canvas.x - 88;
        var ty: i32 = self.canvas.y;
        rl.drawText("TOOLS", tx, ty, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);
        ty += 28;
        if (self.ui.button(@floatFromInt(tx), @floatFromInt(ty), 64, 64, "Pixel", if (self.tool == Tools.pixel) CONF.COLOR_MENU_NORMAL else CONF.COLOR_MENU_SECONDARY, mouse) and !self.locked) {
            self.tool = Tools.pixel;
        }
        ty += 72;
        if (self.ui.button(@floatFromInt(tx), @floatFromInt(ty), 64, 64, "Fill", if (self.tool == Tools.fill) CONF.COLOR_MENU_NORMAL else CONF.COLOR_MENU_SECONDARY, mouse) and !self.locked) {
            self.tool = Tools.fill;
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
                    color = if (checker) rl.getColor(0x11111170) else rl.getColor(0x22222270);
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
        if (self.ui.button(clear_pos.x, clear_pos.y, 160, 32, "Clear canvas", CONF.COLOR_MENU_DANGER, mouse) and !self.locked) {
            self.locked = true;
            self.popup = Popup.confirm_clear;
        }

        // Previews
        const px = self.canvas.x + self.canvas.width + 24;
        const py = self.canvas.y;
        const dw: i32 = @divFloor(self.canvas.height, 4);
        self.draw_preview(px, py, 4, DB16.BLACK, true);
        self.draw_preview(px + dw + 8, py, 4, DB16.WHITE, true);
        const till_x = px + dw + 16 + 8 * 16;
        self.draw_preview(till_x, py, 8, DB16.BLACK, false);
        self.draw_preview(till_x + 64, py, 8, DB16.BLACK, false);
        self.draw_preview(till_x + 128, py, 8, DB16.BLACK, false);
        self.draw_preview(till_x, py + 64, 8, DB16.BLACK, false);
        self.draw_preview(till_x + 64, py + 64, 8, DB16.BLACK, false);
        self.draw_preview(till_x + 128, py + 64, 8, DB16.BLACK, false);
        self.draw_preview(till_x, py + 128, 8, DB16.BLACK, false);
        self.draw_preview(till_x + 64, py + 128, 8, DB16.BLACK, false);
        self.draw_preview(till_x + 128, py + 128, 8, DB16.BLACK, false);
        rl.drawRectangleLines(till_x, py, 192, 192, DB16.STEEL_BLUE);

        // Swatches
        const swa_x: i32 = px;
        const swa_y: i32 = py + 160;
        const swa_size: i32 = 48;
        rl.drawText("ACTIVE SWATCHES", swa_x, swa_y, 20, CONF.COLOR_PRIMARY);
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
        }
        if (self.palette.current[0] == 0) {
            rl.drawText("TRANSPARENT", swa_x, swa_y + swa_size + 32, 10, CONF.COLOR_PRIMARY);
        }

        // Swatches info
        var fsi_x: f32 = @floatFromInt(swa_x);
        const fsi_y: f32 = @floatFromInt(swa_y + swa_size + 48);
        var status_buf: [7:0]u8 = undefined;
        _ = std.fmt.bufPrintZ(&status_buf, "{d:0>2}/{d:0>2}", .{ self.palette.index + 1, self.palette.count }) catch {};
        rl.drawText(&status_buf, @intFromFloat(fsi_x), @intFromFloat(fsi_y), CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);
        fsi_x += 75;
        if (self.palette.count > 1) {
            if (self.palette.swatch > 0) {
                if (self.ui.button(fsi_x, fsi_y, 64, 24, "<", CONF.COLOR_OK, mouse) and !self.locked) {
                    self.palette.prevPalette();
                    self.needs_saving = true;
                }
                fsi_x += 64 + 8;
            }
            if (self.palette.swatch < self.palette.count) {
                if (self.palette.swatch < self.palette.count and self.ui.button(fsi_x, fsi_y, 64, 24, ">", CONF.COLOR_OK, mouse) and !self.locked) {
                    self.palette.nextPalette();
                    self.needs_saving = true;
                }
                fsi_x += 64 + 8;
            }
        }

        // Swatches options
        var fso_x: f32 = @floatFromInt(swa_x);
        const fso_y: f32 = @floatFromInt(swa_y + 132);
        if (self.palette.count > 1 and self.ui.button(fso_x, fso_y, 120, 32, "Del swatch", CONF.COLOR_MENU_DANGER, mouse) and !self.locked) {
            self.locked = true;
            self.popup = Popup.confirm_del;
        }
        fso_x += 128;

        if (self.palette.updated) {
            if (self.ui.button(fso_x, fso_y, 120, 32, "Update", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
                self.palette.updatePalette();
                self.needs_saving = true;
            }
            fso_x += 128;
            if (self.ui.button(fso_x, fso_y, 120, 32, "Save new", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
                self.palette.newPalette();
                self.needs_saving = true;
            }
            fso_x += 128;
        }

        // Palette
        const pal_x: i32 = swa_x;
        const pal_y: i32 = swa_y + 200;
        const pal_size: i32 = 32;
        rl.drawText("DB16 PALETTE", pal_x, pal_y, 20, CONF.COLOR_PRIMARY);
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

        rl.drawText("[1-4] select swatch, [q-w] change palette, [TAB] cycle palette", foo_x, foo_y - CONF.FONT_DEFAULT_SIZE, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_SECONDARY);

        // Popups
        if (self.popup != Popup.none) {
            rl.drawRectangle(0, 0, CONF.SCREEN_W, CONF.SCREEN_H, rl.Color.init(0, 0, 0, CONF.POPUP_DIM));
            switch (self.popup) {
                Popup.info_not_implemented => {
                    if (self.ui.infoPopup("Not implemented yet...", mouse, CONF.COLOR_SECONDARY)) |dismissed| {
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
                Popup.confirm_del => {
                    if (self.ui.yesNoPopup("Delete swatch?", mouse)) |confirmed| {
                        if (confirmed) {
                            self.palette.deletePalette();
                        }
                        self.popup = Popup.none;
                        self.locked = false;
                        self.sm.hot = true;
                    }
                },
                Popup.info_save_ok => {
                    if (self.ui.infoPopup("File saved!", mouse, CONF.COLOR_OK)) |dismissed| {
                        if (dismissed) {
                            self.popup = Popup.none;
                            self.locked = false;
                            self.sm.hot = true;
                        }
                    }
                },
                Popup.info_save_fail => {
                    if (self.ui.infoPopup("File saving failed...", mouse, CONF.COLOR_NO)) |dismissed| {
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

    fn draw_preview(self: EditScreen, x: i32, y: i32, down_scale: i32, background: rl.Color, frame: bool) void {
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

        if (frame) rl.drawRectangleLines(x, y, w, h, DB16.STEEL_BLUE);
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
