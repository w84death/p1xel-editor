const std = @import("std");
const rl = @import("raylib");
const CONF = @import("../config.zig").CONF;
const DB16 = @import("../palette.zig").DB16;
const Ui = @import("../ui.zig").UI;
const PIVOTS = @import("../ui.zig").PIVOTS;
const State = @import("../state_machine.zig").State;
const StateMachine = @import("../state_machine.zig").StateMachine;

const MenuItem = struct {
    text: [:0]const u8,
    color: rl.Color,
    target_state: State,
};

pub const Menu = struct {
    ui: Ui,
    sm: *StateMachine,
    menu_items: []const MenuItem,
    pub fn init(ui: Ui, sm: *StateMachine) Menu {
        const menu_items = [_]MenuItem{
            .{ .text = "Editor", .color = DB16.BLUE, .target_state = State.editor },
            .{ .text = "About", .color = DB16.DARK_GRAY, .target_state = State.about },
        };
        return Menu{
            .ui = ui,
            .sm = sm,
            .menu_items = menu_items[0..],
        };
    }
    pub fn draw(self: Menu, mouse: rl.Vector2) void {
        const cx: i32 = @intFromFloat(self.ui.pivots[PIVOTS.CENTER].x);
        const cy: i32 = @intFromFloat(self.ui.pivots[PIVOTS.CENTER].y - 96);
        const fx: f32 = self.ui.pivots[PIVOTS.CENTER].x;
        const fy: f32 = self.ui.pivots[PIVOTS.CENTER].y - 96;
        const welcome = "Welcome to the indexed pixelart editor!";
        rl.drawText(CONF.THE_NAME, cx - @divFloor(rl.measureText(CONF.THE_NAME, CONF.DEFAULT_FONT_SIZE), 2), cy, CONF.DEFAULT_FONT_SIZE, self.ui.primary_color);
        rl.drawText(welcome, cx - @divFloor(rl.measureText(welcome, CONF.DEFAULT_FONT_SIZE), 2), cy + 22, CONF.DEFAULT_FONT_SIZE, self.ui.primary_color);

        var y: f32 = fy + 128;
        for (self.menu_items) |item| {
            if (self.ui.button(fx - 100, y, 200, 32, item.text, item.color, mouse)) {
                self.sm.goTo(item.target_state);
            }
            y += 38;
        }

        const ver_x: i32 = @intFromFloat(self.ui.pivots[PIVOTS.BOTTOM_RIGHT].x);
        const ver_y: i32 = @intFromFloat(self.ui.pivots[PIVOTS.BOTTOM_RIGHT].y);

        rl.drawText(CONF.VERSION, ver_x - rl.measureText(CONF.THE_NAME, CONF.DEFAULT_FONT_SIZE), ver_y - CONF.DEFAULT_FONT_SIZE, CONF.DEFAULT_FONT_SIZE, self.ui.secondary_color);
    }
};
