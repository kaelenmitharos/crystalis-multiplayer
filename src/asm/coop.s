;;; smudge sha1 fd0dcde4f1708b30d5c3de1e463f1dde89c5cb64
;;; smudge off

;;; Two-player co-op (flag Cp).  Work in progress.
;;;
;;; Milestone M0 reserved RAM for player 2.
;;; Milestone M1 reads controller 2 and lets player 2 join or leave with
;;; Start.  Player 2 has no hero on screen yet.
;;; Later milestones add the second hero, combat and camera.

.ifdef _COOP

;;; Battery RAM block reserved for co-op: $6280..$62db (92 bytes; M3
;;; extended it from $62bf).
;;;
;;; Picked after auditing $6160..$62ef, which is unused in vanilla:
;;;  - $61fb..$61ff are used by the randomizer (WarriorRingStabCounter,
;;;    PlayerStandingTimer, $61fd in triggers.s, $61fe in itemget.s,
;;;    ShouldRedisplayUI).
;;;  - $6160..$61bf is earmarked upstream for multi-world player names.
;;;  - $6220..$6222 is earmarked upstream for crowd control.
;;;  - $62dc is read by spawn.s under _RANDOM_FLYER_SPAWNS as "map width";
;;;    it is probably a typo for $62fc, but stay clear of it either way.
;;;
;;; This is battery-backed RAM, so it keeps stale values from the last
;;; session.  CoopClearRam zeroes it on every reset and whenever a game
;;; starts (new game or continue), so nothing depends on old values.
CoopRamStart  = $6280
CoopRamEnd    = $62dc  ; exclusive: $62dc itself is read by spawn.s

P2Active      = $6280  ; 0 = player 2 not joined, 1 = joined
P2HP          = $6281  ; current HP
P2MaxHP       = $6282  ; max HP
P2Sword       = $6283  ; equipped sword, 0 = none, 1..4 = wind..thunder
P2Charge      = $6284  ; sword charge level
P2ChargeTimer = $6285  ; sword charge timer
P2Status      = $6286  ; combat status bits (mirrors PlayerStatus layout)
P2DownTimer   = $6287  ; frames left before a downed player 2 can revive
P2Held        = $6288  ; pad 2 buttons held this frame (A B Se St U D L R)
P2Pressed     = $6289  ; pad 2 buttons newly pressed this frame
P2Slot        = $628a  ; object slot holding player 2's sprite, 0 = none
P2Loc         = $628b  ; CurrentLocation when player 2 was last spawned
CoopSave43    = $628c  ; player 1's $43/$49/$4b/$61fd while player 2 runs
CoopSave49    = $628d
CoopSave4b    = $628e
CoopSave61fd  = $628f
CoopOldXY     = $6290  ; 4 bytes: player 2 ground coords before this frame
P2Ground      = $6294  ; 17 bytes: player 2's copy of slot 0 (see
                       ; CoopSlot0Fields; first 4 are XLo XHi YLo YHi)
CoopP1Old     = $62a5  ; 4 bytes: player 1 ground coords after last update
CoopP1OldSpr  = $62a9  ; 4 bytes: player 1 sprite (slot 1) coords, ditto
CoopFlags     = $62ad  ; bit 0: CoopP1Old is valid for the leash
                       ; bit 1: player 2 is idle and already settled
COOP_P1OLD_OK = $01
COOP_P2_SETTLED = $02
CoopPA        = $62ae  ; 4 bytes: position A for CoopDist (also scratch)
CoopPB        = $62b2  ; 4 bytes: position B for CoopDist (also scratch)
CoopDX        = $62b6  ; 2 bytes: |A.x - B.x| from CoopDist
CoopDY        = $62b8  ; 2 bytes: |A.y - B.y| (screens are 240 px tall)
CoopDX0       = $62ba  ; 2 bytes: previous distances, for the leash
CoopDY0       = $62bc
CoopTmp       = $62be  ; 2 bytes scratch
;;; M3 (player 2 fights):
P2Invuln      = $62c0  ; player 2's invincibility timer (like $071a)
P2SwordSlot   = $62c1  ; object slot holding player 2's sword, 0 = none
P2SwordPlane  = $62c2  ; collision plane of player 2's sword (upper nibble)
CoopNoHud     = $62c3  ; nonzero: skip UpdateHPDisplayInternal (player 2 hit)
P2Down        = $62c4  ; nonzero: player 2 is down (0 HP, frozen)
CoopFarTarget = $62c5  ; 2 bytes: bank $0d routine for CoopCall0d
CoopFarA      = $62c7  ; A in/out for CoopCall0d
CoopTarget    = $62c8  ; target slot of player 2's collision
;;; M3b:
P2HudHP       = $62c9  ; P2HP / P2MaxHP as last drawn in the status bar
P2HudMax      = $62ca
P2HudState    = $62cb  ; nonzero: player 2's readout is on screen
P2HudTimer    = $62cc  ; counts down; redraw anyway when it wraps
CoopP2Running = $62cd  ; nonzero while the hero code runs as player 2
;;; v0.2:
P2PlaceTimer  = $62ce  ; frames left to re-check player 2's ground after a spawn
;;; $62cf..$62db spare

;;; Sound effects for join and leave (vanilla SFX ids).
COOP_SFX_JOIN  = $4c   ; SFX_CURSOR_SELECT
COOP_SFX_LEAVE = $4b   ; SFX_CURSOR_MOVE

.segment "fe", "ff"

;;; ----------------------------------------------------------------
;;; Pad 2 input.
;;;
;;; The randomizer's controller shortcuts (_CTRL1_SHORTCUTS) patch the
;;; vanilla read routines to read pad 1 only, and reuse pad 2's zero-page
;;; bytes ($46/$48/$4a/$4c) for pad 1 button-up state.  We leave all of
;;; that alone and read pad 2 separately into P2Held/P2Pressed.
;;;
;;; Called once per frame in game mode 8 (normal play), in place of the
;;; usual controller read.  The hook is the tail of CheckFlag0 in flags.s
;;; (or $cb62 directly when _CHECK_FLAG0 is off).
.reloc
CoopReadControllers:
.ifdef _CTRL1_SHORTCUTS
  jsr ReadControllersWithButtonUp
.else
  jsr ReadControllersWithDirections
.endif
  ;; ReadControllerX uses $4f for its result and $49,x ($4a for x=1) as
  ;; scratch for the DPCM double read.  $4a holds pad 1 button-up state
  ;; under _CTRL1_SHORTCUTS, so save and restore both.
  lda $4a
  pha
  lda $4f
  pha
  ldx #$01
  jsr $ff17 ; ReadControllerX: reads pad 2 into $4f (double read for DPCM)
  lda P2Held
  eor #$ff
  and $4f
  sta P2Pressed
  lda $4f
  sta P2Held
  pla
  sta $4f
  pla
  sta $4a
  ;; Join or leave: Start on pad 2 toggles P2Active.
  lda P2Pressed
  and #$10   ; Start
  beq +
   lda P2Active
   eor #$01
   sta P2Active
   beq ++
    lda #COOP_SFX_JOIN
    jmp $c125 ; StartAudioTrack
++  lda #COOP_SFX_LEAVE ; CoopUpdateP2 despawns player 2 next
    jmp $c125 ; StartAudioTrack
+ rts

.ifndef _CHECK_FLAG0
.ifndef _CTRL1_SHORTCUTS
;;; Nothing else claims the game mode 8 controller read in this case.
.org $cb62 ; MainGameModeJump_08_Normal
  jsr CoopReadControllers
.endif
.endif

;;; Without the controller shortcuts, vanilla gives pad 2 two jobs in game
;;; mode 8 (CheckForController2Buttons): B pauses the game, and A while
;;; pad 1 holds A+B wild warps.  Co-op owns pad 2, so turn both off.
;;; (With the shortcuts on, gamepad.s already overwrites this code.)
;;; The vanilla debug-mode reads of pad 2 ($bf46) are already gone: that
;;; space is freed in 01_init.s.
.ifndef _CTRL1_SHORTCUTS
.org $cbc1 ; CheckForController2Buttons
  rts
.endif

;;; ----------------------------------------------------------------
;;; Player 2 movement (milestone M2a): "context swap".
;;;
;;; Findings that shaped this (from RAM traces in Mesen across a new game,
;;; walking, swinging, charging and wild warps):
;;;
;;;  - The hero is several object slots, not one.  Slot 0 is the ground
;;;    position and runs action $03 ($9d9a in bank $0d): movement, facing,
;;;    terrain, charge.  Slot 1 is the drawn sprite and runs action $01
;;;    ($9b45): it follows slot 0 (minus the jump height) and spawns the
;;;    sword.  Slot 2 is the sword and slot 3 the point in front of the
;;;    hero (talk/trigger hitbox).  Slots 4..$0b are sword shots, $0c is the
;;;    paralysis beam, and map spawns fill $0d upwards by index (up to 17).
;;;    $1e is the dolphin (written directly by vanilla), and $1f is scratch:
;;;    the object loop zeroes $04bf every frame and dialogs, boss escapes and
;;;    the start menu borrow its fields.  So no slot is reserved for us.
;;;
;;;  - Absolute accesses made by actions $03 and $01 while walking (no
;;;    sword) are: slot 0's fields in CoopSlot0Fields below; slot 1's fields
;;;    in CoopSwapP2 plus $03a1 (hitbox); pad state $43 (held), $49
;;;    (direction) and $4b (newly pressed); $61fd (the randomizer's
;;;    trigger-skip latch, consumed with lsr); and reads of PlayerStatus,
;;;    the equipment bytes, $62f0/$62ff/$6300 and the screen position.
;;;    Swinging (B) also writes all of slot 2, which is why pad 2's A and B
;;;    are masked off for now.  ($6060.., $6200.., $00..$0b in the raw trace
;;;    came from the NMI and scanline IRQ, not from the hero code.)
;;;
;;;  - Triggers, NPC talk, item and coin pickups and damage are all object
;;;    collisions, driven by CollisionTable ($96f1, bank $0d).  The sources
;;;    are fixed hero slots (1 = body, 3 = front, 2 and 4..$0c = sword and
;;;    shots), checked against targets $0d..$1e that share a collision plane
;;;    (upper nibble of $03a0,x).  Exits and pits are found by FindExit from
;;;    slot 0's position after the object loop.
;;;
;;; So player 2 lives in the highest free slot in $0d..$1d with action $09.
;;; Action $09's jump table entry is null, so the object loop skips it, but
;;; it is non-zero so the sprite is drawn.  Its collision plane is 0, so it
;;; is never a collision target, and it can never be a source.  Player 2
;;; therefore cannot hit triggers, talk, pick things up, fall into pits,
;;; take exits, deal damage or take damage: only player 1 drives the game.
;;;
;;; Player 2's slot holds their copy of slot 1 (the sprite).  Their copy
;;; of slot 0 (ground position etc.) lives in P2Ground.  Each frame, after
;;; the normal object loop, we swap both copies (and the pad bytes) into
;;; slots 0 and 1, run the hero actions $03 and $01, and swap back.
;;;
;;; The fixed bank is full, so only the hook and the part that must run
;;; with bank $0d mapped (the hero actions) live here.  Everything else is
;;; in expanded bank $3a, mapped at $8000 while it runs.

COOP_BANK = $3a

;;; Replaces the jsr to the object loop in MainGameModeJump_08_Normal.
.org $cb6b
  jsr CoopUpdateObjects

.reloc
CoopUpdateObjects:
  jsr $cccc ; object loop: every slot's action, including the hero's
  lda P2Active
  ora P2Slot  ; also run once after leaving, to despawn
  ora P2HudState ; ... and to clear the HP readout
  beq +
   lda #COOP_BANK
   jsr BankSwitch8k_8000
   jsr CoopUpdateP2
   lda #$0d  ; leave bank $0d mapped, as the object loop does
   jsr BankSwitch16k
+ rts

;;; Calls the bank $0d routine at CoopFarTarget from bank $3a code (use the
;;; COOP_FAR macro).  X and Y pass through both ways; A goes in and comes
;;; back through CoopFarA; the carry comes back.  The extra call level
;;; means a "double return" (pla/pla/rts) inside the routine still comes
;;; back here, so bank $3a is always mapped again before we return.
.reloc
CoopCall0d:
  lda #$0d
  jsr BankSwitch16k   ; (bank switches only touch A)
  jsr @go
  php
  sta CoopFarA
  lda #COOP_BANK
  jsr BankSwitch8k_8000
  lda CoopFarA
  plp
  rts
@go:
  lda CoopFarA
  jmp (CoopFarTarget)

;;; Player 2's collisions (M3): after the vanilla collision pass, check
;;; player 2's body and sword (CoopP2Collisions in bank $3a).
.org $cb7e
  jsr CoopCollisions

.reloc
CoopCollisions:
  jsr $8f6e ; CheckAllObjectCollisions (bank $0d)
  lda P2Slot
  beq +
   lda #COOP_BANK
   jsr BankSwitch8k_8000
   jsr CoopP2Collisions
   lda #$0d  ; leave bank $0d mapped, as before
   jsr BankSwitch16k
+ rts

;;; Midpoint camera (M2b).  _3e90a calls KeepPlayerInCenterOfScreenIfPossible
;;; ($e9ad), which is the only camera code that reads the hero.  While
;;; player 2 is on screen, CoopCameraFar (bank $3a) puts the midpoint of the
;;; two heroes into slot 0 around that call.  FindExit runs after
;;; _3e90a, so slot 0 is back to player 1 by then.
.org $e90a
  jsr CoopCamera

.reloc
CoopCamera:
  lda P2Slot
  beq +
   lda #COOP_BANK
   jsr BankSwitch8k_8000 ; _3e90a maps its own bank right after this
   jmp CoopCameraFar
+ jmp $e9ad ; KeepPlayerInCenterOfScreenIfPossible

;;; HUD guard (M3): UpdateHPDisplayInternal ($8cc0, bank $1a) draws
;;; PlayerHP into the status bar.  While player 2's hit is handled,
;;; PlayerHP holds P2HP, so skip the redraw (CoopNoHud).
;;; (The guard itself is in the fixed bank: bank $1a has no free space.)
.pushseg "1a"
.org $8cc2 ; after txa/pha; was lda #$60 / jsr WaitForNametableBufferAvailable
  jsr CoopHpGuard
  nop
  nop
.popseg
.reloc
CoopHpGuard:
  lda CoopNoHud
  bne +
   lda #$60
   jmp $c72b ; WaitForNametableBufferAvailable (then back to $8cc5)
+ pla        ; drop our return address
  pla
  pla        ; X saved by UpdateHPDisplayInternal
  tax
  rts        ; return from UpdateHPDisplayInternal itself

;;; Charge shots (M3b).  The hero's charge shots spawn through
;;; AdHocSpawnObject, whose AdHocSpawns entries ($bc00, bank $14) give each
;;; shot a slot range [start, end) that always starts at 4 (up to $08 or
;;; $0c; Fire 2, Flame and Storm use slot 4 only).  Its one call to
;;; FindEmptySpawnSlot ($98b9) is redirected here: while player 2 is
;;; joined, player 1's shots use slots 4..7 and player 2's (spawned while
;;; their update runs) use 8..$b.  The vanilla collision pass already
;;; checks all of 4..$b against enemies, so player 2's shots need nothing
;;; more.
;;;
;;; ChargeIndicatorDisplay ($8d59) draws the hero's charge meter (and
;;; waits for the nametable buffer).  Its call in action $03 is redirected
;;; to a guard that skips it while player 2's update runs, so player 2 can
;;; charge without drawing over player 1's meter.
.pushseg "1a"
.org $9779 ; in AdHocSpawnObject: was jsr FindEmptySpawnSlot
  jsr CoopFindSlot
.org $9ef5 ; in ObjectActionJump_03: was jsr ChargeIndicatorDisplay
  jsr CoopChargeGuard
.popseg

.reloc
CoopChargeGuard:
  lda CoopP2Running
  bne +
  jmp $8d59 ; ChargeIndicatorDisplay
+ rts

.reloc
CoopFindSlot:
  cpy #$04           ; only the hero's shots start at slot 4
  bne @go
  lda P2Active
  beq @go
  lda CoopP2Running
  bne @p2
  lda $10            ; player 1: 4..7
  cmp #$09
  bcc @go
  lda #$08
  sta $10
  bne @go            ; (always)
@p2:
  ldy #$08           ; player 2: the same range moved up by 4, within 8..$b
  lda $10
  clc
  adc #$04
  cmp #$0d
  bcc +
   lda #$0c
+ sta $10
@go:
  jmp $98b9 ; FindEmptySpawnSlot

.pushseg "3a" ; COOP_BANK

;;; Calls a bank $0d routine from bank $3a (see CoopCall0d).
.macro COOP_FAR ADDR
  lda #<ADDR
  sta CoopFarTarget
  lda #>ADDR
  sta CoopFarTarget+1
  jsr CoopCall0d
.endmacro

;;; Slot 2 (the hero's sword) as 36 bytes: 32 object fields + coordinates.
.macro COOP_PUSH_SLOT2
  .repeat 32, I
    lda $0302 + I * $20
    pha
  .endrep
  lda $72
  pha
  lda $92
  pha
  lda $b2
  pha
  lda $d2
  pha
.endmacro
.macro COOP_POP_SLOT2
  pla
  sta $d2
  pla
  sta $b2
  pla
  sta $92
  pla
  sta $72
  .repeat 32, I
    pla
    sta $06e2 - I * $20
  .endrep
.endmacro
.macro COOP_COPY_SLOT2_TO_Y
  .repeat 32, I
    lda $0302 + I * $20
    sta $0300 + I * $20, y
  .endrep
  lda $72
  sta $0070,y
  lda $92
  sta $0090,y
  lda $b2
  sta $00b0,y
  lda $d2
  sta $00d0,y
.endmacro

;;; Runs the hero actions with player 2 swapped into slots 0 and 1.
.reloc
CoopRunP2Actions:
  ldx #$00
  COOP_FAR $9d9a ; ObjectActionJump_03
  ldx #$01
  COOP_FAR $9b45 ; ObjectActionJump_01
  rts

;;; Terrain under the point $34..$37, for placing player 2 (M2b), using
;;; the hero's own CheckTerrainUnderObject for slot 0 (forced lookup, no
;;; update to $0380).  Result in $20: 01 pit, 02 impassable on foot,
;;; 04 impassable flying, 20 slide, 40 slow, 80 pain.
CoopCheckTerrain:
  lda #$80
  sta CoopFarA
  ldx #$00
  COOP_FAR $9a30 ; CheckTerrainUnderObject
  rts

;;; Slot 0 fields used by actions $03/$01 (address for slot 0).
.reloc
CoopSlot0FieldsLo:
  .byte $70,$90,$b0,$d0,$00,$40,$60,$80,$60,$80,$00,$20,$60,$80,$a0,$c0,$e0
CoopSlot0FieldsHi:
  .byte $00,$00,$00,$00,$03,$03,$03,$03,$04,$04,$06,$06,$06,$06,$06,$06,$06
COOP_SLOT0_FIELDS = 17

;;; Slot 1 fields used by actions $03/$01 are listed in CoopSwapP2 below:
;;; coordinates, $0300 $0340 $0360 $0380 $04e0 $0560 $0580 $0640 $06c0.
;;; $03a0 (hitbox) is deliberately left out: player 2's slot keeps
;;; collision plane 0, and slot 1's value never changes.

COOP_SETTLE_FRAMES = 60   ; see CoopSettleP2
COOP_P2_ACTION = $09        ; null entry in ObjectActionJumpTable
COOP_FIRST_SLOT = $0d       ; lowest slot player 2 may use
COOP_LAST_SLOT = $1d        ; highest ($1e is the dolphin, $1f is scratch)

;;; Removes player 2's object (on leave).
.reloc
CoopDespawnP2:
  ldx P2Slot
  beq +
   lda $04a0,x
   cmp #COOP_P2_ACTION
   bne ++
    lda #$00
    sta $04a0,x
++ lda #$00
   sta P2Slot
   sta CoopFlags
+ ldx P2SwordSlot   ; and their sword
  beq +
   lda $04a0,x
   cmp #$10
   bne ++
    lda #$00
    sta $04a0,x
++ lda #$00
   sta P2SwordSlot
+ rts

;;; Spawns player 2 as a copy of the hero, at the hero's position, in the
;;; highest free slot.  Clears carry if there is no free slot.
.reloc
CoopSpawnP2:
  jsr CoopDespawnP2
  ldx #COOP_LAST_SLOT
-  lda $04a0,x
   beq +
   dex
   cpx #COOP_FIRST_SLOT-1
  bne -
  clc
  rts
+ stx P2Slot
  ;; Copy all 32 object fields from slot 1 into the new slot.
  lda #$00
  sta $12
  lda #$03
  sta $13
-  ldy #$01
   lda ($12),y
   ldy P2Slot
   sta ($12),y
   lda $12
   clc
   adc #$20
   sta $12
   bcc -
   inc $13
   lda $13
   cmp #$07
  bne -
  ;; ... and the coordinates.
  ldx P2Slot
  lda $71
  sta $70,x
  lda $91
  sta $90,x
  lda $b1
  sta $b0,x
  lda $d1
  sta $d0,x
  ;; Inert action, no collision plane.
  lda #COOP_P2_ACTION
  sta $04a0,x
  lda $03a0,x
  and #$0f
  sta $03a0,x
  ;; Player 2's ground state starts as a copy of slot 0.
  ldx #COOP_SLOT0_FIELDS-1
-  lda CoopSlot0FieldsLo,x
   sta $12
   lda CoopSlot0FieldsHi,x
   sta $13
   ldy #$00
   lda ($12),y
   sta P2Ground,x
   dex
  bpl -
  lda $6c ; CurrentLocation
  sta P2Loc
  jsr CoopPlaceP2  ; one tile beside player 1, on walkable ground
  lda #COOP_SETTLE_FRAMES
  sta P2PlaceTimer
  ;; HP: full on first join; a new map (or the end of a set piece)
  ;; revives a downed player 2.
  lda P2Down
  beq +
   jsr CoopReviveP2
   jmp ++
+ lda P2HP
  bne ++
   lda $03c0       ; PlayerMaxHP
   sta P2MaxHP
   sta P2HP
++ sec
  rts

;;; Swaps slot 0's fields with P2Ground, and slot 1's fields with player
;;; 2's slot.  Calling it twice restores everything.  Unrolled, because it
;;; runs twice a frame: about 17 cycles per field, ~1000 cycles per call.
;;; Keep the slot 0 list in sync with CoopSlot0Fields* above.
.macro COOP_SWAP0 ADDR, IDX
  lda ADDR
  ldy P2Ground+IDX
  sta P2Ground+IDX
  sty ADDR
.endmacro
.macro COOP_SWAP1 BASE
  lda BASE+1
  ldy BASE,x
  sty BASE+1
  sta BASE,x
.endmacro

.reloc
CoopSwapP2:
  COOP_SWAP0 $70, 0
  COOP_SWAP0 $90, 1
  COOP_SWAP0 $b0, 2
  COOP_SWAP0 $d0, 3
  COOP_SWAP0 $0300, 4
  COOP_SWAP0 $0340, 5
  COOP_SWAP0 $0360, 6
  COOP_SWAP0 $0380, 7
  COOP_SWAP0 $0460, 8
  COOP_SWAP0 $0480, 9
  COOP_SWAP0 $0600, 10
  COOP_SWAP0 $0620, 11
  COOP_SWAP0 $0660, 12
  COOP_SWAP0 $0680, 13
  COOP_SWAP0 $06a0, 14
  COOP_SWAP0 $06c0, 15
  COOP_SWAP0 $06e0, 16
  ldx P2Slot
  COOP_SWAP1 $70
  COOP_SWAP1 $90
  COOP_SWAP1 $b0
  COOP_SWAP1 $d0
  COOP_SWAP1 $0300
  COOP_SWAP1 $0340
  COOP_SWAP1 $0360
  COOP_SWAP1 $0380
  COOP_SWAP1 $04e0
  COOP_SWAP1 $0560
  COOP_SWAP1 $0580
  COOP_SWAP1 $0640
  COOP_SWAP1 $06c0
  rts

;;; Leash (M2b): the heroes may not get further apart than this, so the
;;; midpoint camera can keep both 16 px inside the screen.  The camera
;;; only scrolls once the midpoint leaves X $68..$a0 / Y $68..$78 of the
;;; screen, and the hero's invisible wall is X $0a..$fc / Y $18..$d0.
COOP_LEASH_X = 176
COOP_LEASH_Y = 128

;;; ----------------------------------------------------------------
;;; Player 2's HP readout (M3b): "2 Lf HHH/MMM" in the status bar.
;;;
;;; Status bar (nametable $2b00..): row $2b20 is Lf + player 1's bar
;;; (17 tiles from $2b23, all redrawn on every change) then Lv and money;
;;; row $2b40 is Pw, the charge arrows and the ball indicators, then Dl and
;;; Ex; row $2b60 has the enemy HP readout at $2b62..$2b6a (_ENEMY_HP),
;;; blanks to $2b75, then Mp.  The enemy name goes on the border row $2b82.
;;; So player 2's readout uses row 3, $2b6c..$2b74, with the randomizer's
;;; HUD layout (_UPDATE_HUD; with the vanilla HUD (Vh) it is not shown).
;;;
;;; Tiles are staged at $6071..$6079 and queued like UpdateHPDisplayInternal
;;; does.  In normal play the staging area at $6000 is used by map
;;; scrolling (from $6000), player 1's bar and the charge meter
;;; ($6060..$6070), the status numbers (from $607b), map rows ($6080..) and
;;; the enemy readouts ($60a0, $60b0); $60c0.. is used by Draygon 2.
;;; Redrawn only when P2HP or P2MaxHP change, plus every 256 frames in
;;; case a full status bar redraw (menus, map loads) wiped it.
.ifdef _UPDATE_HUD
COOP_HUD_BUF = $71         ; staging offset: $6071..$6079
COOP_HUD_PPU_HI = $2b      ; PPU $2b6c
COOP_HUD_PPU_LO = $6c

.reloc
CoopP2Hud:
  lda P2Active
  bne @joined
  lda P2HudState
  bne +
  rts                ; not joined and not shown
+ lda #$00
  sta P2HudState
  lda #COOP_HUD_BUF
  jsr $c72b          ; WaitForNametableBufferAvailable
  lda #$20           ; blank tile
  ldx #$08
-  sta $6000+COOP_HUD_BUF,x
   dex
  bpl -
  jmp @stage
@joined:
  dec P2HudTimer
  beq @draw          ; periodic refresh
  lda P2HudState
  beq @draw
  lda P2HP
  cmp P2HudHP
  bne @draw
  lda P2MaxHP
  cmp P2HudMax
  bne @draw
  rts
@draw:
  lda #$01
  sta P2HudState
  lda P2HP
  sta P2HudHP
  lda P2MaxHP
  sta P2HudMax
  lda #COOP_HUD_BUF
  jsr $c72b          ; WaitForNametableBufferAvailable
  lda #$02           ; "2"
  sta $6000+COOP_HUD_BUF
  lda #$80           ; "Lf"
  sta $6000+COOP_HUD_BUF+1
  lda P2HP
  ldx #COOP_HUD_BUF+2
  jsr @digits
  lda #$9d           ; "/"
  sta $6000+COOP_HUD_BUF+5
  lda P2MaxHP
  ldx #COOP_HUD_BUF+6
  jsr @digits
@stage:
  jsr $c43e          ; DisableNMI
  ldx $0b            ; NametableBufferWriteOffset
  lda #COOP_HUD_PPU_HI
  sta $6200,x
  lda #COOP_HUD_PPU_LO
  sta $6201,x
  lda #$09
  sta $6202,x
  lda #COOP_HUD_BUF
  sta $6203,x
  txa
  clc
  adc #$04
  and #$1f
  sta $0b
  jmp $c436          ; EnableNMI
;;; Three decimal digits of A at $6000+X..X+2 (digit tiles are $00..$09).
@digits:
  ldy #$00
-  cmp #100
   bcc +
   sbc #100
   iny
  bne -
+ pha
  tya
  sta $6000,x
  pla
  ldy #$00
-  cmp #10
   bcc +
   sbc #10
   iny
  bne -
+ pha
  tya
  sta $6001,x
  pla
  sta $6002,x
  rts
.endif ; _UPDATE_HUD

.reloc
CoopUpdateP2:
.ifdef _UPDATE_HUD
  jsr CoopP2Hud
.endif
  ;; Player 2 left: remove their object.
  lda P2Active
  bne +
   jmp CoopDespawnP2
+
  ;; Hide player 2 during set pieces: player 1 changed (Change), riding
  ;; the dolphin, flying (terrain susceptibility $34), or in any hero
  ;; action other than the normal $03/$01 (cutscenes, warps, deaths...).
  ;; They reappear beside player 1 when it ends.
  lda $04a0
  cmp #$03
  bne @hide
  lda $04a1
  cmp #$01
  bne @hide
  lda $0710        ; PlayerStatus: $80 changed, $40 dolphin
  and #$c0
  bne @hide
  lda $0460
  cmp #$34         ; flying
  bne @normal
@hide:
  jmp CoopDespawnP2
@normal:
  ;; (Re)spawn after joining, after a map load, or if the slot was taken.
  ldx P2Slot
  beq @spawn
  lda $04a0,x
  cmp #COOP_P2_ACTION
  bne @spawn
  lda $6c ; CurrentLocation
  cmp P2Loc
  beq @spawned
@spawn:
  jsr CoopSpawnP2
  bcs @spawned
  rts             ; no free slot this frame
@spawned:
  jsr CoopP2Vitals
  lda P2Down
  beq +
   jmp CoopP2DownFrame
+ jsr CoopSettleP2
  ;; Select on pad 2: back next to player 1.
  lda P2Pressed
  and #$20
  beq +
   jsr CoopPlaceP2
+
  ;; Remember where player 2 stood, for the leash and the screen clamp.
  ldx #$03
-  lda P2Ground,x
   sta CoopOldXY,x
   dex
  bpl -
  ;; Idle skip: with no direction held and nothing moving them (jump,
  ;; knockback, slide), the hero update changes nothing for player 2
  ;; after one settling frame, so skip the swap and both actions (about
  ;; 3500 cycles).
  lda P2Held
  and #$0f
  bne @active
  lda P2Pressed
  and #$40             ; B: swing
  bne @active
  lda P2Ground+10      ; $0600 sword timer (swinging)
  bne @active
  lda P2Ground+11      ; $0620 jump height
  bne @active
  lda P2Ground+5       ; $0340 knockback (upper nibble)
  and #$f0
  bne @active
  lda P2Ground+14      ; $06a0 slide counter
  bne @active
  lda CoopFlags
  and #COOP_P2_SETTLED
  beq @settle
  jmp @after
@settle:
  lda CoopFlags
  ora #COOP_P2_SETTLED
  sta CoopFlags
  bne @run             ; (always) one idle frame to settle the pose
@active:
  lda CoopFlags
  and #$ff-COOP_P2_SETTLED
  sta CoopFlags
@run:
  ;; Sword frame?  Action $01 (re)loads the sword into slot 2 on every
  ;; frame of a swing (while the sword timer $0600 runs), so player 1's
  ;; slot 2 is parked on the stack and player 2's new sword is moved to
  ;; their own slot afterwards.
  lda P2Pressed
  and #$40
  ora P2Ground+10      ; $0600 sword timer
  sta CoopTmp+1        ; nonzero: sword frame (kept until after the swap)
  bne @park
  jmp @parked
@park:
  COOP_PUSH_SLOT2
@parked:
  ;; Swap in player 2: objects, then pad bytes.
  jsr CoopSwapP2
  lda $43
  sta CoopSave43
  lda $49
  sta CoopSave49
  lda $4b
  sta CoopSave4b
  lda $61fd
  sta CoopSave61fd
  lda P2Held
  and #$7f         ; no A yet.  B held starts the swing (action $03 sets the
  sta $43          ; sword timer; holding it charges, and releasing it
                   ; fires a charge shot into slots 8..$b (M3b)
  and #$0f
  tay
  lda $fed0,y      ; DirectionsByDpadBits
  sta $49
  lda P2Pressed
  and #$7f         ; B pressed swings; no A yet
  sta $4b
  lda #$00
  sta $61fd        ; never consume player 1's trigger-skip latch
  ;; While player 2 runs (CoopP2Running), CoopChargeGuard skips the charge
  ;; meter, which would draw player 2's charge over player 1's and wait
  ;; for the nametable buffer (it cost 32% lag frames in M2a), and
  ;; CoopFindSlot puts player 2's charge shots in slots 8..$b.
  lda #$01
  sta CoopP2Running
  ;; Player 2's status for their update: action $01 picks the slime
  ;; sprite and speed for curse.
  lda $0710          ; PlayerStatus
  ldy P2Status
  sta P2Status
  sty $0710
  ;; Run the hero's update as player 2 (fixed bank; maps bank $0d).
  jsr CoopRunP2Actions
  lda $0710
  ldy P2Status
  sta P2Status
  sty $0710
  lda #$00
  sta CoopP2Running
  ;; Swap back.
  jsr CoopSwapP2
  lda CoopSave43
  sta $43
  lda CoopSave49
  sta $49
  lda CoopSave4b
  sta $4b
  lda CoopSave61fd
  sta $61fd
  ;; Sword frame: move what action $01 put in slot 2 to player 2's sword
  ;; slot, then bring back player 1's slot 2.
  lda CoopTmp+1
  bne @unpark
  jmp @after
@unpark:
  lda $04a2
  cmp #$10           ; a sword was loaded
  beq @haveSword
  jmp @pop
@haveSword:
  jsr CoopGetSwordSlot
  bcs @copySword
  jmp @pop
@copySword:
  COOP_COPY_SLOT2_TO_Y
  lda $03a0,y        ; keep the plane for our own collision check only
  and #$f0
  sta P2SwordPlane
  lda $03a0,y
  and #$0f
  sta $03a0,y
@pop:
  COOP_POP_SLOT2
@after:
  ;; Leash (undo whichever move stretched it), then keep player 2 on
  ;; screen.  Usually one distance check: the detailed checks only run
  ;; when the heroes are past the leash.
  jsr CoopSetPAToP1
  jsr CoopSetPBToP2
  jsr CoopDist
  jsr CoopOverLeash
  bcc +
   jsr CoopLeashP2
   jsr CoopLeashP1
+ jsr CoopClampP2
  ;; Remember player 1's position for next frame's leash check.
  lda $70
  sta CoopP1Old
  lda $90
  sta CoopP1Old+1
  lda $b0
  sta CoopP1Old+2
  lda $d0
  sta CoopP1Old+3
  lda $71
  sta CoopP1OldSpr
  lda $91
  sta CoopP1OldSpr+1
  lda $b1
  sta CoopP1OldSpr+2
  lda $d1
  sta CoopP1OldSpr+3
  lda CoopFlags
  ora #COOP_P1OLD_OK
  sta CoopFlags
  rts

;;; Sets carry if CoopDX/DY are past the leash on either axis.
CoopOverLeash:
  lda CoopDX+1
  bne @yes
  lda #COOP_LEASH_X
  cmp CoopDX
  bcc @yes
  lda CoopDY+1
  bne @yes
  lda #COOP_LEASH_Y
  cmp CoopDY
  bcc @yes
  clc
  rts
@yes:
  sec
  rts

;;; Undo player 2's move if it stretched the leash.
CoopLeashP2:
  jsr CoopSetPAToP1
  ldx #$03
-  lda CoopOldXY,x
   sta CoopPB,x
   dex
  bpl -
  jsr CoopDist
  jsr CoopSaveDist
  jsr CoopSetPBToP2
  jsr CoopDist
  jsr CoopLeashViolated
  bcc +
  jmp CoopRevertP2
+ rts

;;; Undo player 1's move (since our last update) if it stretched the leash.
CoopLeashP1:
  lda CoopFlags
  and #COOP_P1OLD_OK
  beq +
  ldx #$03
-  lda CoopP1Old,x
   sta CoopPA,x
   dex
  bpl -
  jsr CoopSetPBToP2
  jsr CoopDist
  jsr CoopSaveDist
  jsr CoopSetPAToP1
  jsr CoopDist
  jsr CoopLeashViolated
  bcc +
   lda CoopP1Old
   sta $70
   lda CoopP1Old+1
   sta $90
   lda CoopP1Old+2
   sta $b0
   lda CoopP1Old+3
   sta $d0
   lda CoopP1OldSpr
   sta $71
   lda CoopP1OldSpr+1
   sta $91
   lda CoopP1OldSpr+2
   sta $b1
   lda CoopP1OldSpr+3
   sta $d1
+ rts

CoopSetPAToP1:
  lda $70
  sta CoopPA
  lda $90
  sta CoopPA+1
  lda $b0
  sta CoopPA+2
  lda $d0
  sta CoopPA+3
  rts

CoopSetPBToP2:
  ldx #$03
-  lda P2Ground,x
   sta CoopPB,x
   dex
  bpl -
  rts

CoopSaveDist:
  lda CoopDX
  sta CoopDX0
  lda CoopDX+1
  sta CoopDX0+1
  lda CoopDY
  sta CoopDY0
  lda CoopDY+1
  sta CoopDY0+1
  rts

;;; CoopDX/CoopDY <- |A - B| per axis (16 bits).  Y is in pixels across
;;; 240 px screens: y = hi * 240 + lo.
CoopDist:
  lda CoopPA
  sec
  sbc CoopPB
  sta CoopDX
  lda CoopPA+1
  sbc CoopPB+1
  sta CoopDX+1
  bpl +
   lda #$00
   sec
   sbc CoopDX
   sta CoopDX
   lda #$00
   sbc CoopDX+1
   sta CoopDX+1
+ lda CoopPA+2
  sec
  sbc CoopPB+2
  sta CoopDY
  lda #$00
  sbc #$00          ; sign-extend the borrow
  sta CoopDY+1
  lda CoopPA+3
  sec
  sbc CoopPB+3
  tax               ; signed difference in screens
  beq @abs
  bmi @neg
@pos:
   lda CoopDY
   clc
   adc #240
   sta CoopDY
   lda CoopDY+1
   adc #$00
   sta CoopDY+1
   dex
  bne @pos
  beq @abs
@neg:
   lda CoopDY
   sec
   sbc #240
   sta CoopDY
   lda CoopDY+1
   sbc #$00
   sta CoopDY+1
   inx
  bne @neg
@abs:
  lda CoopDY+1
  bpl +
   lda #$00
   sec
   sbc CoopDY
   sta CoopDY
   lda #$00
   sbc CoopDY+1
   sta CoopDY+1
+ rts

;;; Sets carry if CoopDX/DY break the leash on an axis where the distance
;;; also grew compared with CoopDX0/DY0 (so a move that shortens the
;;; distance is always allowed).
CoopLeashViolated:
  lda CoopDX+1
  bne @xFar
  lda #COOP_LEASH_X
  cmp CoopDX
  bcs @checkY
@xFar:
  lda CoopDX0
  cmp CoopDX
  lda CoopDX0+1
  sbc CoopDX+1
  bcc @yes          ; DX0 < DX: grew
@checkY:
  lda CoopDY+1
  bne @yFar
  lda #COOP_LEASH_Y
  cmp CoopDY
  bcs @no
@yFar:
  lda CoopDY0
  cmp CoopDY
  lda CoopDY0+1
  sbc CoopDY+1
  bcc @yes
@no:
  clc
  rts
@yes:
  sec
  rts

;;; Puts player 2 back where they stood before this frame's move.
CoopRevertP2:
  ldx #$03
-  lda CoopOldXY,x
   sta P2Ground,x
   dex
  bpl -
  jmp CoopSyncP2Sprite

;;; Keeps player 2 on screen.  If this frame's move took them off screen,
;;; undo it; if they are still off screen (the camera moved away), place
;;; them beside player 1.
CoopClampP2:
  jsr CoopSetPBToP2
  jsr CoopPBOnScreen
  bcs +
  jsr CoopRevertP2
  jsr CoopSetPBToP2
  jsr CoopPBOnScreen
  bcs +
  jmp CoopPlaceP2
+ rts

;;; Places player 2 beside player 1 on walkable ground: one tile left,
;;; right, below or above; then the diagonals; then two tiles away; else
;;; on top of player 1.  Each candidate must be on screen, and the
;;; hero's own terrain check must find no pit, wall, slide or pain there.
COOP_PLACE_COUNT = 12
CoopPlaceOffX:
  .byte $f0,$10,$00,$00, $f0,$10,$f0,$10, $e0,$20,$00,$00
CoopPlaceOffY:
  .byte $00,$00,$10,$f0, $10,$10,$f0,$f0, $00,$00,$20,$e0
CoopPlaceP2:
  lda #$00
  sta CoopTmp           ; candidate index
@next:
  ldy CoopTmp
  ;; X: player 1's X plus a signed offset.
  lda CoopPlaceOffX,y
  sta CoopTmp+1
  clc
  adc $70
  sta CoopPB
  lda #$00
  bit CoopTmp+1
  bpl +
   lda #$ff
+ adc $90
  sta CoopPB+1
  ;; Y: player 1's Y plus a signed offset, wrapping at 240 per screen.
  lda $d0
  sta CoopPB+3
  lda CoopPlaceOffY,y
  bmi @yUp
   clc
   adc $b0
   bcs +                ; past 255: certainly past 240
   cmp #240
   bcc @yStore
+  sec
   sbc #240
   inc CoopPB+3
   jmp @yStore
@yUp:
  clc
  adc $b0               ; $b0 - |offset|: carry set if no borrow
  bcs @yStore
   sec
   sbc #16              ; (A + 256) - 16 = A + 240
   dec CoopPB+3
@yStore:
  sta CoopPB+2
  jsr CoopPBOnScreen
  bcc @reject
  jsr CoopTerrainAtPB
  and #$a3              ; pit, impassable on foot, slide, pain
  bne @reject
  ldx #$03
-  lda CoopPB,x
   sta P2Ground,x
   dex
  bpl -
  jmp CoopSyncP2Sprite
@reject:
  inc CoopTmp
  lda CoopTmp
  cmp #COOP_PLACE_COUNT
  bne @next
  ;; Nowhere free: on top of player 1.
  jsr CoopSetPAToP1
  ldx #$03
-  lda CoopPA,x
   sta P2Ground,x
   dex
  bpl -
  jmp CoopSyncP2Sprite

;;; Terrain bits at CoopPB in A (see CoopCheckTerrain), via the hero's
;;; own check.
CoopTerrainAtPB:
  ldx #$03
-  lda CoopPB,x
   sta $34,x
   dex
  bpl -
  jsr CoopCheckTerrain
  lda $20
  rts

;;; For a second after (re)spawning, check the ground under player 2 each
;;; frame and place them again if it is a wall or a pit.  Right after a
;;; map change the first placement can see the wrong terrain (the testers
;;; found player 2 inside the wall on entering some caves).
CoopSettleP2:
  lda P2PlaceTimer
  beq +
  dec P2PlaceTimer
  ldx #$03
-  lda P2Ground,x
   sta CoopPB,x
   dex
  bpl -
  jsr CoopTerrainAtPB
  and #$03              ; only walls and pits (ice floors slide)
  beq +
   jmp CoopPlaceP2
+ rts

;;; Copies player 2's ground position to their sprite slot.
CoopSyncP2Sprite:
  ldx P2Slot
  lda P2Ground
  sta $70,x
  lda P2Ground+1
  sta $90,x
  lda P2Ground+2
  sta $b0,x
  lda P2Ground+3
  sta $d0,x
  rts

;;; Sets carry if the position in CoopPB is inside the play area: 16 px
;;; inside the hero's invisible wall (X $0a..$fc, Y $18..$d0 on screen).
;;; Same screen maths as DrawAllObjectSprites (screens are 240 px tall).
CoopPBOnScreen:
  lda CoopPB         ; X lo
  sec
  sbc $02            ; ScreenXLo
  tay
  lda CoopPB+1       ; X hi
  sbc $03            ; ScreenXHi
  bne @off
  cpy #$10
  bcc @off
  cpy #$f0
  bcs @off
  lda CoopPB+2       ; Y lo
  cmp $04            ; ScreenYLo
  lda CoopPB+3       ; Y hi
  sbc $05            ; ScreenYHi
  bne @off
  lda CoopPB+2
  sec
  sbc $04
  bcs +
   sbc #$0f
+ cmp #$20
  bcc @off
  cmp #$c8
  bcs @off
  sec
  rts
@off:
  clc
  rts

;;; ----------------------------------------------------------------
;;; Player 2 fights (M3a).
;;;
;;; Findings (written up from the vanilla code):
;;;  - CheckAllObjectCollisions ($8f6e, bank $0d) runs at the end of game
;;;    mode 8, after drawing.  It walks CollisionTable ($96f1): source
;;;    slot, target range $0d..$1e, handler.  Even frames run entries 7..0
;;;    (shots 4..8, paralysis beam $0c, hero body 1, hero front 3); odd
;;;    frames run $e..8 (shots 9..$b, beam, sword 2, body, front).
;;;    CheckHitbox ($95f8) returns the first target that shares a plane
;;;    (upper nibble of $03a0) and overlaps, using the draw pass's screen
;;;    coordinates ($05c0/$05e0).  The whole vanilla pass costs ~1500
;;;    cycles in a busy room.
;;;  - Enemy hits hero (CollisionJump_01, $9357, X = 1): status into
;;;    PlayerStatus; knockback into slots 1 and 0 and $0640 = $ff; attacker
;;;    in $0541; damage into ObjectHP,x = $03c1 (PlayerHP); invincibility
;;;    $071a = $1e plus $0381:04 (ticked down in CheckPassiveEffects); then
;;;    UpdateHPDisplayInternal.  Coins (target action $7b) are picked up
;;;    here too.  Chests, triggers and NPCs are front (slot 3) collisions.
;;;  - Sword hits enemy (CollisionJump_00, $90aa, X = sword): damage from
;;;    PlayerAttack + the sword object's attack and element; kills give XP
;;;    and may level up (PlayerMaxHP/PlayerHP, HUD).
;;;  - The sword: action $01 reloads the whole sword object into slot 2 on
;;;    every frame of a swing; the object loop then runs action $10, a
;;;    generic x-indexed mover.
;;;
;;; So after the vanilla pass we run CheckHitbox ourselves with player 2's
;;; body slot and (odd frames, like vanilla) sword slot as sources.  Their
;;; planes are 0 except during these checks, so vanilla never targets
;;; them.  A sword hit calls CollisionJump_00 with X = player 2's sword
;;; slot (no swap needed).  An enemy hit swaps player 2 into slots 0/1,
;;; with $03c1 <-> P2HP, $071a <-> P2Invuln and $0710 <-> P2Status, calls
;;; CollisionJump_01 with X = 1, and swaps back; the HUD redraw is skipped
;;; (CoopHpGuard).  Coins are left for player 1.  Game over still only
;;; comes from player 1's HP.

;;; Keeps player 2's max HP in step with player 1's, and ticks their
;;; invincibility (bit $04 of their copy of $0381, as vanilla does).
CoopP2Vitals:
  ;; Poison: 4 HP every 32 frames, as _3ef55 does for player 1.  At 0 HP
  ;; player 2 goes down.
  lda P2Down
  bne @poisonDone
  lda P2Status
  and #$0f
  cmp #$03           ; STATUS_POISON
  bne @poisonDone
  lda $08            ; GlobalCounter
  and #$1f
  bne @poisonDone
  lda P2HP
  sec
  sbc #$04
  bcs +
   lda #$00
+ sta P2HP
  lda #$36           ; SFX_POISON
  jsr $c125          ; StartAudioTrack
  lda P2HP
  bne @poisonDone
  lda #$01
  sta P2Down
  lda #$00
  sta P2DownTimer
@poisonDone:
  lda $03c0          ; PlayerMaxHP
  sta P2MaxHP
  cmp P2HP
  bcs +
   sta P2HP
+ ldx P2Slot
  lda P2Invuln
  beq +
   dec P2Invuln
   lda $0380,x
   ora #$04
   sta $0380,x
   rts
+ lda $0380,x
  and #$fb
  sta $0380,x
  rts

;;; Player 2 is down: frozen where they fell, blinking, no collisions and
;;; no leash.  Player 1 standing within a tile for 60 frames revives them
;;; (or the next map: see CoopSpawnP2).
COOP_REVIVE_FRAMES = 60
CoopP2DownFrame:
  lda CoopFlags
  and #$ff-COOP_P1OLD_OK  ; restart the leash after reviving
  sta CoopFlags
  jsr CoopSetPAToP1
  jsr CoopSetPBToP2
  jsr CoopDist
  lda CoopDX+1
  ora CoopDY+1
  bne @far
  lda CoopDX
  cmp #20
  bcs @far
  lda CoopDY
  cmp #20
  bcs @far
  inc P2DownTimer
  lda P2DownTimer
  cmp #COOP_REVIVE_FRAMES
  bcc @blink
  jmp CoopReviveP2
@far:
  lda #$00
  sta P2DownTimer
@blink:
  ;; Blink: every 8 frames, move the sprite off screen.
  jsr CoopSyncP2Sprite
  lda $08
  and #$08
  beq +
   ldx P2Slot
   lda #$ff
   sta $d0,x
+ rts

;;; Back on their feet with a quarter of their max HP.
CoopReviveP2:
  lda #$00
  sta P2Down
  sta P2DownTimer
  sta P2Status       ; back on their feet without any status
  lda P2MaxHP
  lsr
  lsr
  bne +
   lda #$01
+ sta P2HP
  lda #$3c           ; a second of invincibility
  sta P2Invuln
  jmp CoopSyncP2Sprite

;;; Y <- player 2's sword slot (reusing it while it still holds their
;;; sword, else the highest free slot).  Clears carry if none is free.
CoopGetSwordSlot:
  ldy P2SwordSlot
  beq @find
  lda $04a0,y
  beq @ok
  cmp #$10
  beq @ok
@find:
  ldy #COOP_LAST_SLOT
-  cpy P2Slot
   beq +
   lda $04a0,y
   beq @found
+  dey
   cpy #COOP_FIRST_SLOT-1
  bne -
  lda #$00
  sta P2SwordSlot
  clc
  rts
@found:
  sty P2SwordSlot
@ok:
  sec
  rts

;;; Player 2's collision pass, called after the vanilla one.
.reloc
CoopP2Collisions:
  lda P2Down
  bne @exit
  lda $41            ; normal play only
  cmp #$08
  beq +
  cmp #$07
  bne @exit
+ ldx P2Slot
  lda $04a0,x
  cmp #COOP_P2_ACTION
  beq @body
@exit:
  rts
@body:
  ;; Enemies and their shots touching player 2's body, every 4th frame
  ;; (the sword below takes the odd ones), so player 2 adds at most one
  ;; CheckHitbox per frame.  Contact lasts several frames (even fast shots
  ;; overlap the hero's hitbox for 4+), so a hit lands at most 3 frames
  ;; late.  Busy-room stress test (perf.lua): body every frame 17%, even
  ;; frames 14.5%, every 4th frame 12.3% lag frames.
  lda $08
  and #$03
  bne @sword
  lda P2Invuln
  bne @sword
  lda $03a1          ; the hero's collision plane
  and #$f0
  ora $03a0,x
  sta $03a0,x
  jsr CoopSetRange
  COOP_FAR $95f8     ; CheckHitbox (X = player 2's slot)
  php
  sty CoopTarget
  ldx P2Slot
  lda $03a0,x
  and #$0f
  sta $03a0,x
  plp
  bcc @sword
  ldy CoopTarget
  lda $04a0,y
  and #$7f
  cmp #$7b           ; a coin: leave it for player 1
  beq @sword
  ;; Status projectiles ($0540 = $ff with a status in $0560) deal no
  ;; damage in vanilla, only a status.  Vanilla's handler would show the
  ;; status message (GameMode $10) and, for curse, recompute player 1's
  ;; equipment, so player 2's are handled here (M3b).
  lda $0540,y
  cmp #$ff
  bne +
  lda $0560,y
  beq +
  jsr CoopP2StatusShot
  jmp @sword
+ jsr CoopP2TakeHit
@sword:
  ;; Player 2's sword, on odd frames like vanilla's sword entry.
  lda $08
  lsr
  bcc @done
  ldx P2SwordSlot
  beq @done
  lda $04a0,x
  cmp #$10
  bne @done
  lda P2SwordPlane
  ora $03a0,x
  sta $03a0,x
  jsr CoopSetRange
  COOP_FAR $95f8     ; CheckHitbox (X = player 2's sword)
  php
  sty CoopTarget
  ldx P2SwordSlot
  lda $03a0,x
  and #$0f
  sta $03a0,x
  plp
  bcc @done
  ldy CoopTarget
  COOP_FAR $90aa     ; CollisionJump_00_SwordHitsEnemy (X = sword, Y = enemy)
@done:
  rts

;;; A status projectile (CoopTarget, status A in its $0560) hit player 2.
;;; Mirrors PlayerHit_ApplyProjectileStatus without the status message:
;;; 1 = paralysis (blocked by the Sacred or Psycho Shield; player 1's
;;; shield stands in for player 2's), 2 = stone and 3 = MP drain (not
;;; supported for player 2 yet: they pass through), anything else = curse.
CoopP2StatusShot:
  cmp #$01
  bne @notParalysis
  lda $0714          ; EquippedShield
  cmp #$06           ; SHIELD_SACRED
  beq @remove
  cmp #$08           ; SHIELD_PSYCHO
  beq @remove
  lda P2Status
  and #$f0
  ora #$01           ; STATUS_PARALYZED
  sta P2Status
  lda #$44           ; SFX_PARALYZED
  jsr $c125          ; StartAudioTrack
  jmp @remove
@notParalysis:
  cmp #$02           ; stone: changes the global palette, not supported
  beq @pass
  cmp #$03           ; MP drain web: not supported
  beq @pass
  lda #$04           ; STATUS_CURSED (vanilla stores it outright)
  sta P2Status
@remove:
  ldy CoopTarget
  lda #$00
  sta $04a0,y
@pass:
  rts

;;; Targets $0d..$1e, as in CollisionTable.
CoopSetRange:
  lda #$0c
  sta $10
  lda #$1f
  sta $11
  rts

;;; Swaps the hero's HP, invincibility timer and status with player 2's.
CoopSwapVitals:
  lda $03c1          ; PlayerHP
  ldy P2HP
  sta P2HP
  sty $03c1
  lda $071a          ; invincibility timer
  ldy P2Invuln
  sta P2Invuln
  sty $071a
  lda $0710          ; PlayerStatus
  ldy P2Status
  sta P2Status
  sty $0710
  rts

;;; Swaps in (or back) the parts of player 2 that CollisionJump_01 uses.
;;; Traced: besides HP, invincibility and status (CoopSwapVitals) it only
;;; touches slot 0's $0340/$0360 (knockback) and slot 1's $0341, $0361 and
;;; $0381 -- except for targets with action $38 or $3c, where
;;; PlayerHit_ApplyKnockback moves slot 0 with MoveObjectWithSpeedAndDirection,
;;; so those get the full CoopSwapP2.  About 100 cycles instead of 1000.
;;; CoopTmp+1 says which (set by CoopP2TakeHit before the first call, as
;;; the handler may remove the target before the swap back).
CoopSwapHit:
  lda CoopTmp+1
  bne @full
  COOP_SWAP0 $0340, 5
  COOP_SWAP0 $0360, 6
  ldx P2Slot
  COOP_SWAP1 $0340
  COOP_SWAP1 $0360
  COOP_SWAP1 $0380
  rts
@full:
  jmp CoopSwapP2

;;; Enemy CoopTarget hit player 2: run vanilla's handler as player 2.
CoopP2TakeHit:
  lda #$01
  sta CoopNoHud
  lda $0541          ; per-pass attacker latches, and slot 0's $0640
  pha
  lda $0643
  pha
  lda $0640
  pha
  ;; Contact poison (PlayerHit_ApplyStatus) lands in P2Status, swapped in
  ;; below; player 1's armor counts as player 2's for the Battle Armor
  ;; check.  It also shows the "poisoned" message by setting GameMode $10
  ;; and $06c3/$06e3, which would stop the game for both players, so
  ;; those are put back afterwards.
  lda $41            ; GameMode
  pha
  lda $06c3
  pha
  lda $06e3
  pha
  ldy CoopTarget     ; knockback-relay targets need the full swap
  lda $04a0,y
  and #$7f
  ldx #$00
  cmp #$38
  beq +
  cmp #$3c
  bne ++
+  inx
++ stx CoopTmp+1
  jsr CoopSwapHit
  jsr CoopSwapVitals
  ldx #$01
  ldy CoopTarget
  COOP_FAR $9357     ; CollisionJump_01_EnemyHitsPlayer
  jsr CoopSwapVitals
  jsr CoopSwapHit
  pla
  sta $06e3
  pla
  sta $06c3
  pla
  sta $41
  pla
  sta $0640
  pla
  sta $0643
  pla
  sta $0541
  lda #$00
  sta CoopNoHud
  ;; Knockback lives in player 2's ground copy (driven by action $03);
  ;; keep it off their sprite slot so the object loop leaves it alone.
  ldx P2Slot
  lda $0340,x
  and #$0f
  sta $0340,x
  lda P2HP
  bne +
   lda #$01
   sta P2Down
   lda #$00
   sta P2DownTimer
+ rts

;;; Midpoint camera, entered from CoopCamera (fixed bank) in place of
;;; KeepPlayerInCenterOfScreenIfPossible.  That routine reads slot 0's
;;; position ($70/$b0), slot 0's on-screen X ($05c0, used to settle the
;;; camera when no left/right is held), the knockback sign ($0340) and
;;; left/right held ($43 & 3).  We give it the midpoint and either pad's
;;; left/right, then restore.  Only in normal play on player 2's map.
.reloc
CoopCameraFar:
  lda $41           ; GameMode: 8 normal, 7 trigger tile
  cmp #$08
  beq +
  cmp #$07
  bne @plain
+ lda P2Down       ; a downed player 2 doesn't pull the camera
  bne @plain
  lda $6c
  cmp P2Loc
  bne @plain
  ldx P2Slot
  lda $04a0,x
  cmp #COOP_P2_ACTION
  beq @midpoint
@plain:
  jmp $e9ad ; KeepPlayerInCenterOfScreenIfPossible
@midpoint:
  ;; Save what we overwrite.
  lda $70
  sta CoopPA
  lda $90
  sta CoopPA+1
  lda $b0
  sta CoopPA+2
  lda $d0
  sta CoopPA+3
  lda $05c0
  sta CoopPB
  lda $43
  sta CoopPB+1
  ;; X: (x1 + x2) / 2, 17-bit sum.
  lda $70
  clc
  adc P2Ground
  sta CoopTmp
  lda $90
  adc P2Ground+1
  ror
  sta $90
  ror CoopTmp
  lda CoopTmp
  sta $70
  ;; Y on the same 240 px screen (the usual case): (y1 + y2) / 2, 9-bit.
  lda P2Ground+3
  cmp CoopPA+3
  bne @yAcross
  lda P2Ground+2
  clc
  adc CoopPA+2
  ror
  sta $b0
  jmp @onScreenX
@yAcross:
  ;; Y: y1 + (y2 - y1) / 2, in pixels across 240 px screens.
  lda P2Ground+2
  sec
  sbc CoopPA+2
  sta CoopTmp
  lda #$00
  sbc #$00
  sta CoopTmp+1
  lda P2Ground+3
  sec
  sbc CoopPA+3
  tax
  beq @half
  bmi @neg
@pos:
   lda CoopTmp
   clc
   adc #240
   sta CoopTmp
   lda CoopTmp+1
   adc #$00
   sta CoopTmp+1
   dex
  bne @pos
  beq @half
@neg:
   lda CoopTmp
   sec
   sbc #240
   sta CoopTmp
   lda CoopTmp+1
   sbc #$00
   sta CoopTmp+1
   inx
  bne @neg
@half:
  lda CoopTmp+1     ; arithmetic shift right
  cmp #$80
  ror CoopTmp+1
  ror CoopTmp
  ;; y1lo + half, then bring back into 0..239 adjusting the screen.
  lda CoopPA+2
  clc
  adc CoopTmp
  sta CoopTmp
  lda CoopTmp+1
  adc #$00
  sta CoopTmp+1
  ldx CoopPA+3
@norm:
  lda CoopTmp+1
  bmi @up
  bne @down
  lda CoopTmp
  cmp #240
  bcc @yDone
@down:
   lda CoopTmp
   sec
   sbc #240
   sta CoopTmp
   lda CoopTmp+1
   sbc #$00
   sta CoopTmp+1
   inx
  jmp @norm
@up:
   lda CoopTmp
   clc
   adc #240
   sta CoopTmp
   lda CoopTmp+1
   adc #$00
   sta CoopTmp+1
   dex
  jmp @norm
@yDone:
  lda CoopTmp
  sta $b0
  stx $d0
@onScreenX:
  ;; On-screen X of the midpoint, and either player's left/right.
  lda $70
  sec
  sbc $02
  sta $05c0
  lda P2Held
  and #$03
  ora $43
  sta $43
  jsr $e9ad ; KeepPlayerInCenterOfScreenIfPossible
  ;; Restore player 1.
  lda CoopPA
  sta $70
  lda CoopPA+1
  sta $90
  lda CoopPA+2
  sta $b0
  lda CoopPA+3
  sta $d0
  lda CoopPB
  sta $05c0
  lda CoopPB+1
  sta $43
  rts

.popseg ; "3a"

;;; ----------------------------------------------------------------
;;; RAM init.

.reloc
CoopClearRam:
  lda #$00
  ldx #CoopRamEnd-CoopRamStart-1
-  sta CoopRamStart,x
   dex
  bpl -
  rts

;;; On every reset (cold or warm).  HandleColdBoot falls through to
;;; HandleWarmBoot, whose first instruction is jsr ValidateSaveFiles at
;;; $f39f.  hud.s claims that call under _ENEMY_HP and chains here.
.reloc
CoopInitOnReset:
  jsr CoopClearRam
  jmp $f0a4 ; ValidateSaveFiles

.ifndef _ENEMY_HP
.org $f39f ; HandleWarmBoot
  jsr CoopInitOnReset
.endif

;;; On game start.  PopulateInitialObjects is called by both new game
;;; (PrepareGame, see savegame.s) and continue (MainLoopJump_08_ContinueGame),
;;; so hook its first two instructions (lda #$00 / ldx #$1f).
.org $c9ff ; PopulateInitialObjects
  jsr CoopInitOnGameStart
  nop
.assert * = $ca03

.reloc
CoopInitOnGameStart:
  jsr CoopClearRam   ; leaves A = 0
  ldx #$1f
  rts

.endif ; _COOP
