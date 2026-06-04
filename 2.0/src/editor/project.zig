const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
});
const CONF = @import("../engine/config.zig").CONF;

pub const Tool = enum { pixel, fill, line };
pub const ColorChannel = enum { r, g, b };
pub const ProjectMode = enum(u8) { tiles = 0, sprites = 1 };
pub const PaletteColor = [3]u8;

pub const Image = struct {
    palette_id: u8 = 0,
    pixels: [CONF.TILE_SIDE * CONF.TILE_SIDE]u8 = [_]u8{0} ** (CONF.TILE_SIDE * CONF.TILE_SIDE),

    pub fn is_empty(self: Image) bool {
        for (self.pixels) |px| if (px != 0) return false;
        return true;
    }
};

pub const Tile = Image;

const ImageBank = struct {
    images: [CONF.MAX_TILES]Image = [_]Image{.{}} ** CONF.MAX_TILES,
    count: u16 = 1,
    selected: u16 = 0,
    selected_palette: u8 = 0,
    selected_color: u8 = 1,
    left_color: u8 = 1,
    right_color: u8 = 0,
    visible_slots: [9]u16 = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8 },

    fn ensureSlotBounds(self: *ImageBank) void {
        if (self.count == 0) self.count = 1;
        if (self.selected >= self.count) self.selected = self.count - 1;
        for (&self.visible_slots, 0..) |*slot, i| {
            if (slot.* >= self.count) slot.* = @intCast(@min(i, @as(usize, self.count - 1)));
        }
    }
};

pub const Project = struct {
    const MAGIC = "P1X2";
    const VERSION: u8 = 4;
    const BANK_COUNT = 2;
    const PALETTE_COLOR_BYTES = 3;
    const PALETTE_BANK_BYTES = CONF.PALETTE_COUNT * CONF.COLORS_PER_PALETTE * PALETTE_COLOR_BYTES;
    const PALETTE_BYTES = BANK_COUNT * PALETTE_BANK_BYTES;
    const IMAGE_BYTES = 1 + CONF.TILE_SIDE * CONF.TILE_SIDE;
    const IMAGE_BANK_STATE_BYTES = 2 + 2 + 1 + 1 + 1 + 1 + 9 * 2;
    const HEADER_BYTES = 4 + 1 + 1 + 1;
    const MAX_FILE_BYTES = HEADER_BYTES + PALETTE_BYTES + BANK_COUNT * (IMAGE_BANK_STATE_BYTES + CONF.MAX_TILES * IMAGE_BYTES);

    palette_banks: [BANK_COUNT][CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor = defaultPaletteBanks(),
    image_banks: [BANK_COUNT]ImageBank = .{ ImageBank{}, ImageBank{} },
    mode: ProjectMode = .tiles,
    dirty: bool = false,
    visual_revision: u64 = 0,

    pub fn init() Project {
        var project = Project{};
        project.ensureBankBounds();
        return project;
    }

    pub fn loadOrDefault() Project {
        var project = Project.init();
        project.load() catch return project;
        project.ensureBankBounds();
        return project;
    }

    pub fn setMode(self: *Project, mode: ProjectMode) void {
        if (self.mode == mode) return;
        self.mode = mode;
        self.activeBank().ensureSlotBounds();
        self.dirty = true;
        self.bumpVisualRevision();
    }

    pub fn isSpriteMode(self: *const Project) bool {
        return self.mode == .sprites;
    }

    pub fn isTransparentColor(self: *const Project, color_id: u8) bool {
        return self.isSpriteMode() and color_id == 0;
    }

    pub fn activePalette(self: *const Project) [CONF.COLORS_PER_PALETTE]PaletteColor {
        return self.palette_banks[self.modeIndex()][self.selectedPalette()];
    }

    pub fn color32(self: *const Project, palette_id: u8, color_id: u8) u32 {
        const safe_palette = @min(palette_id, CONF.PALETTE_COUNT - 1);
        const safe_color = @min(color_id, CONF.COLORS_PER_PALETTE - 1);
        return rgbToU32(self.palette_banks[self.modeIndex()][safe_palette][safe_color]);
    }

    pub fn currentColor32(self: *const Project, color_id: u8) u32 {
        return self.color32(self.selectedPalette(), color_id);
    }

    pub fn selectedRgb(self: *const Project) PaletteColor {
        return self.palette_banks[self.modeIndex()][self.selectedPalette()][self.selectedColor()];
    }

    pub fn imageCount(self: *const Project) u16 {
        return self.activeBankConst().count;
    }

    pub fn selectedImageId(self: *const Project) u16 {
        return self.activeBankConst().selected;
    }

    pub fn selectedPalette(self: *const Project) u8 {
        return self.activeBankConst().selected_palette;
    }

    pub fn selectedColor(self: *const Project) u8 {
        return self.activeBankConst().selected_color;
    }

    pub fn leftColor(self: *const Project) u8 {
        return self.activeBankConst().left_color;
    }

    pub fn rightColor(self: *const Project) u8 {
        return self.activeBankConst().right_color;
    }

    pub fn setLeftColor(self: *Project, color: u8) void {
        const bank = self.activeBank();
        const next = @min(color, CONF.COLORS_PER_PALETTE - 1);
        if (bank.left_color == next) return;
        bank.left_color = next;
    }

    pub fn setRightColor(self: *Project, color: u8) void {
        const bank = self.activeBank();
        const next = @min(color, CONF.COLORS_PER_PALETTE - 1);
        if (bank.right_color == next) return;
        bank.right_color = next;
    }

    pub fn setPaletteSelection(self: *Project, palette_id: u8, color_id: u8) void {
        const bank = self.activeBank();
        const next_palette = @min(palette_id, CONF.PALETTE_COUNT - 1);
        const next_color = @min(color_id, CONF.COLORS_PER_PALETTE - 1);
        const changed = bank.selected_palette != next_palette or bank.selected_color != next_color or bank.images[bank.selected].palette_id != next_palette;
        bank.selected_palette = next_palette;
        bank.selected_color = next_color;
        bank.images[bank.selected].palette_id = bank.selected_palette;
        if (!changed) return;
        self.dirty = true;
        self.bumpVisualRevision();
    }

    pub fn imageAt(self: *const Project, image_id: u16) Image {
        return self.activeBankConst().images[image_id];
    }

    pub fn currentImage(self: *const Project) Image {
        const bank = self.activeBankConst();
        return bank.images[bank.selected];
    }

    pub fn visibleSlot(self: *const Project, slot: usize) u16 {
        return self.activeBankConst().visible_slots[slot];
    }

    pub fn setVisibleSlot(self: *Project, slot: usize, image_id: u16) void {
        if (slot >= 9 or image_id >= self.imageCount()) return;
        const bank = self.activeBank();
        if (bank.visible_slots[slot] == image_id) return;
        bank.visible_slots[slot] = image_id;
        self.dirty = true;
        self.bumpVisualRevision();
    }

    pub fn nonEmptyTiles(self: *const Project) u16 {
        var count: u16 = 0;
        const bank = self.activeBankConst();
        var i: usize = 0;
        while (i < bank.count) : (i += 1) {
            if (!bank.images[i].is_empty()) count += 1;
        }
        return count;
    }

    pub fn selectTile(self: *Project, image_id: u16) void {
        const bank = self.activeBank();
        if (image_id >= bank.count) return;
        const next_palette = @min(bank.images[image_id].palette_id, CONF.PALETTE_COUNT - 1);
        const changed = bank.selected != image_id or bank.selected_palette != next_palette;
        bank.selected = image_id;
        bank.selected_palette = next_palette;
        if (!changed) return;
        self.dirty = true;
        self.bumpVisualRevision();
    }

    pub fn paintPixel(self: *Project, x: u8, y: u8, color: u8) bool {
        if (x >= CONF.TILE_SIDE or y >= CONF.TILE_SIDE) return false;
        const bank = self.activeBank();
        const idx = @as(usize, y) * CONF.TILE_SIDE + x;
        const new = color & 3;
        if (bank.images[bank.selected].pixels[idx] == new and bank.images[bank.selected].palette_id == bank.selected_palette) return false;
        bank.images[bank.selected].pixels[idx] = new;
        bank.images[bank.selected].palette_id = bank.selected_palette;
        self.dirty = true;
        self.bumpVisualRevision();
        return true;
    }

    pub fn fill(self: *Project, x: u8, y: u8, color: u8) bool {
        if (x >= CONF.TILE_SIDE or y >= CONF.TILE_SIDE) return false;
        const bank = self.activeBank();
        const start = @as(usize, y) * CONF.TILE_SIDE + x;
        const old = bank.images[bank.selected].pixels[start];
        const new = color & 3;
        if (old == new) {
            if (bank.images[bank.selected].palette_id == bank.selected_palette) return false;
            bank.images[bank.selected].palette_id = bank.selected_palette;
            self.dirty = true;
            self.bumpVisualRevision();
            return true;
        }
        flood(&bank.images[bank.selected].pixels, x, y, old, new);
        bank.images[bank.selected].palette_id = bank.selected_palette;
        self.dirty = true;
        self.bumpVisualRevision();
        return true;
    }

    pub fn drawLine(self: *Project, x0_in: i32, y0_in: i32, x1: i32, y1: i32, color: u8) bool {
        var changed = false;
        var x0 = x0_in;
        var y0 = y0_in;
        const dx: i32 = @intCast(@abs(x1 - x0));
        const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
        const sx: i32 = if (x0 < x1) 1 else -1;
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err = dx + dy;
        while (true) {
            if (x0 >= 0 and x0 < CONF.TILE_SIDE and y0 >= 0 and y0 < CONF.TILE_SIDE) changed = self.paintPixel(@intCast(x0), @intCast(y0), color) or changed;
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
        return changed;
    }

    pub fn createTile(self: *Project) ?u16 {
        const bank = self.activeBank();
        if (bank.count >= CONF.MAX_TILES) return null;
        const id = bank.count;
        bank.images[id] = .{ .palette_id = bank.selected_palette };
        bank.count += 1;
        bank.visible_slots[id % bank.visible_slots.len] = id;
        bank.selected = id;
        self.dirty = true;
        self.bumpVisualRevision();
        return id;
    }

    pub fn duplicateTile(self: *Project, id: u16) ?u16 {
        const bank = self.activeBank();
        if (id >= bank.count or bank.count >= CONF.MAX_TILES) return null;
        const new_id = bank.count;
        bank.images[new_id] = bank.images[id];
        bank.count += 1;
        bank.selected = new_id;
        bank.selected_palette = bank.images[new_id].palette_id;
        self.dirty = true;
        self.bumpVisualRevision();
        return new_id;
    }

    pub fn deleteTile(self: *Project, id: u16) void {
        const bank = self.activeBank();
        if (bank.count <= 1 or id >= bank.count) return;
        var i: usize = id;
        while (i + 1 < bank.count) : (i += 1) bank.images[i] = bank.images[i + 1];
        bank.count -= 1;
        for (&bank.visible_slots) |*slot| {
            if (slot.* == id) slot.* = 0 else if (slot.* > id) slot.* -= 1;
        }
        if (bank.selected >= bank.count) bank.selected = bank.count - 1;
        bank.selected_palette = bank.images[bank.selected].palette_id;
        self.dirty = true;
        self.bumpVisualRevision();
    }

    pub fn moveTileLeft(self: *Project, id: u16) void {
        if (id == 0 or id >= self.imageCount()) return;
        self.swapTileIds(id, id - 1);
        self.activeBank().selected = id - 1;
    }

    pub fn moveTileRight(self: *Project, id: u16) void {
        if (id + 1 >= self.imageCount()) return;
        self.swapTileIds(id, id + 1);
        self.activeBank().selected = id + 1;
    }

    pub fn swapTileIds(self: *Project, a: u16, b: u16) void {
        const bank = self.activeBank();
        if (a >= bank.count or b >= bank.count or a == b) return;
        const tmp = bank.images[a];
        bank.images[a] = bank.images[b];
        bank.images[b] = tmp;
        for (&bank.visible_slots) |*slot| {
            if (slot.* == a) slot.* = b else if (slot.* == b) slot.* = a;
        }
        if (bank.selected == a) bank.selected = b else if (bank.selected == b) bank.selected = a;
        self.dirty = true;
        self.bumpVisualRevision();
    }

    pub fn adjustSelectedRgb(self: *Project, channel: ColorChannel, delta: i16) void {
        const color = &self.palette_banks[self.modeIndex()][self.selectedPalette()][self.selectedColor()];
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
        self.bumpVisualRevision();
    }

    pub fn visualRevision(self: *const Project) u64 {
        return self.visual_revision;
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
        self.mode = switch (data[6]) {
            0 => .tiles,
            1 => .sprites,
            else => return error.InvalidProject,
        };

        var offset: usize = HEADER_BYTES;
        for (0..BANK_COUNT) |bank| {
            for (0..CONF.PALETTE_COUNT) |p| {
                for (0..CONF.COLORS_PER_PALETTE) |color_slot| {
                    if (offset + PALETTE_COLOR_BYTES > len) return error.InvalidProject;
                    self.palette_banks[bank][p][color_slot] = .{ data[offset], data[offset + 1], data[offset + 2] };
                    offset += PALETTE_COLOR_BYTES;
                }
            }
        }

        for (0..BANK_COUNT) |bank_index| {
            if (offset + IMAGE_BANK_STATE_BYTES > len) return error.InvalidProject;
            var bank = &self.image_banks[bank_index];
            bank.count = readU16(data[offset .. offset + 2]);
            offset += 2;
            bank.selected = readU16(data[offset .. offset + 2]);
            offset += 2;
            bank.selected_palette = @min(data[offset], CONF.PALETTE_COUNT - 1);
            offset += 1;
            bank.selected_color = @min(data[offset], CONF.COLORS_PER_PALETTE - 1);
            offset += 1;
            bank.left_color = @min(data[offset], CONF.COLORS_PER_PALETTE - 1);
            offset += 1;
            bank.right_color = @min(data[offset], CONF.COLORS_PER_PALETTE - 1);
            offset += 1;
            for (&bank.visible_slots) |*slot| {
                slot.* = readU16(data[offset .. offset + 2]);
                offset += 2;
            }
            if (bank.count == 0 or bank.count > CONF.MAX_TILES) return error.InvalidProject;
            const images_bytes = @as(usize, bank.count) * IMAGE_BYTES;
            if (offset + images_bytes > len) return error.InvalidProject;
            for (0..bank.count) |i| {
                bank.images[i].palette_id = @min(data[offset], CONF.PALETTE_COUNT - 1);
                offset += 1;
                @memcpy(bank.images[i].pixels[0..], data[offset .. offset + CONF.TILE_SIDE * CONF.TILE_SIDE]);
                for (&bank.images[i].pixels) |*px| px.* &= 3;
                offset += CONF.TILE_SIDE * CONF.TILE_SIDE;
            }
            bank.ensureSlotBounds();
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
        header[6] = @intFromEnum(self.mode);
        if (c.fwrite(&header, 1, header.len, file) != header.len) return error.InvalidProject;

        for (self.palette_banks) |bank| {
            for (bank) |palette| {
                for (palette) |color| {
                    if (c.fwrite(&color, 1, color.len, file) != color.len) return error.InvalidProject;
                }
            }
        }

        for (self.image_banks) |bank| {
            var state: [IMAGE_BANK_STATE_BYTES]u8 = undefined;
            var offset: usize = 0;
            writeU16(state[offset .. offset + 2], bank.count);
            offset += 2;
            writeU16(state[offset .. offset + 2], bank.selected);
            offset += 2;
            state[offset] = bank.selected_palette;
            offset += 1;
            state[offset] = bank.selected_color;
            offset += 1;
            state[offset] = bank.left_color;
            offset += 1;
            state[offset] = bank.right_color;
            offset += 1;
            for (bank.visible_slots) |slot| {
                writeU16(state[offset .. offset + 2], slot);
                offset += 2;
            }
            if (c.fwrite(&state, 1, state.len, file) != state.len) return error.InvalidProject;

            var image_buf: [IMAGE_BYTES]u8 = undefined;
            var i: usize = 0;
            while (i < bank.count) : (i += 1) {
                image_buf[0] = bank.images[i].palette_id;
                @memcpy(image_buf[1..], bank.images[i].pixels[0..]);
                if (c.fwrite(&image_buf, 1, image_buf.len, file) != image_buf.len) return error.InvalidProject;
            }
        }
        self.dirty = false;
    }

    fn activeBank(self: *Project) *ImageBank {
        return &self.image_banks[self.modeIndex()];
    }

    fn activeBankConst(self: *const Project) *const ImageBank {
        return &self.image_banks[self.modeIndex()];
    }

    fn modeIndex(self: *const Project) usize {
        return @intFromEnum(self.mode);
    }

    fn ensureBankBounds(self: *Project) void {
        for (&self.image_banks) |*bank| bank.ensureSlotBounds();
    }

    fn bumpVisualRevision(self: *Project) void {
        self.visual_revision +%= 1;
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

fn defaultPaletteBanks() [Project.BANK_COUNT][CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor {
    const tile_palettes = defaultTilePalettes();
    var sprite_palettes = tile_palettes;
    for (0..CONF.PALETTE_COUNT) |p| sprite_palettes[p][0] = .{ 0, 0, 0 };
    return .{ tile_palettes, sprite_palettes };
}

fn defaultTilePalettes() [CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor {
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

fn readU16(bytes: []const u8) u16 {
    return @as(u16, bytes[0]) | (@as(u16, bytes[1]) << 8);
}

fn writeU16(bytes: []u8, value: u16) void {
    bytes[0] = @intCast(value & 0xFF);
    bytes[1] = @intCast(value >> 8);
}

fn rgbToU32(rgb: PaletteColor) u32 {
    return (@as(u32, rgb[0]) << 16) | (@as(u32, rgb[1]) << 8) | @as(u32, rgb[2]);
}

fn clampByte(value: i16) u8 {
    return @intCast(@max(0, @min(255, value)));
}
