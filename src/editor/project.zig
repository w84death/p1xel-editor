const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
});
const CONF = @import("../engine/config.zig").CONF;

pub const Tool = enum { pixel, fill, line };
pub const ColorChannel = enum { r, g, b };
pub const ProjectMode = enum(u8) { tiles = 0, sprites = 1 };
pub const PaletteColor = [3]u8;

pub const MAX_MAP_W = 128;
pub const MAX_MAP_H = 32;
pub const MAX_MAP_CELLS = MAX_MAP_W * MAX_MAP_H;
pub const MAX_MAP_SPRITES = 256;

pub const MapSize = enum(u8) { size_32x32 = 0, size_64x16 = 1, size_128x16 = 2 };

pub const TILE_FLAG_TRAVERSABLE: u8 = 1 << 0;

pub const MapTileAttr = struct {
    palette: u8 = 0,
    hflip: bool = false,
    vflip: bool = false,

    pub fn encode(self: MapTileAttr) u8 {
        return (self.palette & 7) | (if (self.hflip) @as(u8, 1) << 5 else 0) | (if (self.vflip) @as(u8, 1) << 6 else 0);
    }

    pub fn decode(value: u8) MapTileAttr {
        return .{ .palette = value & 7, .hflip = (value & (1 << 5)) != 0, .vflip = (value & (1 << 6)) != 0 };
    }
};

pub const MapSprite = struct {
    x: u16 = 0,
    y: u16 = 0,
    sprite_id: u16 = 0,
    palette: u8 = 0,
    hflip: bool = false,
    vflip: bool = false,
};

pub const MapCell = struct {
    tile_id: u8,
    attr: MapTileAttr,
};

pub const Map = struct {
    width: u16 = 32,
    height: u16 = 32,
    tile_ids: [MAX_MAP_CELLS]u8 = [_]u8{0} ** MAX_MAP_CELLS,
    tile_attrs: [MAX_MAP_CELLS]u8 = [_]u8{0} ** MAX_MAP_CELLS,
    sprites: [MAX_MAP_SPRITES]MapSprite = [_]MapSprite{.{}} ** MAX_MAP_SPRITES,
    sprite_count: u16 = 0,
};

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
        if (self.count > CONF.MAX_TILES) self.count = CONF.MAX_TILES;
        if (self.selected >= self.count) self.selected = self.count - 1;
        for (&self.visible_slots, 0..) |*slot, i| {
            if (slot.* >= self.count) slot.* = @intCast(@min(i, @as(usize, self.count - 1)));
        }
    }
};

pub const Project = struct {
    const MAGIC = "P1X2";
    const VERSION: u8 = 9;
    const LEGACY_VERSION: u8 = 5;
    const OLDEST_SUPPORTED_VERSION: u8 = 4;
    pub const IMAGE_BANK_COUNT = 2;
    pub const PALETTE_BANK_COUNT = 4;
    pub const MAP_BANK_COUNT = 4;
    const PALETTE_COLOR_BYTES = 3;
    const PALETTE_BANK_BYTES = CONF.PALETTE_COUNT * CONF.COLORS_PER_PALETTE * PALETTE_COLOR_BYTES;
    const PALETTE_SET_BYTES = PALETTE_BANK_COUNT * PALETTE_BANK_BYTES;
    const PALETTE_BYTES = IMAGE_BANK_COUNT * PALETTE_SET_BYTES;
    const IMAGE_BYTES = 1 + CONF.TILE_SIDE * CONF.TILE_SIDE;
    const IMAGE_BANK_STATE_BYTES = 2 + 2 + 1 + 1 + 1 + 1 + 9 * 2;
    const HEADER_BYTES = 4 + 1 + 1 + 1;
    const MAP_HEADER_BYTES = 2 + 2 + 2;
    const MAP_SPRITE_BYTES = 2 + 2 + 2 + 1;
    const MAP_BYTES = MAP_HEADER_BYTES + MAX_MAP_CELLS * 2 + MAX_MAP_SPRITES * MAP_SPRITE_BYTES;
    const TILE_FLAGS_BYTES = CONF.MAX_TILES;
    const MAX_FILE_BYTES = HEADER_BYTES + 2 + PALETTE_BYTES + TILE_FLAGS_BYTES + IMAGE_BANK_COUNT * (IMAGE_BANK_STATE_BYTES + CONF.MAX_TILES * IMAGE_BYTES) + MAP_BANK_COUNT * MAP_BYTES;

    palette_banks: [IMAGE_BANK_COUNT][PALETTE_BANK_COUNT][CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor = defaultPaletteSets(),
    active_palette_bank: u8 = 0,
    image_banks: [IMAGE_BANK_COUNT]ImageBank = .{ ImageBank{}, ImageBank{} },
    tile_flags: [CONF.MAX_TILES]u8 = [_]u8{TILE_FLAG_TRAVERSABLE} ** CONF.MAX_TILES,
    maps: [MAP_BANK_COUNT]Map = [_]Map{.{}} ** MAP_BANK_COUNT,
    active_map_bank: u8 = 0,
    mode: ProjectMode = .tiles,
    dirty: bool = false,
    visual_revision: u64 = 0,

    pub fn init() Project {
        var project = Project{};
        project.applyDefaultTileset();
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

    pub fn activePaletteBank(self: *const Project) u8 {
        return self.active_palette_bank;
    }

    pub fn activeMapBank(self: *const Project) u8 {
        return self.active_map_bank;
    }

    pub fn setPaletteBank(self: *Project, bank_id: u8) void {
        const next = @min(bank_id, PALETTE_BANK_COUNT - 1);
        if (self.active_palette_bank == next) return;
        self.active_palette_bank = next;
        self.dirty = true;
        self.bumpVisualRevision();
    }

    pub fn setMapBank(self: *Project, bank_id: u8) void {
        const next = @min(bank_id, MAP_BANK_COUNT - 1);
        if (self.active_map_bank == next and self.active_palette_bank == next) return;
        self.active_map_bank = next;
        self.active_palette_bank = next;
        self.dirty = true;
        self.bumpVisualRevision();
    }

    pub fn activeMap(self: anytype) if (@TypeOf(self) == *const Project) *const Map else *Map {
        return &self.maps[self.activeMapBankIndex()];
    }

    pub fn mapAtBank(self: *const Project, bank_id: u8) *const Map {
        return &self.maps[@min(bank_id, MAP_BANK_COUNT - 1)];
    }

    pub fn paletteColorAtBank(self: *const Project, bank_id: u8, palette_id: u8, color_id: u8) PaletteColor {
        return self.paletteColorAtBankMode(self.mode, bank_id, palette_id, color_id);
    }

    pub fn paletteColorAtBankMode(self: *const Project, mode: ProjectMode, bank_id: u8, palette_id: u8, color_id: u8) PaletteColor {
        const safe_bank = @min(bank_id, PALETTE_BANK_COUNT - 1);
        const safe_palette = @min(palette_id, CONF.PALETTE_COUNT - 1);
        const safe_color = @min(color_id, CONF.COLORS_PER_PALETTE - 1);
        return self.palette_banks[@intFromEnum(mode)][safe_bank][safe_palette][safe_color];
    }

    pub fn activePalette(self: *const Project) [CONF.COLORS_PER_PALETTE]PaletteColor {
        return self.palette_banks[self.modeIndex()][self.activePaletteBankIndex()][self.selectedPalette()];
    }

    pub fn color32(self: *const Project, palette_id: u8, color_id: u8) u32 {
        return self.color32Mode(self.mode, palette_id, color_id);
    }

    pub fn color32Mode(self: *const Project, mode: ProjectMode, palette_id: u8, color_id: u8) u32 {
        const safe_palette = @min(palette_id, CONF.PALETTE_COUNT - 1);
        const safe_color = @min(color_id, CONF.COLORS_PER_PALETTE - 1);
        return rgbToU32(self.palette_banks[@intFromEnum(mode)][self.activePaletteBankIndex()][safe_palette][safe_color]);
    }

    pub fn currentColor32(self: *const Project, color_id: u8) u32 {
        return self.color32(self.selectedPalette(), color_id);
    }

    pub fn selectedRgb(self: *const Project) PaletteColor {
        return self.palette_banks[self.modeIndex()][self.activePaletteBankIndex()][self.selectedPalette()][self.selectedColor()];
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

    pub fn imageAtMode(self: *const Project, mode: ProjectMode, image_id: u16) Image {
        return self.image_banks[@intFromEnum(mode)].images[image_id];
    }

    pub fn imageCountMode(self: *const Project, mode: ProjectMode) u16 {
        return @min(self.image_banks[@intFromEnum(mode)].count, CONF.MAX_TILES);
    }

    pub fn visibleSlotMode(self: *const Project, mode: ProjectMode, slot: usize) u16 {
        return self.image_banks[@intFromEnum(mode)].visible_slots[slot];
    }

    pub fn setVisibleSlotMode(self: *Project, mode: ProjectMode, slot: usize, image_id: u16) void {
        if (slot >= 9 or image_id >= self.imageCountMode(mode)) return;
        const bank = &self.image_banks[@intFromEnum(mode)];
        if (bank.visible_slots[slot] == image_id) return;
        bank.visible_slots[slot] = image_id;
        self.dirty = true;
        self.bumpVisualRevision();
    }

    pub fn currentImage(self: *const Project) Image {
        const bank = self.activeBankConst();
        return bank.images[bank.selected];
    }

    pub fn tileFlags(self: *const Project, tile_id: u16) u8 {
        if (tile_id >= CONF.MAX_TILES) return TILE_FLAG_TRAVERSABLE;
        return self.tile_flags[tile_id];
    }

    pub fn selectedTileFlags(self: *const Project) u8 {
        return self.tileFlags(self.selectedImageId());
    }

    pub fn isTileTraversable(self: *const Project, tile_id: u16) bool {
        return (self.tileFlags(tile_id) & TILE_FLAG_TRAVERSABLE) != 0;
    }

    pub fn setSelectedTileTraversable(self: *Project, traversable: bool) void {
        if (self.mode != .tiles) return;
        const tile_id = self.selectedImageId();
        if (tile_id >= CONF.MAX_TILES) return;
        const old = self.tile_flags[tile_id];
        const next = if (traversable) old | TILE_FLAG_TRAVERSABLE else old & ~@as(u8, TILE_FLAG_TRAVERSABLE);
        if (next == old) return;
        self.tile_flags[tile_id] = next;
        self.dirty = true;
        self.bumpVisualRevision();
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

    pub fn copyCurrentPixelsToTransferFile(self: *const Project) !void {
        var path_buf: [512]u8 = undefined;
        const path = try pixelTransferPath(&path_buf);
        const file = c.fopen(path.ptr, "wb") orelse return error.PixelTransferOpenFailed;
        defer _ = c.fclose(file);

        const image = self.currentImage();
        try writeFileBytes(file, "P1XEL_PIXELS_V1\n");
        var y: usize = 0;
        while (y < CONF.TILE_SIDE) : (y += 1) {
            var row: [CONF.TILE_SIDE + 1]u8 = undefined;
            var x: usize = 0;
            while (x < CONF.TILE_SIDE) : (x += 1) {
                row[x] = '0' + (image.pixels[y * CONF.TILE_SIDE + x] & 3);
            }
            row[CONF.TILE_SIDE] = '\n';
            try writeFileBytes(file, &row);
        }
    }

    pub fn pastePixelsFromTransferFile(self: *Project) !void {
        var path_buf: [512]u8 = undefined;
        const path = try pixelTransferPath(&path_buf);
        const file = c.fopen(path.ptr, "rb") orelse return error.PixelTransferOpenFailed;
        defer _ = c.fclose(file);

        var data: [128]u8 = undefined;
        const len = c.fread(&data, 1, data.len, file);
        const header = "P1XEL_PIXELS_V1\n";
        if (len < header.len or !std.mem.eql(u8, data[0..header.len], header)) return error.InvalidPixelTransfer;

        var pixels: [CONF.TILE_SIDE * CONF.TILE_SIDE]u8 = undefined;
        var count: usize = 0;
        var offset: usize = header.len;
        while (offset < len and count < pixels.len) : (offset += 1) {
            const ch = data[offset];
            if (ch >= '0' and ch <= '3') {
                pixels[count] = ch - '0';
                count += 1;
            } else if (ch == '\n' or ch == '\r' or ch == ' ' or ch == '\t') {
                continue;
            } else {
                return error.InvalidPixelTransfer;
            }
        }
        if (count != pixels.len) return error.InvalidPixelTransfer;

        const bank = self.activeBank();
        const image = &bank.images[bank.selected];
        if (std.mem.eql(u8, image.pixels[0..], pixels[0..])) return;
        image.pixels = pixels;
        self.dirty = true;
        self.bumpVisualRevision();
    }

    pub fn adjustSelectedRgb(self: *Project, channel: ColorChannel, delta: i16) void {
        const color = &self.palette_banks[self.modeIndex()][self.activePaletteBankIndex()][self.selectedPalette()][self.selectedColor()];
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

    pub fn mapIndex(self: *const Project, x: u16, y: u16) ?usize {
        if (x >= self.activeMap().width or y >= self.activeMap().height) return null;
        return @as(usize, y) * @as(usize, self.activeMap().width) + x;
    }

    pub fn mapCellAt(self: *const Project, x: u16, y: u16) ?MapCell {
        const idx = self.mapIndex(x, y) orelse return null;
        return .{ .tile_id = self.activeMap().tile_ids[idx], .attr = MapTileAttr.decode(self.activeMap().tile_attrs[idx]) };
    }

    pub fn paintMapTile(self: *Project, x: u16, y: u16, tile_id: u8, attr: MapTileAttr) bool {
        const idx = self.mapIndex(x, y) orelse return false;
        const encoded = attr.encode();
        if (self.activeMap().tile_ids[idx] == tile_id and self.activeMap().tile_attrs[idx] == encoded) return false;
        self.activeMap().tile_ids[idx] = tile_id;
        self.activeMap().tile_attrs[idx] = encoded;
        self.dirty = true;
        self.bumpVisualRevision();
        return true;
    }

    pub fn fillMapTile(self: *Project, x: u16, y: u16, tile_id: u8, attr: MapTileAttr) bool {
        const start = self.mapIndex(x, y) orelse return false;
        const old_id = self.activeMap().tile_ids[start];
        const old_attr = self.activeMap().tile_attrs[start];
        const new_attr = attr.encode();
        if (old_id == tile_id and old_attr == new_attr) return false;

        var stack: [MAX_MAP_CELLS]usize = undefined;
        var top: usize = 0;
        stack[top] = start;
        top += 1;
        var changed = false;
        while (top > 0) {
            top -= 1;
            const idx = stack[top];
            if (self.activeMap().tile_ids[idx] != old_id or self.activeMap().tile_attrs[idx] != old_attr) continue;
            self.activeMap().tile_ids[idx] = tile_id;
            self.activeMap().tile_attrs[idx] = new_attr;
            changed = true;

            const cx = idx % self.activeMap().width;
            const cy = idx / self.activeMap().width;
            if (cx > 0 and top < stack.len) {
                stack[top] = idx - 1;
                top += 1;
            }
            if (cx + 1 < self.activeMap().width and top < stack.len) {
                stack[top] = idx + 1;
                top += 1;
            }
            if (cy > 0 and top < stack.len) {
                stack[top] = idx - self.activeMap().width;
                top += 1;
            }
            if (cy + 1 < self.activeMap().height and top < stack.len) {
                stack[top] = idx + self.activeMap().width;
                top += 1;
            }
        }
        if (!changed) return false;
        self.dirty = true;
        self.bumpVisualRevision();
        return true;
    }

    pub fn resizeMap(self: *Project, width: u16, height: u16) bool {
        if (width == self.activeMap().width and height == self.activeMap().height) return false;
        if (width == 0 or height == 0 or width > MAX_MAP_W or height > MAX_MAP_H) return false;
        var next_ids = [_]u8{0} ** MAX_MAP_CELLS;
        var next_attrs = [_]u8{0} ** MAX_MAP_CELLS;
        const copy_w = @min(width, self.activeMap().width);
        const copy_h = @min(height, self.activeMap().height);
        var y: u16 = 0;
        while (y < copy_h) : (y += 1) {
            var x: u16 = 0;
            while (x < copy_w) : (x += 1) {
                const old_idx = @as(usize, y) * @as(usize, self.activeMap().width) + x;
                const new_idx = @as(usize, y) * @as(usize, width) + x;
                next_ids[new_idx] = self.activeMap().tile_ids[old_idx];
                next_attrs[new_idx] = self.activeMap().tile_attrs[old_idx];
            }
        }
        self.activeMap().width = width;
        self.activeMap().height = height;
        self.activeMap().tile_ids = next_ids;
        self.activeMap().tile_attrs = next_attrs;
        var i: usize = 0;
        while (i < self.activeMap().sprite_count) {
            if (self.activeMap().sprites[i].x >= width or self.activeMap().sprites[i].y >= height) {
                self.activeMap().sprite_count -= 1;
                self.activeMap().sprites[i] = self.activeMap().sprites[self.activeMap().sprite_count];
            } else {
                i += 1;
            }
        }
        self.dirty = true;
        self.bumpVisualRevision();
        return true;
    }

    pub fn addOrUpdateMapSprite(self: *Project, x: u16, y: u16, sprite_id: u16, attr: MapTileAttr) bool {
        if (x >= self.activeMap().width or y >= self.activeMap().height or sprite_id >= self.imageCountMode(.sprites)) return false;
        var i: usize = 0;
        while (i < self.activeMap().sprite_count) : (i += 1) {
            if (self.activeMap().sprites[i].x == x and self.activeMap().sprites[i].y == y) {
                self.activeMap().sprites[i] = .{ .x = x, .y = y, .sprite_id = sprite_id, .palette = attr.palette, .hflip = attr.hflip, .vflip = attr.vflip };
                self.dirty = true;
                self.bumpVisualRevision();
                return true;
            }
        }
        if (self.activeMap().sprite_count >= MAX_MAP_SPRITES) return false;
        self.activeMap().sprites[self.activeMap().sprite_count] = .{ .x = x, .y = y, .sprite_id = sprite_id, .palette = attr.palette, .hflip = attr.hflip, .vflip = attr.vflip };
        self.activeMap().sprite_count += 1;
        self.dirty = true;
        self.bumpVisualRevision();
        return true;
    }

    pub fn removeMapSpriteAt(self: *Project, x: u16, y: u16) bool {
        var i: usize = 0;
        while (i < self.activeMap().sprite_count) : (i += 1) {
            if (self.activeMap().sprites[i].x == x and self.activeMap().sprites[i].y == y) {
                self.activeMap().sprite_count -= 1;
                self.activeMap().sprites[i] = self.activeMap().sprites[self.activeMap().sprite_count];
                self.dirty = true;
                self.bumpVisualRevision();
                return true;
            }
        }
        return false;
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
        const file_version = data[4];
        if (file_version > VERSION or file_version < OLDEST_SUPPORTED_VERSION) return error.InvalidProject;
        if (data[5] != CONF.PALETTE_COUNT) return error.InvalidProject;
        self.mode = switch (data[6]) {
            0 => .tiles,
            1 => .sprites,
            else => return error.InvalidProject,
        };

        var offset: usize = HEADER_BYTES;
        if (file_version >= 6) {
            if (offset + 2 > len) return error.InvalidProject;
            self.active_palette_bank = @min(data[offset], PALETTE_BANK_COUNT - 1);
            offset += 1;
            self.active_map_bank = @min(data[offset], MAP_BANK_COUNT - 1);
            offset += 1;
            if (file_version >= VERSION) {
                for (0..IMAGE_BANK_COUNT) |mode_index| {
                    for (0..PALETTE_BANK_COUNT) |bank| {
                        for (0..CONF.PALETTE_COUNT) |p| {
                            for (0..CONF.COLORS_PER_PALETTE) |color_slot| {
                                if (offset + PALETTE_COLOR_BYTES > len) return error.InvalidProject;
                                self.palette_banks[mode_index][bank][p][color_slot] = .{ data[offset], data[offset + 1], data[offset + 2] };
                                offset += PALETTE_COLOR_BYTES;
                            }
                        }
                    }
                }
            } else {
                var shared_palettes = defaultPaletteBanks();
                for (0..PALETTE_BANK_COUNT) |bank| {
                    for (0..CONF.PALETTE_COUNT) |p| {
                        for (0..CONF.COLORS_PER_PALETTE) |color_slot| {
                            if (offset + PALETTE_COLOR_BYTES > len) return error.InvalidProject;
                            shared_palettes[bank][p][color_slot] = .{ data[offset], data[offset + 1], data[offset + 2] };
                            offset += PALETTE_COLOR_BYTES;
                        }
                    }
                }
                self.palette_banks = duplicatePaletteSets(shared_palettes);
            }
        } else {
            var legacy_palettes = defaultPaletteBanks();
            for (0..IMAGE_BANK_COUNT) |bank| {
                for (0..CONF.PALETTE_COUNT) |p| {
                    for (0..CONF.COLORS_PER_PALETTE) |color_slot| {
                        if (offset + PALETTE_COLOR_BYTES > len) return error.InvalidProject;
                        if (bank == 0) legacy_palettes[0][p][color_slot] = .{ data[offset], data[offset + 1], data[offset + 2] };
                        offset += PALETTE_COLOR_BYTES;
                    }
                }
            }
            self.palette_banks = duplicatePaletteSets(legacy_palettes);
            self.active_palette_bank = 0;
            self.active_map_bank = 0;
        }

        self.tile_flags = [_]u8{TILE_FLAG_TRAVERSABLE} ** CONF.MAX_TILES;
        if (file_version >= 9) {
            if (offset + TILE_FLAGS_BYTES > len) return error.InvalidProject;
            @memcpy(self.tile_flags[0..], data[offset .. offset + TILE_FLAGS_BYTES]);
            offset += TILE_FLAGS_BYTES;
        }

        for (0..IMAGE_BANK_COUNT) |bank_index| {
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

        self.maps = [_]Map{.{}} ** MAP_BANK_COUNT;
        const maps_to_read: usize = if (file_version >= 6) MAP_BANK_COUNT else 1;
        for (0..maps_to_read) |map_bank| {
            if (offset + MAP_HEADER_BYTES > len) return error.InvalidProject;
            const width = readU16(data[offset .. offset + 2]);
            offset += 2;
            const height = readU16(data[offset .. offset + 2]);
            offset += 2;
            const sprite_count = readU16(data[offset .. offset + 2]);
            offset += 2;
            if (width == 0 or height == 0 or width > MAX_MAP_W or height > MAX_MAP_H) return error.InvalidProject;
            var map = &self.maps[map_bank];
            map.width = width;
            map.height = height;
            const cell_count = @as(usize, width) * @as(usize, height);
            if (offset + cell_count * 2 > len) return error.InvalidProject;
            @memcpy(map.tile_ids[0..cell_count], data[offset .. offset + cell_count]);
            offset += cell_count;
            @memcpy(map.tile_attrs[0..cell_count], data[offset .. offset + cell_count]);
            for (map.tile_attrs[0..cell_count]) |*attr| attr.* &= 0x67;
            offset += cell_count;
            map.sprite_count = @min(sprite_count, MAX_MAP_SPRITES);
            if (offset + @as(usize, sprite_count) * MAP_SPRITE_BYTES > len) return error.InvalidProject;
            var i: usize = 0;
            while (i < sprite_count) : (i += 1) {
                const sprite = MapSprite{
                    .x = readU16(data[offset .. offset + 2]),
                    .y = readU16(data[offset + 2 .. offset + 4]),
                    .sprite_id = readU16(data[offset + 4 .. offset + 6]),
                    .palette = data[offset + 6] & 7,
                    .hflip = (data[offset + 6] & (1 << 5)) != 0,
                    .vflip = (data[offset + 6] & (1 << 6)) != 0,
                };
                if (i < MAX_MAP_SPRITES) map.sprites[i] = sprite;
                offset += MAP_SPRITE_BYTES;
            }
        }
        self.ensureDefaultBiomeTiles();
        self.dirty = file_version < VERSION;
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

        var active_state = [_]u8{ self.active_palette_bank, self.active_map_bank };
        if (c.fwrite(&active_state, 1, active_state.len, file) != active_state.len) return error.InvalidProject;

        for (self.palette_banks) |palette_set| {
            for (palette_set) |bank| {
                for (bank) |palette| {
                    for (palette) |color| {
                        if (c.fwrite(&color, 1, color.len, file) != color.len) return error.InvalidProject;
                    }
                }
            }
        }

        if (c.fwrite(&self.tile_flags, 1, self.tile_flags.len, file) != self.tile_flags.len) return error.InvalidProject;

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

        for (self.maps) |map| {
            var map_header: [MAP_HEADER_BYTES]u8 = undefined;
            writeU16(map_header[0..2], map.width);
            writeU16(map_header[2..4], map.height);
            writeU16(map_header[4..6], map.sprite_count);
            if (c.fwrite(&map_header, 1, map_header.len, file) != map_header.len) return error.InvalidProject;
            const cell_count = @as(usize, map.width) * @as(usize, map.height);
            if (c.fwrite(&map.tile_ids, 1, cell_count, file) != cell_count) return error.InvalidProject;
            if (c.fwrite(&map.tile_attrs, 1, cell_count, file) != cell_count) return error.InvalidProject;
            var sprite_buf: [MAP_SPRITE_BYTES]u8 = undefined;
            var si: usize = 0;
            while (si < map.sprite_count) : (si += 1) {
                const sprite = map.sprites[si];
                writeU16(sprite_buf[0..2], sprite.x);
                writeU16(sprite_buf[2..4], sprite.y);
                writeU16(sprite_buf[4..6], sprite.sprite_id);
                sprite_buf[6] = (MapTileAttr{ .palette = sprite.palette, .hflip = sprite.hflip, .vflip = sprite.vflip }).encode();
                if (c.fwrite(&sprite_buf, 1, sprite_buf.len, file) != sprite_buf.len) return error.InvalidProject;
            }
        }
        self.dirty = false;
    }

    fn ensureDefaultBiomeTiles(self: *Project) void {
        _ = self;
    }

    fn applyDefaultTileset(self: *Project) void {
        self.palette_banks = defaultPaletteSets();
        self.active_palette_bank = 0;
        self.active_map_bank = 0;

        var bank = &self.image_banks[@intFromEnum(ProjectMode.tiles)];
        bank.images = [_]Image{.{}} ** CONF.MAX_TILES;
        bank.count = 1;
        bank.selected = 0;
        bank.selected_palette = 0;
        bank.selected_color = 1;
        bank.left_color = 1;
        bank.right_color = 0;
        bank.visible_slots = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0 };

        var sprite_bank = &self.image_banks[@intFromEnum(ProjectMode.sprites)];
        sprite_bank.images = [_]Image{.{}} ** CONF.MAX_TILES;
        sprite_bank.count = 1;
        sprite_bank.selected = 0;
        sprite_bank.selected_palette = 0;
        sprite_bank.selected_color = 1;
        sprite_bank.left_color = 1;
        sprite_bank.right_color = 0;
        sprite_bank.visible_slots = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0 };

        self.tile_flags = [_]u8{TILE_FLAG_TRAVERSABLE} ** CONF.MAX_TILES;
        self.mode = .tiles;
        self.maps = [_]Map{.{}} ** MAP_BANK_COUNT;
        self.dirty = false;
        self.visual_revision = 0;
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

    fn activePaletteBankIndex(self: *const Project) usize {
        return @min(self.active_palette_bank, PALETTE_BANK_COUNT - 1);
    }

    fn activeMapBankIndex(self: *const Project) usize {
        return @min(self.active_map_bank, MAP_BANK_COUNT - 1);
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

const DEFAULT_GRASSLAND_TILE_COUNT: u16 = 33;
const DEFAULT_DESERT_TILE_COUNT: u16 = 19;
const DEFAULT_TILESET_TILE_COUNT: u16 = DEFAULT_GRASSLAND_TILE_COUNT + DEFAULT_DESERT_TILE_COUNT;

fn defaultGrasslandPalettes() [CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor {
    return .{
        .{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } },
        .{ .{ 68, 137, 26 }, .{ 163, 206, 39 }, .{ 173, 157, 51 }, .{ 73, 60, 43 } },
        .{ .{ 68, 137, 26 }, .{ 17, 94, 51 }, .{ 47, 72, 78 }, .{ 163, 206, 39 } },
        .{ .{ 47, 72, 78 }, .{ 17, 94, 51 }, .{ 101, 109, 113 }, .{ 163, 206, 39 } },
        .{ .{ 68, 137, 26 }, .{ 17, 94, 51 }, .{ 47, 72, 78 }, .{ 101, 109, 113 } },
        .{ .{ 68, 137, 26 }, .{ 173, 157, 51 }, .{ 17, 94, 51 }, .{ 164, 100, 34 } },
        .{ .{ 68, 137, 26 }, .{ 17, 94, 51 }, .{ 204, 204, 204 }, .{ 157, 157, 157 } },
        .{ .{ 17, 94, 51 }, .{ 49, 162, 242 }, .{ 68, 137, 26 }, .{ 34, 90, 246 } },
    };
}

const DEFAULT_TILESET_PALETTE_IDS = [_]u8{ 0, 1, 2, 2, 2, 2, 1, 2, 3, 4, 2, 5, 6, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 4, 4 };

const DEFAULT_TILESET_PIXELS = [_][CONF.TILE_SIDE * CONF.TILE_SIDE]u8{
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    .{ 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0 },
    .{ 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0 },
    .{ 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0 },
    .{ 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 2, 1, 0, 0, 0, 0, 1, 1, 1, 2, 1, 0, 0, 0, 1, 1, 1, 2, 1, 0, 0, 1, 1, 1, 2, 1, 2, 1, 0, 1, 1, 1, 1, 2, 1, 2, 1, 0, 1, 2, 2, 1, 2, 1, 0, 0, 0, 2, 2, 2, 0, 0, 0 },
    .{ 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 2, 2, 0, 1, 1, 1, 1, 2, 2, 2, 0, 2, 2, 1, 2, 2, 3, 2, 0, 0, 2, 2, 3, 2, 3, 0, 0, 0, 0, 0, 3, 3, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0 },
    .{ 0, 0, 1, 1, 2, 2, 1, 3, 0, 0, 0, 1, 2, 2, 1, 3, 0, 0, 1, 0, 1, 2, 3, 3, 0, 1, 1, 0, 2, 1, 3, 3, 0, 0, 1, 1, 2, 1, 3, 0, 0, 0, 0, 1, 2, 1, 3, 0, 0, 0, 1, 1, 2, 1, 3, 3, 0, 1, 0, 1, 2, 2, 1, 3 },
    .{ 3, 3, 1, 3, 3, 3, 1, 3, 1, 1, 3, 1, 1, 1, 3, 1, 0, 0, 1, 1, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 2, 2, 2, 2, 1, 2, 0, 0, 0, 0, 2, 1, 0, 2, 2, 2, 2, 2, 0, 2, 2, 2, 1, 2, 0, 0, 0, 2, 0, 0, 0, 0 },
    .{ 0, 0, 0, 0, 1, 2, 2, 1, 0, 0, 0, 1, 1, 3, 2, 2, 0, 0, 0, 0, 3, 1, 3, 2, 0, 0, 0, 0, 1, 1, 3, 2, 0, 1, 1, 0, 0, 1, 1, 2, 0, 0, 0, 1, 0, 1, 3, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1 },
    .{ 3, 3, 3, 0, 0, 0, 0, 0, 1, 1, 3, 3, 3, 3, 0, 0, 2, 2, 1, 1, 1, 3, 3, 0, 2, 1, 2, 2, 2, 1, 3, 0, 1, 1, 2, 1, 2, 1, 3, 3, 0, 1, 1, 1, 2, 2, 1, 3, 1, 0, 0, 1, 2, 1, 1, 3, 0, 0, 2, 1, 2, 2, 1, 3 },
    .{ 0, 0, 0, 1, 2, 0, 0, 0, 0, 0, 1, 3, 1, 0, 0, 0, 0, 0, 2, 1, 2, 0, 1, 0, 0, 1, 0, 2, 0, 1, 3, 1, 1, 3, 1, 0, 0, 2, 1, 2, 2, 1, 2, 0, 1, 0, 2, 0, 0, 2, 0, 1, 2, 1, 0, 0, 0, 0, 0, 2, 1, 2, 0, 0 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 1, 1, 0, 2, 3, 2, 3, 3, 0, 0, 0, 2, 2, 3, 3, 3, 1, 1, 0, 0, 1, 1, 2, 2, 1, 1, 0, 1, 0, 2, 2, 3, 3, 0, 0, 0, 0, 1, 3, 3, 1, 1, 0, 0, 1, 0, 1, 1, 1, 0 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 2, 2, 2, 0, 0, 0, 0, 2, 2, 2, 3, 3, 1, 0, 0, 2, 2, 3, 3, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 0, 0, 1, 0, 1, 2, 3, 2, 1, 0, 0, 0, 0, 2, 2, 2, 3, 1, 0, 0, 1, 2, 2, 3, 3, 1, 1, 1, 2, 2, 3, 2, 2, 3, 1, 0, 1, 1, 1, 3, 3, 1, 1, 0, 0, 0, 1, 1, 1, 1, 0 },
    .{ 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3 },
    .{ 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 1, 1, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 1, 1, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3 },
    .{ 2, 2, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 0, 2, 2, 2, 1, 1, 1, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 3, 3, 1, 1, 1, 1, 1, 3, 3, 3, 3, 3, 3, 3, 3, 3 },
    .{ 0, 2, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 2, 0, 0, 0, 2, 2, 2, 2, 2, 2, 0, 0, 1, 1, 1, 1, 2, 2, 0, 0, 3, 3, 1, 1, 1, 2, 2, 0, 3, 3, 3, 1, 1, 2, 2, 0 },
    .{ 3, 3, 3, 3, 1, 2, 0, 2, 3, 3, 3, 3, 1, 2, 0, 2, 3, 3, 3, 3, 1, 2, 0, 0, 3, 3, 3, 3, 1, 1, 2, 0, 3, 3, 3, 1, 1, 1, 2, 0, 3, 3, 3, 1, 1, 2, 0, 0, 3, 3, 3, 1, 1, 2, 0, 0, 3, 3, 3, 3, 1, 2, 0, 0 },
    .{ 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 1, 1, 3, 3, 3, 3, 3, 1, 2, 2, 3, 3, 3, 3, 1, 2, 2, 0 },
    .{ 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 1, 1, 1, 1, 1, 1, 3, 3, 2, 2, 2, 0, 0, 0, 1, 1, 0, 0, 0, 2, 2, 2, 0, 0 },
    .{ 3, 3, 3, 3, 1, 1, 2, 0, 3, 3, 3, 3, 1, 1, 2, 0, 3, 3, 3, 3, 3, 1, 2, 0, 3, 3, 3, 3, 1, 1, 2, 0, 3, 3, 3, 3, 1, 1, 2, 0, 1, 1, 1, 1, 1, 2, 2, 0, 1, 1, 1, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 2, 2, 2 },
    .{ 3, 3, 3, 3, 1, 2, 2, 0, 3, 3, 3, 3, 1, 1, 2, 0, 3, 3, 3, 3, 3, 1, 2, 2, 3, 3, 3, 3, 3, 1, 1, 2, 3, 3, 3, 3, 3, 3, 1, 1, 3, 3, 3, 3, 3, 3, 3, 1, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3 },
    .{ 2, 2, 0, 3, 1, 3, 2, 2, 0, 2, 2, 2, 3, 1, 0, 2, 2, 2, 0, 0, 1, 3, 1, 2, 0, 0, 3, 1, 3, 1, 3, 2, 0, 3, 1, 3, 1, 2, 2, 2, 0, 1, 3, 1, 3, 0, 2, 2, 2, 3, 1, 3, 1, 3, 0, 0, 2, 2, 3, 1, 3, 1, 3, 2 },
    .{ 2, 0, 1, 3, 1, 0, 2, 2, 0, 0, 3, 1, 3, 0, 0, 0, 0, 0, 1, 3, 1, 1, 0, 0, 0, 1, 3, 1, 3, 1, 2, 0, 2, 1, 1, 3, 1, 3, 1, 2, 1, 1, 3, 1, 3, 1, 3, 1, 3, 3, 1, 3, 1, 3, 3, 3, 3, 1, 3, 3, 3, 3, 1, 3 },
    .{ 2, 0, 0, 2, 2, 2, 2, 2, 0, 1, 3, 0, 0, 2, 0, 0, 1, 3, 1, 3, 0, 0, 1, 3, 3, 1, 3, 1, 3, 1, 3, 1, 1, 3, 1, 3, 1, 3, 1, 3, 0, 2, 2, 1, 3, 1, 2, 0, 2, 0, 2, 2, 2, 2, 0, 2, 2, 2, 0, 2, 2, 2, 2, 2 },
    .{ 2, 2, 2, 2, 2, 2, 2, 2, 0, 2, 2, 0, 0, 0, 0, 2, 2, 0, 0, 3, 1, 3, 1, 3, 0, 0, 3, 1, 3, 1, 2, 1, 0, 3, 1, 3, 1, 2, 2, 2, 0, 1, 3, 1, 3, 0, 2, 0, 2, 0, 1, 3, 1, 3, 2, 2, 2, 2, 3, 1, 3, 2, 2, 2 },
    .{ 2, 2, 0, 3, 1, 3, 2, 2, 0, 2, 0, 1, 3, 1, 2, 2, 0, 0, 1, 3, 1, 3, 0, 2, 3, 1, 3, 1, 3, 1, 2, 0, 1, 3, 1, 3, 1, 2, 2, 2, 0, 1, 2, 2, 2, 2, 0, 0, 2, 2, 2, 0, 0, 0, 2, 2, 2, 2, 0, 2, 2, 2, 2, 2 },
    .{ 3, 3, 3, 3, 3, 3, 3, 3, 3, 1, 3, 3, 3, 3, 1, 3, 3, 3, 3, 1, 3, 3, 3, 3, 3, 3, 3, 3, 3, 1, 3, 3, 3, 3, 1, 3, 1, 3, 1, 3, 1, 1, 3, 1, 3, 1, 3, 3, 2, 2, 1, 3, 1, 3, 1, 1, 0, 0, 2, 1, 3, 1, 0, 0 },
    .{ 3, 3, 3, 3, 1, 2, 0, 2, 3, 1, 3, 3, 1, 0, 0, 2, 3, 3, 1, 3, 1, 1, 0, 0, 1, 3, 3, 1, 3, 1, 3, 1, 3, 3, 1, 3, 1, 3, 1, 3, 3, 3, 3, 1, 3, 1, 0, 0, 3, 3, 1, 3, 1, 2, 0, 0, 1, 3, 3, 3, 1, 2, 0, 0 },
    .{ 0, 0, 1, 2, 2, 2, 0, 0, 1, 0, 2, 3, 3, 2, 1, 0, 0, 0, 1, 3, 3, 3, 3, 0, 1, 1, 3, 2, 3, 3, 3, 2, 1, 2, 3, 3, 2, 2, 2, 0, 1, 3, 3, 3, 2, 1, 0, 0, 0, 2, 3, 2, 3, 3, 1, 1, 0, 0, 2, 2, 3, 3, 2, 0 },
    .{ 0, 1, 1, 1, 0, 0, 0, 0, 1, 2, 3, 2, 2, 1, 2, 1, 2, 3, 3, 2, 3, 3, 3, 2, 3, 3, 3, 2, 3, 3, 2, 3, 3, 3, 2, 3, 2, 2, 3, 3, 2, 2, 3, 3, 3, 3, 2, 1, 0, 1, 1, 2, 2, 2, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0 },
};

fn defaultDesertPalettes() [CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor {
    return .{
        .{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } },
        .{ .{ 235, 137, 49 }, .{ 164, 100, 34 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } },
        .{ .{ 235, 137, 49 }, .{ 68, 137, 26 }, .{ 17, 94, 51 }, .{ 164, 100, 34 } },
        .{ .{ 235, 137, 49 }, .{ 250, 180, 11 }, .{ 164, 100, 34 }, .{ 0, 0, 0 } },
        .{ .{ 157, 157, 157 }, .{ 164, 100, 34 }, .{ 235, 137, 49 }, .{ 82, 79, 64 } },
        .{ .{ 34, 90, 246 }, .{ 49, 162, 242 }, .{ 235, 137, 49 }, .{ 82, 79, 64 } },
        .{ .{ 164, 100, 34 }, .{ 235, 137, 49 }, .{ 247, 226, 107 }, .{ 250, 180, 11 } },
        .{ .{ 178, 220, 239 }, .{ 164, 100, 34 }, .{ 21, 194, 165 }, .{ 235, 137, 49 } },
    };
}

const DEFAULT_DESERT_PALETTE_IDS = [_]u8{ 0, 1, 1, 1, 2, 3, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 6, 7 };

const DEFAULT_DESERT_PIXELS = [_][CONF.TILE_SIDE * CONF.TILE_SIDE]u8{
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    .{ 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0 },
    .{ 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1 },
    .{ 0, 0, 0, 1, 1, 1, 1, 0, 1, 0, 1, 1, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0 },
    .{ 0, 0, 0, 1, 2, 0, 1, 0, 0, 0, 0, 1, 2, 0, 1, 0, 0, 1, 0, 1, 2, 0, 2, 0, 0, 2, 0, 1, 1, 1, 2, 0, 0, 2, 1, 1, 2, 0, 0, 0, 0, 0, 0, 1, 2, 0, 0, 0, 0, 0, 0, 1, 2, 3, 3, 3, 0, 0, 0, 3, 3, 3, 0, 0 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 1, 2, 2, 0, 1, 2, 2, 0, 0, 0, 0 },
    .{ 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 2, 2, 0, 0, 0, 1, 2, 2, 2, 0, 3, 3, 0, 0, 2, 1, 1, 0, 3, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 3, 2, 0, 0, 0, 3, 3, 3, 3, 2, 0, 3, 3, 1, 1, 1, 1, 1, 3, 3, 1, 1, 2, 2, 1 },
    .{ 2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 1, 1, 2, 0, 0, 2, 2, 2, 0, 0, 0, 3, 3, 0, 2, 1, 3, 3, 0, 0, 3, 0, 0, 0, 0, 1, 3, 3, 0, 3, 3, 3, 0, 0, 1, 3, 0, 1, 1, 1, 3, 0, 1, 0, 3, 2, 1, 2, 1, 3, 2, 3, 1, 2 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0 },
    .{ 0, 0, 0, 0, 1, 2, 3, 2, 0, 0, 0, 1, 1, 2, 3, 2, 0, 0, 0, 1, 1, 2, 3, 3, 0, 0, 0, 0, 1, 2, 2, 3, 0, 0, 0, 1, 1, 1, 2, 3, 0, 0, 0, 1, 1, 2, 3, 2, 0, 0, 0, 0, 1, 2, 3, 2, 0, 0, 0, 1, 1, 2, 3, 2 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 2, 0, 0, 0, 0, 1, 1, 2, 3, 0, 0, 0, 0, 1, 1, 2, 3 },
    .{ 0, 0, 0, 1, 1, 2, 3, 2, 0, 0, 0, 1, 1, 2, 3, 3, 0, 0, 1, 1, 1, 2, 2, 3, 1, 1, 1, 1, 2, 2, 3, 2, 2, 2, 2, 2, 2, 2, 3, 2, 2, 3, 3, 3, 2, 3, 2, 2, 3, 2, 2, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2 },
    .{ 0, 0, 0, 1, 1, 2, 3, 3, 0, 0, 0, 0, 1, 2, 3, 3, 0, 0, 0, 0, 0, 1, 2, 3, 0, 0, 0, 0, 0, 1, 1, 2, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    .{ 3, 3, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 2, 2, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 3, 3, 3, 3, 1, 1, 3, 3, 2, 2, 2, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2 },
    .{ 3, 2, 2, 3, 3, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 2, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 3, 3, 3, 1, 1, 1, 2, 2, 2, 3, 3, 1, 1, 1, 1, 2, 2, 3, 3, 0, 0, 1, 1, 1, 2, 3, 3, 0, 0, 0, 1, 1, 2, 3, 3 },
    .{ 0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 0, 2, 2, 0, 1, 0, 0, 0, 2, 2, 3, 2, 0, 1, 1, 0, 2, 2, 3, 2, 0, 1, 1, 0, 2, 2, 3, 2, 0, 0, 0, 3, 2, 3, 3, 3, 0, 1, 0, 2, 3, 3, 2, 2, 3, 1, 1, 3, 0, 0, 2, 3, 1, 0 },
    .{ 3, 3, 3, 0, 0, 3, 1, 0, 3, 3, 0, 2, 0, 2, 3, 2, 0, 1, 0, 0, 2, 0, 0, 3, 2, 3, 1, 2, 2, 0, 2, 3, 1, 1, 0, 0, 2, 2, 0, 1, 1, 2, 0, 2, 0, 1, 1, 1, 3, 2, 2, 0, 2, 1, 0, 3, 3, 1, 1, 1, 1, 3, 2, 1 },
};

fn defaultPaletteBanks() [Project.PALETTE_BANK_COUNT][CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor {
    return [_][CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor{defaultClearPalettes()} ** Project.PALETTE_BANK_COUNT;
}

fn defaultClearPalettes() [CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor {
    const grayscale = [CONF.COLORS_PER_PALETTE]PaletteColor{
        .{ 0, 0, 0 },
        .{ 85, 85, 85 },
        .{ 170, 170, 170 },
        .{ 255, 255, 255 },
    };
    return [_][CONF.COLORS_PER_PALETTE]PaletteColor{grayscale} ** CONF.PALETTE_COUNT;
}

fn defaultPaletteSets() [Project.IMAGE_BANK_COUNT][Project.PALETTE_BANK_COUNT][CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor {
    return duplicatePaletteSets(defaultPaletteBanks());
}

fn duplicatePaletteSets(shared: [Project.PALETTE_BANK_COUNT][CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor) [Project.IMAGE_BANK_COUNT][Project.PALETTE_BANK_COUNT][CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor {
    var sets: [Project.IMAGE_BANK_COUNT][Project.PALETTE_BANK_COUNT][CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor = undefined;
    for (&sets) |*set| set.* = shared;
    return sets;
}

fn defaultTilePalettes() [CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor {
    return defaultClearPalettes();
}
fn pixelTransferPath(buf: *[512]u8) ![:0]u8 {
    const filename = "p1xel_image_clip.p1xpix";
    const dir = if (c.getenv("TEMP")) |value| std.mem.span(value) else if (c.getenv("TMPDIR")) |value| std.mem.span(value) else if (c.getenv("TMP")) |value| std.mem.span(value) else "/tmp";
    const sep: u8 = if (dir.len > 0 and (dir[dir.len - 1] == '/' or dir[dir.len - 1] == '\\')) 0 else '/';
    if (sep == 0) return std.fmt.bufPrintZ(buf, "{s}{s}", .{ dir, filename });
    return std.fmt.bufPrintZ(buf, "{s}{c}{s}", .{ dir, sep, filename });
}

fn writeFileBytes(file: *c.FILE, bytes: []const u8) !void {
    if (c.fwrite(bytes.ptr, 1, bytes.len, file) != bytes.len) return error.PixelTransferWriteFailed;
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
