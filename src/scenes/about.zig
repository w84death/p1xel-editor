const std = @import("std");
const rl = @import("raylib");
const CONF = @import("../config.zig").CONF;
const DB16 = @import("../palette.zig").DB16;
const Ui = @import("../ui.zig").UI;
const PIVOTS = @import("../ui.zig").PIVOTS;
const State = @import("../state.zig").State;
const StateMachine = @import("../state.zig").StateMachine;

pub const AboutScreen = struct {
    ui: Ui,
    sm: *StateMachine,
    pub fn init(ui: Ui, sm: *StateMachine) AboutScreen {
        return AboutScreen{ .ui = ui, .sm = sm };
    }
    pub fn draw(self: AboutScreen, mouse: rl.Vector2) void {
        const px = self.ui.pivots[PIVOTS.TOP_LEFT].x;
        const py = self.ui.pivots[PIVOTS.TOP_LEFT].y;
        if (self.ui.button(px, py, 80, 32, "< Menu", DB16.BLUE, mouse)) {
            self.sm.goTo(State.main_menu);
        }

        const ax: i32 = @intFromFloat(px);
        var ay: i32 = @intFromFloat(py + 64);
        const lines = [_][:0]const u8{ "P1Xel Editor is an indexed (color palette) pixel-art editor", "made for an assembly game engine using a proprietary file format.", "Each sprite is 16x16 pixels with up to 4 colors per palette.", "The first color can be used as transparent (black in the first palette slot).", "Palette consists of 16 colors from DawnBringer's palette.", "", "Software made in Zig with RayLib.", "Written in Zed editor.", "Consulted with Grok Code Fast 1.", "Made by Krzysztof Krystian Jankowski.", "", "MIT Licence." };

        const line_height = 24;
        for (lines) |line| {
            rl.drawText(line, ax, ay, CONF.DEFAULT_FONT_SIZE, self.ui.primary_color);
            ay += line_height;
        }
    }
};
