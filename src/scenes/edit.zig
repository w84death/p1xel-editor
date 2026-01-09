const std = @import("std");
const CONF = @import("../config.zig").CONF;
const DB16 = @import("../palette.zig").DB16;
const Palette = @import("../palette.zig").Palette;
const Fui = @import("../fui.zig").Fui;
const PIVOTS = @import("../fui.zig").PIVOTS;
const State = @import("../state.zig").State;
const StateMachine = @import("../state.zig").StateMachine;
const Tiles = @import("../tiles.zig").Tiles;
const Tile = @import("../tiles.zig").Tile;
const Ppm = @import("../ppm.zig").Ppm;
const RGB = @import("../ppm.zig").RGB;
const Color = @import("../ppm.zig").Color;
const Vec2 = @import("../math.zig").Vec2;
const Mouse = @import("../math.zig").Mouse;

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
    select_tile,
};

const Tools = enum {
    pixel,
    fill,
};

const BackgroundType = enum {
    light,
    dark,
};

pub const EditScene = struct {
    fui: Fui,
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
    bg_type: BackgroundType = BackgroundType.dark,

    pub fn init(fui: Fui, sm: *StateMachine, pal: *Palette, tiles: *Tiles) EditScene {
        const p: *Palette = pal;
        p.index = tiles.db[0].pal;
        p.current = p.db[p.index];
        return EditScene{
            .fui = fui,
            .sm = sm,
            .canvas = Canvas{
                .width = CONF.SPRITE_SIZE * CONF.GRID_SIZE,
                .height = CONF.SPRITE_SIZE * CONF.GRID_SIZE,
                .x = fui.pivots[PIVOTS.TOP_LEFT].x + CONF.CANVAS_X + 96,
                .y = fui.pivots[PIVOTS.TOP_LEFT].y + CONF.CANVAS_Y,
                .data = tiles.db[0].data,
            },
            .palette = p,
            .tiles = tiles,
            .tile_id = 0,
            .locked = false,
            .popup = Popup.none,
            .needs_saving = false,
            .tool = Tools.pixel,
            .bg_type = BackgroundType.dark,
        };
    }
    pub fn handle_keyboard(self: *EditScene, keys: *[256]c_int) void {
        if (self.locked) return;

        for (0..256) |i| {
            if (keys[i] != 0) {
                switch (i) {
                    49 => self.palette.swatch = 0, // '1'
                    50 => self.palette.swatch = 1, // '2'
                    51 => self.palette.swatch = 2, // '3'
                    52 => self.palette.swatch = 3, // '4'
                    9 => self.palette.cycle_palettes(), // Tab
                    81 => self.palette.change_palette_prev(), // 'q'
                    87 => self.palette.change_palette_next(), // 'w'
                    69 => self.tool = Tools.pixel, // 'e'
                    82 => self.tool = Tools.fill, // 'r'
                    else => {},
                }
            }
        }
    }
    pub fn handle_mouse(self: *EditScene, mouse: Mouse) void {
        if (self.locked) return;

        if (self.sm.hot and !mouse.pressed) {
            self.sm.hot = false;
        } else if (self.sm.hot) {
            return;
        }

        const mx: i32 = mouse.x;
        const my: i32 = mouse.y;
        const mouse_cell_x: i32 = @divFloor(mx - self.canvas.x, CONF.GRID_SIZE);
        const mouse_cell_y: i32 = @divFloor(my - self.canvas.y, CONF.GRID_SIZE);

        if (mouse.pressed) {
            const color: u8 = self.palette.swatch;
            if (mouse_cell_x >= 0 and mouse_cell_x < CONF.SPRITE_SIZE and
                mouse_cell_y >= 0 and mouse_cell_y < CONF.SPRITE_SIZE)
            {
                switch (self.tool) {
                    Tools.pixel => {
                        self.canvas.data[@intCast(mouse_cell_y)][@intCast(mouse_cell_x)] = color;
                    },
                    Tools.fill => {
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
            self.fui.draw_text(&status_buf, self.canvas.x, self.canvas.y + CONF.SPRITE_SIZE * CONF.GRID_SIZE + 8, CONF.FONT_DEFAULT_SIZE, DB16.WHITE);
        }
    }

    pub fn clearCanvas(self: *EditScene) void {
        self.canvas.data = [_][CONF.SPRITE_SIZE]u8{[_]u8{0} ** CONF.SPRITE_SIZE} ** CONF.SPRITE_SIZE;
    }
    pub fn draw(self: *EditScene, mouse: Mouse) !void {
        // Navigation (top)
        self.draw_nav(mouse);
        // Tile
        var tx: i32 = self.canvas.x - 88;
        var ty: i32 = self.canvas.y;
        if (self.fui.button(tx, ty, 64, 64, "", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.popup = Popup.select_tile;
            self.tiles.hot = true;
        }
        self.tiles.draw(self.tiles.selected, tx + 1, ty + 1);
        self.fui.draw_rect_lines(tx, ty, CONF.SPRITE_SIZE * 4, CONF.SPRITE_SIZE * 4, DB16.STEEL_BLUE);
        ty += 64 + 32;
        tx -= 64;
        // Tools
        self.fui.draw_text("Tools", tx, ty, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);
        ty += 28;
        if (self.fui.button(tx, ty, 128, 40, "Pixel", if (self.tool == Tools.pixel) CONF.COLOR_MENU_NORMAL else CONF.COLOR_MENU_SECONDARY, mouse) and !self.locked) {
            self.tool = Tools.pixel;
        }
        ty += 50;
        if (self.fui.button(tx, ty, 128, 40, "Fill", if (self.tool == Tools.fill) CONF.COLOR_MENU_NORMAL else CONF.COLOR_MENU_SECONDARY, mouse) and !self.locked) {
            self.tool = Tools.fill;
        }
        ty += 50;
        if (self.fui.button(tx, ty, 128, 40, "Clear", CONF.COLOR_MENU_DANGER, mouse) and !self.locked) {
            self.locked = true;
            self.popup = Popup.confirm_clear;
        }
        ty += 80;
        self.fui.draw_text("Backplate", tx, ty, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);
        ty += 28;
        if (self.fui.button(tx, ty, 128, 32, "Light", if (self.bg_type == BackgroundType.light) CONF.COLOR_MENU_SECONDARY else CONF.COLOR_MENU_NORMAL, mouse)) {
            self.bg_type = BackgroundType.light;
        }
        ty += 50;
        if (self.fui.button(tx, ty, 128, 32, "Dark", if (self.bg_type == BackgroundType.dark) CONF.COLOR_MENU_SECONDARY else CONF.COLOR_MENU_NORMAL, mouse)) {
            self.bg_type = BackgroundType.dark;
        }

        // Canvas
        if (!self.locked) {
            for (0..CONF.SPRITE_SIZE) |y| {
                for (0..CONF.SPRITE_SIZE) |x| {
                    const idx = self.canvas.data[y][x];
                    const db16_idx = self.palette.current[idx];
                    const xx: i32 = @intCast(x * CONF.GRID_SIZE);
                    const yy: i32 = @intCast(y * CONF.GRID_SIZE);
                    var color: u32 = undefined;

                    if (idx == 0 and self.palette.current[0] == 0) {
                        const checker = (x + y) % 2 == 0;
                        switch (self.bg_type) {
                            BackgroundType.dark => color = if (checker) 0xFF111111 else 0xFF222222,
                            BackgroundType.light => color = if (checker) 0xFFAAAAAA else 0xFFCCCCCC,
                        }
                    } else {
                        color = self.palette.get_rgba_from_index(db16_idx);
                    }
                    self.fui.draw_rect(
                        self.canvas.x + xx,
                        self.canvas.y + yy,
                        CONF.GRID_SIZE,
                        CONF.GRID_SIZE,
                        color,
                    );
                }
            }
        }
        self.fui.draw_rect_lines(
            self.canvas.x,
            self.canvas.y,
            self.canvas.width,
            self.canvas.height,
            DB16.STEEL_BLUE,
        );

        // Previews
        const px = self.canvas.x + self.canvas.width + 24;
        const py = self.canvas.y;
        if (!self.locked) {
            inline for (0..3) |dx| {
                inline for (0..3) |dy| {
                    self.draw_tiled_live(px + @as(i32, dx) * 64, py + @as(i32, dy) * 64);
                }
            }
        }
        self.fui.draw_rect_lines(px, py, 192, 192, DB16.STEEL_BLUE);
        // Swatches
        const swa_x: i32 = px;
        const swa_y: i32 = py + 216;
        const swa_size: i32 = 48;
        self.fui.draw_text("Active Swatches", swa_x, swa_y, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);
        inline for (0..4) |i| {
            const x_shift: i32 = @intCast(i * (swa_size + 6));
            const index: u8 = @intCast(i);
            const db16_idx = self.palette.current[i];

            if (self.fui.button(swa_x + x_shift, swa_y + 28, swa_size, swa_size, "", self.palette.get_rgba_from_index(db16_idx), mouse) and !self.locked) {
                self.palette.swatch = index;
            }

            if (self.palette.swatch == i) {
                self.fui.draw_rect_lines(swa_x + x_shift + 5, swa_y + 28 + 5, swa_size - 8, swa_size - 8, DB16.BLACK);
                self.fui.draw_rect_lines(swa_x + x_shift + 4, swa_y + 28 + 4, swa_size - 8, swa_size - 8, DB16.WHITE);
            }
        }
        if (self.palette.current[0] == 0) {
            self.fui.draw_text("TRANSPARENT", swa_x + 4, swa_y + 2 + swa_size + 32, CONF.FONT_SMOL, CONF.COLOR_PRIMARY);
        }

        // Swatches info
        var si_x: i32 = swa_x;
        const si_y: i32 = swa_y + swa_size + 48;
        var status_buf: [7:0]u8 = undefined;
        _ = std.fmt.bufPrintZ(&status_buf, "{d:0>2}/{d:0>2}", .{ self.palette.index + 1, self.palette.count }) catch {};
        self.fui.draw_text(&status_buf, si_x, si_y, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);
        si_x += 120;
        if (self.palette.count > 1) {
            if (self.palette.index > 0) {
                if (self.fui.button(si_x, si_y, 64, 24, "<", CONF.COLOR_OK, mouse) and !self.locked) {
                    self.palette.change_palette_prev();
                    self.needs_saving = true;
                }
            }
            si_x += 64 + 8;
            if (self.palette.index < self.palette.count - 1) {
                if (self.fui.button(si_x, si_y, 64, 24, ">", CONF.COLOR_OK, mouse) and !self.locked) {
                    self.palette.change_palette_next();
                    self.needs_saving = true;
                }
            }
            si_x += 64 + 8;
        }

        // Swatches options
        var so_x: i32 = swa_x;
        const so_y: i32 = swa_y + 132;
        if (self.fui.button(so_x, so_y, 280, 32, "Manage swatches", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.popup = Popup.info_not_implemented;
        }
        so_x += 148;

        if (self.palette.updated) {
            if (self.fui.button(so_x, so_y, 160, 32, "Update", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
                self.palette.update_palette();
                // self.needs_saving = true;
                self.save_tiles();
            }
            so_x += 168;
            if (self.fui.button(so_x, so_y, 160, 32, "Save new", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
                self.palette.new_palette();
                // self.needs_saving = true;
                self.save_tiles();
            }
        }

        // Palette
        const pal_x: i32 = swa_x;
        const pal_y: i32 = swa_y + 200;
        const pal_size: i32 = 32;
        self.fui.draw_text("DB16 Palette", pal_x, pal_y, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);
        const colors_in_row: usize = 8;
        inline for (0..16) |i| {
            const x_shift: i32 = @intCast(@mod(i, colors_in_row) * (pal_size + 6));
            const iy: i32 = @divFloor(i, colors_in_row) * (pal_size + 6);
            if (self.fui.button(pal_x + x_shift, pal_y + iy + 28, pal_size, pal_size, "", self.palette.get_rgba_from_index(i), mouse) and !self.locked) {
                self.palette.update_current_swatch(i);
            }
        }

        const options_x: i32 = self.fui.pivots[PIVOTS.TOP_RIGHT].x;
        var options_y: i32 = self.fui.pivots[PIVOTS.TOP_RIGHT].y + 48;

        if (self.fui.button(options_x - 160, options_y, 160, 32, "Save", if (self.needs_saving) CONF.COLOR_MENU_HIGHLIGHT else CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.save_tiles();
        }
        options_y += 40;
        if (self.fui.button(options_x - 240, options_y, 240, 32, "Export PPM", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.export_to_ppm() catch {
                self.popup = Popup.info_save_fail;
                return;
            };
            self.popup = Popup.info_save_ok;
        }

        // Footer
        const foo_x: i32 = self.fui.pivots[PIVOTS.BOTTOM_LEFT].x;
        const foo_y: i32 = self.fui.pivots[PIVOTS.BOTTOM_LEFT].y;

        self.fui.draw_text("[1-4] select swatch, [q-w] change palette, [TAB] cycle palette", foo_x, foo_y - CONF.FONT_DEFAULT_SIZE, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_SECONDARY);

        // Popups
        if (self.popup != Popup.none) {
            self.fui.draw_rect_trans(0, 0, CONF.SCREEN_W, CONF.SCREEN_H, CONF.POPUP_BG_ALPHA);
            switch (self.popup) {
                Popup.info_not_implemented => {
                    if (self.fui.info_popup("Not implemented yet...", mouse, CONF.COLOR_SECONDARY)) |dismissed| {
                        if (dismissed) {
                            self.popup = Popup.none;
                            self.locked = false;
                            self.sm.hot = true;
                        }
                    }
                },
                Popup.confirm_clear => {
                    if (self.fui.yes_no_popup("Clear canvas?", mouse)) |confirmed| {
                        if (confirmed) {
                            self.clearCanvas();
                        }
                        self.popup = Popup.none;
                        self.locked = false;
                        self.sm.hot = true;
                    }
                },
                Popup.confirm_del => {
                    if (self.fui.yes_no_popup("Delete swatch?", mouse)) |confirmed| {
                        if (confirmed) {
                            self.palette.delete_palette();
                        }
                        self.popup = Popup.none;
                        self.locked = false;
                        self.sm.hot = true;
                    }
                },
                Popup.info_save_ok => {
                    if (self.fui.info_popup("File saved!", mouse, CONF.COLOR_OK)) |dismissed| {
                        if (dismissed) {
                            self.popup = Popup.none;
                            self.locked = false;
                            self.sm.hot = true;
                        }
                    }
                },
                Popup.info_save_fail => {
                    if (self.fui.info_popup("File saving failed...", mouse, CONF.COLOR_NO)) |dismissed| {
                        if (dismissed) {
                            self.popup = Popup.none;
                            self.locked = false;
                            self.sm.hot = true;
                        }
                    }
                },
                Popup.select_tile => {
                    if (self.tiles.show_tiles_selector(mouse)) |dismissed| {
                        if (dismissed) {
                            self.popup = Popup.none;
                            self.locked = false;
                            self.sm.hot = true;
                            self.select();
                        }
                    }
                },
                else => {},
            }
        }
    }
    fn draw_nav(self: *EditScene, mouse: Mouse) void {
        const button_w: i32 = 180;
        const button_h: i32 = 32;
        const gap: i32 = 32;
        const nav_w: i32 = CONF.SCREEN_W;
        const nav_h: i32 = 64;
        const nav: Vec2 = Vec2.init(self.fui.pivots[PIVOTS.TOP_LEFT].x, self.fui.pivots[PIVOTS.TOP_LEFT].y);
        self.fui.draw_rect(0, 0, nav_w, nav_h, CONF.COLOR_NAV_BG);
        self.fui.draw_hline(0, nav_h, nav_w, CONF.COLOR_NAV_FRAME);
        const NavButton = struct {
            label: [:0]const u8,
            state: State,
            width: i32,
            special: bool,
        };
        const buttons = [_]NavButton{
            .{ .label = "< Menu", .state = State.main_menu, .width = button_w - 32, .special = false },
            .{ .label = "Editor", .state = State.editor, .width = button_w, .special = true },
            .{ .label = "Tileset", .state = State.tileset, .width = button_w, .special = false },
            .{ .label = "Palettes", .state = State.palettes, .width = button_w, .special = false },
            .{ .label = "Preview", .state = State.preview, .width = button_w, .special = false },
        };
        var nav_step = nav.x;
        for (buttons) |btn| {
            if (btn.special and self.sm.is(btn.state)) {
                self.fui.draw_rect(nav_step - 16, nav.y - 12, btn.width + 32, button_h + 24, CONF.COLOR_BG);
            }
            var color: u32 = undefined;
            if (self.sm.is(btn.state)) {
                color = CONF.COLOR_MENU_SECONDARY;
            } else {
                color = CONF.COLOR_MENU_NORMAL;
            }
            if (self.fui.button(nav_step, nav.y, btn.width, button_h, btn.label, color, mouse) and !self.locked) {
                self.sm.goTo(btn.state);
            }
            nav_step += btn.width + gap;
        }
    }
    fn save_tiles(self: *EditScene) void {
        self.tiles.db[self.tiles.selected].data = self.canvas.data;
        self.tiles.db[self.tiles.selected].pal = self.palette.index;
        self.tiles.update_pal32(self.tiles.selected);
        self.locked = true;
        self.tiles.save_tileset_to_file() catch {
            self.popup = Popup.info_save_fail;
            return;
        };
        self.popup = Popup.info_save_ok;
        self.needs_saving = false;
    }
    fn draw_tiled_live(self: *EditScene, x: i32, y: i32) void {
        const scale = CONF.PREVIEW_SCALE;
        self.fui.draw_rect(x, y, scale * CONF.SPRITE_SIZE, scale * CONF.SPRITE_SIZE, if (self.bg_type == BackgroundType.light) 0xffffffFF else 0x000000);
        for (0..CONF.SPRITE_SIZE) |py| {
            const yy: i32 = @intCast(py);
            inline for (0..CONF.SPRITE_SIZE) |px| {
                const xx: i32 = @intCast(px);
                const idx = self.canvas.data[py][px];
                const db16_idx = self.palette.current[idx];
                const color = self.palette.get_rgba_from_index(db16_idx);
                inline for (0..2) |i| {
                    const ii: i32 = @intCast(i);
                    inline for (0..2) |j| {
                        if (idx == 0 and self.palette.current[0] == 0) {} else {
                            const jj: i32 = @intCast(j);
                            self.fui.draw_rect(
                                x + jj + xx * scale,
                                y + ii + yy * scale,
                                scale,
                                scale,
                                color,
                            );
                        }
                    }
                }
            }
        }
    }

    fn export_to_ppm(self: *EditScene) !void {
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
                const color = self.palette.get_rgba_from_index(db16_idx);
                const r: u8 = @truncate(color >> 16);
                const g: u8 = @truncate(color >> 8);
                const b: u8 = @truncate(color);
                ppm.data[y * ppm.width + x] = Color{ .data = RGB{ .r = r, .g = g, .b = b } };
            }
        }

        try ppm.save("tile.ppm");
    }
    pub fn select(self: *EditScene) void {
        const selected = self.tiles.db[self.tiles.selected];
        self.canvas.data = selected.data;
        self.palette.current = self.palette.db[selected.pal];
        self.palette.index = selected.pal;
    }
};
