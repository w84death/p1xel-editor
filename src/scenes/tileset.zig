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
};

pub const TilesetScene = struct {
    fui: Fui,
    sm: *StateMachine,
    nav: *NavPanel,
    palette: *Palette,
    tiles: *Tiles,
    edit: *Edit,
    selected: u8,
    needs_saving: bool,
    locked: bool,
    popup: Popup,
    pub fn init(fui: Fui, sm: *StateMachine, nav: *NavPanel, pal: *Palette, tiles: *Tiles, edit: *Edit) TilesetScene {
        return TilesetScene{
            .fui = fui,
            .sm = sm,
            .nav = nav,
            .tiles = tiles,
            .edit = edit,
            .selected = 0,
            .needs_saving = false,
            .palette = pal,
            .locked = false,
            .popup = Popup.none,
        };
    }
    pub fn draw(self: *TilesetScene, mouse: Mouse) !void {

        // Navigation (top)
        self.nav.draw(mouse);

        // options
        const options_x: i32 = self.fui.pivots[PIVOTS.TOP_RIGHT].x;
        var options_y: i32 = self.fui.pivots[PIVOTS.TOP_RIGHT].y + 64;

        if (self.fui.button(options_x - 180, options_y, 180, 32, "Save", if (self.needs_saving) CONF.COLOR_MENU_HIGHLIGHT else CONF.COLOR_MENU_NORMAL, mouse) and !self.nav.locked) {
            self.nav.locked = true;
            self.tiles.save_tileset_to_file() catch {
                self.popup = Popup.info_save_fail;
                return;
            };
            self.popup = Popup.info_save_ok;
        }
        options_y += 40;
        if (self.fui.button(options_x - 180, options_y, 180, 32, "Export ASM", CONF.COLOR_MENU_NORMAL, mouse) and !self.nav.locked) {
            self.nav.locked = true;
            self.popup = Popup.info_not_implemented;
        }

        const t_pos = Vec2.init(self.fui.pivots[PIVOTS.TOP_LEFT].x, self.fui.pivots[PIVOTS.TOP_LEFT].y + 64);
        const tiles_in_row: usize = 16;
        const size: i32 = CONF.SPRITE_SIZE * CONF.PREVIEW_SCALE + 2;

        inline for (0..CONF.MAX_TILES) |i| {
            const x_shift: i32 = @intCast(@mod(i, tiles_in_row) * (CONF.SPRITE_SIZE * CONF.PREVIEW_SCALE + 4));
            const x: i32 = t_pos.x + x_shift;
            const y: i32 = @divFloor(i, tiles_in_row) * (CONF.SPRITE_SIZE * CONF.PREVIEW_SCALE + 4);
            if (i < self.tiles.count) {
                if (self.fui.button(x, t_pos.y + y, size, size, "", DB16.BLACK, mouse)) {
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
                        try self.tiles.create_new();
                        self.needs_saving = true;
                    }
                } else {
                    self.fui.draw_rect_lines(x, t_pos.y + y, size, size, DB16.LIGHT_GRAY);
                }
            }
        }

        const tools: Vec2 = Vec2.init(self.fui.pivots[PIVOTS.BOTTOM_LEFT].x, self.fui.pivots[PIVOTS.BOTTOM_LEFT].y - 32);
        var tools_step = tools.x;

        if (self.fui.button(tools_step, tools.y, 180, 32, "Duplicate", CONF.COLOR_MENU_NORMAL, mouse) and !self.nav.locked) {
            self.tiles.duplicate_tile(self.tiles.selected);
        }
        tools_step += 188;
        self.fui.draw_text("Shift tile:", tools_step, tools.y - 20, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);
        if (self.tiles.selected > 0) {
            if (self.fui.button(tools_step, tools.y, 160, 32, "<< Left", CONF.COLOR_MENU_NORMAL, mouse) and !self.nav.locked) {
                self.tiles.shift_tile_left(self.tiles.selected);
                self.tiles.selected -= 1;
                self.needs_saving = true;
            }
        }
        tools_step += 168;
        if (self.tiles.selected < self.tiles.count - 1) {
            if (self.fui.button(tools_step, tools.y, 160, 32, "Right >>", CONF.COLOR_MENU_NORMAL, mouse) and !self.nav.locked) {
                self.tiles.shift_tile_right(self.tiles.selected);
                self.tiles.selected += 1;
                self.needs_saving = true;
            }
        }
        tools_step += 168;
        if (self.fui.button(tools_step, tools.y, 180, 32, "Delete", CONF.COLOR_MENU_DANGER, mouse) and !self.nav.locked) {
            self.nav.locked = true;
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
                            self.nav.locked = false;
                            self.sm.hot = true;
                        }
                    }
                },
                Popup.info_save_ok => {
                    if (self.fui.info_popup("File saved!", mouse, CONF.COLOR_OK)) |dismissed| {
                        if (dismissed) {
                            self.popup = Popup.none;
                            self.nav.locked = false;
                            self.sm.hot = true;
                        }
                    }
                },
                Popup.info_save_fail => {
                    if (self.fui.info_popup("File saving failed...", mouse, CONF.COLOR_NO)) |dismissed| {
                        if (dismissed) {
                            self.popup = Popup.none;
                            self.nav.locked = false;
                            self.sm.hot = true;
                        }
                    }
                },
                Popup.confirm_delete => {
                    if (self.fui.yes_no_popup("Delete selected tile?", mouse)) |confirmed| {
                        if (confirmed) {
                            self.tiles.delete(self.tiles.selected);
                            self.tiles.selected = self.tiles.selected - 1;
                            self.needs_saving = true;
                        }
                        self.popup = Popup.none;
                        self.nav.locked = false;
                        self.sm.hot = true;
                    }
                },
                else => {},
            }
        }
    }
};
