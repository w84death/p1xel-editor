const CONF = @import("../engine/config.zig").CONF;
const Render = @import("../engine/render.zig").Render;
const Mouse = @import("../engine/mouse.zig").Mouse;
const Project = @import("project.zig").Project;
const Tile = @import("project.zig").Tile;

pub fn hover(mouse: Mouse, x: i32, y: i32, w: i32, h: i32) bool {
    return mouse.x >= x and mouse.x < x + w and mouse.y >= y and mouse.y < y + h;
}

pub fn smallButton(fui: anytype, renderer: *Render, mouse: Mouse, x: i32, y: i32, w: i32, h: i32, label: [:0]const u8, active: bool) bool {
    const bg: u32 = if (active) 0xE8E8E8 else 0x6F6F6F;
    const fg: u32 = if (active) 0x151515 else 0xEEEEEE;
    const is_hover = hover(mouse, x, y, w, h);
    renderer.draw_rect(x, y, w, h, if (is_hover) lighten(bg) else bg);
    renderer.draw_rect_lines(x, y, w, h, 0x000000);
    const tw = fui.text_length(label, 1);
    fui.draw_text(renderer, label, x + @divFloor(w - tw, 2), y + @divFloor(h - CONF.FONT_HEIGHT, 2), 1, fg);
    return is_hover and mouse.just_pressed;
}

pub fn drawTile(renderer: *Render, project: *const Project, tile_id: u16, x: i32, y: i32, scale: i32) void {
    if (tile_id >= project.tile_count) return;
    const tile = project.tiles[tile_id];
    drawTileData(renderer, project, tile, x, y, scale);
}

pub fn drawTileData(renderer: *Render, project: *const Project, tile: Tile, x: i32, y: i32, scale: i32) void {
    var py: usize = 0;
    while (py < CONF.TILE_SIDE) : (py += 1) {
        var px: usize = 0;
        while (px < CONF.TILE_SIDE) : (px += 1) {
            const idx = tile.pixels[py * CONF.TILE_SIDE + px];
            const color = if (project.isTransparentColor(idx)) checker(px, py) else project.color32(tile.palette_id, idx);
            renderer.draw_rect(x + @as(i32, @intCast(px)) * scale, y + @as(i32, @intCast(py)) * scale, scale, scale, color);
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

fn lighten(color: u32) u32 {
    const r: u32 = @min(255, ((color >> 16) & 0xFF) + 24);
    const g: u32 = @min(255, ((color >> 8) & 0xFF) + 24);
    const b: u32 = @min(255, (color & 0xFF) + 24);
    return (r << 16) | (g << 8) | b;
}
