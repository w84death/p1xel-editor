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

pub const PalettesScene = struct {
    fui: Fui,
    sm: *StateMachine,
    nav: *NavPanel,
    pal: *Palette,
    pub fn init(fui: Fui, sm: *StateMachine, nav: *NavPanel, pal: *Palette) PalettesScene {
        return PalettesScene{
            .fui = fui,
            .sm = sm,
            .nav = nav,
            .pal = pal,
        };
    }
    pub fn draw(self: *PalettesScene, mouse: Mouse) void {
        self.nav.draw(mouse);
        const paletes_per_row: usize = 4;
        var pal_x: i32 = self.fui.pivots[PIVOTS.TOP_LEFT].x;
        var pal_y: i32 = self.fui.pivots[PIVOTS.TOP_LEFT].x+96;
        var buf: [3:0]u8 = undefined;

        for(0..self.pal.count) |pal| {
            const cur: u8 = @intCast(pal);
            if(self.pal.index == cur) self.fui.draw_rect(pal_x-8, pal_y-8, 32*4+16, 64+16, CONF.COLOR_PRIMARY);

            for(self.pal.db[pal]) |swatch| {
                self.fui.draw_rect(pal_x, pal_y, 32, 64, self.pal.get_rgba_from_index(swatch));
                _ = std.fmt.bufPrintZ(&buf, "{d}", .{ swatch }) catch {};
                self.fui.draw_text(&buf,pal_x+8, pal_y+8, CONF.FONT_SMOL, CONF.COLOR_PRIMARY);
                pal_x += 32;
            }
            self.fui.draw_text("00",pal_x+16, pal_y+8, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);
            pal_x += 128;
            if (@mod(pal+1,paletes_per_row) == 0){
                pal_x = self.fui.pivots[PIVOTS.TOP_LEFT].x;
                pal_y += 140;
            }
        }

    }
};
