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
;;; $628a..$62bf spare

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
++  lda #COOP_SFX_LEAVE
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
