const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    if (builtin.os.tag == .windows and builtin.cpu.arch == .x86) @cDefine("_X86_", "1");
    @cInclude("fenster.h");
});

const CONF = @import("engine/config.zig").CONF;
const Render = @import("engine/render.zig").Render;
const Fui = @import("engine/fui.zig").Fui(EditorTheme);
const Mouse = @import("engine/mouse.zig").Mouse;
const MouseButtons = @import("engine/mouse.zig").MouseButtons;
const StateMachine = @import("engine/state.zig").StateMachine;
const Project = @import("editor/project.zig").Project;
const editor_mod = @import("editor/main_editor.zig");
const MainEditor = editor_mod.MainEditor;
const State = editor_mod.State;
const TileLibrary = @import("editor/tile_library.zig").TileLibrary;
const MapEditor = @import("editor/map_editor.zig").MapEditor;
const views = @import("editor/views.zig");
const editor_ui = @import("editor/ui.zig");

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

const SplashStyle = struct {
    const bg = 0x111111;
    const title = 0xFFFFFF;
    const muted = 0xAAAAAA;
    const warn = 0xDAD45E;
    const accent = 0x7EDB1E;
    const button_shadow = 0x050505;
    const button = 0x202020;
    const button_hover = 0x355A35;
    const button_border = 0x404040;
};

const AppState = struct {
    fui: Fui,
    mouse_buttons: MouseButtons,
    sm: StateMachine(State),
    project: Project,
    editor: MainEditor,
    map_editor: MapEditor,
    library: TileLibrary,
    esc_lock: bool = false,

    fn init() AppState {
        return .{
            .fui = Fui.init(CONF.SCREEN_W, CONF.SCREEN_H),
            .mouse_buttons = MouseButtons.init(),
            .sm = StateMachine(State).init(.splash),
            .project = Project.loadOrDefault(),
            .editor = .{},
            .map_editor = .{},
            .library = .{},
        };
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
        .fullscreen = CONF.FULLSCREEN,
    });

    if (c.fenster_open(&window) != 0) return error.WindowOpenFailed;
    defer c.fenster_close(&window);

    var renderer = Render.init_scaled(raw_buf, CONF.SCREEN_W, CONF.SCREEN_H, CONF.PIXEL_SCALE);
    defer renderer.deinit();

    var app = AppState.init();

    while (c.fenster_loop(&window) == 0) {
        const mouse = beginFrame(&renderer, &app.mouse_buttons, &window);
        handleEscape(&app.sm, &app.esc_lock, window.keys[27] != 0);

        renderer.perf_begin_draw();
        const previous_state = app.sm.current;
        if (!drawCurrentState(&app, &renderer, mouse)) break;

        app.sm.update();
        handleStateTransition(previous_state, &app);
        if (app.sm.current == .quit) break;

        if (app.sm.current != .splash) drawGlobalOverlay(&app.fui, &renderer);
        presentFrame(&renderer);
    }

    if (app.project.dirty) try app.project.save();
}

fn beginFrame(renderer: *Render, mouse_buttons: *MouseButtons, window: *const c.fenster) Mouse {
    renderer.perf_begin_sim();
    renderer.begin_frame();
    return mouse_buttons.update(@divFloor(window.x, CONF.PIXEL_SCALE), @divFloor(window.y, CONF.PIXEL_SCALE), @intCast(window.mouse));
}

fn handleEscape(sm: *StateMachine(State), esc_lock: *bool, esc_pressed: bool) void {
    if (esc_lock.* and !esc_pressed) {
        esc_lock.* = false;
        return;
    }
    if (esc_lock.* or !esc_pressed) return;

    esc_lock.* = true;
    sm.go_to(if (sm.current == .editor or sm.current == .map_editor) .quit else .editor);
}

fn drawCurrentState(app: *AppState, renderer: *Render, mouse: Mouse) bool {
    switch (app.sm.current) {
        .splash => drawSplash(&app.fui, renderer, &app.editor, mouse, &app.sm),
        .editor => app.editor.draw(&app.fui, renderer, &app.project, mouse, &app.sm),
        .tile_library => app.library.draw(&app.fui, renderer, &app.project, &app.editor, mouse, &app.sm),
        .map_editor => app.map_editor.draw(&app.fui, renderer, &app.project, &app.editor, mouse, &app.sm),
        .quit => return false,
    }
    return true;
}

fn handleStateTransition(previous_state: State, app: *AppState) void {
    if (previous_state == app.sm.current) return;

    if (previous_state == .map_editor and app.sm.current != .map_editor) {
        app.editor.ui_cache_dirty = true;
        app.map_editor.invalidateCache();
    }
    if (previous_state != .map_editor and app.sm.current == .map_editor) {
        if (previous_state == .tile_library) app.map_editor.syncLibrarySelection(&app.project);
        app.map_editor.invalidateCache();
    }
}

fn presentFrame(renderer: *Render) void {
    renderer.perf_begin_present();
    renderer.present();
    renderer.perf_end_present();
    renderer.cap_frame(CONF.TARGET_FPS);
}

fn drawSplash(fui: *Fui, renderer: *Render, editor: *MainEditor, mouse: Mouse, sm: anytype) void {
    const cx = @divFloor(CONF.SCREEN_W, 2);
    const cy = @divFloor(CONF.SCREEN_H, 2);

    renderer.draw_rect(0, 0, CONF.SCREEN_W, CONF.SCREEN_H, SplashStyle.bg);
    drawCenteredText(fui, renderer, CONF.THE_NAME, cx, cy - 44, 3, SplashStyle.title);
    drawCenteredText(fui, renderer, CONF.VERSION, cx, cy - 14, 1, SplashStyle.muted);
    drawCenteredText(fui, renderer, "GameBoy Color Edition", cx, cy + 8, 2, SplashStyle.warn);
    drawCenteredText(fui, renderer, "SHAREWARE VERSION", cx, cy + 82, 3, SplashStyle.accent);

    const start_clicked = drawSplashButton(fui, renderer, mouse, cx, cy + 130);

    drawCenteredText(fui, renderer, "Powered by Borowik Engine", cx, CONF.SCREEN_H - 58, 1, SplashStyle.warn);

    if (start_clicked) {
        editor.suppress_canvas_paint_until_mouse_up = true;
        sm.go_to(.editor);
    }
}

fn drawSplashButton(fui: *Fui, renderer: *Render, mouse: Mouse, center_x: i32, y: i32) bool {
    const button_w: i32 = 220;
    const button_h: i32 = 44;
    const x = center_x - @divFloor(button_w, 2);
    const hovered = views.hover(mouse, x, y, button_w, button_h);

    renderer.draw_rect(x + 3, y + 3, button_w, button_h, SplashStyle.button_shadow);
    renderer.draw_rect(x, y, button_w, button_h, if (hovered) SplashStyle.button_hover else SplashStyle.button);
    renderer.draw_rect_lines(x, y, button_w, button_h, if (hovered) SplashStyle.accent else SplashStyle.button_border);
    drawCenteredText(fui, renderer, "START", center_x, y + 15, 1, if (hovered) SplashStyle.title else SplashStyle.muted);

    return hovered and (mouse.just_pressed or mouse.just_right_pressed);
}

fn drawGlobalOverlay(fui: *Fui, renderer: *Render) void {
    const save_button_x: i32 = CONF.SCREEN_W - editor_ui.Layout.side_x - 192;
    renderer.draw_fps_overlay_at(fui, EditorTheme, save_button_x - 120, editor_ui.Layout.top_y + 38);
}

fn drawCenteredText(fui: *Fui, renderer: *Render, text: []const u8, center_x: i32, y: i32, scale: i32, color: u32) void {
    const x = center_x - @divFloor(fui.text_length(text, scale), 2);
    fui.draw_text(renderer, text, x, y, scale, color);
}
