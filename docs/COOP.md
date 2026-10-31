# Crystalis two-player co-op (v0.2)

This is a patch for the NES game Crystalis that adds a second player. Player
2 joins with controller 2 as a second hero: they walk, fight with the sword
and charge shots, take their own damage, and can be knocked down and
revived. Player 1 still drives the story (talking, items, exits), and the
camera follows the point between the two heroes.

The patch is built from this repository (the Crystalis Randomizer) with
all shuffling turned off: items, chests and mimics, monsters, maps, shops
and wild warp are where they are in the original, and the randomizer's
joke item and monster names are off. The game plays like the original
apart from the co-op changes and the randomizer's usual quality-of-life
fixes (for example, the Love Pendant under the Underground Channel is
picked up from the dolphin). The flags are `Dn Ec Et Vemsw Cp` and the
seed is 0.

The patch contains no game data. You need your own copy of the game.

## What you need

- A dump of the US Crystalis cartridge, headered (`.nes`, 393232 bytes),
  with this SHA-1:

  `fd0dcde4f1708b30d5c3de1e463f1dde89c5cb64`

- The patch: `crystalis-coop-v0.2.bps`
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

`e47c708323c36a298ba6a600629ee0aeff130a9d`

For netplay, both players need exactly this ROM. You can also check on the
title screen: it says **RANDOMIZER COOP**, and after pressing Start the
top box shows **VERSION COOP 0.2**.

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
- Player 2's HP is shown on the status bar's bottom row as `2` and a life
  bar, next to the MP. Each tile of player 2's bar is 32 HP (player 1's
  are 16), so it fits even at full health.
- At 0 HP player 2 is down: they freeze where they fell and blink. Player 1
  revives them by standing next to them for about a second, or by going to
  another map. Player 2 comes back with a quarter of their HP. The game is
  only over when player 1 runs out of HP.
- Player 2 hides while player 1 rides the dolphin, flies, or is changed
  into another form, and reappears next to player 1 afterwards.
- Player 2 uses player 1's sword, armor and level. Coins either player
  picks up go into the shared money. Player 2 can't pick up items, talk to
  people or take exits.

## Playing online (netplay)

Co-op works over RetroArch netplay: the host plays player 1 and the friend
who connects plays player 2. It has been tested with RetroArch 1.22.2 on
Windows, with the Mesen core (and FCEUmm).

### Quick start

**Before you start (both players)**

1. Install RetroArch 1.22 or newer from <https://www.retroarch.com>. In
   **Main Menu → Online Updater → Core Downloader**, get
   **Nintendo - NES / Famicom (Mesen)**.
2. Patch your own ROM (see above) and check that the patched ROM's SHA-1
   is the one above. Both of you need the exact same patched ROM.
3. Set up your controller as **Port 1** (**Settings → Input → Port 1
   Controls**; most gamepads are picked up by themselves). Each of you uses
   your own Port 1: netplay makes the friend player 2.
4. Load the game: **Main Menu → Load Core → Mesen**, then **Load Content →**
   the patched ROM. Press **F1** for RetroArch's menu, and in **Quick Menu
   → Core Options** turn **Remove Sprite Limit** on. Press F1 again to go
   back to the game.

**The host (player 1)**

5. In **Settings → Network**: turn on **Use Relay Server** and pick a
   **Relay Server Location** near you both; set a **Server Password** (the
   room is listed publicly otherwise); and note your username
   (**Settings → User → Username**). Tell your friend both.
6. With the game loaded, go to **Main Menu → Netplay → Start Netplay Host**.

**The friend (player 2)**

7. Load the same core and the same patched ROM (step 4).
8. **Main Menu → Netplay → Refresh Netplay Host List**, wait a few seconds,
   and pick the room with the host's username. Enter the password.
   RetroArch says "You have joined as player 2".
9. Once the host is playing (past the title screen), press **Start** to
   join as the second hero. If nothing happens (Start is ignored during a
   screen change), press it again. Start also leaves.

**Make sure nobody is a spectator.** If a message says you joined as a
spectator, or your controller does nothing: open RetroArch's menu (F1),
go to the **Netplay** menu, and switch from spectating to playing. To stop
it happening, make sure the "start as spectator" option in RetroArch's
network settings is off (the default).

### Settings

| Setting | Value |
| --- | --- |
| RetroArch | 1.22 or newer (the same version on both sides is safest) |
| Core | Mesen on both sides (FCEUmm also works, but both must match) |
| ROM | the patched ROM, SHA-1 above, the same on both sides |
| Remove Sprite Limit | on (both) |
| Overclock | off (the default; not tested with co-op) |
| Relay server | on, for playing over the internet |
| Everything else | defaults |

Without the relay server, the host must forward TCP port 55435 on their
router, and the friend uses **Netplay → Connect to Netplay Host** with the
host's public IP address.

### Troubleshooting

- *The friend can't see the host's room*: check the lobby filters in the
  host list (turn off "only connectable" and "only installed cores", turn
  on passworded rooms); make sure the friend has the Mesen core installed;
  check that the host turned on **Use Relay Server** before starting to
  host (stop and start hosting again after changing it).
- *"Content not loaded", or the connection is refused*: the ROMs or cores
  differ. Check the patched ROM's SHA-1 on both sides and that both use
  Mesen.
- *Joined as a spectator, or player 2's controller does nothing*: see
  "Make sure nobody is a spectator" above. Player 2 also has to press Start
  in the game to join; this doesn't work on the title screen.
- *Lag*: try a different relay server location.
- *Pausing*: RetroArch's pause is off in netplay. Use the game's Start
  menu for breaks; opening RetroArch's own menu doesn't pause the game for
  the other player.
- *Saving*: save in the game as usual; the host's save file is the one
  that counts.
- *The two screens show different things*: this hasn't happened in
  testing. RetroArch checks every 10 seconds and repairs it by sending the
  host's game state. If it keeps happening, both restart RetroArch and
  reconnect.

## Known limitations (v0.2)

- Status effects: player 2 can be poisoned, paralyzed and cursed, but not
  turned to stone or drained of MP, and there is no way to cure them
  except being knocked down and revived (or a new map after a revive).
- Enemies only chase player 1.
- Player 2 can't pick up items, talk to people or take exits; only player
  1 drives the story.
- Player 2 has no shadow and the same colours as player 1.
- Player 2's first Start press can be ignored during a screen change;
  press it again.
- Busy rooms with many enemies slow down more than in the original while
  both players move.
- Player 2's HP bar is only shown with the randomizer's updated status bar
  (the default).
- Netplay has only been tested between two PCs once, and on one PC with
  scripted input.

### Changes in v0.2

- The original game: no shuffled monsters or mimics, so every item is in
  its original chest (v0.1 had moved the Ball of Wind to Goa Fortress), and
  no joke item names.
- Player 2 no longer appears inside walls when entering some caves.
- A downed player 2 can no longer leave and rejoin to get back up.
- Player 2's HP is a life bar instead of numbers.
- Player 2 is hidden in shops and inns.
- Player 2 picks up coins into the shared money.
- A fix for a bug in the original game: if a poisonous enemy hit the hero
  while they were turned to stone, they stayed grey after they could move
  again. The grey now goes as soon as the stone does.
- A step-by-step netplay quick start.

## For developers: building the patch

See `BUILD.md` for building. With your ROM in the repo root:

```
scripts/coop-release.sh            # writes release/crystalis-coop-v0.2.{nes,bps}
```

The script checks the source SHA-1, builds twice and checks the builds are
identical, makes the patch with `scripts/bps.js`, and checks that applying it
to the source reproduces the build byte for byte. It prints the source,
output and patch SHA-1s. The `.nes` and `.bps` outputs are gitignored; the
patch is published on a release.

Tests for the co-op code are in `test/coop/` (Lua scripts for MesenCE and
Mesen 0.9.9; see each file's header). `test/coop/m4_determinism.lua` checks
that two runs of the same input give the same RAM, and that the co-op build
without player 2 plays exactly like the co-op-off build. The same-PC
netplay test needs RetroArch and Node.js:

```
test\coop\netplay\run.ps1 -RetroArch C:\path\to\RetroArch-Win64 -Rom release\crystalis-coop-v0.2.nes -Core mesen -Minutes 15
```
