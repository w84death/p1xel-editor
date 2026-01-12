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
    confirm_delete,
    select_tile,
};
pub const Layer = struct {
    data: [CONF.PREVIEW_H][CONF.PREVIEW_W]u8,
    visible: bool = false,
};
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
    locked: bool,
    iso_mode: bool = false,
    popup: Popup,
    pub fn init(fui: Fui, sm: *StateMachine, nav: *NavPanel, edit: *Edit, pal: *Palette, tiles: *Tiles, layers: *[CONF.PREVIEW_LAYERS]Layer) PreviewScene {
        for (0..CONF.PREVIEW_LAYERS) |i| {
            var data: [CONF.PREVIEW_H][CONF.PREVIEW_W]u8 = undefined;
            for (0..CONF.PREVIEW_H) |y| {
                for (0..CONF.PREVIEW_W) |x| {
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
    pub fn handle_mouse(self: *PreviewScene, mouse: Mouse) void {
        if (self.locked or !self.layers[self.selected].visible) return;

        if (self.sm.hot and !mouse.pressed) {
            self.sm.hot = false;
        } else if (self.sm.hot) {
            return;
        }

        const mouse_cell_y: i32 = @divFloor(mouse.y - self.tiles_area.y, if (self.iso_mode) @as(i32, CONF.PREVIEW_SIZE / 2) else CONF.PREVIEW_SIZE);
        const mouse_cell_x: i32 = if (self.iso_mode and @rem(mouse_cell_y, 2) == 1) @divFloor(mouse.x - self.tiles_area.x - @as(i32, CONF.PREVIEW_SIZE / 2), CONF.PREVIEW_SIZE) else @divFloor(mouse.x - self.tiles_area.x, CONF.PREVIEW_SIZE);
        if (mouse.pressed) {
            if (mouse_cell_x >= 0 and mouse_cell_x < CONF.PREVIEW_W and
                mouse_cell_y >= 0 and mouse_cell_y < CONF.PREVIEW_H)
            {
                var data = self.layers[self.selected].data[@intCast(mouse_cell_y)][@intCast(mouse_cell_x)];
                data = if (data == self.tiles.selected) 255 else self.tiles.selected;
                self.layers[self.selected].data[@intCast(mouse_cell_y)][@intCast(mouse_cell_x)] = data;
            }
        }
    }
    pub fn savePreviewToFile(self: *const PreviewScene) !void {
        const per_layer = CONF.PREVIEW_H * CONF.PREVIEW_W;
        var buf = [_]u8{0} ** (CONF.PREVIEW_LAYERS * CONF.PREVIEW_H * CONF.PREVIEW_W);
        for (0..CONF.PREVIEW_LAYERS) |l| {
            for (0..CONF.PREVIEW_H) |y| {
                for (0..CONF.PREVIEW_W) |x| {
                    buf[l * per_layer + y * CONF.PREVIEW_W + x] = self.layers[l].data[y][x];
                }
            }
        }
        const file = try std.fs.cwd().createFile(CONF.PREVIEW_FILE, .{});
        defer file.close();
        _ = try file.write(&buf);
    }
    pub fn loadPreviewFromFile(self: *PreviewScene) void {
        const per_layer = CONF.PREVIEW_H * CONF.PREVIEW_W;
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
            for (0..CONF.PREVIEW_H) |y| {
                for (0..CONF.PREVIEW_W) |x| {
                    self.layers[l].data[y][x] = data[l * per_layer + y * CONF.PREVIEW_W + x];
                    self.layers[l].visible = true;
                }
            }
        }
    }
    pub fn draw(self: *PreviewScene, mouse: Mouse) void {
        // Navigation (top)
        self.nav.draw(mouse);

        // options
        const options_x: i32 = self.fui.pivots[PIVOTS.TOP_RIGHT].x;
        const options_y: i32 = self.fui.pivots[PIVOTS.TOP_RIGHT].y + 64;

        if (self.fui.button(options_x - 160, options_y, 160, 32, "Save", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.savePreviewToFile() catch {
                self.popup = Popup.info_save_fail;
                return;
            };
            self.popup = Popup.info_save_ok;
        }

        if (self.fui.button(options_x - 160, options_y + 40, 160, 32, if (self.iso_mode) "ISO: ON" else "ISO: OFF", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.iso_mode = !self.iso_mode;
        }

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
            for (self.layers) |layer| {
                if (layer.visible) {
                    for (0..CONF.PREVIEW_H) |y| {
                        for (0..CONF.PREVIEW_W) |x| {
                            const tile = layer.data[y][x];
                            if (tile < 255) {
                                const y_step = if (self.iso_mode) @as(i32, CONF.PREVIEW_SIZE / 2) else CONF.PREVIEW_SIZE;
                                var xx: i32 = @intCast(@as(u64, x) * @as(u64, @intCast(CONF.PREVIEW_SIZE)));
                                const yy: i32 = @intCast(@as(u64, y) * @as(u64, @intCast(y_step)));
                                if (self.iso_mode and @rem(y, 2) == 1) {
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
                const y_step = if (self.iso_mode) @as(i32, CONF.PREVIEW_SIZE / 2) else CONF.PREVIEW_SIZE;
                const mouse_cell_x_u: usize = @intCast(mouse_cell_x);
                const mouse_cell_y_u: usize = @intCast(mouse_cell_y);
                var xx: i32 = @intCast(@as(u64, mouse_cell_x_u) * @as(u64, @intCast(CONF.PREVIEW_SIZE)));
                const yy: i32 = @intCast(@as(u64, mouse_cell_y_u) * @as(u64, @intCast(y_step)));
                if (self.iso_mode and @rem(mouse_cell_y, 2) == 1) {
                    xx += @as(i32, CONF.PREVIEW_SIZE / 2);
                }
                self.tiles.draw(self.tiles.selected, px + xx, py + yy);
                self.fui.draw_rect_lines(px + xx, py + yy, CONF.PREVIEW_SIZE, CONF.PREVIEW_SIZE, DB16.WHITE);
            }
        }
        const pw: i32 = if (self.iso_mode) CONF.PREVIEW_SIZE * CONF.PREVIEW_W + @as(i32, CONF.PREVIEW_SIZE / 2) else CONF.PREVIEW_SIZE * CONF.PREVIEW_W;
        const ph: i32 = if (self.iso_mode) @as(i32, CONF.PREVIEW_SIZE * CONF.PREVIEW_H / 2) + @as(i32, CONF.PREVIEW_SIZE / 2) else CONF.PREVIEW_SIZE * CONF.PREVIEW_H;
        self.fui.draw_rect_lines(px, py, pw, ph, DB16.STEEL_BLUE);

        const tools: Vec2 = Vec2.init(self.fui.pivots[PIVOTS.BOTTOM_LEFT].x, self.fui.pivots[PIVOTS.BOTTOM_LEFT].y - 32);
        var tools_step = tools.x;
        self.fui.draw_text("Move layer:", tools.x, tools.y - 20, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);
        if (self.fui.button(tools_step, tools.y, 160, 32, "Up", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.popup = Popup.info_not_implemented;
        }
        tools_step += 168;
        if (self.fui.button(tools_step, tools.y, 160, 32, "Down", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.popup = Popup.info_not_implemented;
        }
        tools_step += 188;
        if (self.fui.button(tools_step, tools.y, 220, 32, "Clear layer", CONF.COLOR_MENU_DANGER, mouse) and !self.locked) {
            self.locked = true;
            self.popup = Popup.info_not_implemented;
        }

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
