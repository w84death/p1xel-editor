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

pub const AutomataScene = struct {
    fui: Fui,
    sm: *StateMachine,
    nav: *NavPanel,
    pal: *Palette,
    pub fn init(fui: Fui, sm: *StateMachine, nav: *NavPanel, pal: *Palette) AutomataScene {
        return AutomataScene{
            .fui = fui,
            .sm = sm,
            .nav = nav,
            .pal = pal,
        };
    }
    pub fn draw(self: *AutomataScene, mouse: Mouse) void {
        self.nav.draw(mouse);
    }
};
