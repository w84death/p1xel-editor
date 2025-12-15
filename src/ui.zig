const std = @import("std");
const rl = @import("raylib");
const raygui = @import("raylib").raygui;
const palette = @import("palette.zig");
const DB16 = palette.DB16;
const Math = @import("math.zig");
const IVec2 = Math.IVec2;

const SCREEN_W = 1024;
const SCREEN_H = 640;

const PIVOT_PADDING = 24;
const pivots = struct {
    tl: IVec2 = IVec2.init(PIVOT_PADDING, PIVOT_PADDING),
    tr: IVec2 = IVec2.init(SCREEN_W - PIVOT_PADDING, PIVOT_PADDING),
    bl: IVec2 = IVec2.init(PIVOT_PADDING, SCREEN_H - PIVOT_PADDING),
    br: IVec2 = IVec2.init(SCREEN_W - PIVOT_PADDING, SCREEN_H - PIVOT_PADDING),
};

pub const UI = struct {
    app_name: [24]u8 = undefined,
    pivots: pivots,
    pub fn init(title: [:0]u8) UI {
        createWindow(title);
        raygui.GuiSetStyle(raygui.TEXTBOX, raygui.TEXT_ALIGNMENT, raygui.TEXT_ALIGN_CENTER);
        return UI{ .app_name = title };
    }

    pub fn createWindow(title: []u8) void {
        rl.initWindow(SCREEN_W, SCREEN_W, title);
    }

    pub fn closeWindow() void {
        rl.closeWindow();
    }

    pub fn button() void {}

    pub fn demo(self: UI) void {
        rl.drawText(self.app_name, 300, 25, 20, DB16.WHITE);
    }
};
