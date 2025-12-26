const std = @import("std");
const rl = @import("raylib");
const CONF = @import("config.zig").CONF;
const DB16 = @import("palette.zig").DB16;

const Particle = struct {
    x: f32,
    y: f32,
    size: f32,
    speed: f32,
};

fn randomFloat(seed: usize) f32 {
    const r: usize = @as(u32, @intCast(seed)) *% 73856093 ^ (seed *% 19349663);
    const fr: f32 = @floatFromInt(r);
    const norm: f32 = @floatFromInt(0xFFFFFFFF);
    return fr / norm;
}

pub const Vfx = struct {
    vfx: [32]Particle = undefined,
    frame: usize = 0,

    pub fn init() Vfx {
        const screen_width = CONF.SCREEN_W;
        const screen_height = CONF.SCREEN_H;
        var vfx: [32]Particle = undefined;
        for (&vfx, 0..) |*p, i| {
            p.x = randomFloat(i * 3) * screen_width;
            p.y = randomFloat(i * 3 + 1) * screen_height;
            p.size = 4 + randomFloat(i * 3 + 2) * 64;
            p.speed = 0.5 + (p.size - 4) / (24 - 4) * 2.0;
        }
        return Vfx{
            .vfx = vfx,
            .frame = 0,
        };
    }
    pub fn draw(self: *Vfx) void {
        for (&self.vfx, 0..) |*p, i| {
            const alpha_color = rl.Color.alpha(rl.Color.white, 0.001 * p.size); // Semi-transparent white for snow effect
            const x: i32 = @intFromFloat(p.x - p.size / 2);
            const y: i32 = @intFromFloat(p.y - p.size / 2);
            const size: i32 = @intFromFloat(p.size);
            rl.drawRectangle(x, y, size, size, alpha_color);
            p.y += p.speed;
            if (p.y > CONF.SCREEN_H) {
                p.x = randomFloat(i * 3) * CONF.SCREEN_W;
                p.size = 4 + randomFloat(i * 3 + 2) * 64;
                p.y = -p.size;
                p.speed = 0.5 + (p.size - 4) / (24 - 4) * 2.0;
            }
        }
        self.frame += 1;
    }
};
