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
        var pal_y: i32 = self.fui.pivots[PIVOTS.TOP_LEFT].x + 96;
        var buf: [3:0]u8 = undefined;

        for (start_pal..end_pal) |pal| {
            const cur: u8 = @intCast(pal);
            if (self.pal.index == cur) self.fui.draw_rect(pal_x - 8, pal_y - 8, 32 * 4 + 16, 64 + 16, CONF.COLOR_PRIMARY);

            for (self.pal.db[pal]) |swatch| {
                self.fui.draw_rect(pal_x, pal_y, 32, 64, self.pal.get_rgba_from_index(swatch));
                _ = std.fmt.bufPrintZ(&buf, "{d}", .{swatch}) catch {};
                self.fui.draw_text(&buf, pal_x + 8, pal_y + 8, CONF.FONT_SMOL, CONF.COLOR_PRIMARY);
                pal_x += 32;
            }
            var count_buf: [3:0]u8 = undefined;
            _ = std.fmt.bufPrintZ(&count_buf, "{d}", .{self.count_tiles_using_palette(cur)}) catch {};
            self.fui.draw_text(&count_buf, pal_x + 16, pal_y + 8, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);
            if (self.pal.index != cur) {
                if (self.fui.button(pal_x + 16, pal_y + 32, 64, 24, "THIS", CONF.COLOR_MENU_NORMAL, mouse)) {
                    self.pal.index = cur;
                }
            }

            pal_x += 128;
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
    }
};
