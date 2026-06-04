const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
});
const CONF = @import("../engine/config.zig").CONF;

pub const Tool = enum { pixel, fill, line };
pub const ColorChannel = enum { r, g, b };
pub const PaletteColor = [3]u8;

pub const Tile = struct {
    palette_id: u8 = 0,
    pixels: [CONF.TILE_SIDE * CONF.TILE_SIDE]u8 = [_]u8{0} ** (CONF.TILE_SIDE * CONF.TILE_SIDE),

    pub fn is_empty(self: Tile) bool {
        for (self.pixels) |px| if (px != 0) return false;
        return true;
    }
};

pub const Project = struct {
    const MAGIC = "P1X2";
    const VERSION: u8 = 2;
    const PALETTE_COLOR_BYTES = 3;
    const PALETTE_BYTES = CONF.PALETTE_COUNT * CONF.COLORS_PER_PALETTE * PALETTE_COLOR_BYTES;
    const TILE_BYTES = 1 + CONF.TILE_SIDE * CONF.TILE_SIDE;
    const HEADER_BYTES = 4 + 1 + 1 + 2;
    const MAX_FILE_BYTES = HEADER_BYTES + PALETTE_BYTES + CONF.MAX_TILES * TILE_BYTES;

    palettes: [CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor = defaultPalettes(),
    tiles: [CONF.MAX_TILES]Tile = [_]Tile{.{}} ** CONF.MAX_TILES,
    tile_count: u16 = 1,
    selected_tile: u16 = 0,
    selected_palette: u8 = 0,
    selected_color: u8 = 1,
    left_color: u8 = 1,
    right_color: u8 = 0,
    visible_slots: [9]u16 = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8 },
    dirty: bool = false,

    pub fn init() Project {
        var project = Project{};
        project.ensureSlotBounds();
        return project;
    }

    pub fn loadOrDefault() Project {
        var project = Project.init();
        project.load() catch return project;
        project.ensureSlotBounds();
        return project;
    }

    pub fn activePalette(self: *const Project) [CONF.COLORS_PER_PALETTE]PaletteColor {
        return self.palettes[self.selected_palette];
    }

    pub fn color32(self: *const Project, palette_id: u8, color_id: u8) u32 {
        const safe_palette = @min(palette_id, CONF.PALETTE_COUNT - 1);
        const safe_color = @min(color_id, CONF.COLORS_PER_PALETTE - 1);
        const rgb = self.palettes[safe_palette][safe_color];
        return rgbToU32(rgb);
    }

    pub fn currentColor32(self: *const Project, color_id: u8) u32 {
        return self.color32(self.selected_palette, color_id);
    }

    pub fn selectedRgb(self: *const Project) PaletteColor {
        return self.palettes[self.selected_palette][self.selected_color];
    }

    pub fn nonEmptyTiles(self: *const Project) u16 {
        var count: u16 = 0;
        var i: usize = 0;
        while (i < self.tile_count) : (i += 1) {
            if (!self.tiles[i].is_empty()) count += 1;
        }
        return count;
    }

    pub fn selectTile(self: *Project, tile_id: u16) void {
        if (tile_id >= self.tile_count) return;
        self.selected_tile = tile_id;
        self.selected_palette = @min(self.tiles[tile_id].palette_id, CONF.PALETTE_COUNT - 1);
    }

    pub fn paintPixel(self: *Project, x: u8, y: u8, color: u8) void {
        if (x >= CONF.TILE_SIDE or y >= CONF.TILE_SIDE) return;
        self.tiles[self.selected_tile].pixels[@as(usize, y) * CONF.TILE_SIDE + x] = color & 3;
        self.tiles[self.selected_tile].palette_id = self.selected_palette;
        self.dirty = true;
    }

    pub fn fill(self: *Project, x: u8, y: u8, color: u8) void {
        if (x >= CONF.TILE_SIDE or y >= CONF.TILE_SIDE) return;
        const start = @as(usize, y) * CONF.TILE_SIDE + x;
        const old = self.tiles[self.selected_tile].pixels[start];
        const new = color & 3;
        if (old == new) return;
        flood(&self.tiles[self.selected_tile].pixels, x, y, old, new);
        self.tiles[self.selected_tile].palette_id = self.selected_palette;
        self.dirty = true;
    }

    pub fn drawLine(self: *Project, x0_in: i32, y0_in: i32, x1: i32, y1: i32, color: u8) void {
        var x0 = x0_in;
        var y0 = y0_in;
        const dx: i32 = @intCast(@abs(x1 - x0));
        const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
        const sx: i32 = if (x0 < x1) 1 else -1;
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err = dx + dy;
        while (true) {
            if (x0 >= 0 and x0 < CONF.TILE_SIDE and y0 >= 0 and y0 < CONF.TILE_SIDE) {
                self.paintPixel(@intCast(x0), @intCast(y0), color);
            }
            if (x0 == x1 and y0 == y1) break;
            const e2 = 2 * err;
            if (e2 >= dy) {
                err += dy;
                x0 += sx;
            }
            if (e2 <= dx) {
                err += dx;
                y0 += sy;
            }
        }
    }

    pub fn createTile(self: *Project) ?u16 {
        if (self.tile_count >= CONF.MAX_TILES) return null;
        const id = self.tile_count;
        self.tiles[id] = .{ .palette_id = self.selected_palette };
        self.tile_count += 1;
        self.visible_slots[id % self.visible_slots.len] = id;
        self.selectTile(id);
        self.dirty = true;
        return id;
    }

    pub fn duplicateTile(self: *Project, id: u16) ?u16 {
        if (id >= self.tile_count or self.tile_count >= CONF.MAX_TILES) return null;
        const new_id = self.tile_count;
        self.tiles[new_id] = self.tiles[id];
        self.tile_count += 1;
        self.selectTile(new_id);
        self.dirty = true;
        return new_id;
    }

    pub fn deleteTile(self: *Project, id: u16) void {
        if (self.tile_count <= 1 or id >= self.tile_count) return;
        var i: usize = id;
        while (i + 1 < self.tile_count) : (i += 1) self.tiles[i] = self.tiles[i + 1];
        self.tile_count -= 1;
        for (&self.visible_slots) |*slot| {
            if (slot.* == id) slot.* = 0 else if (slot.* > id) slot.* -= 1;
        }
        if (self.selected_tile >= self.tile_count) self.selected_tile = self.tile_count - 1;
        self.selected_palette = self.tiles[self.selected_tile].palette_id;
        self.dirty = true;
    }

    pub fn moveTileLeft(self: *Project, id: u16) void {
        if (id == 0 or id >= self.tile_count) return;
        self.swapTileIds(id, id - 1);
        self.selected_tile = id - 1;
    }

    pub fn moveTileRight(self: *Project, id: u16) void {
        if (id + 1 >= self.tile_count) return;
        self.swapTileIds(id, id + 1);
        self.selected_tile = id + 1;
    }

    pub fn swapTileIds(self: *Project, a: u16, b: u16) void {
        if (a >= self.tile_count or b >= self.tile_count or a == b) return;
        const tmp = self.tiles[a];
        self.tiles[a] = self.tiles[b];
        self.tiles[b] = tmp;
        for (&self.visible_slots) |*slot| {
            if (slot.* == a) slot.* = b else if (slot.* == b) slot.* = a;
        }
        if (self.selected_tile == a) self.selected_tile = b else if (self.selected_tile == b) self.selected_tile = a;
        self.dirty = true;
    }

    pub fn adjustSelectedRgb(self: *Project, channel: ColorChannel, delta: i16) void {
        const color = &self.palettes[self.selected_palette][self.selected_color];
        const channel_index: usize = switch (channel) {
            .r => 0,
            .g => 1,
            .b => 2,
        };
        const current = color[channel_index];
        const next = clampByte(@as(i16, current) + delta);
        if (next == current) return;
        color[channel_index] = next;
        self.dirty = true;
    }

    pub fn load(self: *Project) !void {
        const file = c.fopen(CONF.PROJECT_FILE, "rb") orelse return error.InvalidProject;
        defer _ = c.fclose(file);
        var data: [MAX_FILE_BYTES]u8 = undefined;
        const len = c.fread(&data, 1, data.len, file);
        if (len < HEADER_BYTES) return error.InvalidProject;
        if (!std.mem.eql(u8, data[0..4], MAGIC)) return error.InvalidProject;
        if (data[4] != VERSION) return error.InvalidProject;
        if (data[5] != CONF.PALETTE_COUNT) return error.InvalidProject;
        const loaded_tiles = std.mem.readInt(u16, data[6..8], .little);
        if (loaded_tiles == 0 or loaded_tiles > CONF.MAX_TILES) return error.InvalidProject;
        const expected = HEADER_BYTES + PALETTE_BYTES + @as(usize, loaded_tiles) * TILE_BYTES;
        if (len < expected) return error.InvalidProject;

        var offset: usize = HEADER_BYTES;
        for (0..CONF.PALETTE_COUNT) |p| {
            for (0..CONF.COLORS_PER_PALETTE) |color_slot| {
                self.palettes[p][color_slot] = .{ data[offset], data[offset + 1], data[offset + 2] };
                offset += PALETTE_COLOR_BYTES;
            }
        }
        self.tile_count = loaded_tiles;
        for (0..loaded_tiles) |i| {
            self.tiles[i].palette_id = @min(data[offset], CONF.PALETTE_COUNT - 1);
            offset += 1;
            @memcpy(self.tiles[i].pixels[0..], data[offset .. offset + CONF.TILE_SIDE * CONF.TILE_SIDE]);
            for (&self.tiles[i].pixels) |*px| px.* &= 3;
            offset += CONF.TILE_SIDE * CONF.TILE_SIDE;
        }
        self.dirty = false;
    }

    pub fn save(self: *Project) !void {
        const file = c.fopen(CONF.PROJECT_FILE, "wb") orelse return error.InvalidProject;
        defer _ = c.fclose(file);
        var header: [HEADER_BYTES]u8 = undefined;
        @memcpy(header[0..4], MAGIC);
        header[4] = VERSION;
        header[5] = CONF.PALETTE_COUNT;
        std.mem.writeInt(u16, header[6..8], self.tile_count, .little);
        if (c.fwrite(&header, 1, header.len, file) != header.len) return error.InvalidProject;
        for (self.palettes) |palette| {
            for (palette) |color| {
                if (c.fwrite(&color, 1, color.len, file) != color.len) return error.InvalidProject;
            }
        }
        var tile_buf: [TILE_BYTES]u8 = undefined;
        var i: usize = 0;
        while (i < self.tile_count) : (i += 1) {
            tile_buf[0] = self.tiles[i].palette_id;
            @memcpy(tile_buf[1..], self.tiles[i].pixels[0..]);
            if (c.fwrite(&tile_buf, 1, tile_buf.len, file) != tile_buf.len) return error.InvalidProject;
        }
        self.dirty = false;
    }

    fn ensureSlotBounds(self: *Project) void {
        for (&self.visible_slots, 0..) |*slot, i| {
            if (slot.* >= self.tile_count) slot.* = @intCast(@min(i, @as(usize, self.tile_count - 1)));
        }
    }
};

fn flood(pixels: *[CONF.TILE_SIDE * CONF.TILE_SIDE]u8, x: u8, y: u8, old: u8, new: u8) void {
    if (x >= CONF.TILE_SIDE or y >= CONF.TILE_SIDE) return;
    const idx = @as(usize, y) * CONF.TILE_SIDE + x;
    if (pixels[idx] != old) return;
    pixels[idx] = new;
    if (x > 0) flood(pixels, x - 1, y, old, new);
    if (x + 1 < CONF.TILE_SIDE) flood(pixels, x + 1, y, old, new);
    if (y > 0) flood(pixels, x, y - 1, old, new);
    if (y + 1 < CONF.TILE_SIDE) flood(pixels, x, y + 1, old, new);
}

fn defaultPalettes() [CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor {
    return .{
        .{ .{ 218, 212, 94 }, .{ 210, 125, 44 }, .{ 117, 113, 97 }, .{ 222, 238, 214 } },
        .{ .{ 218, 212, 94 }, .{ 210, 125, 44 }, .{ 89, 125, 206 }, .{ 48, 52, 109 } },
        .{ .{ 218, 212, 94 }, .{ 210, 125, 44 }, .{ 68, 36, 52 }, .{ 48, 52, 109 } },
        .{ .{ 20, 12, 28 }, .{ 117, 113, 97 }, .{ 133, 149, 161 }, .{ 222, 238, 214 } },
        .{ .{ 109, 170, 44 }, .{ 52, 101, 36 }, .{ 78, 74, 79 }, .{ 20, 12, 28 } },
        .{ .{ 109, 194, 202 }, .{ 89, 125, 206 }, .{ 48, 52, 109 }, .{ 20, 12, 28 } },
        .{ .{ 210, 170, 153 }, .{ 208, 70, 72 }, .{ 68, 36, 52 }, .{ 20, 12, 28 } },
        .{ .{ 222, 238, 214 }, .{ 133, 149, 161 }, .{ 117, 113, 97 }, .{ 78, 74, 79 } },
    };
}

fn rgbToU32(rgb: PaletteColor) u32 {
    return (@as(u32, rgb[0]) << 16) | (@as(u32, rgb[1]) << 8) | @as(u32, rgb[2]);
}

fn clampByte(value: i16) u8 {
    return @intCast(@max(0, @min(255, value)));
}
