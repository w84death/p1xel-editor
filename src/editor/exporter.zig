const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
});
const CONF = @import("../engine/config.zig").CONF;
const project_mod = @import("project.zig");
const Project = project_mod.Project;
const Image = project_mod.Image;
const Map = project_mod.Map;
const PaletteColor = project_mod.PaletteColor;

pub const ENGINE_EXPORT_PATH = "engine_export.p1xb";

pub fn errorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.ExportOpenFailed => "Export open failed",
        error.ExportWriteFailed => "Export write failed",
        else => "Export failed",
    };
}

const BG_TILE_BASE: u8 = 6;
const ENGINE_MAP_W: u16 = 32;
const ENGINE_MAP_H: u16 = 32;
const MAX_BG_TILES: u16 = 256 - @as(u16, BG_TILE_BASE);
const EXPORT_VERSION: u8 = 1;

const ExportLevel = struct {
    label: []const u8,
    bank_id: u8,
};

const LEVELS = [_]ExportLevel{
    .{ .label = "GrasslandLevel", .bank_id = 0 },
    .{ .label = "DesertLevel", .bank_id = 1 },
};

pub fn exportGameBoyEngine(project: *const Project) !void {
    std.debug.print("[export] starting binary engine export to {s}\n", .{ENGINE_EXPORT_PATH});
    std.debug.print("[export] active_palette_bank={d} active_map_bank={d} tile_count={d} sprite_count={d}\n", .{
        project.activePaletteBank(),
        project.activeMapBank(),
        project.imageCountMode(.tiles),
        project.imageCountMode(.sprites),
    });

    var writer = try BinaryWriter.create(ENGINE_EXPORT_PATH);
    defer writer.close();

    try writeHeader(&writer, project);
    try writeSpritePalettes(&writer, project);
    try writeSpriteTiles(&writer, project);
    try writeLevels(&writer, project);

    std.debug.print("[export] finished binary engine export to {s}\n", .{ENGINE_EXPORT_PATH});
}

fn writeHeader(writer: *BinaryWriter, project: *const Project) !void {
    const sprite_count = @min(project.imageCountMode(.sprites), BG_TILE_BASE);
    const tile_count = @min(project.imageCountMode(.tiles), MAX_BG_TILES);

    try writer.writeAll("P1XB");
    try writer.writeU8(EXPORT_VERSION);
    try writer.writeU8(BG_TILE_BASE);
    try writer.writeU8(@intCast(LEVELS.len));
    try writer.writeU8(0); // reserved
    try writer.writeU16(sprite_count);
    try writer.writeU16(tile_count);
    try writer.writeU16(ENGINE_MAP_W);
    try writer.writeU16(ENGINE_MAP_H);
    std.debug.print("[export] header: version={d} levels={d} sprite_tiles={d} bg_tiles={d} map={d}x{d}\n", .{
        EXPORT_VERSION,
        LEVELS.len,
        sprite_count,
        tile_count,
        ENGINE_MAP_W,
        ENGINE_MAP_H,
    });
}

fn writeSpritePalettes(writer: *BinaryWriter, project: *const Project) !void {
    std.debug.print("[export] writing sprite palettes from palette bank {d}\n", .{project.activePaletteBank()});
    try writePaletteWords(writer, project, .sprites, project.activePaletteBank());
}

fn writeSpriteTiles(writer: *BinaryWriter, project: *const Project) !void {
    const sprite_count = project.imageCountMode(.sprites);
    std.debug.print("[export] writing {d} fixed OBJ tile slots ({d} project sprites available)\n", .{ BG_TILE_BASE, sprite_count });

    var i: u16 = 0;
    while (i < BG_TILE_BASE) : (i += 1) {
        const image = if (i < sprite_count) project.imageAtMode(.sprites, i) else blankImage();
        try writeTile2bpp(writer, image);
    }
}

fn writeLevels(writer: *BinaryWriter, project: *const Project) !void {
    for (LEVELS) |level| try writeLevel(writer, project, level);
}

fn writeLevel(writer: *BinaryWriter, project: *const Project, level: ExportLevel) !void {
    const map = project.mapAtBank(level.bank_id);
    const tile_count = @min(project.imageCountMode(.tiles), MAX_BG_TILES);
    const sprite_count = @min(map.sprite_count, project_mod.MAX_MAP_SPRITES);

    std.debug.print("[export] writing level {s}: bank={d} source_map={d}x{d} exported_map={d}x{d} bg_tiles={d} sprites={d}\n", .{
        level.label,
        level.bank_id,
        map.width,
        map.height,
        ENGINE_MAP_W,
        ENGINE_MAP_H,
        tile_count,
        sprite_count,
    });

    try writer.writeU8(level.bank_id);
    try writer.writeU8(0); // reserved
    try writer.writeU16(map.width);
    try writer.writeU16(map.height);
    try writer.writeU16(ENGINE_MAP_W);
    try writer.writeU16(ENGINE_MAP_H);
    try writer.writeU16(tile_count);
    try writer.writeU16(sprite_count);

    try writePaletteWords(writer, project, .tiles, level.bank_id);

    var tile_id: u16 = 0;
    while (tile_id < tile_count) : (tile_id += 1) {
        try writeTile2bpp(writer, project.imageAtMode(.tiles, tile_id));
    }

    try writeTileMap(writer, map, tile_count);
    try writeAttrMap(writer, map);
    try writeSprites(writer, map, sprite_count);
}

fn writeTileMap(writer: *BinaryWriter, map: *const Map, tile_count: u16) !void {
    var y: u16 = 0;
    while (y < ENGINE_MAP_H) : (y += 1) {
        var x: u16 = 0;
        while (x < ENGINE_MAP_W) : (x += 1) {
            const value: u8 = if (x < map.width and y < map.height) value: {
                const idx = @as(usize, y) * @as(usize, map.width) + x;
                const safe_id = @min(@as(u16, map.tile_ids[idx]), tile_count -| 1);
                break :value @intCast(safe_id + BG_TILE_BASE);
            } else BG_TILE_BASE;
            try writer.writeU8(value);
        }
    }
}

fn writeAttrMap(writer: *BinaryWriter, map: *const Map) !void {
    var y: u16 = 0;
    while (y < ENGINE_MAP_H) : (y += 1) {
        var x: u16 = 0;
        while (x < ENGINE_MAP_W) : (x += 1) {
            const value: u8 = if (x < map.width and y < map.height) value: {
                const idx = @as(usize, y) * @as(usize, map.width) + x;
                break :value map.tile_attrs[idx] & 0x67;
            } else 0;
            try writer.writeU8(value);
        }
    }
}

fn writeSprites(writer: *BinaryWriter, map: *const Map, sprite_count: u16) !void {
    var i: u16 = 0;
    while (i < sprite_count) : (i += 1) {
        const sprite = map.sprites[i];
        try writer.writeU16(sprite.x);
        try writer.writeU16(sprite.y);
        try writer.writeU16(sprite.sprite_id);
        try writer.writeU8((project_mod.MapTileAttr{ .palette = sprite.palette, .hflip = sprite.hflip, .vflip = sprite.vflip }).encode());
        try writer.writeU8(0); // reserved/alignment
    }
}

fn writePaletteWords(writer: *BinaryWriter, project: *const Project, mode: project_mod.ProjectMode, bank_id: u8) !void {
    for (0..CONF.PALETTE_COUNT) |palette_id| {
        for (0..CONF.COLORS_PER_PALETTE) |color_id| {
            const rgb = project.paletteColorAtBankMode(mode, bank_id, @intCast(palette_id), @intCast(color_id));
            try writer.writeU16(gbcColor(rgb));
        }
    }
}

fn writeTile2bpp(writer: *BinaryWriter, image: Image) !void {
    var row: usize = 0;
    while (row < CONF.TILE_SIDE) : (row += 1) {
        var lo: u8 = 0;
        var hi: u8 = 0;
        var col: usize = 0;
        while (col < CONF.TILE_SIDE) : (col += 1) {
            const px = image.pixels[row * CONF.TILE_SIDE + col] & 3;
            const bit: u3 = @intCast(7 - col);
            lo |= (px & 1) << bit;
            hi |= ((px >> 1) & 1) << bit;
        }
        try writer.writeU8(lo);
        try writer.writeU8(hi);
    }
}

fn gbcColor(rgb: PaletteColor) u16 {
    const r: u16 = @as(u16, rgb[0] >> 3);
    const g: u16 = @as(u16, rgb[1] >> 3);
    const b: u16 = @as(u16, rgb[2] >> 3);
    return r | (g << 5) | (b << 10);
}

fn blankImage() Image {
    return .{};
}

const BinaryWriter = struct {
    file: *c.FILE,
    path: []const u8,

    fn create(comptime path: [:0]const u8) !BinaryWriter {
        const file = c.fopen(path.ptr, "wb") orelse {
            std.debug.print("[export] failed to open {s} for writing\n", .{path});
            return error.ExportOpenFailed;
        };
        return .{ .file = file, .path = path };
    }

    fn close(self: *BinaryWriter) void {
        if (c.fclose(self.file) != 0) {
            std.debug.print("[export] failed to close {s}\n", .{self.path});
        }
    }

    fn writeAll(self: *const BinaryWriter, bytes: []const u8) !void {
        if (bytes.len == 0) return;
        const written = c.fwrite(bytes.ptr, 1, bytes.len, self.file);
        if (written != bytes.len) {
            std.debug.print("[export] short write to {s}: wanted={d} wrote={d}\n", .{ self.path, bytes.len, written });
            return error.ExportWriteFailed;
        }
    }

    fn writeU8(self: *const BinaryWriter, value: u8) !void {
        var buf = [_]u8{value};
        try self.writeAll(&buf);
    }

    fn writeU16(self: *const BinaryWriter, value: u16) !void {
        var buf = [_]u8{ @intCast(value & 0x00ff), @intCast(value >> 8) };
        try self.writeAll(&buf);
    }
};
