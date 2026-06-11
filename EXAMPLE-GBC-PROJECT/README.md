# P1X GameBoy Color Engine

## About

I started this project to learn 8-bit assembly. As an x86 assembly programmer I'm starting right from making an actual engne.

## Architecture


## Memory


## Level PNG workflow

The game generates two background sets during `zig build`:

- grassland level from `ASSETS/grassland_level.png`
- desert level rendered from `../BLUE-LAGOON-SURVIVOR/DOCS/desert_level.tmx` into `ASSETS/desert_level.png`

The converter uses `rgbgfx` to emit background tiles, tile maps, attribute maps,
and CGB palettes into `BUILD/generated/`, then writes `SRC/level.inc` for RGBDS.
Press `START` in-game to hot-swap the active background tiles, tile map,
attribute map, and BG palettes between grassland and desert.

Limits enforced by the build:
- max 8 CGB background palettes
- max 128 generated background tiles (`0..127` are reserved for sprites)
- max 128 generated sprite tiles
- max 4 colors per 8x8 tile
- max 256x256 px / 32x32 tiles for the current BG map

If `rgbgfx` reports too many palettes/colors/tiles, reduce the PNG and run
`zig build` again.

## Build & Test

Build .gbc ROM file:
```
zig build
```

Run in mGBA emulator:
```
zig build emulate
```




## Dev Logs

### 05-05-2026 Hello, World
I asked ChatGPT for a simple Hello, World game that will show a custom sprite in the center of the screen.
That project is saved in [HELLO-WORLD](/HELLO-WORLD/) folder.

### 05-05-2026 Engine Beginnings
I started playing with the code, ask for more features. Starting refactoring it. Soon I got few sprites, background terrain, and movable player.
