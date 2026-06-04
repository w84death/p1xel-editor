const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    if (builtin.os.tag == .windows and builtin.cpu.arch == .x86) @cDefine("_X86_", "1");
    @cInclude("fenster.h");
});

const CONF = @import("engine/config.zig").CONF;
const Render = @import("engine/render.zig").Render;
const Sprite = @import("engine/sprites.zig").Sprite;
const SpriteSheet = @import("engine/sprites.zig").SpriteSheet;
const Fui = @import("engine/fui.zig").Fui(EditorTheme);
const Mouse = @import("engine/mouse.zig").Mouse;
const MouseButtons = @import("engine/mouse.zig").MouseButtons;
const StateMachine = @import("engine/state.zig").StateMachine;
const Project = @import("editor/project.zig").Project;
const editor_mod = @import("editor/main_editor.zig");
const MainEditor = editor_mod.MainEditor;
const State = editor_mod.State;
const TileLibrary = @import("editor/tile_library.zig").TileLibrary;

const EditorTheme = struct {
    pub const PIVOT_PADDING = 4;
    pub const FONT_DEFAULT = 1;
    pub const FONT_PERF = 1;
    pub const FONT_PERFLINE_HEIGHT = 9;
    pub const SHADOW_COLOR = 0x000000;
    pub const CROSSHAIR_COLOR = 0x404040;
    pub const MENU_FRAME_COLOR = 0x000000;
    pub const MENU_FRAME_HOVER_COLOR = 0xFFFFFF;
    pub const BUTTON_TEXT_COLOR = 0xEEEEEE;
    pub const BUTTON_TEXT_HOVER_COLOR = 0xFFFFFF;
    pub const SECONDARY_COLOR = 0xAAAAAA;
    pub const PRIMARY_COLOR = 0xFFFFFF;
    pub const LIGHT_COLOR = 0xFFFFFF;
    pub const POPUP_MSG_COLOR = 0xFFFFFF;
    pub const POPUP_COLOR = 0x202020;
    pub const OK_COLOR = 0x404040;
    pub const MENU_OK_COLOR = 0x606060;
    pub const YES_COLOR = 0x355A35;
    pub const MENU_YES_COLOR = 0x477A47;
    pub const NO_COLOR = 0x663333;
    pub const MENU_NO_COLOR = 0x884444;
};

const SpriteAssets = struct {
    logo_sheet: ?*SpriteSheet = null,
    icon_sheet: ?*SpriteSheet = null,
    logo: ?Sprite = null,
    icon: ?Sprite = null,

    fn load(allocator: std.mem.Allocator) SpriteAssets {
        var assets = SpriteAssets{};
        if (SpriteSheet.load(allocator, .{
            .name = "logo.bmp",
            .source = @embedFile("sprites/logo.bmp"),
            .tile_w = 100,
            .tile_h = 26,
        })) |sheet| {
            assets.logo_sheet = sheet;
            var sprite = Sprite.init(sheet, 0.14);
            sprite.set_animation(0, @min(@as(usize, 3), sheet.frame_count()), 0.14, true) catch {};
            assets.logo = sprite;
        } else |err| {
            std.log.err("failed to load logo sprite: {s}", .{@errorName(err)});
        }

        if (SpriteSheet.load(allocator, .{
            .name = "borowik.bmp",
            .source = @embedFile("sprites/borowik.bmp"),
            .tile_w = 32,
            .tile_h = 32,
        })) |sheet| {
            assets.icon_sheet = sheet;
            var sprite = Sprite.init(sheet, 0.12);
            sprite.set_animation(0, @min(@as(usize, 3), sheet.frame_count()), 0.12, true) catch {};
            assets.icon = sprite;
        } else |err| {
            std.log.err("failed to load borowik icon sprite: {s}", .{@errorName(err)});
        }
        return assets;
    }

    fn deinit(self: *SpriteAssets, allocator: std.mem.Allocator) void {
        if (self.logo_sheet) |sheet| {
            sheet.deinit();
            allocator.destroy(sheet);
        }
        if (self.icon_sheet) |sheet| {
            sheet.deinit();
            allocator.destroy(sheet);
        }
    }

    fn update(self: *SpriteAssets, dt: f32) void {
        if (self.logo) |*sprite| sprite.update(dt);
        if (self.icon) |*sprite| sprite.update(dt);
    }
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    const window_w = CONF.SCREEN_W * CONF.PIXEL_SCALE;
    const window_h = CONF.SCREEN_H * CONF.PIXEL_SCALE;
    const total_pixels: usize = @intCast(window_w * window_h);

    const raw_buf = try allocator.alloc(u32, total_pixels);
    defer allocator.free(raw_buf);
    @memset(raw_buf, 0);

    var window = std.mem.zeroInit(c.fenster, .{
        .width = window_w,
        .height = window_h,
        .title = CONF.THE_NAME,
        .buf = raw_buf.ptr,
        .fullscreen = 0,
    });

    _ = c.fenster_open(&window);
    defer c.fenster_close(&window);

    var renderer = Render.init_scaled(raw_buf, CONF.SCREEN_W, CONF.SCREEN_H, CONF.PIXEL_SCALE);
    defer renderer.deinit();

    var assets = SpriteAssets.load(allocator);
    defer assets.deinit(allocator);

    var fui = Fui.init(CONF.SCREEN_W, CONF.SCREEN_H);
    var mouse_buttons = MouseButtons.init();
    var sm = StateMachine(State).init(.splash);
    var project = Project.loadOrDefault();
    var editor = MainEditor{};
    var library = TileLibrary{};
    var esc_lock = false;

    while (c.fenster_loop(&window) == 0) {
        renderer.perf_begin_sim();
        renderer.begin_frame();
        renderer.clear_background(0x1B1B1B);

        const mouse = mouse_buttons.update(@divFloor(window.x, CONF.PIXEL_SCALE), @divFloor(window.y, CONF.PIXEL_SCALE), @intCast(window.mouse));
        assets.update(renderer.dt);

        if (esc_lock and window.keys[27] == 0) {
            esc_lock = false;
        } else if (!esc_lock and window.keys[27] != 0) {
            esc_lock = true;
            if (sm.current == .editor) sm.go_to(.quit) else sm.go_to(.editor);
        }

        switch (sm.current) {
            .splash => drawSplash(&fui, &renderer, &assets, mouse, &sm),
            .editor => editor.draw(&fui, &renderer, &project, mouse, &sm),
            .tile_library => library.draw(&fui, &renderer, &project, &editor, mouse, &sm),
            .quit => break,
        }
        sm.update();
        if (sm.current == .quit) break;

        renderer.perf_begin_draw();
        drawGlobalOverlay(&fui, &renderer, &assets);
        renderer.perf_begin_present();
        renderer.present();
        renderer.perf_end_present();
        renderer.cap_frame(CONF.TARGET_FPS);
    }

    try project.save();
}

fn drawSplash(fui: *Fui, renderer: *Render, assets: *SpriteAssets, mouse: Mouse, sm: anytype) void {
    const cx = @divFloor(CONF.SCREEN_W, 2);
    const cy = @divFloor(CONF.SCREEN_H, 2);

    renderer.draw_rect(0, 0, CONF.SCREEN_W, CONF.SCREEN_H, 0x111111);
    if (assets.logo) |*logo| logo.draw(renderer, cx - 50, cy - 96);
    if (assets.icon) |*icon| icon.draw(renderer, cx - 16, cy - 34);
    drawCenteredText(fui, renderer, "P1xel Editor", cx, cy + 28, 3, 0xFFFFFF);
    drawCenteredText(fui, renderer, "GameBoy Color Edition", cx, cy + 66, 2, 0xDAD45E);
    drawCenteredText(fui, renderer, "Click anywhere to start", cx, cy + 108, 2, 0xAAAAAA);

    if (mouse.just_pressed or mouse.just_right_pressed) sm.go_to(.editor);
}

fn drawGlobalOverlay(fui: *Fui, renderer: *Render, assets: *SpriteAssets) void {
    const icon_x = fui.pivotX(.bottom_right) - 32;
    const icon_y = fui.pivotY(.bottom_right) - 32;
    if (assets.icon) |*icon| icon.draw(renderer, icon_x, icon_y);
    renderer.draw_perf_overlay_at(fui, EditorTheme, icon_x - 116, icon_y - 4);
}

fn drawCenteredText(fui: *Fui, renderer: *Render, text: []const u8, center_x: i32, y: i32, scale: i32, color: u32) void {
    const x = center_x - @divFloor(fui.text_length(text, scale), 2);
    fui.draw_text(renderer, text, x, y, scale, color);
}
