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

const Popup = enum {
    none,
    info_not_implemented,
    info_save_ok,
    info_save_fail,
    confirm_delete,
    select_tile,
};
const Layer = struct {
    data: [CONF.PREVIEW_H][CONF.PREVIEW_W]u8,
};
pub const PreviewScene = struct {
    fui: Fui,
    sm: *StateMachine,
    edit: *Edit,
    palette: *Palette,
    tiles: *Tiles,
    tiles_area: Vec2,
    layers: [CONF.PREVIEW_LAYERS]Layer = undefined,
    selected: u8,
    locked: bool,
    popup: Popup,
    pub fn init(fui: Fui, sm: *StateMachine, edit: *Edit, pal: *Palette, tiles: *Tiles) PreviewScene {
        var layers: [CONF.PREVIEW_LAYERS]Layer = undefined;
        for (0..CONF.PREVIEW_LAYERS) |i| {
            var data: [CONF.PREVIEW_H][CONF.PREVIEW_W]u8 = undefined;
            for (0..CONF.PREVIEW_H) |y| {
                for (0..CONF.PREVIEW_W) |x| {
                    data[y][x] = 255;
                }
            }
            layers[i].data = data;
        }
        return PreviewScene{
            .fui = fui,
            .sm = sm,
            .edit = edit,
            .tiles = tiles,
            .tiles_area = Vec2.init(fui.pivots[PIVOTS.TOP_LEFT].x + 72, fui.pivots[PIVOTS.TOP_LEFT].y + 64),
            .layers = layers,
            .selected = 0,
            .palette = pal,
            .locked = false,
            .popup = Popup.none,
        };
    }
    pub fn handleMouse(self: *PreviewScene, mouse: Mouse) void {
        if (self.locked) return;

        if (self.sm.hot and !mouse.pressed) {
            self.sm.hot = false;
        } else if (self.sm.hot) {
            return;
        }

        const mouse_cell_x: i32 = @divFloor(mouse.x - self.tiles_area.x, CONF.PREVIEW_SIZE);
        const mouse_cell_y: i32 = @divFloor(mouse.y - self.tiles_area.y, CONF.PREVIEW_SIZE);
        if (mouse.pressed) {
            if (mouse_cell_x >= 0 and mouse_cell_x < CONF.PREVIEW_W and
                mouse_cell_y >= 0 and mouse_cell_y < CONF.PREVIEW_H)
            {
                self.layers[self.selected].data[@intCast(mouse_cell_y)][@intCast(mouse_cell_x)] = self.tiles.selected;
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
                }
            }
        }
    }
    pub fn draw(self: *PreviewScene, mouse: Mouse) void {
        const nav: Vec2 = Vec2.init(self.fui.pivots[PIVOTS.TOP_LEFT].x, self.fui.pivots[PIVOTS.TOP_LEFT].y);
        var nav_step = nav.x;
        if (self.fui.button(nav_step, nav.y, 120, 32, "< Menu", CONF.COLOR_MENU_SECONDARY, mouse) and !self.locked) {
            self.sm.goTo(State.main_menu);
        }
        nav_step += 128 + 32;
        if (self.fui.button(nav_step, nav.y, 180, 32, "Tileset", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.sm.goTo(State.tileset);
        }
        nav_step += 188;
        if (self.fui.button(nav_step, nav.y, 180, 32, "Edit tile", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.sm.goTo(State.editor);
        }
        nav_step += 188 + 32;
        if (self.fui.button(nav_step, nav.y, 160, 32, "Save Preview", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.savePreviewToFile() catch {
                self.popup = Popup.info_save_fail;
                return;
            };
            self.popup = Popup.info_save_ok;
        }

        // Tile

        const tx: i32 = self.tiles_area.x - 72;
        const ty: i32 = self.tiles_area.y;
        if (self.fui.button(tx, ty, 64, 64, "", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.popup = Popup.select_tile;
            self.tiles.hot = true;
        }
        self.tiles.draw(self.tiles.selected, tx + 1, ty + 1, 4);
        self.fui.draw_rect_lines(tx, ty, CONF.SPRITE_SIZE * 4, CONF.SPRITE_SIZE * 4, DB16.STEEL_BLUE);

        // Layers
        const lx: i32 = self.tiles_area.x - 72;
        var ly: i32 = ty + 128;
        if (self.fui.button(lx, ly, 64, 32, "1", if (self.selected == 0) CONF.COLOR_MENU_HIGHLIGHT else CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.selected = 0;
        }
        ly += 40;
        if (self.fui.button(lx, ly, 64, 32, "2", if (self.selected == 1) CONF.COLOR_MENU_HIGHLIGHT else CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.selected = 1;
        }
        ly += 40;
        if (self.fui.button(lx, ly, 64, 32, "3", if (self.selected == 2) CONF.COLOR_MENU_HIGHLIGHT else CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.selected = 2;
        }

        // Playground
        const px: i32 = self.tiles_area.x;
        const py: i32 = self.tiles_area.y;
        for (self.layers) |layer| {
            for (0..CONF.PREVIEW_H) |y| {
                for (0..CONF.PREVIEW_W) |x| {
                    const tile = layer.data[y][x];
                    if (tile < 255) {
                        const xx: i32 = @intCast(x * CONF.PREVIEW_SIZE);
                        const yy: i32 = @intCast(y * CONF.PREVIEW_SIZE);
                        self.tiles.draw(tile, px + xx, py + yy, CONF.PREVIEW_SCALE);
                    }
                }
            }
        }
        const pw: i32 = CONF.PREVIEW_SIZE * CONF.PREVIEW_W;
        const ph: i32 = CONF.PREVIEW_SIZE * CONF.PREVIEW_H;
        self.fui.draw_rect_lines(px, py, pw, ph, DB16.STEEL_BLUE);

        // Popups
        if (self.popup != Popup.none) {
            self.fui.draw_rect(0, 0, CONF.SCREEN_W, CONF.SCREEN_H, CONF.POPUP_BG_ALPHA);
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
                    if (self.tiles.showTilesSelector(mouse)) |dismissed| {
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
