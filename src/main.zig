const std = @import("std");
const rl = @import("raylib");
const math = @import("math.zig");
const Ui = @import("ui.zig").UI;
const PIVOTS = @import("ui.zig").PIVOTS;
const DB16 = @import("palette.zig").DB16;
const CONF = @import("config.zig").CONF;
const StateMachine = @import("state_machine.zig").StateMachine;
const State = @import("state_machine.zig").State;
const Menu = @import("scenes/menu.zig").Menu;
const Edit = @import("scenes/edit.zig").Edit;
const About = @import("scenes/about.zig").About;

pub fn main() !void {
    const ui = Ui.init(CONF.THE_NAME, DB16.NAVY_BLUE, DB16.WHITE, DB16.BLUE);
    var sm = StateMachine.init(State.main_menu);
    const menu = Menu.init(ui, &sm);
    const edit = Edit.init(ui, &sm);
    const about = About.init(ui, &sm);

    ui.createWindow();
    defer ui.closeWindow();

    rl.setTargetFPS(60);

    var shouldClose = false;
    while (!rl.windowShouldClose() and !shouldClose) {
        const mouse = rl.getMousePosition();
        sm.update();
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(ui.bg_color);

        switch (sm.current) {
            State.main_menu => {
                menu.draw(mouse);
            },
            State.editor => {
                edit.draw(mouse);
            },
            State.about => {
                about.draw(mouse);
            },
            else => {},
        }

        if (ui.button(ui.pivots[PIVOTS.TOP_RIGHT].x - 80, ui.pivots[PIVOTS.TOP_RIGHT].y, 80, 32, "Quit", DB16.RED, mouse)) {
            shouldClose = true;
        }
    }
}
