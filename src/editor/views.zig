const CONF = @import("../engine/config.zig").CONF;
const Render = @import("../engine/render.zig").Render;
const Mouse = @import("../engine/mouse.zig").Mouse;
const Project = @import("project.zig").Project;
const Tile = @import("project.zig").Tile;

pub fn hover(mouse: Mouse, x: i32, y: i32, w: i32, h: i32) bool {
    return mouse.x >= x and mouse.x < x + w and mouse.y >= y and mouse.y < y + h;
}

pub fn drawTile(renderer: *Render, project: *const Project, tile_id: u16, x: i32, y: i32, scale: i32) void {
    if (tile_id >= project.imageCount()) return;
    const tile = project.imageAt(tile_id);
    drawTileData(renderer, project, tile, x, y, scale);
}

pub fn drawImageWithAttrs(renderer: *Render, project: *const Project, mode: @import("project.zig").ProjectMode, image_id: u16, palette_id: u8, hflip: bool, vflip: bool, x: i32, y: i32, scale: i32) void {
    if (scale <= 0 or image_id >= project.imageCountMode(mode)) return;
    const tile = project.imageAtMode(mode, image_id);
    var colors: [CONF.COLORS_PER_PALETTE]u32 = undefined;
    for (0..CONF.COLORS_PER_PALETTE) |i| colors[i] = project.color32Mode(mode, palette_id, @intCast(i));

    var py: usize = 0;
    while (py < CONF.TILE_SIDE) : (py += 1) {
        var px: usize = 0;
        while (px < CONF.TILE_SIDE) : (px += 1) {
            const src_x = if (hflip) CONF.TILE_SIDE - 1 - px else px;
            const src_y = if (vflip) CONF.TILE_SIDE - 1 - py else py;
            const idx = tile.pixels[src_y * CONF.TILE_SIDE + src_x];
            if (mode == .sprites and idx == 0) continue;
            const color = colors[idx];
            renderer.draw_rect(x + @as(i32, @intCast(px)) * scale, y + @as(i32, @intCast(py)) * scale, scale, scale, color);
        }
    }
}

pub fn drawTileData(renderer: *Render, project: *const Project, tile: Tile, x: i32, y: i32, scale: i32) void {
    if (scale <= 0) return;

    var colors: [CONF.COLORS_PER_PALETTE]u32 = undefined;
    for (0..CONF.COLORS_PER_PALETTE) |i| {
        colors[i] = project.color32(tile.palette_id, @intCast(i));
    }

    const size = CONF.TILE_SIDE * scale;
    if (x >= 0 and y >= 0 and x + size <= renderer.width and y + size <= renderer.height) {
        drawTileDataFast(renderer, project, tile, x, y, scale, colors);
        return;
    }

    var py: usize = 0;
    while (py < CONF.TILE_SIDE) : (py += 1) {
        var px: usize = 0;
        while (px < CONF.TILE_SIDE) : (px += 1) {
            const idx = tile.pixels[py * CONF.TILE_SIDE + px];
            const color = if (project.isTransparentColor(idx)) checker(px, py) else colors[idx];
            renderer.draw_rect(x + @as(i32, @intCast(px)) * scale, y + @as(i32, @intCast(py)) * scale, scale, scale, color);
        }
    }
}

fn drawTileDataFast(renderer: *Render, project: *const Project, tile: Tile, x: i32, y: i32, scale: i32, colors: [CONF.COLORS_PER_PALETTE]u32) void {
    const buf = renderer.target_buffer();
    const screen_w: usize = @intCast(renderer.width);
    const sx: usize = @intCast(x);
    const sy: usize = @intCast(y);
    const scale_usize: usize = @intCast(scale);

    var py: usize = 0;
    while (py < CONF.TILE_SIDE) : (py += 1) {
        var px: usize = 0;
        while (px < CONF.TILE_SIDE) : (px += 1) {
            const idx = tile.pixels[py * CONF.TILE_SIDE + px];
            const color = if (project.isTransparentColor(idx)) checker(px, py) else colors[idx];
            const dst_x = sx + px * scale_usize;
            const dst_y = sy + py * scale_usize;

            var row: usize = 0;
            while (row < scale_usize) : (row += 1) {
                const start = (dst_y + row) * screen_w + dst_x;
                @memset(buf[start .. start + scale_usize], color);
            }
        }
    }
}

pub fn saveIfDirty(project: *Project) void {
    if (!project.dirty) return;
    project.save() catch {};
}

fn checker(x: usize, y: usize) u32 {
    return if ((x + y) % 2 == 0) 0x2E2E2E else 0x484848;
}
