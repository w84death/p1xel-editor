# P1Xel Editor

## About
Sprite editor for my MS-DOS game. Made in Zig and Raylib.

### Features

- Linux and Windows under 400KB binary
- pixel perfect, 16x16 sprite/tile editor
- DawBringer's 16 color palette
- custom 4 color palette per tile
- 128 custom palettes
- organizing custom plalettes
- 128 tile per tileset
- save/load custom palettes
- save/load tileset
- organize tiles in tileset
- animated background

### Screenshots

![menu window](media/alpha2-menu.png)

![edit window](media/alpha2-edit.png)

![tileset window](media/alpha2-tileset.png)

## Run
```
zig build run
```

## Build Small Binary

Host Linux -> Linux.
```
zig build \
  -Doptimize=ReleaseSmall \
  upx
```

Host Linux -> Windows
``` 
zig build \
  -Dtarget=x86_64-windows \
  -Doptimize=ReleaseSmall \
  upx
```
