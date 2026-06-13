; ==========================================================================|80|
; Hello, World GameBoy Color Game
; by Krzysztof Krystian Jankowski
; smol.p1x.in/assembly/
; https://github.com/w84death/gameboy-color-games
; ==========================================================================|80|

; ======================================> GBC REGISTERS <===================|80|
INCLUDE "gbc_regs.inc"
; ==========================================================================|80|

; ======================================> GAME CONSTANTS  <=================|80|
DEF DPAD_RIGHT_BIT                      EQU $0000
DEF DPAD_LEFT_BIT                       EQU $0001
DEF DPAD_UP_BIT                         EQU $0002
DEF DPAD_DOWN_BIT                       EQU $0003
DEF BUTTON_START_BIT                    EQU $0003
DEF SPRITE_TILE_ADDR                    EQU $8000
DEF BG_TILE_ADDR                        EQU $8000
DEF BG_MAP_ADDR                         EQU _SCRN0

DEF SCREEN_WIDTH                        EQU 160
DEF SCREEN_HEIGHT                       EQU 144
DEF TILE_SIZE                           EQU 8
DEF SPRITE_WIDTH                        EQU 8
DEF SPRITE_HEIGHT                       EQU 8

DEF OAM_X_OFFSET                        EQU 8
DEF OAM_Y_OFFSET                        EQU 16
DEF OAM_RIGHT_THRESH                    EQU 152
DEF OAM_LEFT_THRESH                     EQU 16
DEF OAM_TOP_THRESH                      EQU 24
DEF OAM_BOTTOM_THRESH                   EQU 144
DEF CAMERA_X_MAX                        EQU 96
DEF CAMERA_Y_MAX                        EQU 112
DEF WORLD_X_MAX                         EQU 256 - SPRITE_WIDTH
DEF WORLD_Y_MAX                         EQU 256 - SPRITE_HEIGHT
DEF CAMERA_DEAD_ZONE_TILES              EQU 4
DEF CAMERA_DEAD_ZONE_PX                 EQU CAMERA_DEAD_ZONE_TILES * TILE_SIZE
DEF CAMERA_DEAD_LEFT                    EQU CAMERA_DEAD_ZONE_PX
DEF CAMERA_DEAD_TOP                     EQU CAMERA_DEAD_ZONE_PX
DEF CAMERA_DEAD_RIGHT                   EQU SCREEN_WIDTH - CAMERA_DEAD_ZONE_PX - SPRITE_WIDTH
DEF CAMERA_DEAD_BOTTOM                  EQU SCREEN_HEIGHT - CAMERA_DEAD_ZONE_PX - SPRITE_HEIGHT

DEF SPRITE_X_CENTER                     EQU 80 + 8
DEF SPRITE_Y_CENTER                     EQU 72 + 8
DEF PLAYER_CAMERA_CENTER_X              EQU SPRITE_X_CENTER - OAM_X_OFFSET
DEF PLAYER_CAMERA_CENTER_Y              EQU SPRITE_Y_CENTER - OAM_Y_OFFSET
DEF PLAYER_START_WORLD_X                EQU PLAYER_CAMERA_CENTER_X
DEF PLAYER_START_WORLD_Y                EQU PLAYER_CAMERA_CENTER_Y
DEF PLAYER_ANIM_DELAY                   EQU 4
DEF TREE_FIRST_SLOT                     EQU 0
DEF PLAYER_OAM_ADDR                     EQU _OAMRAM
DEF PLAYER_BASE_OAM_ADDR                EQU PLAYER_OAM_ADDR
DEF PLAYER_IDLE_TILE                    EQU 0
DEF PLAYER_WALK_TILE_1                  EQU 1
DEF PLAYER_WALK_TILE_2                  EQU 2
DEF PLAYER_TILE                         EQU PLAYER_IDLE_TILE
DEF PLAYER_PALETTE                      EQU 0
DEF PLAYER_ATTR                         EQU PLAYER_PALETTE
DEF PLAYER_MOVE_STEPS                   EQU TILE_SIZE
DEF PLAYER_MOVE_DELAY                   EQU 1
DEF PLAYER_SLOW_MOVE_DELAY              EQU 3
DEF TILE_FLAG_TRAVERSABLE               EQU 0
DEF TILE_FLAG_SLOW                      EQU 1

DEF TILES_BG_INDEX_START                EQU 128
; ==========================================================================|80|

; ======================================> HEADER DATA <=====================|80|
SECTION "VBlank vector", ROM0[$0040]
  jp VBlankISR

SECTION "Header", ROM0[$100]
  nop
  jp Entry
  ds $150 - @, 0
; ==========================================================================|80|

; ======================================> WRAM DATA <=======================|80|
SECTION "WRAM Data", WRAM0
FrameCounter:                           ds 1
FrameReady:                             ds 1
PlayerAnimTimer:                        ds 1
PlayerAnimFrame:                        ds 1
PlayerFacing:                           ds 1
CameraX:                                ds 1
CameraY:                                ds 1
CurrentLevel:                           ds 1
PrevButtons:                            ds 1
LevelDataStart:                         ds 2
LevelDataEnd:                           ds 2
PlayerTargetX:                          ds 1
PlayerTargetY:                          ds 1
PlayerWorldX:                           ds 1
PlayerWorldY:                           ds 1
PlayerMoveDX:                           ds 1
PlayerMoveDY:                           ds 1
PlayerMoveFrames:                       ds 1
PlayerMoveDelay:                        ds 1
PlayerMoveTimer:                        ds 1
CollisionMap:                           ds 1024
; ==========================================================================|80|

; ======================================> MAIN SECTION <====================|80|
SECTION "Main", ROM0[$150]

Entry:
  di                                    ; disable interrups
  ld sp, $FFFE
  xor a
  ld [rIE], a
  ld [rIF], a
  call WaitVBlank

  xor a
  ld [rLCDC], a

  .init_camera
  xor a
  ld [CameraX], a
  ld [CameraY], a

  .init_level_switch
  xor a
  ld [CurrentLevel], a
  ld a, %00001111
  ld [PrevButtons], a

  .init_player
  xor a
  ld [FrameCounter], a
  ld [FrameReady], a
  ld [PlayerAnimFrame], a
  ld [PlayerFacing], a
  ld a, PLAYER_ANIM_DELAY
  ld [PlayerAnimTimer], a
  xor a
  ld [PlayerMoveDX], a
  ld [PlayerMoveDY], a
  ld [PlayerMoveFrames], a
  ld a, PLAYER_MOVE_DELAY
  ld [PlayerMoveDelay], a
  ld [PlayerMoveTimer], a

  .init_vram
  xor a
  ld [rVBK], a

  .init_oamram
  ld hl, _OAMRAM
  ld b, 160
  .clear_oam
    xor a
    ld [hli], a
    dec b
    jr nz, .clear_oam

  .load_sprite_tiles
    ld hl, GameTiles
    ld de, SPRITE_TILE_ADDR
    ld bc, GameTilesEnd - GameTiles
    call LoadBytes

  .load_palettes
    ld hl, SpritesPalettes
    ld b, SpritesPalettesEnd - SpritesPalettes
    call LoadObjPalettesCGB

  ld hl, GrasslandLevelDescriptor
  call LoadLevel
  call InitPlayer

  .init_lcd
  ld a, LCDCF_ON | LCDCF_OBJON | LCDCF_BGON | LCDCF_BG8000 | LCDCF_BG9800
  ld [rLCDC], a

  xor a
  ld [rIF], a
  ld a, IEF_VBLANK
  ld [rIE], a
  ei

; ======================================> MAIN LOOP <=======================|80|
MainLoop:
  call WaitFrame
  call HandleLevelSwap
  call HandleDPad
  call AnimatePlayer
  call UpdateCamera
  jr MainLoop

; ==========================================================================|80|



; ======================================> PROCEDURES <======================|80|
WaitVBlank:
  .wait_vblank_end
  ld a, [rLY]
  cp 144
  jr nc, .wait_vblank_end

  .wait_vblank
  ld a, [rLY]
  cp 144
  jr c, .wait_vblank
  ret

WaitFrame:
  halt
  nop
  ld a, [FrameReady]
  and a
  jr z, WaitFrame
  xor a
  ld [FrameReady], a
  ret

VBlankISR:
  push af
  ld a, 1
  ld [FrameReady], a
  pop af
  reti

LoadBytes:
  ; Copies BC bytes from HL to DE
  ; input:
  ;   HL = source
  ;   DE = destination
  ;   BC = byte count
.copy
  ld a, b
  or c
  ret z

  ld a, [hli]
  ld [de], a
  inc de
  dec bc
  jr .copy
  ret

LoadBgPalettesCGB:
  ld a, $80
  ld [rBGPI], a

.copy
  ld a, b
  or a
  ret z

  ld a, [hli]
  ld [rBGPD], a
  dec b
  jr .copy
  ret

LoadObjPalettesCGB:
  ld a, $80
  ld [rOBPI], a

  .copy
  ld a, b
  or a
  ret z

  ld a, [hli]
  ld [rOBPD], a
  dec b
  jr .copy
  ret

WaitForAnyDPad:
  .wait
    call ReadDPad
    cp %00001111       ; no d-pad pressed
    jr z, .wait
  ret

UpdateCamera:
  .camera_x_left
  ld a, [CameraX]
  add CAMERA_DEAD_LEFT
  ld b, a
  ld a, [PlayerWorldX]
  cp b
  jr nc, .camera_x_right
  cp CAMERA_DEAD_LEFT
  jr c, .camera_x_zero
  sub CAMERA_DEAD_LEFT
  jr .clamp_camera_x
.camera_x_right
  ld a, [CameraX]
  add CAMERA_DEAD_RIGHT
  ld b, a
  ld a, [PlayerWorldX]
  cp b
  jr c, .keep_camera_x
  sub CAMERA_DEAD_RIGHT
  jr .clamp_camera_x
.keep_camera_x
  ld a, [CameraX]
  jr .store_camera_x
.camera_x_zero
  xor a
  jr .store_camera_x
.clamp_camera_x
  cp CAMERA_X_MAX + 1
  jr c, .store_camera_x
  ld a, CAMERA_X_MAX
.store_camera_x
  ld [CameraX], a
  ld [rSCX], a

  .camera_y_top
  ld a, [CameraY]
  add CAMERA_DEAD_TOP
  ld b, a
  ld a, [PlayerWorldY]
  cp b
  jr nc, .camera_y_bottom
  cp CAMERA_DEAD_TOP
  jr c, .camera_y_zero
  sub CAMERA_DEAD_TOP
  jr .clamp_camera_y
.camera_y_bottom
  ld a, [CameraY]
  add CAMERA_DEAD_BOTTOM
  ld b, a
  ld a, [PlayerWorldY]
  cp b
  jr c, .keep_camera_y
  sub CAMERA_DEAD_BOTTOM
  jr .clamp_camera_y
.keep_camera_y
  ld a, [CameraY]
  jr .store_camera_y
.camera_y_zero
  xor a
  jr .store_camera_y
.clamp_camera_y
  cp CAMERA_Y_MAX + 1
  jr c, .store_camera_y
  ld a, CAMERA_Y_MAX
.store_camera_y
  ld [CameraY], a
  ld [rSCY], a

  .player_screen_x
  ld a, [PlayerWorldX]
  ld b, a
  ld a, [CameraX]
  ld c, a
  ld a, b
  sub c
  add OAM_X_OFFSET
  ld [PLAYER_OAM_ADDR + 1], a

  .player_screen_y
  ld a, [PlayerWorldY]
  ld b, a
  ld a, [CameraY]
  ld c, a
  ld a, b
  sub c
  add OAM_Y_OFFSET
  ld [PLAYER_OAM_ADDR], a
  ret

HandleDPad:
  ld a, [PlayerMoveFrames]
  and a
  ret nz

  call ReadDPad
  bit DPAD_RIGHT_BIT, a
  jp z, MoveRight
  bit DPAD_LEFT_BIT, a
  jp z, MoveLeft
  bit DPAD_UP_BIT, a
  jp z, MoveUp
  bit DPAD_DOWN_BIT, a
  jp z, MoveDown
  ret

ReadDPad:
  ld a, %00100000     ; select d-pad buttons
  ld [rP1], a
  ld a, [rP1]
  ld a, [rP1]         ; read twice for stability
  and %00001111       ; clean hiher bits to leave only buttons information
  ret

HandleLevelSwap:
  call ReadButtons
  ld b, a
  ld a, [PrevButtons]
  ld c, a
  ld a, b
  ld [PrevButtons], a

  bit BUTTON_START_BIT, b               ; pressed = 0
  ret nz
  bit BUTTON_START_BIT, c               ; ignore held START
  ret z

  call ToggleLevel
  ret

ReadButtons:
  ld a, %00010000                       ; select A/B/Select/Start
  ld [rP1], a
  ld a, [rP1]
  ld a, [rP1]
  and %00001111
  ret

ToggleLevel:
  ld a, [CurrentLevel]
  xor 1
  ld [CurrentLevel], a
  or a
  jr z, .load_grassland

.load_desert
  ld hl, DesertLevelDescriptor
  call LoadLevelHot
  ret

.load_grassland
  ld hl, GrasslandLevelDescriptor
  call LoadLevelHot
  ret

MoveRight:
  ld a, 1
  ld [PlayerFacing], a
  call ApplyPlayerFacingAttr
  call TargetRightWalkable
  ret nc
  call SetPlayerMoveDelayForFlags
  ld a, 1
  ld [PlayerMoveDX], a
  xor a
  ld [PlayerMoveDY], a
  call BeginPlayerMove
  ret

MoveLeft:
  xor a
  ld [PlayerFacing], a
  call ApplyPlayerFacingAttr
  call TargetLeftWalkable
  ret nc
  call SetPlayerMoveDelayForFlags
  ld a, $FF
  ld [PlayerMoveDX], a
  xor a
  ld [PlayerMoveDY], a
  call BeginPlayerMove
  ret

MoveUp:
  call TargetUpWalkable
  ret nc
  call SetPlayerMoveDelayForFlags
  xor a
  ld [PlayerMoveDX], a
  ld a, $FF
  ld [PlayerMoveDY], a
  call BeginPlayerMove
  ret

MoveDown:
  call TargetDownWalkable
  ret nc
  call SetPlayerMoveDelayForFlags
  xor a
  ld [PlayerMoveDX], a
  ld a, 1
  ld [PlayerMoveDY], a
  call BeginPlayerMove
  ret

AnimatePlayer:
  ld a, [PlayerMoveFrames]
  and a
  ret z

  call UpdatePlayerWalkAnimation
  ld hl, PlayerMoveTimer
  dec [hl]
  ret nz

  ld a, [PlayerMoveDelay]
  ld [hl], a

  ld a, [PlayerMoveDX]
  bit 7, a
  jr nz, .move_left
  and a
  jr z, .vertical
  ld hl, PlayerWorldX
  inc [hl]
  jr .vertical
.move_left
  ld a, [PlayerWorldX]
  and a
  jr z, .vertical
  ld hl, PlayerWorldX
  dec [hl]

.vertical
  ld a, [PlayerMoveDY]
  bit 7, a
  jr nz, .move_up
  and a
  jr z, .tick
  ld hl, PlayerWorldY
  inc [hl]
  jr .tick
.move_up
  ld a, [PlayerWorldY]
  and a
  jr z, .tick
  ld hl, PlayerWorldY
  dec [hl]

.tick
  ld hl, PlayerMoveFrames
  dec [hl]
  jr z, .finish_move
  ret
.finish_move
  call SetPlayerIdleTile
  ret

BeginPlayerMove:
  xor a
  ld [PlayerAnimFrame], a
  ld a, PLAYER_ANIM_DELAY
  ld [PlayerAnimTimer], a
  ld a, PLAYER_WALK_TILE_1
  ld [PLAYER_OAM_ADDR + 2], a
  ld a, [PlayerMoveDelay]
  ld [PlayerMoveTimer], a
  ld a, PLAYER_MOVE_STEPS
  ld [PlayerMoveFrames], a
  ret

SetPlayerMoveDelayForFlags:
  bit TILE_FLAG_SLOW, a
  jr z, .normal
  ld a, PLAYER_SLOW_MOVE_DELAY
  jr .store
.normal
  ld a, PLAYER_MOVE_DELAY
.store
  ld [PlayerMoveDelay], a
  ret

UpdatePlayerWalkAnimation:
  ld hl, PlayerAnimTimer
  dec [hl]
  ret nz

  ld a, PLAYER_ANIM_DELAY
  ld [hl], a
  ld a, [PlayerAnimFrame]
  xor 1
  ld [PlayerAnimFrame], a
  or a
  jr z, .frame_1

.frame_2
  ld a, PLAYER_WALK_TILE_2
  jr .store_tile
.frame_1
  ld a, PLAYER_WALK_TILE_1
.store_tile
  ld [PLAYER_OAM_ADDR + 2], a
  ret

SetPlayerIdleTile:
  ld a, PLAYER_IDLE_TILE
  ld [PLAYER_OAM_ADDR + 2], a
  xor a
  ld [PlayerAnimFrame], a
  ld a, PLAYER_ANIM_DELAY
  ld [PlayerAnimTimer], a
  ret

TargetRightWalkable:
  ld a, [PlayerWorldX]
  cp WORLD_X_MAX
  ret nc
  add TILE_SIZE
  ld b, a
  ld a, [PlayerWorldY]
  ld c, a
  jp TargetWorldWalkable

TargetLeftWalkable:
  ld a, [PlayerWorldX]
  cp TILE_SIZE
  jr nc, .inside_map
.blocked
  xor a
  ret
.inside_map
  sub TILE_SIZE
  ld b, a
  ld a, [PlayerWorldY]
  ld c, a
  jp TargetWorldWalkable

TargetUpWalkable:
  ld a, [PlayerWorldY]
  cp TILE_SIZE
  jr nc, .inside_map
.blocked
  xor a
  ret
.inside_map
  sub TILE_SIZE
  ld c, a
  ld a, [PlayerWorldX]
  ld b, a
  jp TargetWorldWalkable

TargetDownWalkable:
  ld a, [PlayerWorldY]
  cp WORLD_Y_MAX
  ret nc
  add TILE_SIZE
  ld c, a
  ld a, [PlayerWorldX]
  ld b, a
  jp TargetWorldWalkable

TargetWorldWalkable:
  ; B = target world pixel X, C = target world pixel Y.
  ; Returns carry set and A = terrain flags when traversable.
  ; Returns carry clear when blocked.
  ld a, c
  srl a
  srl a
  srl a
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl

  ld a, b
  srl a
  srl a
  srl a
  ld e, a
  ld d, 0
  add hl, de
  ld de, CollisionMap
  add hl, de

  ld a, [hl]
  bit TILE_FLAG_TRAVERSABLE, a
  jr z, .blocked
  scf
  ret
.blocked
  xor a
  ret

ApplyPlayerFacingAttr:
  ld hl, PLAYER_OAM_ADDR + 3
  ld a, [PlayerFacing]
  or a
  jr z, .face_left

.face_right
  ld a, PLAYER_ATTR | OAMF_XFLIP
  ld [hl], a
  ret

.face_left
  ld a, PLAYER_ATTR
  ld [hl], a
  ret

InitPlayer:
  ld a, PLAYER_START_WORLD_X
  ld [PlayerWorldX], a
  ld a, PLAYER_START_WORLD_Y
  ld [PlayerWorldY], a

  ld hl, PLAYER_OAM_ADDR
  ld a, SPRITE_Y_CENTER
  ld [hli], a
  ld a, SPRITE_X_CENTER
  ld [hli], a
  ld a, PLAYER_TILE
  ld [hli], a
  ld a, PLAYER_ATTR
  ld [hli], a

  call ApplyPlayerFacingAttr
  call UpdateCamera
  ret

LoadLevelHot:
  push hl
  call WaitVBlank
  xor a
  ld [rLCDC], a
  pop hl
  call LoadLevel
  call RestoreLCD
  ret

RestoreLCD:
  ld a, LCDCF_ON | LCDCF_OBJON | LCDCF_BGON | LCDCF_BG8000 | LCDCF_BG9800
  ld [rLCDC], a
  ret

LoadLevel:
  ; HL = level descriptor:
  ;   DW BgPalettes, BgPalettesEnd
  ;   DW Tiles, TilesEnd
  ;   DW TileMap, TileMapEnd
  ;   DW AttrMap, AttrMapEnd
  ;   DW LogicMap, LogicMapEnd
  .load_palettes
    call ReadLevelDataRange
    push hl
    call LoadLevelBgPalettes
    pop hl

  .load_tiles
    call ReadLevelDataRange
    push hl
    xor a
    ld [rVBK], a
    ld de, BG_TILE_ADDR + (TILES_BG_INDEX_START * 16)
    call LoadLevelBytes
    pop hl

  .load_tilemap
    call ReadLevelDataRange
    push hl
    xor a
    ld [rVBK], a
    ld de, BG_MAP_ADDR
    call LoadLevelBytes
    pop hl

  .load_attrmap
    call ReadLevelDataRange
    push hl
    ld a, 1
    ld [rVBK], a
    ld de, BG_MAP_ADDR
    call LoadLevelBytes
    pop hl

  .load_logicmap
    call ReadLevelDataRange
    push hl
    ld de, CollisionMap
    call LoadLevelBytes
    pop hl

    xor a
    ld [rVBK], a
    ret

ReadLevelDataRange:
  ld a, [hli]
  ld [LevelDataStart], a
  ld a, [hli]
  ld [LevelDataStart + 1], a
  ld a, [hli]
  ld [LevelDataEnd], a
  ld a, [hli]
  ld [LevelDataEnd + 1], a
  ret

LoadLevelBgPalettes:
  ld a, [LevelDataStart]
  ld l, a
  ld a, [LevelDataStart + 1]
  ld h, a
  ld a, [LevelDataEnd]
  sub l
  ld b, a
  call LoadBgPalettesCGB
  ret

LoadLevelBytes:
  ; DE = destination
  push de

  ld a, [LevelDataEnd]
  ld c, a
  ld a, [LevelDataEnd + 1]
  ld b, a
  ld a, [LevelDataStart]
  ld e, a
  ld a, [LevelDataStart + 1]
  ld d, a

  ld a, c
  sub e
  ld c, a
  ld a, b
  sbc a, d
  ld b, a

  ld a, e
  ld l, a
  ld a, d
  ld h, a

  pop de
  call LoadBytes
  ret
; ==========================================================================|80|

; ======================================> P1XEL EDITOR EXPORT <============|80|
; Generated by src/editor/exporter.zig next to each engine_export.p1xb export.
; Provides SpritesPalettes, GameTiles, GrasslandLevelDescriptor,
; DesertLevelDescriptor, and all backing INCBIN label ranges.
include "SRC/p1xel_export.inc"
