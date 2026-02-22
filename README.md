# P1Xel Editor

![menu window](media/alpha9-menu.png)

## About
Sprite editor for my MS-DOS game. Made in Zig and [fenster](https://github.com/zserge/fenster).

![edit window](media/alpha9-editor.png)

### Features

#### General
- Linux and Windows support (small binary, <40KiB compressed)
- Built with Zig and fenster (minimal dependencies)
- VFX (Snow effect in menu/about)

#### Editor
- Pixel-perfect 16x16 sprite editing
- Tools: Pixel, Fill, Line (with preview)
- Background toggle (Light/Dark) for transparency checking
- Export single sprite to PPM

#### Palette System
- Based on DawBringer's 16-color palette (DB16)
- Custom 4-color sub-palettes per tile
- Manage up to 128 custom palettes
- Palette operations: Create, Delete, Update, Save as New
- Keyboard shortcuts for palette switching and cycling

#### Tileset Management
- Support for up to 128 tiles
- Reorder tiles (Move, Swap, Delete)
- Save/Load tileset data (`tiles.dat`)

#### Preview & Scene
- Real-time preview with 3 layers
- Layer visibility controls
- **Isometric (ISO) view mode**
- Camera navigation (North, South, East, West)
- **Export preview to flattened PPM image**

![tileset window](media/alpha9-tileset.png)
![palettes window](media/alpha9-palettes.png)
![preview window](media/alpha9-preview.png)

## Run
```
zig build run
```

## Build Small Binary

Host Linux -> **Linux 64**
```
zig build \
  -Doptimize=ReleaseSmall \
  upx
```

Host Linux -> **Windows 32**
``` 
zig build \
  -Dtarget=x86-windows \
  -Doptimize=ReleaseSmall \
  upx
```
