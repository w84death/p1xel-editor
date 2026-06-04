const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    if (builtin.os.tag == .windows and builtin.cpu.arch == .x86) @cDefine("_X86_", "1");
    @cInclude("fenster.h");
});

const CONF = @import("engine/config.zig").CONF;
const Render = @import("engine/render.zig").Render;

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

    while (c.fenster_loop(&window) == 0) {
        if (window.keys[27] != 0) break;

        renderer.begin_frame();
        renderer.clear_background(0x00101820);
        renderer.present();
        renderer.cap_frame(CONF.TARGET_FPS);
    }
}
