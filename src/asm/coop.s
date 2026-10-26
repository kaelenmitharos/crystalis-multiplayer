;;; smudge sha1 fd0dcde4f1708b30d5c3de1e463f1dde89c5cb64
;;; smudge off

;;; Two-player co-op (flag Cp).  Work in progress.
;;;
;;; Milestone M0: this file only reserves RAM for player 2.  It writes no
;;; code or data, so a Cp build plays exactly like a build without it.
;;; Later milestones add pad 2 input, the second hero, combat and camera.

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
;;; session.  Co-op code must initialize it on power-on and never base
;;; decisions on what was there before (the two netplay machines' save
;;; files can differ).
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
;;; $6288..$62bf spare

.endif ; _COOP
