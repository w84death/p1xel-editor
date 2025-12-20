const std = @import("std");
const rl = @import("raylib");
const CONF = @import("../config.zig").CONF;
const DB16 = @import("../palette.zig").DB16;
const Ui = @import("../ui.zig").UI;
const PIVOTS = @import("../ui.zig").PIVOTS;
const State = @import("../state_machine.zig").State;
const StateMachine = @import("../state_machine.zig").StateMachine;

pub const Edit = struct {
    ui: Ui,
    sm: *StateMachine,
    canvas: [CONF.SPRITE_SIZE][CONF.SPRITE_SIZE]u8,
    pub fn init(ui: Ui, sm: *StateMachine) Edit {
        return Edit{ .ui = ui, .sm = sm, .canvas = [_][CONF.SPRITE_SIZE]u8{[_]u8{0} ** CONF.SPRITE_SIZE} ** CONF.SPRITE_SIZE };
    }
    pub fn draw(self: Edit, mouse: rl.Vector2) void {
        if (self.ui.button(self.ui.pivots[PIVOTS.TOP_LEFT].x, self.ui.pivots[PIVOTS.TOP_LEFT].y, 80, 32, "< Menu", DB16.BLUE, mouse)) {
            self.sm.goTo(State.main_menu);
        }
    }
};
