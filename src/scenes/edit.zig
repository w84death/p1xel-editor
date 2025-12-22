const std = @import("std");
const rl = @import("raylib");
const CONF = @import("../config.zig").CONF;
const DB16 = @import("../palette.zig").DB16;
const Palette = @import("../palette.zig").Palette;
const Ui = @import("../ui.zig").UI;
const PIVOTS = @import("../ui.zig").PIVOTS;
const State = @import("../state.zig").State;
const StateMachine = @import("../state.zig").StateMachine;

const Canvas = struct {
    width: i32,
    height: i32,
    x: i32,
    y: i32,
    data: [CONF.SPRITE_SIZE][CONF.SPRITE_SIZE]u8,
};

const Popup = enum {
    confirm_clear,
};

pub const Edit = struct {
    ui: Ui,
    sm: *StateMachine,
    canvas: Canvas,
    palette: Palette,
    locked: bool,
    popup: ?Popup,

    pub fn init(ui: Ui, sm: *StateMachine) Edit {
        const ix: i32 = @intFromFloat(ui.pivots[PIVOTS.TOP_LEFT].x + CONF.CANVAS_X);
        const iy: i32 = @intFromFloat(ui.pivots[PIVOTS.TOP_LEFT].y + CONF.CANVAS_Y);
        var pal = Palette.init();
        pal.loadPalettesFromFile();
        std.debug.print("Palettes loaded: {d}\n", .{pal.count});
        return Edit{
            .ui = ui,
            .sm = sm,
            .canvas = Canvas{
                .width = CONF.SPRITE_SIZE * CONF.GRID_SIZE,
                .height = CONF.SPRITE_SIZE * CONF.GRID_SIZE,
                .x = ix,
                .y = iy,
                .data = [_][CONF.SPRITE_SIZE]u8{[_]u8{0} ** CONF.SPRITE_SIZE} ** CONF.SPRITE_SIZE,
            },
            .palette = pal,
            .locked = false,
            .popup = null,
        };
    }
    pub fn handleKeyboard(self: *Edit) void {
        if (self.locked) return;
        const key = rl.getKeyPressed();
        switch (key) {
            rl.KeyboardKey.one => self.palette.swatch = 0,
            rl.KeyboardKey.two => self.palette.swatch = 1,
            rl.KeyboardKey.three => self.palette.swatch = 2,
            rl.KeyboardKey.four => self.palette.swatch = 3,
            else => {},
        }
    }
    pub fn handleMouse(self: *Edit, mouse: rl.Vector2) void {
        if (self.locked) return;

        if (self.sm.hot and rl.isMouseButtonReleased(rl.MouseButton.left)) {
            self.sm.hot = false;
        } else if (self.sm.hot) {
            return;
        }

        const mx: i32 = @intFromFloat(mouse.x);
        const my: i32 = @intFromFloat(mouse.y);
        const mouse_cell_x: i32 = @divFloor(mx - self.canvas.x, CONF.GRID_SIZE);
        const mouse_cell_y: i32 = @divFloor(my - self.canvas.y, CONF.GRID_SIZE);

        if ((rl.isMouseButtonDown(rl.MouseButton.left) or rl.isMouseButtonDown(rl.MouseButton.right))) {
            var color: u8 = self.palette.swatch;
            if (mouse_cell_x >= 0 and mouse_cell_x < CONF.SPRITE_SIZE and
                mouse_cell_y >= 0 and mouse_cell_y < CONF.SPRITE_SIZE)
            {
                if (rl.isMouseButtonDown(rl.MouseButton.right)) color = 0;
                self.canvas.data[@intCast(mouse_cell_y)][@intCast(mouse_cell_x)] = color;
            }
        }
    }
    pub fn clearCanvas(self: *Edit) void {
        self.canvas.data = [_][CONF.SPRITE_SIZE]u8{[_]u8{0} ** CONF.SPRITE_SIZE} ** CONF.SPRITE_SIZE;
    }
    pub fn draw(self: *Edit, mouse: rl.Vector2) void {
        const nav: rl.Vector2 = rl.Vector2.init(self.ui.pivots[PIVOTS.TOP_LEFT].x, self.ui.pivots[PIVOTS.TOP_LEFT].y);
        if (self.ui.button(nav.x, nav.y, 80, 32, "< Menu", DB16.BLUE, mouse)) {
            self.sm.goTo(State.main_menu);
        }

        if (self.ui.button(nav.x + 88, nav.y, 160, 32, "Clear canvas", DB16.RED, mouse)) {
            self.locked = true;
            self.popup = Popup.confirm_clear;
        }
        if (self.ui.button(nav.x + 88 + 160 + 8, nav.y, 80, 32, "Save", DB16.GREEN, mouse)) {
            self.palette.savePalettesToFile();
        }

        for (0..CONF.SPRITE_SIZE) |y| {
            for (0..CONF.SPRITE_SIZE) |x| {
                const idx = self.canvas.data[y][x];
                const db16_idx = self.palette.current[idx];
                const xx: i32 = @intCast(x * CONF.GRID_SIZE);
                const yy: i32 = @intCast(y * CONF.GRID_SIZE);
                var color: rl.Color = undefined;

                if (idx == 0 and self.palette.current[0] == 0) {
                    const checker = (x + y) % 2 == 0;
                    color = if (checker) rl.getColor(0x33333310) else rl.getColor(0xAAAAAA10);
                } else {
                    color = self.palette.getColorFromIndex(db16_idx);
                }
                rl.drawRectangle(
                    self.canvas.x + xx,
                    self.canvas.y + yy,
                    CONF.GRID_SIZE,
                    CONF.GRID_SIZE,
                    color,
                );
            }
        }

        rl.drawRectangleLines(
            self.canvas.x,
            self.canvas.y,
            self.canvas.width,
            self.canvas.height,
            DB16.STEEL_BLUE,
        );

        const px = self.canvas.width + 48;
        const py = self.canvas.y;

        const dw: i32 = @divFloor(self.canvas.height, 4);

        self.draw_preview(px, py, 4, DB16.BLACK);
        self.draw_preview(px + dw + 8, py, 4, DB16.WHITE);

        if (self.popup == Popup.confirm_clear) {
            const result = self.ui.yesNoPopup("Clear canvas?", mouse);
            if (result) |res| {
                if (res) {
                    self.clearCanvas();
                }
                self.popup = null;
                self.locked = false;
                self.sm.hot = true;
            }
        }
    }

    fn draw_preview(self: Edit, x: i32, y: i32, down_scale: i32, background: rl.Color) void {
        const w: i32 = @divFloor(self.canvas.width, down_scale);
        const h: i32 = @divFloor(self.canvas.height, down_scale);
        rl.drawRectangle(x, y, w, h, background);

        for (0..CONF.SPRITE_SIZE) |py| {
            for (0..CONF.SPRITE_SIZE) |px| {
                const idx = self.canvas.data[py][px];
                const db16_idx = self.palette.current[idx];
                const scaled_grid_size: i32 = @divFloor(CONF.GRID_SIZE, down_scale);
                const xx: i32 = @intCast(px);
                const yy: i32 = @intCast(py);

                if (!(idx == 0 and self.palette.current[0] == 0)) {
                    rl.drawRectangle(
                        x + xx * scaled_grid_size,
                        y + yy * scaled_grid_size,
                        scaled_grid_size,
                        scaled_grid_size,
                        self.palette.getColorFromIndex(db16_idx),
                    );
                }
            }
        }

        rl.drawRectangleLines(x, y, w, h, DB16.STEEL_BLUE);
    }

    fn draw_palette() void {}

    fn draw_swatches() void {}
};
