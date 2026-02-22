const std = @import("std");
const Vec2 = @import("../math.zig").Vec2;
const Mouse = @import("../math.zig").Mouse;
const CONF = @import("../config.zig").CONF;
const DB16 = @import("../palette.zig").DB16;
const Palette = @import("../palette.zig").Palette;
const Fui = @import("../fui.zig").Fui;
const PIVOTS = @import("../fui.zig").PIVOTS;
const State = @import("../state.zig").State;
const StateMachine = @import("../state.zig").StateMachine;
const Tiles = @import("../tiles.zig").Tiles;
const Edit = @import("edit.zig").EditScene;
const NavPanel = @import("../nav.zig").NavPanel;
const Popup = enum {
    none,
    info_not_implemented,
    info_save_ok,
    info_save_fail,
    info_export_ok,
    info_export_fail,
    confirm_delete,
    select_tile,
};
const Layer = @import("../tiles.zig").Layer;
pub const PreviewScene = struct {
    fui: Fui,
    sm: *StateMachine,
    nav: *NavPanel,
    edit: *Edit,
    palette: *Palette,
    tiles: *Tiles,
    tiles_area: Vec2,
    layers: *[CONF.PREVIEW_LAYERS]Layer,
    selected: u8,
    cam_x: usize = 0,
    cam_y: usize = 0,
    locked: bool,
    iso_mode: bool = false,
    popup: Popup,
    pub fn init(fui: Fui, sm: *StateMachine, nav: *NavPanel, edit: *Edit, pal: *Palette, tiles: *Tiles, layers: *[CONF.PREVIEW_LAYERS]Layer) PreviewScene {
        for (0..CONF.PREVIEW_LAYERS) |i| {
            var data: [CONF.MAX_PREVIEW_H][CONF.MAX_PREVIEW_W]u8 = undefined;
            for (0..CONF.MAX_PREVIEW_H) |y| {
                for (0..CONF.MAX_PREVIEW_W) |x| {
                    data[y][x] = 255;
                }
            }
            layers[i].data = data;
            layers[i].visible = false;
        }
        return PreviewScene{
            .fui = fui,
            .sm = sm,
            .nav = nav,
            .edit = edit,
            .tiles = tiles,
            .tiles_area = Vec2.init(fui.pivots[PIVOTS.TOP_LEFT].x + 180, fui.pivots[PIVOTS.TOP_LEFT].y + 64),
            .layers = layers,
            .selected = 0,
            .palette = pal,
            .locked = false,
            .iso_mode = false,
            .popup = Popup.none,
        };
    }
    pub fn move_camera(self: *PreviewScene, dx: i32, dy: i32) void {
        const new_x = @as(i32, @intCast(self.cam_x)) + dx;
        const new_y = @as(i32, @intCast(self.cam_y)) + dy;
        if (new_x >= 0 and new_x <= @as(i32, CONF.MAX_PREVIEW_W - CONF.PREVIEW_W)) {
            self.cam_x = @intCast(new_x);
        }
        if (new_y >= 0 and new_y <= @as(i32, CONF.MAX_PREVIEW_H - CONF.PREVIEW_H)) {
            self.cam_y = @intCast(new_y);
        }
    }
    pub fn handle_mouse(self: *PreviewScene, mouse: Mouse) void {
        if (self.locked or !self.layers[self.selected].visible) return;

        if (self.sm.hot and !mouse.pressed) {
            self.sm.hot = false;
        } else if (self.sm.hot) {
            return;
        }

        const mouse_cell_y: i32 = @divFloor(mouse.y - self.tiles_area.y, if (self.iso_mode) @as(i32, CONF.PREVIEW_SIZE / 2) else CONF.PREVIEW_SIZE);
        const tentative_data_y: i32 = mouse_cell_y + @as(i32, @intCast(self.cam_y));
        const mouse_cell_x: i32 = if (self.iso_mode and @rem(tentative_data_y, 2) == 1) @divFloor(mouse.x - self.tiles_area.x - @as(i32, CONF.PREVIEW_SIZE / 2), CONF.PREVIEW_SIZE) else @divFloor(mouse.x - self.tiles_area.x, CONF.PREVIEW_SIZE);
        if (mouse.pressed) {
            if (mouse_cell_x >= 0 and mouse_cell_x < CONF.PREVIEW_W and
                mouse_cell_y >= 0 and mouse_cell_y < CONF.PREVIEW_H)
            {
                const data_y: i32 = tentative_data_y;
                const data_x: i32 = mouse_cell_x + @as(i32, @intCast(self.cam_x));
                if (data_y >= 0 and data_y < CONF.MAX_PREVIEW_H and data_x >= 0 and data_x < CONF.MAX_PREVIEW_W) {
                    var data = self.layers[self.selected].data[@intCast(data_y)][@intCast(data_x)];
                    data = if (data == self.tiles.selected) 255 else self.tiles.selected;
                    self.layers[self.selected].data[@intCast(data_y)][@intCast(data_x)] = data;
                }
            }
        }
    }
    pub fn handle_keyboard(self: *PreviewScene, keys: *[256]c_int) void {
        if (self.locked) return;
        for (0..256) |i| {
            if (keys[i] != 0) {
                switch (i) {
                    49 => self.selected = 0, // '1'
                    50 => self.selected = 1, // '2'
                    51 => self.selected = 2, // '3'
                    0x11 => self.move_camera(0, -1), // up
                    0x12 => self.move_camera(0, 1), // down
                    0x14 => self.move_camera(-1, 0), // left
                    0x13 => self.move_camera(1, 0), // right
                    else => {
                        std.debug.print("Debug key pressed: {x}\n", .{i});
                    },
                }
            }
        }
    }
    pub fn savePreviewToFile(self: *const PreviewScene) !void {
        const per_layer = CONF.MAX_PREVIEW_H * CONF.MAX_PREVIEW_W;
        var buf = [_]u8{0} ** (CONF.PREVIEW_LAYERS * CONF.MAX_PREVIEW_H * CONF.MAX_PREVIEW_W);
        for (0..CONF.PREVIEW_LAYERS) |l| {
            for (0..CONF.MAX_PREVIEW_H) |y| {
                for (0..CONF.MAX_PREVIEW_W) |x| {
                    buf[l * per_layer + y * CONF.MAX_PREVIEW_W + x] = self.layers[l].data[y][x];
                }
            }
        }
        const file = try std.fs.cwd().createFile(CONF.PREVIEW_FILE, .{});
        defer file.close();
        _ = try file.write(&buf);
    }
    pub fn loadPreviewFromFile(self: *PreviewScene) void {
        const per_layer = CONF.MAX_PREVIEW_H * CONF.MAX_PREVIEW_W;
        const file = std.fs.cwd().openFile(CONF.PREVIEW_FILE, .{}) catch {
            return;
        };
        defer file.close();
        const data = file.readToEndAlloc(std.heap.page_allocator, 1024 * 1024) catch {
            return;
        };
        defer std.heap.page_allocator.free(data);
        if (data.len < CONF.PREVIEW_LAYERS * per_layer) return;
        for (0..CONF.PREVIEW_LAYERS) |l| {
            for (0..CONF.MAX_PREVIEW_H) |y| {
                for (0..CONF.MAX_PREVIEW_W) |x| {
                    self.layers[l].data[y][x] = data[l * per_layer + y * CONF.MAX_PREVIEW_W + x];
                    self.layers[l].visible = true;
                }
            }
        }
    }
    pub fn exportPreviewToPPM(self: *const PreviewScene) !void {
        const sprite_size = CONF.SPRITE_SIZE;
        const width: usize = if (self.iso_mode)
            CONF.MAX_PREVIEW_W * sprite_size + sprite_size / 2
        else
            CONF.MAX_PREVIEW_W * sprite_size;

        const height: usize = if (self.iso_mode)
            CONF.MAX_PREVIEW_H * (sprite_size / 2) + sprite_size / 2
        else
            CONF.MAX_PREVIEW_H * sprite_size;

        const file = try std.fs.cwd().createFile("preview.ppm", .{});
        defer file.close();

        var buffer: [8192]u8 = undefined;
        var fwrite = file.writer(&buffer);
        const writer = &fwrite.interface;

        try writer.print("P6\n{d} {d}\n255\n", .{ width, height });

        for (0..height) |py| {
            for (0..width) |px| {
                var color: u32 = 0xFF000000;

                var i: usize = 0;
                while (i < CONF.PREVIEW_LAYERS) : (i += 1) {
                    const layer = self.layers[i];
                    if (!layer.visible) continue;

                    if (!self.iso_mode) {
                        const tile_x = px / sprite_size;
                        const tile_y = py / sprite_size;
                        if (tile_x >= CONF.MAX_PREVIEW_W or tile_y >= CONF.MAX_PREVIEW_H) continue;

                        const tile_idx = layer.data[tile_y][tile_x];
                        if (tile_idx == 255 or tile_idx >= self.tiles.count) continue;

                        const pixel_x = px % sprite_size;
                        const pixel_y = py % sprite_size;

                        const tile = self.tiles.db[tile_idx];
                        const palette_idx = tile.data[pixel_y][pixel_x];
                        if (palette_idx >= 4) continue;
                        const pixel_color = tile.pal32[palette_idx];

                        if (palette_idx == 0 and pixel_color == DB16.BLACK) continue;
                        color = pixel_color;
                    } else {
                        const y_step = sprite_size / 2;
                        const r_max_ideal = py / y_step;

                        var r_iter: usize = 0;
                        while (r_iter < 2) : (r_iter += 1) {
                            if (r_max_ideal == 0 and r_iter == 0) continue;
                            const r = if (r_iter == 0) r_max_ideal - 1 else r_max_ideal;
                            if (r >= CONF.MAX_PREVIEW_H) continue;

                            const row_y_start = r * y_step;
                            if (py < row_y_start or py >= row_y_start + sprite_size) continue;

                            const x_shift: usize = if (r % 2 == 1) sprite_size / 2 else 0;
                            if (px < x_shift) continue;

                            const c = (px - x_shift) / sprite_size;
                            if (c >= CONF.MAX_PREVIEW_W) continue;

                            const tile_idx = layer.data[r][c];
                            if (tile_idx == 255 or tile_idx >= self.tiles.count) continue;

                            const pixel_x = (px - x_shift) % sprite_size;
                            const pixel_y = py - row_y_start;

                            const tile = self.tiles.db[tile_idx];
                            const palette_idx = tile.data[pixel_y][pixel_x];
                            if (palette_idx >= 4) continue;
                            const pixel_color = tile.pal32[palette_idx];

                            if (palette_idx == 0 and pixel_color == DB16.BLACK) continue;
                            color = pixel_color;
                        }
                    }
                }

                const r: u8 = @intCast((color >> 16) & 0xFF);
                const g: u8 = @intCast((color >> 8) & 0xFF);
                const b: u8 = @intCast(color & 0xFF);

                try writer.writeByte(r);
                try writer.writeByte(g);
                try writer.writeByte(b);
            }
        }
        try writer.flush();
    }
    pub fn draw(self: *PreviewScene, mouse: Mouse) void {
        // Navigation (top)
        self.nav.draw(mouse);

        // options
        const options_x: i32 = self.fui.pivots[PIVOTS.TOP_RIGHT].x;
        const options_y: i32 = self.fui.pivots[PIVOTS.TOP_RIGHT].y + 64;

        if (self.fui.button(options_x - 160, options_y, 160, CONF.MAX_PREVIEW_W, "Save", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.savePreviewToFile() catch {
                self.popup = Popup.info_save_fail;
                return;
            };
            self.popup = Popup.info_save_ok;
        }

        if (self.fui.button(options_x - 160, options_y + 40, 160, 32, "Export PPM", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.exportPreviewToPPM() catch {
                self.popup = Popup.info_export_fail;
                return;
            };
            self.popup = Popup.info_export_ok;
        }

        if (self.fui.button(options_x - 160, options_y + 80, 160, 32, if (self.iso_mode) "ISO: ON" else "ISO: OFF", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.iso_mode = !self.iso_mode;
        }

        const tools_x = options_x - 120;
        const tools_y = options_y + 124;

        self.fui.draw_text("Move:", tools_x - 40, tools_y - 24, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);

        if (self.fui.button(tools_x - 60, tools_y, 120, 32, "North", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.move_camera(0, -1);
        }
        if (self.fui.button(tools_x - 60, tools_y + 80, 120, 32, "Shouth", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.move_camera(0, 1);
        }
        if (self.fui.button(tools_x - 60 - 65, tools_y + 40, 120, 32, "Left", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.move_camera(-1, 0);
        }
        if (self.fui.button(tools_x - 60 + 65, tools_y + 40, 120, 32, "Right", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.move_camera(1, 0);
        }

        // tools_step += 88;
        // if (self.fui.button(tools_step, tools.y, 120, 32, "Clear layer", CONF.COLOR_MENU_DANGER, mouse) and !self.locked) {
        //     self.locked = true;
        //     self.popup = Popup.info_not_implemented;
        // }
        //
        // Tile

        const tx: i32 = self.tiles_area.x - 72;
        const ty: i32 = self.tiles_area.y;
        if (self.fui.button(tx, ty, 64, 64, "", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.popup = Popup.select_tile;
            self.tiles.hot = true;
        }
        self.tiles.draw(self.tiles.selected, tx + 1, ty + 1);
        self.fui.draw_rect_lines(tx, ty, CONF.SPRITE_SIZE * 4, CONF.SPRITE_SIZE * 4, DB16.STEEL_BLUE);

        // Layers
        var lx: i32 = self.tiles_area.x - 180;
        var ly: i32 = ty + 128;
        self.fui.draw_text("LAYERS:", lx, ly, CONF.FONT_SMOL, CONF.COLOR_PRIMARY);
        ly += 24;
        if (self.fui.button(lx, ly, 64, 32, "1", if (self.selected == 0) CONF.COLOR_MENU_NORMAL else CONF.COLOR_MENU_SECONDARY, mouse) and !self.locked) {
            self.selected = 0;
        }
        ly += 40;
        if (self.fui.button(lx, ly, 64, 32, "2", if (self.selected == 1) CONF.COLOR_MENU_NORMAL else CONF.COLOR_MENU_SECONDARY, mouse) and !self.locked) {
            self.selected = 1;
        }
        ly += 40;
        if (self.fui.button(lx, ly, 64, 32, "3", if (self.selected == 2) CONF.COLOR_MENU_NORMAL else CONF.COLOR_MENU_SECONDARY, mouse) and !self.locked) {
            self.selected = 2;
        }
        ly = ty + 128;
        lx += 80;
        self.fui.draw_text("VISIBLE:", lx, ly, CONF.FONT_SMOL, CONF.COLOR_PRIMARY);
        ly += 24;
        inline for (0..self.layers.len) |i| {
            if (self.fui.button(lx, ly, 64, 32, if (self.layers[i].visible) "ON" else "OFF", if (self.layers[i].visible) CONF.COLOR_MENU_NORMAL else CONF.COLOR_MENU_SECONDARY, mouse) and !self.locked) {
                self.layers[i].visible = !self.layers[i].visible;
            }
            ly += 40;
        }

        // Playground
        const px: i32 = self.tiles_area.x;
        const py: i32 = self.tiles_area.y;
        if (!self.locked) {
            for (self.layers.*) |layer| {
                if (layer.visible) {
                    for (0..CONF.PREVIEW_H) |view_y| {
                        for (0..CONF.PREVIEW_W) |view_x| {
                            const data_y = self.cam_y + view_y;
                            if (data_y >= 48) continue;
                            const data_x = self.cam_x + view_x;
                            if (data_x >= 32) continue;
                            const tile = layer.data[data_y][data_x];
                            if (tile < 255) {
                                const y_step = if (self.iso_mode) @as(i32, CONF.PREVIEW_SIZE / 2) else CONF.PREVIEW_SIZE;
                                var xx: i32 = @intCast(@as(u64, view_x) * @as(u64, @intCast(CONF.PREVIEW_SIZE)));
                                const yy: i32 = @intCast(@as(u64, view_y) * @as(u64, @intCast(y_step)));
                                if (self.iso_mode and @rem(data_y, 2) == 1) {
                                    xx += @as(i32, CONF.PREVIEW_SIZE / 2);
                                }
                                self.tiles.draw(tile, px + xx, py + yy);
                            }
                        }
                    }
                }
            }
            // Preview tile under cursor
            const mouse_cell_y: i32 = @divFloor(mouse.y - py, if (self.iso_mode) @as(i32, CONF.PREVIEW_SIZE / 2) else CONF.PREVIEW_SIZE);
            const mouse_cell_x: i32 = if (self.iso_mode and @rem(mouse_cell_y, 2) == 1) @divFloor(mouse.x - px - @as(i32, CONF.PREVIEW_SIZE / 2), CONF.PREVIEW_SIZE) else @divFloor(mouse.x - px, CONF.PREVIEW_SIZE);
            if (mouse_cell_x >= 0 and mouse_cell_x < CONF.PREVIEW_W and mouse_cell_y >= 0 and mouse_cell_y < CONF.PREVIEW_H and self.layers[self.selected].visible) {
                const data_mouse_y: i32 = mouse_cell_y + @as(i32, @intCast(self.cam_y));
                const y_step = if (self.iso_mode) @as(i32, CONF.PREVIEW_SIZE / 2) else CONF.PREVIEW_SIZE;
                const mouse_cell_x_u: usize = @intCast(mouse_cell_x);
                const mouse_cell_y_u: usize = @intCast(mouse_cell_y);
                var xx: i32 = @intCast(@as(u64, mouse_cell_x_u) * @as(u64, @intCast(CONF.PREVIEW_SIZE)));
                const yy: i32 = @intCast(@as(u64, mouse_cell_y_u) * @as(u64, @intCast(y_step)));
                if (self.iso_mode and @rem(data_mouse_y, 2) == 1) {
                    xx += @as(i32, CONF.PREVIEW_SIZE / 2);
                }
                self.tiles.draw(self.tiles.selected, px + xx, py + yy);
                self.fui.draw_rect_lines(px + xx, py + yy, CONF.PREVIEW_SIZE, CONF.PREVIEW_SIZE, DB16.WHITE);
            }
        }
        const pw: i32 = if (self.iso_mode) CONF.PREVIEW_SIZE * CONF.PREVIEW_W + @as(i32, CONF.PREVIEW_SIZE / 2) else CONF.PREVIEW_SIZE * CONF.PREVIEW_W;
        const ph: i32 = if (self.iso_mode) @as(i32, CONF.PREVIEW_SIZE * CONF.PREVIEW_H / 2) + @as(i32, CONF.PREVIEW_SIZE / 2) else CONF.PREVIEW_SIZE * CONF.PREVIEW_H;
        self.fui.draw_rect_lines(px, py, pw, ph, DB16.STEEL_BLUE);

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
                Popup.info_export_ok => {
                    if (self.fui.info_popup("Exported preview.ppm!", mouse, CONF.COLOR_OK)) |dismissed| {
                        if (dismissed) {
                            self.popup = Popup.none;
                            self.locked = false;
                            self.sm.hot = true;
                        }
                    }
                },
                Popup.info_export_fail => {
                    if (self.fui.info_popup("Export failed...", mouse, CONF.COLOR_NO)) |dismissed| {
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
                            self.edit.select();
                        }
                    }
                },
                else => {},
            }
        }
    }
};
