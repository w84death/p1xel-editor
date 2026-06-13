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
DEF MAX_ENEMIES                         EQU 8
DEF ENEMY_ANIM_DELAY                    EQU 16
DEF ENEMY_MOVE_DELAY                    EQU 4
DEF ENEMY_OAM_ADDR                      EQU PLAYER_OAM_ADDR + 4
DEF ENEMY_DIR_RIGHT                     EQU 0
DEF ENEMY_DIR_LEFT                      EQU 1
DEF ENEMY_DIR_UP                        EQU 2
DEF ENEMY_DIR_DOWN                      EQU 3
DEF ENEMY_SNAKE_MARKER_TILE             EQU 3
DEF ENEMY_SNAKE_TILE_1                  EQU 3
DEF ENEMY_SCORPION_MARKER_TILE          EQU 5
DEF ENEMY_SCORPION_TILE_1               EQU 5

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
PlayerSpriteTile:                       ds 1
PlayerSpriteAttr:                       ds 1
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
EnemyCount:                             ds 1
EnemyAnimTimer:                         ds 1
EnemyAnimFrame:                         ds 1
EnemyMoveTimer:                         ds 1
EnemySpawnX:                            ds 1
EnemySpawnY:                            ds 1
EnemySpawnBaseTile:                     ds 1
EnemySpawnAttr:                         ds 1
EnemyWorldX:                            ds MAX_ENEMIES
EnemyWorldY:                            ds MAX_ENEMIES
EnemyBaseTile:                          ds MAX_ENEMIES
EnemyAttr:                              ds MAX_ENEMIES
EnemyDir:                               ds MAX_ENEMIES
EnemyMoveIndex:                         ds 1
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
  ld a, ENEMY_MOVE_DELAY
  ld [EnemyMoveTimer], a

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
  call UpdateEnemySprites

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
  call UpdateCamera
  call UpdateEnemySprites
  call HandleLevelSwap
  call HandleDPad
  call MoveEnemies
  call AnimatePlayer
  call AnimateEnemies
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
  ld a, [FrameCounter]
  inc a
  ld [FrameCounter], a
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

  .player_tile
  ld a, [PlayerSpriteTile]
  ld [PLAYER_OAM_ADDR + 2], a

  .player_attr
  ld a, [PlayerSpriteAttr]
  ld [PLAYER_OAM_ADDR + 3], a
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
  ld [PlayerSpriteTile], a
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
  ld [PlayerSpriteTile], a
  ret

SetPlayerIdleTile:
  ld a, PLAYER_IDLE_TILE
  ld [PlayerSpriteTile], a
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
  ld a, [PlayerFacing]
  or a
  jr z, .face_left

.face_right
  ld a, PLAYER_ATTR | OAMF_XFLIP
  ld [PlayerSpriteAttr], a
  ret

.face_left
  ld a, PLAYER_ATTR
  ld [PlayerSpriteAttr], a
  ret

InitPlayer:
  ld a, PLAYER_START_WORLD_X
  ld [PlayerWorldX], a
  ld a, PLAYER_START_WORLD_Y
  ld [PlayerWorldY], a
  ld a, PLAYER_TILE
  ld [PlayerSpriteTile], a
  ld a, PLAYER_ATTR
  ld [PlayerSpriteAttr], a

  call ApplyPlayerFacingAttr
  call UpdateCamera
  ret

LoadLevelEnemies:
  xor a
  ld [EnemyCount], a
  ld [EnemyAnimFrame], a
  ld a, ENEMY_ANIM_DELAY
  ld [EnemyAnimTimer], a
  ld a, ENEMY_MOVE_DELAY
  ld [EnemyMoveTimer], a

  ld a, [LevelDataStart]
  ld l, a
  ld a, [LevelDataStart + 1]
  ld h, a

.loop
  ld a, h
  ld b, a
  ld a, [LevelDataEnd + 1]
  cp b
  jr nz, .read_record
  ld a, l
  ld b, a
  ld a, [LevelDataEnd]
  cp b
  ret z

.read_record
  ld a, [hli]                            ; x tile
  add a
  add a
  add a
  ld [EnemySpawnX], a
  inc hl                                  ; x high byte

  ld a, [hli]                            ; y tile
  add a
  add a
  add a
  ld [EnemySpawnY], a
  inc hl                                  ; y high byte

  ld a, [hli]                            ; sprite id low byte
  ld b, a
  inc hl                                  ; sprite id high byte
  ld a, [hli]                            ; exported OAM attrs
  ld [EnemySpawnAttr], a
  inc hl                                  ; reserved byte

  ld a, b
  cp ENEMY_SNAKE_MARKER_TILE
  jr z, .snake
  cp ENEMY_SCORPION_MARKER_TILE
  jr z, .scorpion
  jr .loop

.snake
  ld a, ENEMY_SNAKE_TILE_1
  jr .spawn

.scorpion
  ld a, ENEMY_SCORPION_TILE_1

.spawn
  ld [EnemySpawnBaseTile], a
  push hl
  call SpawnEnemy
  pop hl
  jr .loop

SpawnEnemy:
  ld a, [EnemyCount]
  cp MAX_ENEMIES
  ret nc
  ld b, a

  ld l, b
  ld h, 0
  ld de, EnemyWorldX
  add hl, de
  ld a, [EnemySpawnX]
  ld [hl], a

  ld l, b
  ld h, 0
  ld de, EnemyWorldY
  add hl, de
  ld a, [EnemySpawnY]
  ld [hl], a

  ld l, b
  ld h, 0
  ld de, EnemyBaseTile
  add hl, de
  ld a, [EnemySpawnBaseTile]
  ld [hl], a

  ld l, b
  ld h, 0
  ld de, EnemyAttr
  add hl, de
  ld a, [EnemySpawnAttr]
  ld [hl], a

  ld a, b
  ld [EnemyMoveIndex], a
  call StoreInitialEnemyDirection

  ld hl, EnemyCount
  inc [hl]
  ret

MoveEnemies:
  ld a, [EnemyCount]
  and a
  ret z

  ld hl, EnemyMoveTimer
  dec [hl]
  ret nz
  ld a, ENEMY_MOVE_DELAY
  ld [hl], a

  ld a, [EnemyCount]
  ld b, a
  ld c, 0
.loop
  push bc
  call MoveEnemy
  pop bc
  inc c
  dec b
  jr nz, .loop
  ret

MoveEnemy:
  ld a, c
  ld [EnemyMoveIndex], a

  ld l, c
  ld h, 0
  ld de, EnemyDir
  add hl, de
  ld a, [hl]
  and 3
  cp ENEMY_DIR_LEFT
  jr z, .try_left
  cp ENEMY_DIR_UP
  jr z, .try_up
  cp ENEMY_DIR_DOWN
  jr z, .try_down

.try_right
  call LoadEnemyPosition
  ld a, b
  cp WORLD_X_MAX
  jr nc, .blocked
  add TILE_SIZE
  ld b, a
  call TargetWorldWalkable
  jr nc, .blocked
  call IncrementEnemyX
  ret

.try_left
  call LoadEnemyPosition
  ld a, b
  and a
  jr z, .blocked
  dec a
  ld b, a
  call TargetWorldWalkable
  jr nc, .blocked
  call DecrementEnemyX
  ret

.try_up
  call LoadEnemyPosition
  ld a, c
  and a
  jr z, .blocked
  dec a
  ld c, a
  call TargetWorldWalkable
  jr nc, .blocked
  call DecrementEnemyY
  ret

.try_down
  call LoadEnemyPosition
  ld a, c
  cp WORLD_Y_MAX
  jr nc, .blocked
  add TILE_SIZE
  ld c, a
  call TargetWorldWalkable
  jr nc, .blocked
  call IncrementEnemyY
  ret

.blocked
  call StoreNextEnemyDirection
  ret

LoadEnemyPosition:
  ld a, [EnemyMoveIndex]
  ld l, a
  ld h, 0
  ld de, EnemyWorldX
  add hl, de
  ld a, [hl]
  ld b, a

  ld a, [EnemyMoveIndex]
  ld l, a
  ld h, 0
  ld de, EnemyWorldY
  add hl, de
  ld a, [hl]
  ld c, a
  ret

IncrementEnemyX:
  ld a, [EnemyMoveIndex]
  ld l, a
  ld h, 0
  ld de, EnemyWorldX
  add hl, de
  inc [hl]
  ret

DecrementEnemyX:
  ld a, [EnemyMoveIndex]
  ld l, a
  ld h, 0
  ld de, EnemyWorldX
  add hl, de
  dec [hl]
  ret

IncrementEnemyY:
  ld a, [EnemyMoveIndex]
  ld l, a
  ld h, 0
  ld de, EnemyWorldY
  add hl, de
  inc [hl]
  ret

DecrementEnemyY:
  ld a, [EnemyMoveIndex]
  ld l, a
  ld h, 0
  ld de, EnemyWorldY
  add hl, de
  dec [hl]
  ret

RandomEnemyDirection:
  ld a, [rDIV]
  ld b, a
  ld a, [FrameCounter]
  xor b
  ld b, a
  ld a, [EnemyMoveIndex]
  xor b
  and 3
  ret

StoreInitialEnemyDirection:
  call RandomEnemyDirection
  ld b, a
  ld a, [EnemyMoveIndex]
  ld l, a
  ld h, 0
  ld de, EnemyDir
  add hl, de
  ld a, b
  ld [hl], a
  ret

StoreNextEnemyDirection:
  call RandomEnemyDirection
  ld b, a
  ld a, [EnemyMoveIndex]
  ld l, a
  ld h, 0
  ld de, EnemyDir
  add hl, de
  ld a, [hl]
  and 3
  cp b
  jr nz, .store
  ld a, b
  inc a
  and 3
  ld b, a
.store
  ld a, b
  ld [hl], a
  ret

AnimateEnemies:
  ld a, [EnemyCount]
  and a
  ret z

  ld hl, EnemyAnimTimer
  dec [hl]
  ret nz

  ld a, ENEMY_ANIM_DELAY
  ld [hl], a
  ld a, [EnemyAnimFrame]
  xor 1
  ld [EnemyAnimFrame], a
  ret

UpdateEnemySprites:
  call ClearEnemyOAM
  ld a, [EnemyCount]
  and a
  ret z

  ld b, a
  ld c, 0

.loop
  ld a, c
  add a
  add a
  ld l, a
  ld h, 0
  ld de, ENEMY_OAM_ADDR
  add hl, de
  push hl

  ld l, c
  ld h, 0
  ld de, EnemyWorldY
  add hl, de
  ld a, [hl]
  ld d, a
  ld a, [CameraY]
  ld e, a
  ld a, d
  sub e
  add OAM_Y_OFFSET
  pop hl
  ld [hli], a
  push hl

  ld l, c
  ld h, 0
  ld de, EnemyWorldX
  add hl, de
  ld a, [hl]
  ld d, a
  ld a, [CameraX]
  ld e, a
  ld a, d
  sub e
  add OAM_X_OFFSET
  pop hl
  ld [hli], a
  push hl

  ld l, c
  ld h, 0
  ld de, EnemyBaseTile
  add hl, de
  ld a, [hl]
  ld d, a
  ld a, [EnemyAnimFrame]
  add d
  pop hl
  ld [hli], a
  push hl

  ld l, c
  ld h, 0
  ld de, EnemyAttr
  add hl, de
  ld a, [hl]
  pop hl
  ld [hl], a

  inc c
  dec b
  jr nz, .loop
  ret

ClearEnemyOAM:
  ld hl, ENEMY_OAM_ADDR
  ld b, MAX_ENEMIES
.loop
  xor a
  ld [hli], a
  inc hl
  inc hl
  inc hl
  dec b
  jr nz, .loop
  ret

LoadLevelHot:
  push hl
  call WaitVBlank
  xor a
  ld [rLCDC], a
  pop hl
  call LoadLevel
  call UpdateCamera
  call UpdateEnemySprites
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
  ;   DW Sprites, SpritesEnd
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

  .load_sprites
    call ReadLevelDataRange
    push hl
    call LoadLevelEnemies
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
