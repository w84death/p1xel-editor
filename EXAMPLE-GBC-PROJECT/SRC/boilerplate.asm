; ============================================================
; Hardware constants
; ============================================================

rJOYP  EQU $FF00
rIF    EQU $FF0F
rLCDC  EQU $FF40
rSTAT  EQU $FF41
rSCY   EQU $FF42
rSCX   EQU $FF43
rLY    EQU $FF44
rDMA   EQU $FF46
rVBK   EQU $FF4F
rBCPS  EQU $FF68
rBCPD  EQU $FF69
rIE    EQU $FFFF

IEF_VBLANK EQU %00000001

; ============================================================
; Interrupt vectors
; ============================================================

SECTION "VBlank vector", ROM0[$0040]
    jp VBlankISR

; ============================================================
; Cartridge entry
; ============================================================

SECTION "Header", ROM0[$0100]
    nop
    jp EntryPoint
    ds $0150 - @, 0

; ============================================================
; Main code
; ============================================================

SECTION "Main", ROM0[$0150]

EntryPoint:
    di
    ld sp, $FFFE

    xor a
    ldh [rIE], a
    ldh [rIF], a

.waitVBlank
    ldh a, [rLY]
    cp 144
    jr c, .waitVBlank

    xor a
    ldh [rLCDC], a          ; LCD off during VBlank

    call ClearShadowOAM
    call CopyDMARoutine
    call LoadGraphics
    call LoadBGPalettes

    ; Turn LCD on: LCD enable + BG enable
    ld a, %10000001
    ldh [rLCDC], a

    ld a, IEF_VBLANK
    ldh [rIE], a
    ei

MainLoop:
    call WaitFrame
    call ReadJoypad
    call UpdateGame
    call BuildSprites
    jr MainLoop

WaitFrame:
    halt
    nop
    ld a, [wFrameReady]
    and a
    jr z, WaitFrame
    xor a
    ld [wFrameReady], a
    ret

; ============================================================
; VBlank
; ============================================================

VBlankISR:
    push af

    ld a, HIGH(wShadowOAM)
    call hOAMDMA

    ld a, 1
    ld [wFrameReady], a

    pop af
    reti

; ============================================================
; Variables
; ============================================================

SECTION "WRAM variables", WRAM0

wFrameReady:
    db

wJoyHeld:
    db

SECTION "Shadow OAM", WRAM0, ALIGN[8]
wShadowOAM:
    ds 160
