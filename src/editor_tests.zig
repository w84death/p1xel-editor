const std = @import("std");

const project_mod = @import("editor/project.zig");
const map_ops = @import("editor/project/map_ops.zig");
const storage = @import("editor/project/storage.zig");

const Project = project_mod.Project;
const ProjectMode = project_mod.ProjectMode;
const Map = project_mod.Map;
const MapTileAttr = project_mod.MapTileAttr;
const MapSprite = project_mod.MapSprite;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "MapTileAttr encodes palette and flip flags" {
    const attr = MapTileAttr{ .palette = 9, .hflip = true, .vflip = true };
    const encoded = attr.encode();

    try expectEqual(@as(u8, 0b0110_0001), encoded);

    const decoded = MapTileAttr.decode(encoded | 0b1000_0000);
    try expectEqual(@as(u8, 1), decoded.palette);
    try expect(decoded.hflip);
    try expect(decoded.vflip);
}

test "storage reads and writes little-endian u16 values" {
    var bytes = [_]u8{ 0, 0 };
    storage.writeU16(bytes[0..], 0xBEEF);

    try expectEqual(@as(u8, 0xEF), bytes[0]);
    try expectEqual(@as(u8, 0xBE), bytes[1]);
    try expectEqual(@as(u16, 0xBEEF), storage.readU16(bytes[0..]));
}

test "map fill changes only the connected matching region" {
    var map = Map{ .width = 4, .height = 3 };
    const ids = [_]u8{
        1, 1, 9, 1,
        1, 9, 9, 1,
        1, 1, 1, 1,
    };
    @memcpy(map.tile_ids[0..ids.len], ids[0..]);

    const replacement = MapTileAttr{ .palette = 2, .hflip = true };
    try expect(map_ops.fillTile(&map, 0, 0, 4, replacement));

    const expected_ids = [_]u8{
        4, 4, 9, 4,
        4, 9, 9, 4,
        4, 4, 4, 4,
    };
    for (expected_ids, 0..) |expected, i| {
        try expectEqual(expected, map.tile_ids[i]);
        if (expected == 4) {
            const attr = MapTileAttr.decode(map.tile_attrs[i]);
            try expectEqual(@as(u8, 2), attr.palette);
            try expect(attr.hflip);
            try expect(!attr.vflip);
        } else {
            try expectEqual(@as(u8, 0), map.tile_attrs[i]);
        }
    }

    try expect(!map_ops.fillTile(&map, 0, 0, 4, replacement));
    try expect(!map_ops.fillTile(&map, 99, 0, 4, replacement));
}

test "tile palette remap updates matching map placements and preserves overrides" {
    var maps = [_]Map{Map{ .width = 3, .height = 1 }};
    maps[0].tile_ids[0] = 5;
    maps[0].tile_attrs[0] = (MapTileAttr{ .palette = 2, .hflip = true }).encode();
    maps[0].tile_ids[1] = 5;
    maps[0].tile_attrs[1] = (MapTileAttr{ .palette = 4, .vflip = true }).encode();
    maps[0].tile_ids[2] = 6;
    maps[0].tile_attrs[2] = (MapTileAttr{ .palette = 2 }).encode();

    map_ops.remapTilePaletteReferences(maps[0..], 5, 2, 7);

    const updated = MapTileAttr.decode(maps[0].tile_attrs[0]);
    try expectEqual(@as(u8, 7), updated.palette);
    try expect(updated.hflip);
    try expect(!updated.vflip);

    const override = MapTileAttr.decode(maps[0].tile_attrs[1]);
    try expectEqual(@as(u8, 4), override.palette);
    try expect(override.vflip);

    const other_tile = MapTileAttr.decode(maps[0].tile_attrs[2]);
    try expectEqual(@as(u8, 2), other_tile.palette);
}

test "sprite palette remap updates only matching sprite placements" {
    var maps = [_]Map{Map{}};
    maps[0].sprite_count = 3;
    maps[0].sprites[0] = MapSprite{ .sprite_id = 1, .palette = 2 };
    maps[0].sprites[1] = MapSprite{ .sprite_id = 1, .palette = 4 };
    maps[0].sprites[2] = MapSprite{ .sprite_id = 2, .palette = 2 };

    map_ops.remapSpritePaletteReferences(maps[0..], 1, 2, 7);

    try expectEqual(@as(u8, 7), maps[0].sprites[0].palette);
    try expectEqual(@as(u8, 4), maps[0].sprites[1].palette);
    try expectEqual(@as(u8, 2), maps[0].sprites[2].palette);
}

test "tile delete and swap remap map references" {
    var maps = [_]Map{Map{ .width = 4, .height = 1 }};
    maps[0].tile_ids[0] = 0;
    maps[0].tile_ids[1] = 1;
    maps[0].tile_ids[2] = 2;
    maps[0].tile_ids[3] = 3;

    map_ops.remapDeletedTileReferences(maps[0..], 2);
    try expectEqual(@as(u8, 0), maps[0].tile_ids[0]);
    try expectEqual(@as(u8, 1), maps[0].tile_ids[1]);
    try expectEqual(@as(u8, 0), maps[0].tile_ids[2]);
    try expectEqual(@as(u8, 2), maps[0].tile_ids[3]);

    map_ops.remapSwappedTileReferences(maps[0..], 1, 2);
    try expectEqual(@as(u8, 0), maps[0].tile_ids[0]);
    try expectEqual(@as(u8, 2), maps[0].tile_ids[1]);
    try expectEqual(@as(u8, 0), maps[0].tile_ids[2]);
    try expectEqual(@as(u8, 1), maps[0].tile_ids[3]);
}

test "sprite delete and swap remap map references" {
    var maps = [_]Map{Map{}};
    maps[0].sprite_count = 3;
    maps[0].sprites[0] = MapSprite{ .sprite_id = 0 };
    maps[0].sprites[1] = MapSprite{ .sprite_id = 2 };
    maps[0].sprites[2] = MapSprite{ .sprite_id = 3 };

    map_ops.remapDeletedSpriteReferences(maps[0..], 2);
    try expectEqual(@as(u16, 2), maps[0].sprite_count);
    try expectEqual(@as(u16, 0), maps[0].sprites[0].sprite_id);
    try expectEqual(@as(u16, 2), maps[0].sprites[1].sprite_id);

    map_ops.remapSwappedSpriteReferences(maps[0..], 0, 2);
    try expectEqual(@as(u16, 2), maps[0].sprites[0].sprite_id);
    try expectEqual(@as(u16, 0), maps[0].sprites[1].sprite_id);
}

test "Project visible tile slots support independent banks" {
    var project = Project.init();
    const first = project.createTile().?;
    const second = project.createTile().?;

    project.setVisibleSlot(0, first);
    try expectEqual(first, project.visibleSlot(0));

    project.setVisibleSlotBank(1);
    try expectEqual(@as(u8, 1), project.activeVisibleSlotBank());
    try expectEqual(@as(u16, 0), project.visibleSlot(0));

    project.setVisibleSlot(0, second);
    try expectEqual(second, project.visibleSlot(0));

    project.setVisibleSlotBank(0);
    try expectEqual(first, project.visibleSlot(0));
}

test "Project view changes refresh visuals without marking data dirty" {
    var project = Project.init();
    const initial_revision = project.visualRevision();

    project.setMode(ProjectMode.sprites);

    try expect(!project.dirty);
    try expect(project.visualRevision() != initial_revision);
}

test "Project tile flags expose traversable and slow terrain bits" {
    var project = Project.init();

    try expect(project.isTileTraversable(project.selectedImageId()));
    try expect(!project.isTileSlow(project.selectedImageId()));

    project.setSelectedTileSlow(true);
    try expect(project.isTileSlow(project.selectedImageId()));
    try expectEqual(project_mod.TILE_FLAG_TRAVERSABLE | project_mod.TILE_FLAG_SLOW, project.selectedTileFlags());

    project.setSelectedTileTraversable(false);
    try expect(!project.isTileTraversable(project.selectedImageId()));
    try expect(project.isTileSlow(project.selectedImageId()));
}

test "Project tile palette cycle flags animate only tile palettes" {
    var project = Project.init();
    project.dirty = false;

    project.setActiveTilePaletteCycle(2, true);
    try expect(project.dirty);
    try expect(project.activeTilePaletteCycles(2));
    try expectEqual(@as(u8, 1 << 2), project.tilePaletteCycleFlags(project.activePaletteBank()));

    const revision = project.visualRevision();
    for (0..24) |_| project.tickAnimation();
    try expect(project.visualRevision() != revision);

    project.setMode(ProjectMode.sprites);
    project.setActiveTilePaletteCycle(3, true);
    try expect(!project.activeTilePaletteCycles(3));
}

test "Project painting marks data dirty and changes selected image pixels" {
    var project = Project.init();

    try expect(project.paintPixel(1, 2, 3));
    try expect(project.dirty);
    try expectEqual(@as(u8, 3), project.currentImage().pixels[2 * 8 + 1]);
}

test "Project tile palette changes remap map cells using the old default palette" {
    var project = Project.init();
    _ = project.paintMapTile(0, 0, 0, MapTileAttr{ .palette = 0, .hflip = true });
    _ = project.paintMapTile(1, 0, 0, MapTileAttr{ .palette = 3 });
    project.dirty = false;
    const revision = project.visualRevision();

    project.setPaletteSelection(2, 1);

    try expect(project.dirty);
    try expect(project.visualRevision() != revision);
    try expectEqual(@as(u8, 2), project.currentImage().palette_id);

    const remapped = project.mapCellAt(0, 0).?;
    try expectEqual(@as(u8, 2), remapped.attr.palette);
    try expect(remapped.attr.hflip);

    const override = project.mapCellAt(1, 0).?;
    try expectEqual(@as(u8, 3), override.attr.palette);
}

test "Project sprite palette changes remap sprite instances using the old default palette" {
    var project = Project.init();
    project.setMode(ProjectMode.sprites);
    _ = project.addOrUpdateMapSprite(0, 0, 0, MapTileAttr{ .palette = 0 });
    _ = project.addOrUpdateMapSprite(1, 0, 0, MapTileAttr{ .palette = 3 });
    project.dirty = false;

    project.setPaletteSelection(2, 1);

    const map = project.activeMap();
    try expect(project.dirty);
    try expectEqual(@as(u8, 2), project.currentImage().palette_id);
    try expectEqual(@as(u8, 2), map.sprites[0].palette);
    try expectEqual(@as(u8, 3), map.sprites[1].palette);
}

test "Project sprite stamp no-op does not dirty or refresh" {
    var project = Project.init();
    project.setMode(ProjectMode.sprites);
    const attr = MapTileAttr{ .palette = 1, .hflip = true };

    try expect(project.addOrUpdateMapSprite(0, 0, 0, attr));
    project.dirty = false;
    const revision = project.visualRevision();

    try expect(!project.addOrUpdateMapSprite(0, 0, 0, attr));
    try expect(!project.dirty);
    try expectEqual(revision, project.visualRevision());
}
