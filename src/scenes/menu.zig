const std = @import("std");
const CONF = @import("../config.zig").CONF;
const DB16 = @import("../palette.zig").DB16;
const Fui = @import("../fui.zig").Fui;
const PIVOTS = @import("../fui.zig").PIVOTS;
const State = @import("../state.zig").State;
const StateMachine = @import("../state.zig").StateMachine;
const Vec2 = @import("../math.zig").Vec2;
const Mouse = @import("../math.zig").Mouse;
const MenuItem = struct {
    text: [:0]const u8,
    color: u32,
    target_state: State,
};

pub const MenuScene = struct {
    fui: Fui,
    sm: *StateMachine,
    menu_items: []const MenuItem,
    pub fn init(fui: Fui, sm: *StateMachine) MenuScene {
        return MenuScene{
            .fui = fui,
            .sm = sm,
            .menu_items = &[_]MenuItem{
                .{ .text = "Editor", .color = CONF.COLOR_MENU_NORMAL, .target_state = State.editor },
                .{ .text = "Tileset", .color = CONF.COLOR_MENU_NORMAL, .target_state = State.tileset },
                .{ .text = "Preview", .color = CONF.COLOR_MENU_NORMAL, .target_state = State.preview },
                .{ .text = "About", .color = CONF.COLOR_MENU_SECONDARY, .target_state = State.about },
            },
        };
    }
    pub fn draw(self: *MenuScene, mouse: Mouse) void {
        const cx: i32 = self.fui.pivots[PIVOTS.CENTER].x;
        const cy: i32 = self.fui.pivots[PIVOTS.CENTER].y - 96;

        const welcome = "Welcome to the indexed pixelart editor!";
        self.fui.draw_text(CONF.THE_NAME, cx - self.fui.text_center(CONF.THE_NAME, CONF.FONT_BIG).x, cy, CONF.FONT_BIG, CONF.COLOR_PRIMARY);
        self.fui.draw_text(welcome, cx - self.fui.text_center(welcome, CONF.FONT_DEFAULT_SIZE).x, cy + 44, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_PRIMARY);

        var y: i32 = cy + 128;
        for (self.menu_items) |item| {
            if (self.fui.button(cx - 100, y, 200, 32, item.text, item.color, mouse)) {
                self.sm.goTo(item.target_state);
            }
            y += 38;
        }
    }
};
