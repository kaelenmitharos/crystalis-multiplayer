;;; smudge sha1 fd0dcde4f1708b30d5c3de1e463f1dde89c5cb64
;;; smudge off

;;; Two-player co-op (flag Cp).  Work in progress.
;;;
;;; Milestone M0 reserved RAM for player 2.
;;; Milestone M1 reads controller 2 and lets player 2 join or leave with
;;; Start.  Player 2 has no hero on screen yet.
;;; Later milestones add the second hero, combat and camera.

.ifdef _COOP

;;; Battery RAM block reserved for co-op: $6280..$62bf (64 bytes).
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
CoopRamEnd    = $62c0

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
;;; ($62bf is the last byte of the block)

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
  beq +
   lda #COOP_BANK
   jsr BankSwitch8k_8000
   jsr CoopUpdateP2
   lda #$0d  ; leave bank $0d mapped, as the object loop does
   jsr BankSwitch16k
+ rts

;;; Called from bank $3a with player 2 swapped into slots 0 and 1.  The
;;; extra call level around each action means a "double return"
;;; (pla/pla/rts) inside it still comes back here, so the swap is undone.
.reloc
CoopRunP2Actions:
  lda #$0d
  jsr BankSwitch16k
  ldx #$00
  jsr @Action03
  lda #$0d
  jsr BankSwitch16k
  ldx #$01
  jsr @Action01
  lda #COOP_BANK
  jmp BankSwitch8k_8000 ; returns to the caller in bank $3a
@Action03:
  jsr $9d9a ; ObjectActionJump_03 (bank $0d)
  rts
@Action01:
  jsr $9b45 ; ObjectActionJump_01 (bank $0d)
  rts

;;; Terrain under the point $34..$37, for placing player 2 (M2b).  Called
;;; from bank $3a.  Runs the hero's own CheckTerrainUnderObject (bank $0d)
;;; for slot 0, forcing a lookup without touching $0380.  Result in $20:
;;; 01 pit, 02 impassable on foot, 04 impassable flying, 20 slide,
;;; 40 slow, 80 pain.
.reloc
CoopCheckTerrain:
  lda #$0d
  jsr BankSwitch16k
  ldx #$00
  lda #$80
  jsr $9a30 ; CheckTerrainUnderObject (bank $0d)
  lda #COOP_BANK
  jmp BankSwitch8k_8000

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

.pushseg "3a" ; COOP_BANK

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
  sec
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

.reloc
CoopUpdateP2:
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
  lda P2Ground+11      ; $0620 jump height
  bne @active
  lda P2Ground+5       ; $0340 knockback (upper nibble)
  and #$f0
  bne @active
  lda P2Ground+14      ; $06a0 slide counter
  bne @active
  lda CoopFlags
  and #COOP_P2_SETTLED
  bne @after
  lda CoopFlags
  ora #COOP_P2_SETTLED
  sta CoopFlags
  bne @run             ; (always) one idle frame to settle the pose
@active:
  lda CoopFlags
  and #$ff-COOP_P2_SETTLED
  sta CoopFlags
@run:
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
  and #$3f         ; no A or B yet (B would swing player 1's sword slot)
  sta $43
  and #$0f
  tay
  lda $fed0,y      ; DirectionsByDpadBits
  sta $49
  lda P2Pressed
  and #$3f
  sta $4b
  lda #$00
  sta $61fd        ; never consume player 1's trigger-skip latch
  ;; Make GlobalCounter odd while player 2 runs.  Action $03 calls
  ;; ChargeIndicatorDisplay when (GlobalCounter & 3) == 0; for player 2
  ;; that would draw their charge over player 1's meter and wait for the
  ;; nametable buffer, which cost a whole frame (measured: 32% lag frames
  ;; in a busy room).  GlobalCounter is only changed by the main loop, so
  ;; restoring it afterwards is exact.
  lda $08
  pha
  ora #$01
  sta $08
  ;; Run the hero's update as player 2 (fixed bank; maps bank $0d).
  jsr CoopRunP2Actions
  pla
  sta $08
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

;;; Places player 2 one tile beside player 1 on walkable ground: left,
;;; right, below, above, else on top of player 1.
CoopPlaceOffX:
  .byte $f0,$10,$00,$00   ; -16, +16, 0, 0
CoopPlaceOffXHi:
  .byte $ff,$00,$00,$00
CoopPlaceOffY:
  .byte $00,$00,$10,$f0   ; 0, 0, +16, -16
CoopPlaceP2:
  lda #$00
  sta CoopTmp           ; candidate index
@next:
  ldy CoopTmp
  lda $70
  clc
  adc CoopPlaceOffX,y
  sta CoopPB
  lda $90
  adc CoopPlaceOffXHi,y
  sta CoopPB+1
  lda $d0
  sta CoopPB+3
  lda CoopPlaceOffY,y
  beq @y0
  bmi @yUp
   lda $b0
   clc
   adc #$10
   cmp #240
   bcc @yStore
   sbc #240             ; carry is set here
   inc CoopPB+3
   bcs @yStore          ; (always)
@yUp:
   lda $b0
   sec
   sbc #$10
   bcs @yStore
   adc #240             ; carry is clear here
   dec CoopPB+3
   jmp @yStore
@y0:
  lda $b0
@yStore:
  sta CoopPB+2
  jsr CoopPBOnScreen
  bcc @reject
  ;; Terrain at the candidate, via the hero's own check.
  ldx #$03
-  lda CoopPB,x
   sta $34,x
   dex
  bpl -
  jsr CoopCheckTerrain
  lda $20
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
  cmp #$04
  bne @next
  ;; Nowhere free: on top of player 1.
  jsr CoopSetPAToP1
  ldx #$03
-  lda CoopPA,x
   sta P2Ground,x
   dex
  bpl -
  jmp CoopSyncP2Sprite

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
+ lda $6c
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
