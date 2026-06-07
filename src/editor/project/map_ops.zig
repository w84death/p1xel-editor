const types = @import("types.zig");

pub fn fillTile(map: *types.Map, x: u16, y: u16, tile_id: u8, attr: types.MapTileAttr) bool {
    if (x >= map.width or y >= map.height) return false;
    const width = @as(usize, map.width);
    const height = @as(usize, map.height);
    const start = @as(usize, y) * width + x;
    const old_id = map.tile_ids[start];
    const old_attr = map.tile_attrs[start];
    const new_attr = attr.encode();
    if (old_id == tile_id and old_attr == new_attr) return false;

    var stack: [types.MAX_MAP_CELLS]usize = undefined;
    var queued = [_]bool{false} ** types.MAX_MAP_CELLS;
    var top: usize = 1;
    stack[0] = start;
    queued[start] = true;

    var changed = false;
    while (top > 0) {
        top -= 1;
        const idx = stack[top];
        if (map.tile_ids[idx] != old_id or map.tile_attrs[idx] != old_attr) continue;
        map.tile_ids[idx] = tile_id;
        map.tile_attrs[idx] = new_attr;
        changed = true;

        const cx = idx % width;
        const cy = idx / width;
        if (cx > 0) pushFillNeighbor(map, &stack, &queued, &top, idx - 1, old_id, old_attr);
        if (cx + 1 < width) pushFillNeighbor(map, &stack, &queued, &top, idx + 1, old_id, old_attr);
        if (cy > 0) pushFillNeighbor(map, &stack, &queued, &top, idx - width, old_id, old_attr);
        if (cy + 1 < height) pushFillNeighbor(map, &stack, &queued, &top, idx + width, old_id, old_attr);
    }
    return changed;
}

pub fn remapTilePaletteReferences(maps: []types.Map, tile_id: u16, old_palette: u8, new_palette: u8) void {
    for (maps) |*map| {
        const cell_count = @as(usize, map.width) * @as(usize, map.height);
        var i: usize = 0;
        while (i < cell_count) : (i += 1) {
            if (map.tile_ids[i] != tile_id) continue;
            const attr = types.MapTileAttr.decode(map.tile_attrs[i]);
            if (attr.palette != old_palette) continue;
            map.tile_attrs[i] = (types.MapTileAttr{ .palette = new_palette, .hflip = attr.hflip, .vflip = attr.vflip }).encode();
        }
    }
}

pub fn remapSpritePaletteReferences(maps: []types.Map, sprite_id: u16, old_palette: u8, new_palette: u8) void {
    for (maps) |*map| {
        var i: usize = 0;
        while (i < map.sprite_count) : (i += 1) {
            if (map.sprites[i].sprite_id == sprite_id and map.sprites[i].palette == old_palette) {
                map.sprites[i].palette = new_palette;
            }
        }
    }
}

pub fn remapDeletedTileReferences(maps: []types.Map, deleted_id: u16) void {
    for (maps) |*map| {
        const cell_count = @as(usize, map.width) * @as(usize, map.height);
        var i: usize = 0;
        while (i < cell_count) : (i += 1) {
            const tile_id = @as(u16, map.tile_ids[i]);
            if (tile_id == deleted_id) {
                map.tile_ids[i] = 0;
            } else if (tile_id > deleted_id) {
                map.tile_ids[i] -= 1;
            }
        }
    }
}

pub fn remapDeletedSpriteReferences(maps: []types.Map, deleted_id: u16) void {
    for (maps) |*map| {
        var i: usize = 0;
        while (i < map.sprite_count) {
            const sprite_id = map.sprites[i].sprite_id;
            if (sprite_id == deleted_id) {
                map.sprite_count -= 1;
                map.sprites[i] = map.sprites[map.sprite_count];
            } else {
                if (sprite_id > deleted_id) map.sprites[i].sprite_id -= 1;
                i += 1;
            }
        }
    }
}

pub fn remapSwappedTileReferences(maps: []types.Map, a: u16, b: u16) void {
    for (maps) |*map| {
        const cell_count = @as(usize, map.width) * @as(usize, map.height);
        var i: usize = 0;
        while (i < cell_count) : (i += 1) {
            const tile_id = @as(u16, map.tile_ids[i]);
            if (tile_id == a) {
                map.tile_ids[i] = @intCast(b);
            } else if (tile_id == b) {
                map.tile_ids[i] = @intCast(a);
            }
        }
    }
}

pub fn remapSwappedSpriteReferences(maps: []types.Map, a: u16, b: u16) void {
    for (maps) |*map| {
        var i: usize = 0;
        while (i < map.sprite_count) : (i += 1) {
            if (map.sprites[i].sprite_id == a) {
                map.sprites[i].sprite_id = b;
            } else if (map.sprites[i].sprite_id == b) {
                map.sprites[i].sprite_id = a;
            }
        }
    }
}

fn pushFillNeighbor(map: *const types.Map, stack: *[types.MAX_MAP_CELLS]usize, queued: *[types.MAX_MAP_CELLS]bool, top: *usize, idx: usize, old_id: u8, old_attr: u8) void {
    if (queued[idx] or map.tile_ids[idx] != old_id or map.tile_attrs[idx] != old_attr) return;
    if (top.* >= stack.len) return;
    queued[idx] = true;
    stack[top.*] = idx;
    top.* += 1;
}
