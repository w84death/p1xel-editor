const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    if (builtin.os.tag == .windows and builtin.cpu.arch == .x86) @cDefine("_X86_", "1");
    @cInclude("stdlib.h");
    @cInclude("fenster.h");
});

const CONF = @import("engine/config.zig").CONF;
const Render = @import("engine/render.zig").Render;
const Fui = @import("engine/fui.zig").Fui(EditorTheme);
const Mouse = @import("engine/mouse.zig").Mouse;
const MouseButtons = @import("engine/mouse.zig").MouseButtons;
const StateMachine = @import("engine/state.zig").StateMachine;
const project_mod = @import("editor/project.zig");
const Project = project_mod.Project;
const MapTileAttr = project_mod.MapTileAttr;
const editor_mod = @import("editor/main_editor.zig");
const MainEditor = editor_mod.MainEditor;
const State = editor_mod.State;
const TileLibrary = @import("editor/tile_library.zig").TileLibrary;
const map_editor_mod = @import("editor/map_editor.zig");
const MapEditor = map_editor_mod.MapEditor;
const ArrowKeys = map_editor_mod.ArrowKeys;
const views = @import("editor/views.zig");
const editor_ui = @import("editor/ui.zig");
const logo_project_bytes = @embedFile("logo.p1x");
const PROJECT_SLOT_KEYS = [_]usize{ 112, 113, 114, 115 };

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
    const button_disabled = 0x151515;
    const button_border = 0x404040;
    const disabled_text = 0x666666;
};

const SplashLogo = struct {
    const tiles_w: i32 = 5;
    const tiles_h: i32 = 6;
    const scale: i32 = 6;
    const sprite_group_offset_tiles_x: i32 = 3;
    const sprite_group_tiles_w: i32 = 4;
    const sprite_group_tiles_h: i32 = 4;

    fn tilePixelSize() i32 {
        return CONF.TILE_SIDE * scale;
    }

    fn pixelWidth() i32 {
        return tiles_w * tilePixelSize();
    }

    fn pixelHeight() i32 {
        return tiles_h * tilePixelSize();
    }

    fn spriteGroupPixelWidth() i32 {
        return sprite_group_tiles_w * tilePixelSize();
    }

    fn spriteGroupPixelHeight() i32 {
        return sprite_group_tiles_h * tilePixelSize();
    }
};

const AppState = struct {
    fui: Fui,
    mouse_buttons: MouseButtons,
    sm: StateMachine(State),
    project: Project,
    editor: MainEditor,
    map_editor: MapEditor,
    library: TileLibrary,
    logo_project: Project,
    logo_available: bool,
    esc_lock: bool = false,
    project_slot_key_lock: [Project.FILE_SLOT_COUNT]bool = [_]bool{false} ** Project.FILE_SLOT_COUNT,
    splash_started_ms: i64,

    fn init() AppState {
        var logo_project = Project.init();
        const logo_available = blk: {
            logo_project.loadFromBytes(logo_project_bytes) catch |err| {
                std.debug.print("[splash] failed to load embedded logo.p1x: {s}\n", .{@errorName(err)});
                break :blk false;
            };
            break :blk true;
        };

        return .{
            .fui = Fui.init(CONF.SCREEN_W, CONF.SCREEN_H),
            .mouse_buttons = MouseButtons.init(),
            .sm = StateMachine(State).init(.splash),
            .project = Project.loadOrDefault(),
            .editor = .{},
            .map_editor = .{},
            .library = .{},
            .logo_project = logo_project,
            .logo_available = logo_available,
            .splash_started_ms = c.fenster_time(),
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
        app.project.tickAnimation();
        handleEscape(&app.sm, &app.esc_lock, window.keys[27] != 0);
        handleProjectSlotKeys(&app, &window);

        renderer.perf_begin_draw();
        const previous_state = app.sm.current;
        if (!drawCurrentState(&app, &renderer, mouse, &window)) break;

        app.sm.update();
        handleStateTransition(previous_state, &app);
        if (app.sm.current == .quit) break;

        if (app.sm.current != .splash) drawGlobalOverlay(&app.fui, &renderer, &app.project);
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
    if (sm.current == .splash) {
        sm.go_to(.quit);
        return;
    }
    sm.go_to(if (sm.current == .editor or sm.current == .map_editor) .quit else .editor);
}

fn handleProjectSlotKeys(app: *AppState, window: *const c.fenster) void {
    for (PROJECT_SLOT_KEYS, 0..) |key, index| {
        const pressed = window.keys[key] != 0;
        if (app.project_slot_key_lock[index]) {
            if (!pressed) app.project_slot_key_lock[index] = false;
            continue;
        }
        if (!pressed) continue;

        app.project_slot_key_lock[index] = true;
        switchProjectSlot(app, @intCast(index + 1));
        return;
    }
}

fn switchProjectSlot(app: *AppState, slot: u8) void {
    if (slot == app.project.activeFileSlot()) return;

    if (app.project.dirty) {
        app.project.save() catch {
            setProjectSlotInfo(app, projectSlotSaveFailedLabel(app.project.activeFileSlot()), editor_ui.Theme.danger);
            return;
        };
    }

    app.project = Project.loadOrDefaultSlot(slot);
    app.editor.line_start = null;
    app.editor.library_request = null;
    app.editor.suppress_canvas_paint_until_mouse_up = true;
    app.editor.ui_cache_dirty = true;
    app.editor.cached_canvas_revision = std.math.maxInt(u64);
    app.library.active = false;
    app.map_editor.syncLibrarySelection(&app.project);
    app.map_editor.invalidateCache();
    Project.rememberFileSlot(slot);
    setProjectSlotInfo(app, projectSlotLoadedLabel(slot), editor_ui.Theme.accent);
}

fn setProjectSlotInfo(app: *AppState, text: []const u8, color: u32) void {
    app.editor.setInfo(text, color);
    app.map_editor.setInfo(text, color);
}

fn projectSlotLoadedLabel(slot: u8) []const u8 {
    return switch (slot) {
        1 => "Project F1 loaded",
        2 => "Project F2 loaded",
        3 => "Project F3 loaded",
        else => "Project F4 loaded",
    };
}

fn projectSlotSaveFailedLabel(slot: u8) []const u8 {
    return switch (slot) {
        1 => "Save F1 failed",
        2 => "Save F2 failed",
        3 => "Save F3 failed",
        else => "Save F4 failed",
    };
}

fn drawCurrentState(app: *AppState, renderer: *Render, mouse: Mouse, window: *const c.fenster) bool {
    switch (app.sm.current) {
        .splash => drawSplash(&app.fui, renderer, &app.editor, mouse, &app.sm, &app.logo_project, app.logo_available, app.splash_started_ms),
        .editor => app.editor.draw(&app.fui, renderer, &app.project, mouse, &app.sm),
        .tile_library => app.library.draw(&app.fui, renderer, &app.project, &app.editor, mouse, &app.sm),
        .map_editor => app.map_editor.draw(&app.fui, renderer, &app.project, &app.editor, mouse, arrowKeys(window), &app.sm),
        .quit => return false,
    }
    return true;
}

fn arrowKeys(window: *const c.fenster) ArrowKeys {
    return .{
        .up = window.keys[17] != 0,
        .down = window.keys[18] != 0,
        .right = window.keys[19] != 0,
        .left = window.keys[20] != 0,
    };
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

fn drawSplash(fui: *Fui, renderer: *Render, editor: *MainEditor, mouse: Mouse, sm: anytype, logo_project: *const Project, logo_available: bool, splash_started_ms: i64) void {
    const cx = @divFloor(CONF.SCREEN_W, 2);
    const cy = @divFloor(CONF.SCREEN_H, 2);

    renderer.draw_rect(0, 0, CONF.SCREEN_W, CONF.SCREEN_H, SplashStyle.bg);
    if (logo_available) {
        const logo_x = cx - @divFloor(SplashLogo.pixelWidth(), 2);
        const logo_y: i32 = 42;
        drawSplashLogo(renderer, logo_project, logo_x, logo_y, SplashLogo.scale, c.fenster_time() - splash_started_ms, mouse);
        drawCenteredText(fui, renderer, CONF.THE_NAME, cx, logo_y + SplashLogo.pixelHeight() + 14, 2, SplashStyle.title);
        drawCenteredText(fui, renderer, CONF.VERSION, cx, logo_y + SplashLogo.pixelHeight() + 40, 1, SplashStyle.muted);
        drawCenteredText(fui, renderer, "GameBoy Color Edition", cx, logo_y + SplashLogo.pixelHeight() + 62, 2, SplashStyle.warn);
    } else {
        drawCenteredText(fui, renderer, CONF.THE_NAME, cx, cy - 44, 3, SplashStyle.title);
        drawCenteredText(fui, renderer, CONF.VERSION, cx, cy - 14, 1, SplashStyle.muted);
        drawCenteredText(fui, renderer, "GameBoy Color Edition", cx, cy + 8, 2, SplashStyle.warn);
    }

    var start_clicked = false;
    switch (CONF.APP_MODE) {
        .shareware => {
            drawCenteredText(fui, renderer, "SHAREWARE VERSION", cx, cy + 62, 3, SplashStyle.accent);
            drawCenteredText(fui, renderer, "FULL VERSION IS JUST $5", cx, cy + 96, 1, SplashStyle.warn);
            drawCenteredText(fui, renderer, "SUPPORT THE CREATOR", cx, cy + 114, 1, SplashStyle.warn);
            drawCenteredText(fui, renderer, CONF.BUY_URL, cx, cy + 134, 1, SplashStyle.muted);

            if (drawSplashButton(fui, renderer, mouse, cx - 126, cy + 170, "BUY", true)) handleBuyClicked();

            const remaining_seconds = sharewareWaitSecondsRemaining(splash_started_ms);
            var wait_label_buf: [16]u8 = undefined;
            const start_label = if (remaining_seconds > 0)
                std.fmt.bufPrint(&wait_label_buf, "WAIT {d} SEK", .{remaining_seconds}) catch "WAIT"
            else
                "START";
            start_clicked = drawSplashButton(fui, renderer, mouse, cx + 126, cy + 170, start_label, remaining_seconds == 0);
        },
        .full => {
            drawCenteredText(fui, renderer, "FULL VERSION", cx, cy + 82, 3, SplashStyle.accent);
            drawCenteredText(fui, renderer, "THANK YOU FOR REGISTERING", cx, cy + 116, 1, SplashStyle.warn);
            start_clicked = drawSplashButton(fui, renderer, mouse, cx, cy + 150, "START", true);
        },
    }

    drawCenteredText(fui, renderer, "Powered by Borowik Engine", cx, CONF.SCREEN_H - 58, 1, SplashStyle.warn);

    if (start_clicked) {
        editor.suppress_canvas_paint_until_mouse_up = true;
        sm.go_to(.editor);
    }
}

fn drawSplashLogo(renderer: *Render, project: *const Project, x: i32, y: i32, scale: i32, elapsed_ms: i64, mouse: Mouse) void {
    if (scale <= 0) return;
    drawSplashLogoTiles(renderer, project, x, y, scale);
    drawSplashLogoSpriteGroup(renderer, project, x, y, scale, elapsed_ms, mouse);
}

fn drawSplashLogoTiles(renderer: *Render, project: *const Project, x: i32, y: i32, scale: i32) void {
    if (splashLogoUsesMap(project)) {
        drawSplashLogoMapTiles(renderer, project, x, y, scale);
    } else {
        drawSplashLogoFirstTiles(renderer, project, x, y, scale);
    }
}

fn splashLogoUsesMap(project: *const Project) bool {
    const map = project.mapAtBank(0);
    const max_y = @min(SplashLogo.tiles_h, @as(i32, @intCast(map.height)));
    const max_x = @min(SplashLogo.tiles_w, @as(i32, @intCast(map.width)));

    var tile_y: i32 = 0;
    while (tile_y < max_y) : (tile_y += 1) {
        var tile_x: i32 = 0;
        while (tile_x < max_x) : (tile_x += 1) {
            const idx = mapCellIndex(map.width, tile_x, tile_y);
            if (map.tile_ids[idx] != 0 or map.tile_attrs[idx] != 0) return true;
        }
    }
    return false;
}

fn drawSplashLogoMapTiles(renderer: *Render, project: *const Project, x: i32, y: i32, scale: i32) void {
    const map = project.mapAtBank(0);
    const max_y = @min(SplashLogo.tiles_h, @as(i32, @intCast(map.height)));
    const max_x = @min(SplashLogo.tiles_w, @as(i32, @intCast(map.width)));
    const tile_px = CONF.TILE_SIDE * scale;

    var tile_y: i32 = 0;
    while (tile_y < max_y) : (tile_y += 1) {
        var tile_x: i32 = 0;
        while (tile_x < max_x) : (tile_x += 1) {
            const idx = mapCellIndex(map.width, tile_x, tile_y);
            const attr = MapTileAttr.decode(map.tile_attrs[idx]);
            views.drawImageWithAttrs(
                renderer,
                project,
                .tiles,
                @intCast(map.tile_ids[idx]),
                attr.palette,
                attr.hflip,
                attr.vflip,
                x + tile_x * tile_px,
                y + tile_y * tile_px,
                scale,
            );
        }
    }
}

fn drawSplashLogoFirstTiles(renderer: *Render, project: *const Project, x: i32, y: i32, scale: i32) void {
    const tile_px = CONF.TILE_SIDE * scale;

    var tile_y: i32 = 0;
    while (tile_y < SplashLogo.tiles_h) : (tile_y += 1) {
        var tile_x: i32 = 0;
        while (tile_x < SplashLogo.tiles_w) : (tile_x += 1) {
            const image_id: u16 = @intCast(tile_y * SplashLogo.tiles_w + tile_x);
            const palette_id = if (image_id < project.imageCountMode(.tiles)) project.imageAtMode(.tiles, image_id).palette_id else 0;
            views.drawImageWithAttrs(renderer, project, .tiles, image_id, palette_id, false, false, x + tile_x * tile_px, y + tile_y * tile_px, scale);
        }
    }
}

fn drawSplashLogoSpriteGroup(renderer: *Render, project: *const Project, x: i32, y: i32, scale: i32, elapsed_ms: i64, mouse: Mouse) void {
    const map = project.mapAtBank(0);
    if (map.sprite_count == 0) return;

    const tile_px = CONF.TILE_SIDE * scale;
    const logo_hovered = hoverRect(mouse.x, mouse.y, x, y, SplashLogo.pixelWidth(), SplashLogo.pixelHeight());
    const idle_group_x = x + SplashLogo.sprite_group_offset_tiles_x * tile_px;
    const idle_group_y = y;
    const group_x = if (logo_hovered) mouse.x else idle_group_x;
    const group_y = if (logo_hovered) mouse.y - SplashLogo.spriteGroupPixelHeight() else idle_group_y;
    const phase = @as(f32, @floatFromInt(elapsed_ms)) / 420.0;
    const scale_f = @as(f32, @floatFromInt(scale));
    const dx: i32 = if (logo_hovered) 0 else @intFromFloat(@round(std.math.sin(phase) * scale_f * 0.6));
    const dy: i32 = if (logo_hovered) 0 else @intFromFloat(@round(std.math.cos(phase) * scale_f * 0.7));

    const sprite_count: usize = @intCast(map.sprite_count);
    var i: usize = 0;
    while (i < sprite_count) : (i += 1) {
        const sprite = map.sprites[i];
        views.drawImageWithAttrs(
            renderer,
            project,
            .sprites,
            sprite.sprite_id,
            sprite.palette,
            sprite.hflip,
            sprite.vflip,
            group_x + @as(i32, @intCast(sprite.x)) * tile_px + dx,
            group_y + @as(i32, @intCast(sprite.y)) * tile_px + dy,
            scale,
        );
    }
}

fn hoverRect(px: i32, py: i32, x: i32, y: i32, w: i32, h: i32) bool {
    return px >= x and py >= y and px < x + w and py < y + h;
}

fn mapCellIndex(map_width: u16, tile_x: i32, tile_y: i32) usize {
    return @as(usize, @intCast(tile_y)) * @as(usize, @intCast(map_width)) + @as(usize, @intCast(tile_x));
}

fn sharewareWaitSecondsRemaining(splash_started_ms: i64) i64 {
    const wait_ms = CONF.SHAREWARE_WAIT_SECONDS * std.time.ms_per_s;
    const elapsed_ms = c.fenster_time() - splash_started_ms;
    if (elapsed_ms >= wait_ms) return 0;
    if (elapsed_ms <= 0) return CONF.SHAREWARE_WAIT_SECONDS;

    const remaining_ms = wait_ms - elapsed_ms;
    return @divFloor(remaining_ms + std.time.ms_per_s - 1, std.time.ms_per_s);
}

fn handleBuyClicked() void {
    openBuyUrl() catch |err| {
        std.debug.print("[shareware] Failed to open buy URL {s}: {s}\n", .{ CONF.BUY_URL, @errorName(err) });
    };
}

fn openBuyUrl() !void {
    const command = switch (builtin.os.tag) {
        .windows => "start \"\" \"" ++ CONF.BUY_URL ++ "\"",
        .macos => "open \"" ++ CONF.BUY_URL ++ "\" >/dev/null 2>&1 &",
        .linux => "xdg-open \"" ++ CONF.BUY_URL ++ "\" >/dev/null 2>&1 &",
        else => return error.UnsupportedOpenUrl,
    };

    if (c.system(command) != 0) return error.OpenUrlFailed;
}

fn drawSplashButton(fui: *Fui, renderer: *Render, mouse: Mouse, center_x: i32, y: i32, label: []const u8, enabled: bool) bool {
    const button_w: i32 = 220;
    const button_h: i32 = 44;
    const x = center_x - @divFloor(button_w, 2);
    const hovered = enabled and views.hover(mouse, x, y, button_w, button_h);

    const bg: u32 = if (!enabled) SplashStyle.button_disabled else if (hovered) SplashStyle.button_hover else SplashStyle.button;
    const border: u32 = if (hovered) SplashStyle.accent else SplashStyle.button_border;
    const text_color: u32 = if (!enabled) SplashStyle.disabled_text else if (hovered) SplashStyle.title else SplashStyle.muted;

    renderer.draw_rect(x + 3, y + 3, button_w, button_h, SplashStyle.button_shadow);
    renderer.draw_rect(x, y, button_w, button_h, bg);
    renderer.draw_rect_lines(x, y, button_w, button_h, border);
    const label_y = y + @divFloor(button_h - CONF.FONT_HEIGHT, 2);
    drawCenteredText(fui, renderer, label, center_x, label_y, 1, text_color);

    return enabled and hovered and (mouse.just_pressed or mouse.just_right_pressed);
}

fn drawGlobalOverlay(fui: *Fui, renderer: *Render, project: *const Project) void {
    const save_button_x: i32 = CONF.SCREEN_W - editor_ui.Layout.side_x - 192;
    renderer.draw_fps_overlay_at(fui, EditorTheme, save_button_x - 120, editor_ui.Layout.top_y + 38);
    drawProjectSlotOverlay(fui, renderer, project);
}

fn drawProjectSlotOverlay(fui: *Fui, renderer: *Render, project: *const Project) void {
    var label_buf: [64]u8 = undefined;
    const label = std.fmt.bufPrint(&label_buf, "PROJECT F{d}: {s}", .{ project.activeFileSlot(), project.activeFileName() }) catch "PROJECT";
    fui.draw_text(renderer, label, editor_ui.Layout.side_x + 24, editor_ui.Layout.top_y + 58, 1, editor_ui.Theme.warn);
}

fn drawCenteredText(fui: *Fui, renderer: *Render, text: []const u8, center_x: i32, y: i32, scale: i32, color: u32) void {
    const x = center_x - @divFloor(fui.text_length(text, scale), 2);
    fui.draw_text(renderer, text, x, y, scale, color);
}
