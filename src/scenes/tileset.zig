const std = @import("std");
const rl = @import("raylib");
const CONF = @import("../config.zig").CONF;
const DB16 = @import("../palette.zig").DB16;
const Palette = @import("../palette.zig").Palette;
const Ui = @import("../ui.zig").UI;
const PIVOTS = @import("../ui.zig").PIVOTS;
const State = @import("../state.zig").State;
const StateMachine = @import("../state.zig").StateMachine;
const Tiles = @import("../tiles.zig").Tiles;

pub const TilesetScene = struct {
    ui: Ui,
    sm: *StateMachine,
    palette: *Palette,
    tiles: *Tiles,
    pub fn init(ui: Ui, sm: *StateMachine, pal: *Palette, tiles: *Tiles) TilesetScene {
        return TilesetScene{
            .ui = ui,
            .sm = sm,
            .tiles = tiles,
            .palette = pal,
        };
    }
    pub fn draw(self: *TilesetScene, mouse: rl.Vector2) void {
        const px = self.ui.pivots[PIVOTS.TOP_LEFT].x;
        const py = self.ui.pivots[PIVOTS.TOP_LEFT].y;
        if (self.ui.button(px, py, 80, 32, "< Menu", DB16.BLUE, mouse)) {
            self.sm.goTo(State.main_menu);
        }

        const tiles_x: i32 = @intFromFloat(px);
        const tiles_y: i32 = @intFromFloat(py + 64);
        const tiles_in_row: usize = 16;
        const scale: i32 = 4;
        inline for (0..CONF.MAX_TILES) |i| {
            const x_shift: i32 = @intCast(@mod(i, tiles_in_row) * (CONF.SPRITE_SIZE * scale + 8));
            const x: i32 = tiles_x + x_shift;
            const y: i32 = @divFloor(i, tiles_in_row) * (CONF.SPRITE_SIZE * scale + 8);
            const size: i32 = CONF.SPRITE_SIZE * scale + 2;
            if (i < self.tiles.count) {
                _ = self.ui.button(@floatFromInt(x), @floatFromInt(tiles_y + y), size, size, "", DB16.BLACK, mouse);
                self.tiles.draw_tile(i, x, tiles_y + y, scale);
            } else {
                if (i == self.tiles.count) {
                    _ = self.ui.button(@floatFromInt(x), @floatFromInt(tiles_y + y), size, size, "+", DB16.DARK_GREEN, mouse);
                } else {
                    const rec = rl.Rectangle.init(@floatFromInt(x), @floatFromInt(tiles_y + y), @floatFromInt(size), @floatFromInt(size));
                    rl.drawRectangleRounded(rec, CONF.CORNER_RADIUS, CONF.CORNER_QUALITY, DB16.DARK_GRAY);
                }
            }
        }
    }
};
