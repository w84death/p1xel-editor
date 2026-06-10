// *************************************
// BOROWIK ENGINE
// by Krzysztof Krystian Jankowski
// github.com/w84death/borowik-engine
// *************************************

const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    if (builtin.os.tag == .windows and builtin.cpu.arch == .x86) @cDefine("_X86_", "1");
    @cInclude("fenster.h");
});
const CONF = @import("config.zig").CONF;

pub const Framebuffer = enum {
    frame,
    terrain,
};

pub const Render = struct {
    const PERF_ALPHA: f32 = 0.1;

    const PerfStats = struct {
        sim_start_ns: i128 = 0,
        draw_start_ns: i128 = 0,
        present_start_ns: i128 = 0,
        smoothed_fps: f32 = CONF.TARGET_FPS,
        smoothed_sim_ms: f32 = 0.0,
        smoothed_draw_ms: f32 = 0.0,
        smoothed_present_ms: f32 = 0.0,
        fps_text_buf: [32]u8 = undefined,
        sim_text_buf: [32]u8 = undefined,
        draw_text_buf: [32]u8 = undefined,
        present_text_buf: [32]u8 = undefined,
    };

    const ClippedRect = struct {
        x: i32,
        y: i32,
        w: i32,
        h: i32,
    };

    window_buf: []u32,
    window_width: i32,
    window_height: i32,
    width: i32,
    height: i32,
    pixel_scale: i32,
    pixels_count: usize,
    frame_buf: []u32,
    terrain_buf: []u32,
    allocator: std.mem.Allocator,
    target: Framebuffer = .frame,
    dt: f32 = 0.0,
    now: i64,
    perf: PerfStats = .{},

    pub fn init(buf: []u32, width: i32, height: i32) Render {
        return init_scaled(buf, width, height, 1);
    }

    pub fn init_scaled(buf: []u32, width: i32, height: i32, scale: i32) Render {
        const allocator = std.heap.c_allocator;
        const w: i32 = if (width > 0) width else CONF.SCREEN_W;
        const h: i32 = if (height > 0) height else CONF.SCREEN_H;
        const s: i32 = if (scale == 4 or scale == 8) scale else 1;
        const count: usize = @intCast(@as(i64, w) * @as(i64, h));

        const frame_buf = allocator.alloc(u32, count) catch @panic("failed to allocate frame buffer");
        const terrain_buf = allocator.alloc(u32, count) catch @panic("failed to allocate terrain buffer");

        @memset(frame_buf, 0);
        @memset(terrain_buf, 0);

        std.debug.print("[init] Borowik Engine {s}\n", .{CONF.ENGINE});
        std.debug.print("[init] {s} {s}\n", .{ CONF.THE_NAME, CONF.VERSION });
        std.debug.print("[init] by Krzysztof Krystian Jankowski - github.com/w84death/borowik-engine\n", .{});
        std.debug.print("[init] renderer initialized\n", .{});

        return .{
            .window_buf = buf,
            .window_width = w * s,
            .window_height = h * s,
            .width = w,
            .height = h,
            .pixel_scale = s,
            .pixels_count = count,
            .frame_buf = frame_buf,
            .terrain_buf = terrain_buf,
            .allocator = allocator,
            .target = .frame,
            .now = c.fenster_time(),
        };
    }

    pub fn deinit(self: *Render) void {
        self.allocator.free(self.frame_buf);
        self.allocator.free(self.terrain_buf);
    }

    pub fn begin_frame(self: *Render) void {
        const now_ms = c.fenster_time();
        const d: f32 = @floatFromInt(now_ms - self.now);
        self.dt = d / 1000.0;
        self.now = now_ms;
    }

    pub fn cap_frame(self: *Render, target_fps: f64) void {
        const frame_time_target: f64 = 1000.0 / target_fps;
        const processing_time: f64 = @floatFromInt(c.fenster_time() - self.now);
        const sleep_ms: i64 = @intFromFloat(@max(0.0, frame_time_target - processing_time));
        if (sleep_ms > 0) {
            c.fenster_sleep(sleep_ms);
        }
    }

    pub fn present(self: *Render) void {
        if (self.pixel_scale == 1) {
            @memcpy(self.window_buf, self.frame_buf);
            return;
        }

        const scale: usize = @intCast(self.pixel_scale);
        const logical_w: usize = @intCast(self.width);
        const logical_h: usize = @intCast(self.height);
        const window_w: usize = @intCast(self.window_width);

        var y: usize = 0;
        while (y < logical_h) : (y += 1) {
            const src_row = y * logical_w;
            const dst_row = y * scale * window_w;

            var x: usize = 0;
            while (x < logical_w) : (x += 1) {
                const color = self.frame_buf[src_row + x];
                const dst = dst_row + x * scale;
                @memset(self.window_buf[dst .. dst + scale], color);
            }

            var sy: usize = 1;
            while (sy < scale) : (sy += 1) {
                const dst = dst_row + sy * window_w;
                @memcpy(self.window_buf[dst .. dst + window_w], self.window_buf[dst_row .. dst_row + window_w]);
            }
        }
    }

    pub fn perf_begin_sim(self: *Render) void {
        self.perf.sim_start_ns = c.fenster_time() * 1_000_000;
    }

    pub fn perf_begin_draw(self: *Render) void {
        const now_ns = c.fenster_time() * 1_000_000;
        const sim_ms = ns_to_ms(now_ns - self.perf.sim_start_ns);
        self.perf.smoothed_sim_ms = smooth(self.perf.smoothed_sim_ms, sim_ms);
        self.perf.draw_start_ns = now_ns;
    }

    pub fn perf_begin_present(self: *Render) void {
        const now_ns = c.fenster_time() * 1_000_000;
        const draw_ms = ns_to_ms(now_ns - self.perf.draw_start_ns);
        self.perf.smoothed_draw_ms = smooth(self.perf.smoothed_draw_ms, draw_ms);
        self.perf.present_start_ns = now_ns;
    }

    pub fn perf_end_present(self: *Render) void {
        const now_ns = c.fenster_time() * 1_000_000;
        const present_ms = ns_to_ms(now_ns - self.perf.present_start_ns);
        self.perf.smoothed_present_ms = smooth(self.perf.smoothed_present_ms, present_ms);

        if (self.dt > 0.0) {
            const instant_fps: f32 = 1.0 / self.dt;
            self.perf.smoothed_fps = smooth(self.perf.smoothed_fps, instant_fps);
        }
    }

    pub fn draw_perf_overlay(self: *Render, fui: anytype, comptime Theme: type) void {
        self.draw_perf_overlay_at(fui, Theme, fui.pivotX(.bottom_left), fui.pivotY(.bottom_left) - Theme.FONT_PERFLINE_HEIGHT * 3);
    }

    pub fn draw_fps_overlay_at(self: *Render, fui: anytype, comptime Theme: type, x: i32, y: i32) void {
        const fps: i32 = @intFromFloat(@round(self.perf.smoothed_fps));
        const fps_text = std.fmt.bufPrint(&self.perf.fps_text_buf, "FPS: {d}", .{fps}) catch "FPS: ?";
        fui.draw_text(self, fps_text, x, y, Theme.FONT_PERF, Theme.SECONDARY_COLOR);
    }

    pub fn draw_perf_overlay_at(self: *Render, fui: anytype, comptime Theme: type, x: i32, y: i32) void {
        self.draw_fps_overlay_at(fui, Theme, x, y);

        const sim_ms_text = std.fmt.bufPrint(&self.perf.sim_text_buf, "SIM: {d:.2}ms", .{self.perf.smoothed_sim_ms}) catch "SIM: ?";
        fui.draw_text(self, sim_ms_text, x, y + Theme.FONT_PERFLINE_HEIGHT, Theme.FONT_PERF, Theme.SECONDARY_COLOR);

        const draw_ms_text = std.fmt.bufPrint(&self.perf.draw_text_buf, "DRAW: {d:.2}ms", .{self.perf.smoothed_draw_ms}) catch "DRAW: ?";
        fui.draw_text(self, draw_ms_text, x, y + Theme.FONT_PERFLINE_HEIGHT * 2, Theme.FONT_PERF, Theme.SECONDARY_COLOR);

        const present_ms_text = std.fmt.bufPrint(&self.perf.present_text_buf, "PRESENT: {d:.2}ms", .{self.perf.smoothed_present_ms}) catch "PRESENT: ?";
        fui.draw_text(self, present_ms_text, x, y + Theme.FONT_PERFLINE_HEIGHT * 3, Theme.FONT_PERF, Theme.SECONDARY_COLOR);
    }

    pub fn set_target(self: *Render, target: Framebuffer) void {
        self.target = target;
    }

    pub fn clear_buffer(self: *Render, target: Framebuffer, color: u32) void {
        @memset(self.buffer_ptr(target), color);
    }

    pub fn copy_buffer(self: *Render, src: Framebuffer, dst: Framebuffer) void {
        const src_buf = self.buffer_ptr(src);
        const dst_buf = self.buffer_ptr(dst);
        @memcpy(dst_buf, src_buf);
    }

    pub fn target_buffer(self: *Render) []u32 {
        return self.active_buffer_ptr();
    }

    pub fn put_pixel(self: *Render, x: i32, y: i32, color: u32) void {
        const buf = self.active_buffer_ptr();
        const index: usize = @intCast(y * self.width + x);
        buf[index] = color;
    }

    pub fn get_pixel(self: *Render, x: i32, y: i32) u32 {
        const buf = self.active_buffer_ptr();
        const index: usize = @intCast(y * self.width + x);
        return buf[index];
    }

    pub fn clear_background(self: *Render, color: u32) void {
        self.clear_buffer(self.target, color);
    }

    pub fn draw_line(self: *Render, x0: i32, y0: i32, x1: i32, y1: i32, color: u32) void {
        if (y0 == y1) {
            const x = @min(x0, x1);
            const w: i32 = @intCast(@abs(x1 - x0) + 1);
            self.draw_hline(x, y0, w, color);
            return;
        }
        if (x0 == x1) {
            const y = @min(y0, y1);
            const h: i32 = @intCast(@abs(y1 - y0) + 1);
            self.draw_vline(x0, y, h, color);
            return;
        }

        var x = x0;
        var y = y0;
        const dx: i32 = @intCast(@abs(x1 - x0));
        const dy: i32 = @intCast(@abs(y1 - y0));
        const sx: i32 = if (x0 < x1) 1 else -1;
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err: i32 = if (dx > dy) dx else -dy;
        err = @divFloor(err, 2);
        while (true) {
            if (x >= 0 and x < self.width and y >= 0 and y < self.height) {
                self.put_pixel(x, y, color);
            }
            if (x == x1 and y == y1) break;
            const e2 = err;
            if (e2 > -dx) {
                err -= dy;
                x += sx;
            }
            if (e2 < dy) {
                err += dx;
                y += sy;
            }
        }
    }

    pub fn draw_rect(self: *Render, x: i32, y: i32, w: i32, h: i32, color: u32) void {
        const clipped = self.clip_rect(x, y, w, h) orelse return;
        const buf = self.active_buffer_ptr();
        const screen_w: usize = @intCast(self.width);
        const sx: usize = @intCast(clipped.x);
        const sy: usize = @intCast(clipped.y);
        const sw: usize = @intCast(clipped.w);
        const sh: usize = @intCast(clipped.h);

        var row: usize = 0;
        while (row < sh) : (row += 1) {
            const start = (sy + row) * screen_w + sx;
            @memset(buf[start .. start + sw], color);
        }
    }

    pub fn splat_sprite(
        self: *Render,
        target: Framebuffer,
        sheet: anytype,
        sprite_size: i32,
        anim_start: usize,
        anim_len: usize,
        x: i32,
        y: i32,
        rand: *const std.Random,
    ) void {
        if (anim_len == 0) return;

        const frame_offset = rand.intRangeAtMost(usize, 0, anim_len - 1);
        const frame = anim_start + frame_offset;
        const draw_x = x - @divFloor(sprite_size, 2);
        const draw_y = y - @divFloor(sprite_size, 2);

        const prev_target = self.target;
        self.set_target(target);
        defer self.set_target(prev_target);

        sheet.draw_frame(self, frame, draw_x, draw_y);
    }

    pub fn draw_rect_trans(self: *Render, x: i32, y: i32, w: i32, h: i32, color: u32) void {
        const clipped = self.clip_rect(x, y, w, h) orelse return;

        const screen_w: usize = @intCast(self.width);
        const sx: usize = @intCast(clipped.x);
        const sy: usize = @intCast(clipped.y);
        const sw: usize = @intCast(clipped.w);
        const sh: usize = @intCast(clipped.h);
        const buf = self.active_buffer_ptr();

        var row: usize = 0;
        while (row < sh) : (row += 1) {
            if (row % 4 == 1) continue;
            const start = (sy + row) * screen_w + sx;
            @memset(buf[start .. start + sw], color);
        }
    }

    pub fn draw_rect_lines(self: *Render, x: i32, y: i32, w: i32, h: i32, color: u32) void {
        if (w <= 0 or h <= 0) return;
        self.draw_hline(x, y, w, color);
        if (h > 1) self.draw_hline(x, y + h - 1, w, color);
        if (h > 2) {
            self.draw_vline(x, y + 1, h - 2, color);
            if (w > 1) self.draw_vline(x + w - 1, y + 1, h - 2, color);
        }
    }

    pub fn draw_hline(self: *Render, x: i32, y: i32, w: i32, color: u32) void {
        if (w <= 0 or y < 0 or y >= self.height) return;

        var rx = x;
        var rw = w;
        if (rx < 0) {
            rw += rx;
            rx = 0;
        }
        if (rx + rw > self.width) rw = self.width - rx;
        if (rw <= 0) return;

        const screen_w: usize = @intCast(self.width);
        const sx: usize = @intCast(rx);
        const sy: usize = @intCast(y);
        const sw: usize = @intCast(rw);
        const start = sy * screen_w + sx;
        @memset(self.active_buffer_ptr()[start .. start + sw], color);
    }

    pub fn draw_vline(self: *Render, x: i32, y: i32, h: i32, color: u32) void {
        if (h <= 0 or x < 0 or x >= self.width) return;

        var ry = y;
        var rh = h;
        if (ry < 0) {
            rh += ry;
            ry = 0;
        }
        if (ry + rh > self.height) rh = self.height - ry;
        if (rh <= 0) return;

        const screen_w: usize = @intCast(self.width);
        const sx: usize = @intCast(x);
        var row: usize = @intCast(ry);
        const end: usize = @intCast(ry + rh);
        const buf = self.active_buffer_ptr();
        while (row < end) : (row += 1) {
            buf[row * screen_w + sx] = color;
        }
    }

    pub fn draw_circle(self: *Render, x: i32, y: i32, r: u32, color: u32) void {
        const rr = @as(i64, r) * r;
        const ir: i32 = @intCast(r);
        const screen_w: usize = @intCast(self.width);
        const buf = self.active_buffer_ptr();
        var dy: i32 = -ir;
        while (dy <= ir) : (dy += 1) {
            var dx: i32 = -ir;
            while (dx <= ir) : (dx += 1) {
                const px = x + dx;
                const py = y + dy;
                if (px >= 0 and px < self.width and py >= 0 and py < self.height) {
                    const dist = @as(i64, dx) * dx + @as(i64, dy) * dy;
                    if (dist <= rr) {
                        const index = @as(usize, @intCast(py)) * screen_w + @as(usize, @intCast(px));
                        buf[index] = color;
                    }
                }
            }
        }
    }

    pub fn fill(self: *Render, x: i32, y: i32, old_color: u32, new_color: u32) void {
        if (old_color == new_color) return;
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) return;
        if (self.get_pixel(x, y) != old_color) return;

        var stack = std.ArrayListUnmanaged([2]i32).empty;
        defer stack.deinit(self.allocator);

        self.put_pixel(x, y, new_color);
        stack.append(self.allocator, .{ x, y }) catch return;

        while (stack.items.len > 0) {
            const point = stack.items[stack.items.len - 1];
            stack.items.len -= 1;

            if (!self.pushFillPixel(&stack, point[0] - 1, point[1], old_color, new_color)) return;
            if (!self.pushFillPixel(&stack, point[0] + 1, point[1], old_color, new_color)) return;
            if (!self.pushFillPixel(&stack, point[0], point[1] - 1, old_color, new_color)) return;
            if (!self.pushFillPixel(&stack, point[0], point[1] + 1, old_color, new_color)) return;
        }
    }

    fn pushFillPixel(self: *Render, stack: *std.ArrayListUnmanaged([2]i32), x: i32, y: i32, old_color: u32, new_color: u32) bool {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) return true;
        if (self.get_pixel(x, y) != old_color) return true;
        self.put_pixel(x, y, new_color);
        stack.append(self.allocator, .{ x, y }) catch return false;
        return true;
    }

    fn clip_rect(self: *Render, x: i32, y: i32, w: i32, h: i32) ?ClippedRect {
        if (w <= 0 or h <= 0) return null;

        var rx = x;
        var ry = y;
        var rw = w;
        var rh = h;

        if (rx < 0) {
            rw += rx;
            rx = 0;
        }
        if (ry < 0) {
            rh += ry;
            ry = 0;
        }
        if (rx + rw > self.width) {
            rw = self.width - rx;
        }
        if (ry + rh > self.height) {
            rh = self.height - ry;
        }

        if (rw <= 0 or rh <= 0) return null;

        return ClippedRect{ .x = rx, .y = ry, .w = rw, .h = rh };
    }

    fn active_buffer_ptr(self: *Render) []u32 {
        return self.buffer_ptr(self.target);
    }

    fn buffer_ptr(self: *Render, target: Framebuffer) []u32 {
        return switch (target) {
            .frame => self.frame_buf,
            .terrain => self.terrain_buf,
        };
    }

    fn smooth(current: f32, next: f32) f32 {
        return current + (next - current) * PERF_ALPHA;
    }

    fn ns_to_ms(value_ns: i128) f32 {
        return @as(f32, @floatFromInt(value_ns)) / 1_000_000.0;
    }
};
