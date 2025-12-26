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
const Edit = @import("edit.zig").EditScreen;
const Popup = enum {
    none,
    info_not_implemented,
    info_save_ok,
    info_save_fail,
    confirm_delete,
};

pub const TilesetScene = struct {
    ui: Ui,
    sm: *StateMachine,
    palette: *Palette,
    tiles: *Tiles,
    edit: *Edit,
    selected: u8,
    locked: bool,
    popup: Popup,
    pub fn init(ui: Ui, sm: *StateMachine, pal: *Palette, tiles: *Tiles, edit: *Edit) TilesetScene {
        return TilesetScene{
            .ui = ui,
            .sm = sm,
            .tiles = tiles,
            .edit = edit,
            .selected = 0,
            .palette = pal,
            .locked = false,
            .popup = Popup.none,
        };
    }
    pub fn draw(self: *TilesetScene, mouse: rl.Vector2) !void {
        const nav: rl.Vector2 = rl.Vector2.init(self.ui.pivots[PIVOTS.TOP_LEFT].x, self.ui.pivots[PIVOTS.TOP_LEFT].y);
        var nav_step = nav.x;
        if (self.ui.button(nav_step, nav.y, 120, 32, "< Menu", CONF.COLOR_MENU_SECONDARY, mouse) and !self.locked) {
            self.sm.goTo(State.main_menu);
        }
        nav_step += 128;

        if (self.ui.button(nav_step, nav.y, 160, 32, "Edit", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            const selected = self.tiles.db[self.selected];
            self.edit.canvas.data = selected.data;
            self.palette.current = self.palette.db[selected.pal];
            self.palette.index = selected.pal;
            self.edit.tile_id = self.selected;
            self.sm.goTo(State.editor);
        }

        nav_step += 168;
        if (self.ui.button(nav_step, nav.y, 160, 32, "Save tiles", if (self.tiles.updated) CONF.COLOR_MENU_HIGHLIGHT else CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.tiles.saveTilesToFile() catch {
                self.popup = Popup.info_save_fail;
                return;
            };
            self.popup = Popup.info_save_ok;
        }
        nav_step += 168;
        if (self.ui.button(nav_step, nav.y, 160, 32, "Export tileset", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.popup = Popup.info_not_implemented;
        }

        const t_pos = rl.Vector2.init(self.ui.pivots[PIVOTS.TOP_LEFT].x, self.ui.pivots[PIVOTS.TOP_LEFT].y + 64);
        const tiles_x: i32 = @intFromFloat(t_pos.x);
        const tiles_y: i32 = @intFromFloat(t_pos.y);
        const tiles_in_row: usize = 16;
        const scale: i32 = 4;
        inline for (0..CONF.MAX_TILES) |i| {
            const x_shift: i32 = @intCast(@mod(i, tiles_in_row) * (CONF.SPRITE_SIZE * scale + 12));
            const x: i32 = tiles_x + x_shift;
            const y: i32 = @divFloor(i, tiles_in_row) * (CONF.SPRITE_SIZE * scale + 12);
            const size: i32 = CONF.SPRITE_SIZE * scale + 2;
            const fx: f32 = @floatFromInt(x);
            const fy: f32 = @floatFromInt(tiles_y + y);
            if (i < self.tiles.count) {
                if (self.ui.button(fx, fy, size, size, "", DB16.BLACK, mouse)) {
                    self.selected = i;
                }
                self.tiles.draw(i, x + 1, tiles_y + y + 1, scale);
                if (self.selected == i) {
                    rl.drawRectangleLines(x + 5, y + tiles_y + 5, size - 8, size - 8, DB16.BLACK);
                    rl.drawRectangleLines(x + 4, y + tiles_y + 4, size - 8, size - 8, DB16.WHITE);
                }
            } else {
                if (i == self.tiles.count) {
                    if (self.ui.button(@floatFromInt(x), @floatFromInt(tiles_y + y), size, size, "+", CONF.COLOR_MENU_NORMAL, mouse)) {
                        self.tiles.newTile();
                    }
                } else {
                    rl.drawRectangleLines(x, tiles_y + y, size, size, DB16.LIGHT_GRAY);
                }
            }
        }

        const tools: rl.Vector2 = rl.Vector2.init(self.ui.pivots[PIVOTS.BOTTOM_LEFT].x, self.ui.pivots[PIVOTS.BOTTOM_LEFT].y - 20);
        var tools_step = tools.x;

        if (self.ui.button(tools_step, tools.y, 160, 32, "Duplicate", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.popup = Popup.info_not_implemented;
        }
        tools_step += 168;
        if (self.selected > 0) {
            if (self.ui.button(tools_step, tools.y, 160, 32, "<< Shift left", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
                self.tiles.shiftLeft(self.selected);
                self.selected -= 1;
            }
            tools_step += 168;
        }
        if (self.selected < self.tiles.count - 1) {
            if (self.ui.button(tools_step, tools.y, 160, 32, "Shift right >>", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
                self.tiles.shiftRight(self.selected);
                self.selected += 1;
            }
            tools_step += 168;
        }
        if (self.ui.button(tools_step, tools.y, 160, 32, "Delete tile", CONF.COLOR_MENU_DANGER, mouse) and !self.locked) {
            self.locked = true;
            self.popup = Popup.confirm_delete;
        }

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
                Popup.confirm_delete => {
                    if (self.ui.yesNoPopup("Delete selected tile?", mouse)) |confirmed| {
                        if (confirmed) {
                            self.tiles.delete(self.selected);

                            self.selected = self.selected - 1;
                        }
                        self.popup = Popup.none;
                        self.locked = false;
                        self.sm.hot = true;
                    }
                },
                else => {},
            }
        }
    }
};
