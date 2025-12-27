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
    ui: Ui,
    sm: *StateMachine,
    edit: *Edit,
    palette: *Palette,
    tiles: *Tiles,
    tiles_area: rl.Vector2,
    layers: [CONF.PREVIEW_LAYERS]Layer = undefined,
    selected: u8,
    locked: bool,
    popup: Popup,
    pub fn init(ui: Ui, sm: *StateMachine, edit: *Edit, pal: *Palette, tiles: *Tiles) PreviewScene {
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
            .ui = ui,
            .sm = sm,
            .edit = edit,
            .tiles = tiles,
            .tiles_area = rl.Vector2.init(ui.pivots[PIVOTS.TOP_LEFT].x + 72, ui.pivots[PIVOTS.TOP_LEFT].y + 64),
            .layers = layers,
            .selected = 0,
            .palette = pal,
            .locked = false,
            .popup = Popup.none,
        };
    }
    pub fn handleMouse(self: *PreviewScene, mouse: rl.Vector2) void {
        if (self.locked) return;

        if (self.sm.hot and rl.isMouseButtonReleased(rl.MouseButton.left)) {
            self.sm.hot = false;
        } else if (self.sm.hot) {
            return;
        }

        const mx: i32 = @intFromFloat(mouse.x);
        const my: i32 = @intFromFloat(mouse.y);
        const i_tx: i32 = @intFromFloat(self.tiles_area.x);
        const i_ty: i32 = @intFromFloat(self.tiles_area.y);
        const mouse_cell_x: i32 = @divFloor(mx - i_tx, CONF.PREVIEW_SIZE);
        const mouse_cell_y: i32 = @divFloor(my - i_ty, CONF.PREVIEW_SIZE);
        if ((rl.isMouseButtonDown(rl.MouseButton.left) or rl.isMouseButtonDown(rl.MouseButton.right))) {
            var tile: u8 = self.tiles.selected;
            if (mouse_cell_x >= 0 and mouse_cell_x < CONF.PREVIEW_W and
                mouse_cell_y >= 0 and mouse_cell_y < CONF.PREVIEW_H)
            {
                if (rl.isMouseButtonDown(rl.MouseButton.right)) tile = 255;
                self.layers[self.selected].data[@intCast(mouse_cell_y)][@intCast(mouse_cell_x)] = tile;
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
    pub fn draw(self: *PreviewScene, mouse: rl.Vector2) void {
        const nav: rl.Vector2 = rl.Vector2.init(self.ui.pivots[PIVOTS.TOP_LEFT].x, self.ui.pivots[PIVOTS.TOP_LEFT].y);
        var nav_step = nav.x;
        if (self.ui.button(nav_step, nav.y, 120, 32, "< Menu", CONF.COLOR_MENU_SECONDARY, mouse) and !self.locked) {
            self.sm.goTo(State.main_menu);
        }
        nav_step += 128 + 32;
        if (self.ui.button(nav_step, nav.y, 180, 32, "Tileset", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.sm.goTo(State.tileset);
        }
        nav_step += 188;
        if (self.ui.button(nav_step, nav.y, 180, 32, "Edit tile", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.sm.goTo(State.editor);
        }
        nav_step += 188 + 32;
        if (self.ui.button(nav_step, nav.y, 160, 32, "Save Preview", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.savePreviewToFile() catch {
                self.popup = Popup.info_save_fail;
                return;
            };
            self.popup = Popup.info_save_ok;
        }

        // Tile

        const tx: i32 = @intFromFloat(self.tiles_area.x - 72);
        const ty: i32 = @intFromFloat(self.tiles_area.y);
        if (self.ui.button(@floatFromInt(tx), @floatFromInt(ty), 64, 64, "", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.popup = Popup.select_tile;
            self.tiles.hot = true;
        }
        self.tiles.draw(self.tiles.selected, tx + 1, ty + 1, 4);
        rl.drawRectangleLines(tx, ty, CONF.SPRITE_SIZE * 4, CONF.SPRITE_SIZE * 4, DB16.STEEL_BLUE);

        // Layers
        const lx: f32 = self.tiles_area.x - 72;
        var ly: f32 = @floatFromInt(ty + 128);
        if (self.ui.button(lx, ly, 64, 32, "1", if (self.selected == 0) CONF.COLOR_MENU_HIGHLIGHT else CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.selected = 0;
        }
        ly += 40;
        if (self.ui.button(lx, ly, 64, 32, "2", if (self.selected == 1) CONF.COLOR_MENU_HIGHLIGHT else CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.selected = 1;
        }
        ly += 40;
        if (self.ui.button(lx, ly, 64, 32, "3", if (self.selected == 2) CONF.COLOR_MENU_HIGHLIGHT else CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.selected = 2;
        }

        // Playground
        const px: i32 = @intFromFloat(self.tiles_area.x);
        const py: i32 = @intFromFloat(self.tiles_area.y);
        const pw: i32 = CONF.PREVIEW_SIZE * CONF.PREVIEW_W;
        const ph: i32 = CONF.PREVIEW_SIZE * CONF.PREVIEW_H;
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
        rl.drawRectangleLines(px, py, pw, ph, DB16.STEEL_BLUE);

        // Popups
        if (self.popup != Popup.none) {
            rl.drawRectangle(0, 0, CONF.SCREEN_W, CONF.SCREEN_H, rl.Color.init(0, 0, 0, 128));
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
