const std = @import("std");
const CONF = @import("config.zig").CONF;
const DB16 = @import("palette.zig").DB16;
const Fui = @import("fui.zig").Fui;
const PIVOTS = @import("fui.zig").PIVOTS;
const State = @import("state.zig").State;
const StateMachine = @import("state.zig").StateMachine;
const Vec2 = @import("math.zig").Vec2;
const Mouse = @import("math.zig").Mouse;
const NavButton = struct {
    label: [:0]const u8,
    state: State,
    width: i32,
};
pub const NavPanel = struct {
    fui: Fui,
    sm: *StateMachine,
    locked: bool = false,
    pub fn init(fui: Fui, sm: *StateMachine) NavPanel {
        return NavPanel{
            .fui = fui,
            .sm = sm,
            .locked = false,
        };
    }
    pub fn draw(self: *NavPanel, mouse: Mouse) void {
        const button_w: i32 = 180;
        const button_h: i32 = 32;
        const gap: i32 = 32;
        const nav_w: i32 = CONF.SCREEN_W;
        const nav_h: i32 = 64;
        const nav: Vec2 = Vec2.init(self.fui.pivots[PIVOTS.TOP_LEFT].x, self.fui.pivots[PIVOTS.TOP_LEFT].y);
        self.fui.draw_rect(0, 0, nav_w, nav_h, CONF.COLOR_NAV_BG);
        self.fui.draw_hline(0, nav_h, nav_w, CONF.COLOR_NAV_FRAME);
        const buttons = [_]NavButton{
            .{ .label = "< Menu", .state = State.main_menu, .width = button_w - 32 },
            .{ .label = "Editor", .state = State.editor, .width = button_w },
            .{ .label = "Tileset", .state = State.tileset, .width = button_w },
            .{ .label = "Palettes", .state = State.palettes, .width = button_w },
            .{ .label = "Preview", .state = State.preview, .width = button_w },
        };
        var nav_step = nav.x;
        for (buttons) |btn| {
            if (self.sm.is(btn.state)) {
                self.fui.draw_rect(nav_step - 16, nav.y - 12, btn.width + 32, button_h + 24, CONF.COLOR_BG);
            }
            var color: u32 = undefined;
            if (self.sm.is(btn.state)) {
                color = CONF.COLOR_MENU_SECONDARY;
            } else {
                color = CONF.COLOR_MENU_NORMAL;
            }
            if (self.fui.button(nav_step, nav.y, btn.width, button_h, btn.label, color, mouse) and !self.locked) {
                self.sm.goTo(btn.state);
            }
            nav_step += btn.width + gap;
        }
    }
};
