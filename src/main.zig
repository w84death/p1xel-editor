const std = @import("std");
const rl = @import("raylib");
const Ui = @import("ui.zig").UI;
const PIVOTS = @import("ui.zig").PIVOTS;
const DB16 = @import("palette.zig").DB16;
const Palette = @import("palette.zig").Palette;
const CONF = @import("config.zig").CONF;
const StateMachine = @import("state.zig").StateMachine;
const State = @import("state.zig").State;
const Tiles = @import("tiles.zig").Tiles;
const Vfx = @import("vfx.zig").Vfx;
const MenuScene = @import("scenes/menu.zig").MenuScene;
const EditScene = @import("scenes/edit.zig").EditScene;
const AboutScene = @import("scenes/about.zig").AboutScene;
const TilesetScene = @import("scenes/tileset.zig").TilesetScene;
const PreviewScene = @import("scenes/preview.zig").PreviewScene;

pub fn main() !void {
    const ui = Ui.init(CONF.THE_NAME);
    var sm = StateMachine.init(State.main_menu);
    var pal = Palette.init();
    pal.loadPalettesFromFile();
    var tiles = Tiles.init(&pal);
    tiles.loadTilesFromFile();
    var menu = MenuScene.init(ui, &sm);
    var edit = EditScene.init(ui, &sm, &pal, &tiles);
    const about = AboutScene.init(ui, &sm);
    var tileset = TilesetScene.init(ui, &sm, &pal, &tiles, &edit);
    var vfx = try Vfx.init();
    var preview = PreviewScene.init(ui, &sm, &pal, &tiles);
    preview.loadPreviewFromFile();
    ui.createWindow();
    defer ui.closeWindow();

    rl.setTargetFPS(60);
    rl.setMouseCursor(rl.MouseCursor.crosshair);

    var shouldClose = false;
    while (!rl.windowShouldClose() and !shouldClose) {
        const mouse = rl.getMousePosition();
        const fps: f32 = @floatFromInt(rl.getFPS());
        const dt: f32 = 1000 / fps;

        sm.update();
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(CONF.COLOR_BG);
        switch (sm.current) {
            State.main_menu, State.about => vfx.draw(dt),
            else => {},
        }
        ui.drawCursorLines(mouse);

        switch (sm.current) {
            State.main_menu => {
                menu.draw(mouse);
            },
            State.editor => {
                edit.handleKeyboard();
                edit.handleMouse(mouse);
                try edit.draw(mouse);
            },
            State.preview => {
                preview.handleMouse(mouse);
                preview.draw(mouse);
            },
            State.about => {
                about.draw(mouse);
            },
            State.tileset => {
                try tileset.draw(mouse);
            },
        }

        // Quit
        if (ui.button(ui.pivots[PIVOTS.TOP_RIGHT].x - 80, ui.pivots[PIVOTS.TOP_RIGHT].y, 80, 32, "Quit", CONF.COLOR_MENU_SECONDARY, mouse)) {
            shouldClose = true;
        }
        // Version
        ui.drawVersion();
    }
}
