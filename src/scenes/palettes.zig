const std = @import("std");
const CONF = @import("../config.zig").CONF;
const DB16 = @import("../palette.zig").DB16;
const Palette = @import("../palette.zig").Palette;
const Fui = @import("../fui.zig").Fui;
const PIVOTS = @import("../fui.zig").PIVOTS;
const State = @import("../state.zig").State;
const StateMachine = @import("../state.zig").StateMachine;
const Color = @import("../ppm.zig").Color;
const Vec2 = @import("../math.zig").Vec2;
const Mouse = @import("../math.zig").Mouse;
const NavPanel = @import("../nav.zig").NavPanel;
const Tiles = @import("../tiles.zig").Tiles;

pub const PalettesScene = struct {
    fui: Fui,
    sm: *StateMachine,
    nav: *NavPanel,
    pal: *Palette,
    tiles: *Tiles,
    current_page: usize = 0,
    pub fn init(fui: Fui, sm: *StateMachine, nav: *NavPanel, pal: *Palette, tiles: *Tiles) PalettesScene {
        return PalettesScene{
            .fui = fui,
            .sm = sm,
            .nav = nav,
            .pal = pal,
            .tiles = tiles,
        };
    }
    pub fn count_tiles_using_palette(self: *PalettesScene, pal_index: u8) usize {
        var count: usize = 0;
        for (0..self.tiles.count) |i| {
            if (self.tiles.db[i].pal == pal_index) {
                count += 1;
            }
        }
        return count;
    }
    pub fn draw(self: *PalettesScene, mouse: Mouse) void {
        self.nav.draw(mouse);
        const paletes_per_row: usize = 4;
        const start_pal = self.current_page * CONF.PALETTES_PER_PAGE;
        const end_pal = @min(start_pal + CONF.PALETTES_PER_PAGE, self.pal.count);
        var pal_x: i32 = self.fui.pivots[PIVOTS.TOP_LEFT].x;
        var pal_y: i32 = self.fui.pivots[PIVOTS.TOP_LEFT].y + 96;
        var buf: [3:0]u8 = undefined;

        for (start_pal..end_pal) |pal| {
            const cur: u8 = @intCast(pal);

            if (self.pal.index == cur) {
                self.fui.draw_rect(pal_x - 8, pal_y - 8, 128 + 16, 64 + 16, CONF.COLOR_PRIMARY);
            } else {
                if (self.fui.button(pal_x, pal_y, 128, 64, " ", CONF.COLOR_MENU_NORMAL, mouse)) {
                    self.pal.index = cur + 1;
                    self.pal.change_palette_prev();
                }
            }

            for (self.pal.db[pal]) |swatch| {
                self.fui.draw_rect(pal_x, pal_y, 32, 64, self.pal.get_rgba_from_index(swatch));
                _ = std.fmt.bufPrintZ(&buf, "{d}", .{swatch}) catch {};
                self.fui.draw_text(&buf, pal_x + 8, pal_y + 8, CONF.FONT_SMOL, CONF.COLOR_PRIMARY);
                pal_x += 32;
            }

            _ = std.fmt.bufPrintZ(&buf, "{d}", .{self.count_tiles_using_palette(cur)}) catch {};
            self.fui.draw_text(&buf, pal_x + 16, pal_y + 8, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);

            pal_x += 96;
            if (@mod((pal - start_pal) + 1, paletes_per_row) == 0) {
                pal_x = self.fui.pivots[PIVOTS.TOP_LEFT].x;
                pal_y += 80;
            }
        }

        // Pagination buttons
        const button_y = self.fui.pivots[PIVOTS.BOTTOM_LEFT].y - 32;
        const button_x_prev = self.fui.pivots[PIVOTS.BOTTOM_LEFT].x;
        const button_x_next = self.fui.pivots[PIVOTS.BOTTOM_LEFT].x + 200;
        if (self.current_page > 0) {
            if (self.fui.button(button_x_prev, button_y, 180, 32, "< Prev Page", CONF.COLOR_MENU_NORMAL, mouse)) {
                self.current_page -= 1;
            }
        }
        if (end_pal < self.pal.count) {
            if (self.fui.button(button_x_next, button_y, 180, 32, "Next Page >", CONF.COLOR_MENU_NORMAL, mouse)) {
                self.current_page += 1;
            }
        }

        // Stats panel
        const stats_x = self.fui.pivots[PIVOTS.TOP_RIGHT].x - 256;
        const stats_y = self.fui.pivots[PIVOTS.TOP_RIGHT].y + 128;
        self.fui.draw_rect(stats_x, stats_y, 240, 40, CONF.COLOR_MENU_NORMAL);
        var stats_buf: [14:0]u8 = undefined;
        _ = std.fmt.bufPrintZ(&stats_buf, "Palettes: {d} ", .{self.pal.count}) catch {};
        self.fui.draw_text(&stats_buf, stats_x + 10, stats_y + 10, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);

        // Action buttons for palette management (positioned under stats)
        var action_y = stats_y + 50;
        const action_x = stats_x;
        const action_button_width = 200;

        // Shift Left button
        if (self.fui.button(action_x, action_y, action_button_width, 32, "Shift Left", CONF.COLOR_MENU_NORMAL, mouse)) {
            self.pal.shift_palette_left(self.tiles);
        }
        action_y += 40;

        // Delete button
        if (self.fui.button(action_x, action_y, action_button_width, 32, "Delete", CONF.COLOR_MENU_DANGER, mouse)) {
            self.pal.delete_palette_safe(self.tiles);
        }
        action_y += 40;

        // Shift Right button
        if (self.fui.button(action_x, action_y, action_button_width, 32, "Shift Right", CONF.COLOR_MENU_NORMAL, mouse)) {
            self.pal.shift_palette_right(self.tiles);
        }
    }
};
