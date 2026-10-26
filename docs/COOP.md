# Crystalis two-player co-op (v0.1)

This is a patch for the NES game Crystalis that adds a second player. Player
2 joins with controller 2 as a second hero: they walk, fight with the sword
and charge shots, take their own damage, and can be knocked down and
revived. Player 1 still drives the story (talking, items, exits), and the
camera follows the point between the two heroes.

The patch is built from this repository (the Crystalis Randomizer) with
item, map, shop and wild-warp shuffling turned off, so the game plays like
the original apart from the co-op changes and the randomizer's usual
quality-of-life fixes. The flags are `Dn Vmsw Cp` and the seed is 0.

The patch contains no game data. You need your own copy of the game.

## What you need

- A dump of the US Crystalis cartridge, headered (`.nes`, 393232 bytes),
  with this SHA-1:

  `fd0dcde4f1708b30d5c3de1e463f1dde89c5cb64`

- The patch: `crystalis-coop-v0.1.bps`
- A patcher, or RetroArch's soft-patching (below).

## Check your ROM

The patch only works on the exact ROM above. Check its SHA-1 first:

- Windows (PowerShell): `Get-FileHash -Algorithm SHA1 Crystalis.nes`
- macOS / Linux: `shasum -a 1 Crystalis.nes` or `sha1sum Crystalis.nes`
- In a browser: Rom Patcher JS (below) shows the SHA-1 of the ROM you load.

If the SHA-1 is different, the patch is refused (it carries a checksum of the
source ROM). A different SHA-1 usually means a different region, a hack, or
a ROM without its 16-byte header.

## Apply the patch

Any BPS patcher works:

- **Flips** (Windows, macOS, Linux): Apply Patch, pick the `.bps`, pick
  your ROM, save the result.
- **Rom Patcher JS** (any browser): <https://www.marcrobledo.com/RomPatcher.js/>
  — load your ROM and the patch, click Apply.
- **RetroArch soft-patching**: put the patch next to the ROM with the same
  name, e.g. `Crystalis.nes` and `Crystalis.bps`. RetroArch applies it
  whenever it loads the ROM, leaving the ROM file unchanged. Both netplay
  players must do the same.

The patched ROM must have this SHA-1:

`006705575d3e417de1c788590a393f0db5e13755`

For netplay, both players need exactly this ROM. You can also check on the
title screen: it says **RANDOMIZER COOP**, and after pressing Start the
top box shows **VERSION COOP 0.1**.

## Controls

Player 1 plays as in the original. Player 2, on controller 2:

| Button | Action |
| --- | --- |
| Start | Join, or leave (in normal play) |
| D-pad | Walk |
| B | Swing the sword; hold to charge, release to fire a charge shot |
| Select | Teleport next to player 1 |
| A | Nothing yet |

- The two heroes can't get further apart than about two thirds of the
  screen: the camera keeps both in view.
- Player 2's HP is shown on the status bar's bottom row as `2 HHH/MMM`,
  next to the MP.
- At 0 HP player 2 is down: they freeze where they fell and blink. Player 1
  revives them by standing next to them for about a second, or by going to
  another map. Player 2 comes back with a quarter of their HP. The game is
  only over when player 1 runs out of HP.
- Player 2 hides while player 1 rides the dolphin, flies, or is changed
  into another form, and reappears next to player 1 afterwards.
- Player 2 uses player 1's sword, armor and level. They can't pick up items
  or coins, talk to people or take exits.

## Playing online (netplay)

<!-- Filled in from the M4 RetroArch tests. -->
See the RetroArch section below.

## Known limitations (v0.1)

- Status effects: player 2 can be poisoned, paralyzed and cursed, but not
  turned to stone or drained of MP, and there is no way to cure them
  except being knocked down and revived (or a new map after a revive).
- Enemies only chase player 1.
- Busy rooms with many enemies slow down more than in the original while
  both players move.
- Player 2's HP is only shown with the randomizer's updated status bar
  (the default).

## For developers: building the patch

See `BUILD.md` for building. With your ROM in the repo root:

```
scripts/coop-release.sh            # writes release/crystalis-coop-v0.1.{nes,bps}
```

The script checks the source SHA-1, builds twice and checks the builds are
identical, makes the patch with `scripts/bps.js`, and checks that applying it
to the source reproduces the build byte for byte. It prints the source,
output and patch SHA-1s. The `.nes` and `.bps` outputs are gitignored; the
patch is published on a release.
