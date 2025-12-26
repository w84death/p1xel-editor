const std = @import("std");
const rl = @import("raylib");
const CONF = @import("../config.zig").CONF;
const DB16 = @import("../palette.zig").DB16;
const Ui = @import("../ui.zig").UI;
const PIVOTS = @import("../ui.zig").PIVOTS;
const State = @import("../state.zig").State;
const StateMachine = @import("../state.zig").StateMachine;

const MenuItem = struct {
    text: [:0]const u8,
    color: rl.Color,
    target_state: State,
};

pub const MenuScreen = struct {
    ui: Ui,
    sm: *StateMachine,
    menu_items: []const MenuItem,
    pub fn init(ui: Ui, sm: *StateMachine) MenuScreen {
        return MenuScreen{
            .ui = ui,
            .sm = sm,
            .menu_items = &[_]MenuItem{
                .{ .text = "Editor", .color = CONF.COLOR_MENU_NORMAL, .target_state = State.editor },
                .{ .text = "Tileset", .color = CONF.COLOR_MENU_NORMAL, .target_state = State.tileset },
                .{ .text = "About", .color = CONF.COLOR_MENU_SECONDARY, .target_state = State.about },
            },
        };
    }
    pub fn draw(self: *MenuScreen, mouse: rl.Vector2) void {
        const cx: i32 = @intFromFloat(self.ui.pivots[PIVOTS.CENTER].x);
        const cy: i32 = @intFromFloat(self.ui.pivots[PIVOTS.CENTER].y - 96);
        const fx: f32 = self.ui.pivots[PIVOTS.CENTER].x;
        const fy: f32 = self.ui.pivots[PIVOTS.CENTER].y - 96;

        const welcome = "Welcome to the indexed pixelart editor!";
        rl.drawText(CONF.THE_NAME, cx - @divFloor(rl.measureText(CONF.THE_NAME, CONF.FONT_BIG), 2), cy, CONF.FONT_BIG, CONF.COLOR_PRIMARY);
        rl.drawText(welcome, cx - @divFloor(rl.measureText(welcome, CONF.FONT_DEFAULT_SIZE), 2), cy + 44, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);

        var y: f32 = fy + 128;
        for (self.menu_items) |item| {
            if (self.ui.button(fx - 100, y, 200, 32, item.text, item.color, mouse)) {
                self.sm.goTo(item.target_state);
            }
            y += 38;
        }
    }
};
