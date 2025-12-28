const std = @import("std");
const c = @cImport({
    @cInclude("fenster.h");
});
const CONF = @import("config.zig").CONF;
const PIVOTS = @import("fui.zig").PIVOTS;
const DB16 = @import("palette.zig").DB16;
const Palette = @import("palette.zig").Palette;
const StateMachine = @import("state.zig").StateMachine;
const State = @import("state.zig").State;
const Tiles = @import("tiles.zig").Tiles;
const Vfx = @import("vfx.zig").Vfx;
const Fui = @import("fui.zig").Fui;
const Vec2 = @import("math.zig").Vec2;
const Mouse = @import("math.zig").Mouse;
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
    var mouse_pressed = false;
    var mouse_lock = false;
    var fui = Fui.init(&buf);
    var sm = StateMachine.init(State.main_menu);
    var pal = Palette.init();
    pal.loadPalettesFromFile();
    var tiles = Tiles.init(fui, &pal);
    tiles.loadTilesFromFile();
    var vfx = Vfx.init(fui);
    var menu = MenuScene.init(fui, &sm);
    var about = AboutScene.init(fui, &sm);
    var edit = EditScene.init(fui, &sm, &pal, &tiles);
    var tileset = TilesetScene.init(fui, &sm, &pal, &tiles, &edit);
    var preview = PreviewScene.init(fui, &sm, &edit, &pal, &tiles);
    preview.loadPreviewFromFile();

    var shouldClose = false;
    var dt: f32 = 0.0;
    var now: i64 = c.fenster_time();
    while (!shouldClose and c.fenster_loop(&f) == 0) {
        const d: f32 = @floatFromInt(c.fenster_time() - now);
        dt = @as(f32, d / 1000.0);
        now = c.fenster_time();

        sm.update();
        fui.clear_background(CONF.COLOR_BG);
        switch (sm.current) {
            State.main_menu, State.about => vfx.draw(CONF.VFX_SNOW_COLOR, dt),
            else => {},
        }
        fui.draw_cursor_lines(Vec2.init(f.x, f.y));

        if (mouse_lock and mouse_pressed and f.mouse == 0) {
            mouse_pressed = false;
            mouse_lock = false;
        } else if (!mouse_lock and !mouse_pressed and f.mouse == 1) {
            mouse_pressed = true;
            mouse_lock = true;
        } else if (mouse_lock and !mouse_pressed and f.mouse == 0) {
            mouse_pressed = false;
            mouse_lock = false;
        } else {
            mouse_pressed = false;
        }
        const mouse = Mouse.init(f.x, f.y, mouse_pressed);

        switch (sm.current) {
            State.main_menu => {
                menu.draw(mouse);
            },
            State.editor => {
                edit.handleKeyboard(&f.keys);
                edit.handleMouse(mouse);
                try edit.draw(mouse);
            },
            State.tileset => {
                try tileset.draw(mouse);
            },
            State.preview => {
                preview.handleMouse(mouse);
                preview.draw(mouse);
            },
            State.about => {
                about.draw(mouse);
            },
        }

        if (f.keys[27] != 0) {
            break;
        }

        // Quit
        if (fui.button(fui.pivots[PIVOTS.TOP_RIGHT].x - 80, fui.pivots[PIVOTS.TOP_RIGHT].y, 80, 32, "Quit", CONF.COLOR_MENU_NORMAL, mouse)) {
            shouldClose = true;
        }
        // Version
        fui.draw_version();

        const frame_time_target: f64 = 1000.0 / 60.0; // ~16.666 ms
        const processing_time: f64 = @floatFromInt(c.fenster_time() - now);
        const sleep_ms: i64 = @intFromFloat(@max(0.0, frame_time_target - processing_time));
        if (sleep_ms > 0) {
            c.fenster_sleep(sleep_ms);
        }
    }
}
