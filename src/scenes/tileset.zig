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
};

pub const TilesetScene = struct {
    fui: Fui,
    sm: *StateMachine,
    palette: *Palette,
    tiles: *Tiles,
    edit: *Edit,
    selected: u8,
    locked: bool,
    popup: Popup,
    pub fn init(fui: Fui, sm: *StateMachine, pal: *Palette, tiles: *Tiles, edit: *Edit) TilesetScene {
        return TilesetScene{
            .fui = fui,
            .sm = sm,
            .tiles = tiles,
            .edit = edit,
            .selected = 0,
            .palette = pal,
            .locked = false,
            .popup = Popup.none,
        };
    }
    pub fn draw(self: *TilesetScene, mouse: Mouse) !void {
        const nav: Vec2 = Vec2.init(self.fui.pivots[PIVOTS.TOP_LEFT].x, self.fui.pivots[PIVOTS.TOP_LEFT].y);
        var nav_step = nav.x;
        if (self.fui.button(nav_step, nav.y, 120, 32, "< Menu", CONF.COLOR_MENU_SECONDARY, mouse) and !self.locked) {
            self.sm.goTo(State.main_menu);
        }
        nav_step += 128 + 32;

        if (self.fui.button(nav_step, nav.y, 180, 32, "Edit tile", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.sm.goTo(State.editor);
        }
        nav_step += 188;
        if (self.fui.button(nav_step, nav.y, 180, 32, "Preview", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.sm.goTo(State.preview);
        }

        nav_step += 188 + 32;
        if (self.fui.button(nav_step, nav.y, 160, 32, "Save tiles", if (self.tiles.updated) CONF.COLOR_MENU_HIGHLIGHT else CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.tiles.saveTilesToFile() catch {
                self.popup = Popup.info_save_fail;
                return;
            };
            self.popup = Popup.info_save_ok;
        }
        nav_step += 168;
        if (self.fui.button(nav_step, nav.y, 160, 32, "Export tileset", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.locked = true;
            self.popup = Popup.info_not_implemented;
        }

        const t_pos = Vec2.init(self.fui.pivots[PIVOTS.TOP_LEFT].x, self.fui.pivots[PIVOTS.TOP_LEFT].y + 64);
        const tiles_in_row: usize = 16;
        inline for (0..CONF.MAX_TILES) |i| {
            const x_shift: i32 = @intCast(@mod(i, tiles_in_row) * (CONF.SPRITE_SIZE * CONF.PREVIEW_SCALE + 12));
            const x: i32 = t_pos.x + x_shift;
            const y: i32 = @divFloor(i, tiles_in_row) * (CONF.SPRITE_SIZE * CONF.PREVIEW_SCALE + 12);
            const size: i32 = CONF.SPRITE_SIZE * CONF.PREVIEW_SCALE + 2;
            const fx: i32 = x;
            const fy: i32 = t_pos.y + y;
            if (i < self.tiles.count) {
                if (self.fui.button(fx, fy, size, size, "", DB16.BLACK, mouse)) {
                    self.tiles.selected = i;

                    self.edit.select();
                }
                self.tiles.draw(i, x + 1, t_pos.y + y + 1);
                if (self.tiles.selected == i) {
                    self.fui.draw_rect_lines(x + 5, y + t_pos.y + 5, size - 8, size - 8, DB16.BLACK);
                    self.fui.draw_rect_lines(x + 4, y + t_pos.y + 4, size - 8, size - 8, DB16.WHITE);
                }
            } else {
                if (i == self.tiles.count) {
                    if (self.fui.button(x, t_pos.y + y, size, size, "+", CONF.COLOR_MENU_NORMAL, mouse)) {
                        try self.tiles.newTile();
                    }
                } else {
                    self.fui.draw_rect_lines(x, t_pos.y + y, size, size, DB16.LIGHT_GRAY);
                }
            }
        }

        const tools: Vec2 = Vec2.init(self.fui.pivots[PIVOTS.BOTTOM_LEFT].x, self.fui.pivots[PIVOTS.BOTTOM_LEFT].y - 32);
        var tools_step = tools.x;

        if (self.fui.button(tools_step, tools.y, 160, 32, "Duplicate", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
            self.tiles.duplicateTile(self.tiles.selected);
        }
        tools_step += 168;
        if (self.tiles.selected > 0) {
            if (self.fui.button(tools_step, tools.y, 160, 32, "<< Shift left", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
                self.tiles.shiftLeft(self.tiles.selected);
                self.tiles.selected -= 1;
            }
        }
        tools_step += 168;
        if (self.tiles.selected < self.tiles.count - 1) {
            if (self.fui.button(tools_step, tools.y, 160, 32, "Shift right >>", CONF.COLOR_MENU_NORMAL, mouse) and !self.locked) {
                self.tiles.shiftRight(self.tiles.selected);
                self.tiles.selected += 1;
            }
        }
        tools_step += 168;
        if (self.fui.button(tools_step, tools.y, 160, 32, "Delete tile", CONF.COLOR_MENU_DANGER, mouse) and !self.locked) {
            self.locked = true;
            self.popup = Popup.confirm_delete;
        }

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
                Popup.confirm_delete => {
                    if (self.fui.yes_no_popup("Delete selected tile?", mouse)) |confirmed| {
                        if (confirmed) {
                            self.tiles.delete(self.tiles.selected);

                            self.tiles.selected = self.tiles.selected - 1;
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
