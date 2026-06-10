# P1Xel Editor export format and Game Boy Color import guide

This document explains how to import P1Xel Editor exports into a game engine, with examples focused on **Game Boy Color** / RGBDS projects.

The editor exports two files:

| File | Purpose |
| --- | --- |
| `engine_export.p1xb` | Main binary data blob: palettes, OBJ tiles, level tile data, maps, attributes, collision/logic, and sprite placements. |
| `P1X-GBC-ENGINE/SRC/p1xel_export.inc` | RGBDS include file generated from the binary. It defines offsets, constants, labels, and `INCBIN` blocks for a GBC engine. |

> Note: the repository path used by the exporter is `P1X-GBC-ENGINE/SRC/p1xel_export.inc`. Make sure `P1X-GBC-ENGINE/SRC/` exists before exporting, or the include-file write will fail.

## Exporting from the editor

1. Open **MAP EDITOR**.
2. Press **EXPORT**.
3. The editor writes:
   - `engine_export.p1xb`
   - `P1X-GBC-ENGINE/SRC/p1xel_export.inc`
4. Add/include `p1xel_export.inc` from your RGBDS source, or parse `engine_export.p1xb` directly in another engine/tool.

The export currently targets a GBC-style runtime:

- 8×8 tiles.
- 2 bits per pixel tile data.
- 4 colours per palette.
- 8 BG palettes per level.
- 8 OBJ palettes from the active sprite palette bank.
- Up to 250 exported BG tiles, because GBC tile IDs `0..5` are reserved for OBJ tiles and the background starts at tile ID `6`.
- 6 fixed OBJ tile slots.
- 32×32 exported tile maps.
- Two exported levels:
  - `GrasslandLevel` from map/palette bank `0`.
  - `DesertLevel` from map/palette bank `1`.

## Quick RGBDS integration

In a RGBDS project, the generated include file is the easiest route.

Example:

```asm
; In your engine source, for example SRC/main.asm
INCLUDE "p1xel_export.inc"
```

The generated include file creates labels like:

```asm
SpritesPalettes:
GameTiles:
GrasslandLevelBgPalettes:
GrasslandLevelTiles:
GrasslandLevelTileMap:
GrasslandLevelAttrMap:
GrasslandLevelLogicMap:
GrasslandLevelDescriptor:
DesertLevelBgPalettes:
DesertLevelTiles:
DesertLevelTileMap:
DesertLevelAttrMap:
DesertLevelLogicMap:
DesertLevelDescriptor:
```

It also defines constants such as:

```asm
P1XB_HEADER_SIZE
P1XB_PALETTE_BYTES
P1XB_OBJ_TILE_COUNT
P1XB_OBJ_TILE_BYTES
P1XB_BG_TILE_COUNT
P1XB_BG_TILE_BYTES
P1XB_TILEMAP_BYTES
P1XB_ATTRMAP_BYTES
P1XB_LOGICMAP_BYTES
LEVEL_MAP_WIDTH_TILES
LEVEL_MAP_HEIGHT_TILES
LEVEL_BG_TILE_BASE
```

Typical GBC load flow:

1. Copy `SpritesPalettes` into OBJ palette RAM.
2. Copy `GameTiles` into OBJ VRAM tile slots `0..5`.
3. For the active level:
   - Copy `<Level>BgPalettes` into BG palette RAM.
   - Copy `<Level>Tiles` into BG VRAM starting at tile slot `LEVEL_BG_TILE_BASE` (`6`).
   - Copy `<Level>TileMap` into BG map memory.
   - Copy `<Level>AttrMap` into BG attribute map memory.
   - Use `<Level>LogicMap` for collision/gameplay.
   - Spawn sprites using the exported sprite placement records if your engine reads them.

## Binary format overview

All multi-byte integers in `engine_export.p1xb` are **little-endian**.

Top-level layout:

```text
P1XB header              16 bytes
Sprite/OBJ palettes      64 bytes
Sprite/OBJ tiles         6 * 16 bytes
Level 0 data             variable
Level 1 data             variable
...
```

### Header

Offset | Size | Type | Meaning
---: | ---: | --- | ---
`0` | `4` | bytes | Magic: ASCII `P1XB`
`4` | `1` | `u8` | Export version. Current version: `1`
`5` | `1` | `u8` | BG tile base. Current value: `6`
`6` | `1` | `u8` | Level count. Current value: `2`
`7` | `1` | `u8` | Reserved, currently `0`
`8` | `2` | `u16` | Usable/exported OBJ sprite count, max `6`. The OBJ tile block still contains `BG_TILE_BASE` fixed slots.
`10` | `2` | `u16` | Exported BG tile count, max `250`
`12` | `2` | `u16` | Exported map width, currently `32`
`14` | `2` | `u16` | Exported map height, currently `32`

Validate these fields when importing. If the magic or version does not match, reject the file or run a migration path.

### Palettes

Palette data is stored as GBC-native 15-bit colour words:

```text
bits 0..4    red   (0..31)
bits 5..9    green (0..31)
bits 10..14  blue  (0..31)
bit 15       unused
```

The editor converts 24-bit RGB to GBC colour like this:

```c
uint16_t gbc_color(uint8_t r, uint8_t g, uint8_t b) {
    return (r >> 3) | ((g >> 3) << 5) | ((b >> 3) << 10);
}
```

Palette block sizes:

```text
8 palettes * 4 colours * 2 bytes = 64 bytes
```

There is one global OBJ palette block after the header, then one BG palette block per exported level.

### Tile graphics

Tiles are stored in standard Game Boy / Game Boy Color **2bpp tile format**:

```text
8 rows per tile
2 bytes per row
16 bytes per tile
```

For each pixel index `0..3`:

- bit 0 goes into the low byte for that row.
- bit 1 goes into the high byte for that row.
- leftmost pixel uses bit 7.
- rightmost pixel uses bit 0.

Pseudo-code:

```c
for (row = 0; row < 8; row++) {
    uint8_t lo = 0;
    uint8_t hi = 0;
    for (col = 0; col < 8; col++) {
        uint8_t px = pixels[row][col] & 3;
        uint8_t bit = 7 - col;
        lo |= (px & 1) << bit;
        hi |= ((px >> 1) & 1) << bit;
    }
    write_u8(lo);
    write_u8(hi);
}
```

OBJ/sprite tiles:

- The exporter always writes `6` fixed OBJ tile slots (`BG_TILE_BASE * 16` bytes).
- The header’s OBJ count tells you how many of those slots are valid/usable sprite images.
- If the project has fewer than 6 sprites, missing slots are blank.
- Map sprite placements must reference sprite IDs lower than the usable OBJ count, or export fails.

BG tiles:

- The exporter writes up to `250` BG tiles.
- Runtime BG tile IDs start at `6`, so map cells store `tile_id + 6`.

## Level layout

Each level block has this structure:

```text
Level header       14 bytes
BG palettes        64 bytes
BG tiles           bg_tile_count * 16 bytes
Tile map           32 * 32 bytes
Attribute map      32 * 32 bytes
Logic map          32 * 32 bytes
Sprite records     sprite_count * 8 bytes
```

### Level header

Offset in level | Size | Type | Meaning
---: | ---: | --- | ---
`0` | `1` | `u8` | Source bank ID (`0` for Grassland, `1` for Desert)
`1` | `1` | `u8` | Reserved, currently `0`
`2` | `2` | `u16` | Source map width in editor
`4` | `2` | `u16` | Source map height in editor
`6` | `2` | `u16` | Exported map width, currently `32`
`8` | `2` | `u16` | Exported map height, currently `32`
`10` | `2` | `u16` | BG tile count for this export
`12` | `2` | `u16` | Sprite placement count for this level

The source map can be larger than 32×32 in the editor, but this exporter writes a 32×32 runtime map. Cells outside the exported 32×32 region are not included.

### Tile map

The tile map is `32 * 32 = 1024` bytes.

Each byte is a runtime BG tile ID:

```text
runtime_tile_id = editor_tile_id + BG_TILE_BASE
```

With the current exporter:

```text
BG_TILE_BASE = 6
```

If a source map cell references a tile outside the exported tile count, it is clamped to the last exported tile.

### Attribute map

The attribute map is also `1024` bytes.

Each byte is already in a GBC-friendly layout:

```text
bits 0..2   BG palette number (0..7)
bit 3       VRAM bank, currently unused/0
bit 4       unused/0
bit 5       horizontal flip
bit 6       vertical flip
bit 7       priority, currently unused/0
```

The exporter masks attributes with `0x67`, preserving only palette, horizontal flip, and vertical flip.

To use it on GBC:

1. Select VRAM bank 1.
2. Copy the attribute map to the same BG map address used for the tile map.
3. Select VRAM bank 0 again before copying tile IDs or tile graphics.

### Logic map

The logic map is `1024` bytes and mirrors the exported tile map dimensions.

Each byte stores tile gameplay flags. Current flag layout:

```text
bit 0 = traversable / walkable
```

This is intentionally engine-agnostic. A GBC engine can keep it in ROM and query it during movement/collision checks, or copy it to WRAM if maps are mutable.

Example:

```c
bool is_walkable(uint8_t logic_value) {
    return (logic_value & 0x01) != 0;
}
```

### Sprite placement records

Each exported sprite placement is 8 bytes:

Offset | Size | Type | Meaning
---: | ---: | --- | ---
`0` | `2` | `u16` | Tile/cell X coordinate
`2` | `2` | `u16` | Tile/cell Y coordinate
`4` | `2` | `u16` | Sprite tile ID / OBJ tile slot
`6` | `1` | `u8` | Attribute byte: palette + hflip + vflip
`7` | `1` | `u8` | Reserved/alignment, currently `0`

Sprite attributes use the same packed format as map attributes:

```text
bits 0..2 = OBJ palette number
bit 5     = horizontal flip
bit 6     = vertical flip
```

For native GBC OAM you will likely convert cell coordinates to pixels:

```text
screen_x = cell_x * 8
screen_y = cell_y * 8
```

Remember that hardware OAM coordinates have the usual Game Boy offsets (`x + 8`, `y + 16`) when writing OAM entries.

## Direct parser outline for non-RGBDS engines

Any engine can import `engine_export.p1xb` directly. The core requirements are:

1. Read little-endian values.
2. Validate the header.
3. Read fixed-size blocks in order.
4. Convert or upload GBC-native data as needed.

C-like pseudo-code:

```c
typedef struct {
    uint8_t magic[4];
    uint8_t version;
    uint8_t bg_tile_base;
    uint8_t level_count;
    uint8_t reserved;
    uint16_t obj_tile_count;
    uint16_t bg_tile_count;
    uint16_t map_w;
    uint16_t map_h;
} P1XBHeader;

uint16_t read_le16(const uint8_t *p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

bool load_p1xb(const uint8_t *data, size_t len) {
    if (len < 16) return false;
    if (memcmp(data, "P1XB", 4) != 0) return false;
    if (data[4] != 1) return false;

    uint8_t bg_tile_base = data[5];
    uint8_t level_count = data[6];
    uint16_t obj_tile_count = read_le16(data + 8);
    uint16_t bg_tile_count = read_le16(data + 10);
    uint16_t map_w = read_le16(data + 12);
    uint16_t map_h = read_le16(data + 14);

    size_t cursor = 16;

    const uint8_t *obj_palettes = data + cursor;
    cursor += 8 * 4 * 2;

    const uint8_t *obj_tiles = data + cursor;
    cursor += bg_tile_base * 16; // fixed OBJ tile block, currently 6 slots

    for (uint8_t level = 0; level < level_count; level++) {
        const uint8_t *level_header = data + cursor;
        uint16_t level_bg_tile_count = read_le16(level_header + 10);
        uint16_t sprite_count = read_le16(level_header + 12);
        cursor += 14;

        const uint8_t *bg_palettes = data + cursor;
        cursor += 8 * 4 * 2;

        const uint8_t *bg_tiles = data + cursor;
        cursor += level_bg_tile_count * 16;

        const uint8_t *tile_map = data + cursor;
        cursor += map_w * map_h;

        const uint8_t *attr_map = data + cursor;
        cursor += map_w * map_h;

        const uint8_t *logic_map = data + cursor;
        cursor += map_w * map_h;

        const uint8_t *sprites = data + cursor;
        cursor += sprite_count * 8;

        // Upload/convert these pointers for your engine here.
    }

    return cursor <= len;
}
```

For engines that are not Game Boy Color-based:

- Decode the 2bpp tile data back to pixel indices `0..3`.
- Convert GBC palette words back to RGB if needed.
- Treat tile maps and attribute maps as separate layers.
- Use the logic map as collision/material metadata.
- Convert tile coordinates to your engine’s world units.

GBC colour word back to 8-bit RGB approximation:

```c
uint8_t expand5(uint8_t v) {
    return (v << 3) | (v >> 2);
}

void gbc_to_rgb(uint16_t c, uint8_t *r, uint8_t *g, uint8_t *b) {
    *r = expand5(c & 31);
    *g = expand5((c >> 5) & 31);
    *b = expand5((c >> 10) & 31);
}
```

## Recommended GBC runtime loading order

A common GBC loading sequence for each level:

```text
1. Disable LCD or enter a safe VRAM-copy window.
2. Load OBJ palettes from SpritesPalettes into OBJ palette RAM.
3. Load OBJ tiles from GameTiles into VRAM tile slots 0..5.
4. Load BG palettes for the selected level into BG palette RAM.
5. Load BG tile graphics into VRAM starting at tile slot 6.
6. Select VRAM bank 0 and copy the tile map.
7. Select VRAM bank 1 and copy the attribute map.
8. Restore VRAM bank 0.
9. Initialize collision/logic pointer to the level logic map.
10. Spawn sprite entities from the level sprite records.
11. Re-enable LCD / finish transition.
```

Exact register code depends on your engine, but these are the GBC hardware concepts involved:

- BG/OBJ palette RAM: written through `BCPS/BCPD` and `OCPS/OCPD` or equivalent engine helpers.
- VRAM bank select: `VBK`.
- BG map area: usually `$9800` or `$9C00` depending on LCDC setup.
- Tile data area: usually `$8000` for unsigned tile IDs.
- OAM: sprite entries use hardware coordinate offsets.

## Current exporter assumptions and limits

The current exporter is intentionally simple and GBC-oriented:

- Binary magic/version: `P1XB`, version `1`.
- Exported maps are always `32×32`.
- Only map banks `0` and `1` are exported by name:
  - `GrasslandLevel`
  - `DesertLevel`
- BG tile IDs reserve `0..5`; exported BG tiles start at `6`.
- Exactly 6 OBJ tile slots are written.
- The header records how many of those 6 slots are valid sprite images.
- Sprite placements must reference one of the valid OBJ slots.
- Tile maps, attr maps, and logic maps are uncompressed.
- Colour index `0` is transparent in sprite editing, but OBJ tile bytes are still standard 2bpp data.
- Attribute priority and VRAM-bank bits are currently not exported.

If your engine needs more maps, compressed maps, more sprites, metatiles, animated tiles, or streaming banks, extend `src/editor/exporter.zig` and bump the export version.

## Troubleshooting

### `EXPORT` says export failed

Check that the output directory exists:

```text
P1X-GBC-ENGINE/SRC/
```

The exporter writes `p1xel_export.inc` there. If the directory is missing, file creation fails.

### Sprite export fails with “Sprite ID exceeds export limit”

Only the first 6 sprite images are exported as OBJ tiles. Any map sprite placement referencing sprite ID `6` or higher fails validation.

Fix it by either:

- Moving important sprite art into sprite slots `0..5`, or
- Increasing `BG_TILE_BASE` / changing OBJ tile export policy in `src/editor/exporter.zig`.

### Tile IDs look shifted in-game

This is expected: runtime BG tile IDs are editor tile IDs plus `BG_TILE_BASE` (`6`). Your engine must load exported BG tiles into VRAM starting at tile slot `6`.

### Palettes look wrong

Confirm that:

- Palette words are read little-endian.
- Colours are treated as GBC 15-bit BGR/RGB word layout: `rrrrr ggggg bbbbb` in bits `0..14` as described above.
- BG palettes go to BG palette RAM, and sprite palettes go to OBJ palette RAM.

### Attribute map has no effect

On GBC, BG tile attributes live in **VRAM bank 1**, not bank 0. Copy tile IDs to bank 0 and attributes to bank 1 at the same BG map address.
