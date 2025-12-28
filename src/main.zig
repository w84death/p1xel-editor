const std = @import("std");
const c = @cImport({
    @cInclude("fenster.h");
});
const CONF = @import("config.zig").CONF;
const PIVOTS = @import("ui.zig").PIVOTS;
const DB16 = @import("palette.zig").DB16;
const Palette = @import("palette.zig").Palette;
const StateMachine = @import("state.zig").StateMachine;
const State = @import("state.zig").State;
const Tiles = @import("tiles.zig").Tiles;
const Vfx = @import("vfx.zig").Vfx;
const Fui = @import("fui.zig").Fui;
const MenuScene = @import("scenes/menu.zig").MenuScene;
const EditScene = @import("scenes/edit.zig").EditScene;
const AboutScene = @import("scenes/about.zig").AboutScene;
const TilesetScene = @import("scenes/tileset.zig").TilesetScene;
const PreviewScene = @import("scenes/preview.zig").PreviewScene;

pub fn main() void {
    var buf: [CONF.SCREEN_W * CONF.SCREEN_H]u32 = undefined;
    var f = std.mem.zeroInit(c.fenster, .{
        .width = CONF.SCREEN_W,
        .height = CONF.SCREEN_H,
        .title = CONF.THE_NAME,
        .buf = &buf[0],
    });
    _ = c.fenster_open(&f);
    defer c.fenster_close(&f);
    var fui = Fui.init(&buf);
    var sm = StateMachine.init(State.main_menu);
    var pal = Palette.init();
    pal.loadPalettesFromFile();
    var tiles = Tiles.init(fui, &pal);
    tiles.loadTilesFromFile();
    // var menu = MenuScene.init(fui, &sm);
    // var edit = EditScene.init(fui, &sm, &pal, &tiles);
    // const about = AboutScene.init(fui, &sm);
    // var tileset = TilesetScene.init(fui, &sm, &pal, &tiles, &edit);
    // var vfx = try Vfx.init();
    // var preview = PreviewScene.init(fui, &sm, &edit, &pal, &tiles);
    // preview.loadPreviewFromFile();

    const shouldClose = false;
    var now: i64 = c.fenster_time();
    while (!shouldClose and c.fenster_loop(&f) == 0) {
        sm.update();
        fui.clear_background(CONF.COLOR_BG);

        if (f.keys[27] != 0) {
            break;
        }

        const diff: i64 = 1000 / 60 - (c.fenster_time() - now);
        if (diff > 0) {
            c.fenster_sleep(diff);
        }
        now = c.fenster_time();
    }
}
