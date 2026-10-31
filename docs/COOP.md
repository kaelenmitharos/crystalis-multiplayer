# Crystalis two-player co-op (v0.1)

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

`8f28b1c79af121134156fda36f76372cbe5b1aa2`

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

Co-op works over RetroArch netplay. The host is player 1 (controller 1)
and the friend who connects is player 2 (controller 2). Tested with
RetroArch 1.22.2 on Windows, with the Mesen core and with the FCEUmm core.

### Both players

1. Install RetroArch (<https://www.retroarch.com>, 1.22 or newer). In
   **Main Menu → Online Updater → Core Downloader**, get
   **Nintendo - NES / Famicom (Mesen)**. Both players must use the same core
   (and ideally the same RetroArch version). FCEUmm also works, but both
   must pick the same one.
2. Patch your ROM (above) and check the SHA-1. Both players need the exact
   same patched ROM: RetroArch refuses to connect if the content differs.
   Use the patched `.nes` file rather than soft-patching, so there is
   nothing to get out of step.
3. Load the patched ROM once (**Load Core**, then **Load Content**). In the
   **Quick Menu → Core Options**, set:
   - **Remove Sprite Limit** (Mesen; FCEUmm calls it "No Sprite Limit"):
     **enabled**. Two heroes plus enemies on one line flicker less. It only
     changes what is drawn, so it can't cause a desync, but both players
     should still set it the same way.
   - **Overclock**: leave it at **None** / **disabled** (the default).
     Overclocking would reduce slowdown in busy rooms, but has not been
     tested for co-op.
   Leave everything else at its default.
4. Map your controller as **Port 1** in **Settings → Input → Port 1
   Controls**. Each player plays on *their own* port 1: netplay gives the
   host's controller to the game's controller 1 and the friend's to
   controller 2.

### The host (player 1)

1. Start the game: **Load Core** (Mesen) and **Load Content** (the patched
   ROM).
2. **Main Menu → Netplay → Host → Start Netplay Host**.
3. Tell your friend your IP address and port (55435 by default). Over the
   internet the port has to be reachable: either forward TCP 55435 on your
   router (or turn on NAT traversal / UPnP in RetroArch's network
   settings, if your router allows it), or turn on **Use Relay Server** in
   RetroArch's network settings before hosting, and let your friend pick
   you from the host list instead of typing an IP.

### The friend (player 2)

1. Load the same core and the same patched ROM.
2. **Main Menu → Netplay → Connect to Netplay Host**, enter the host's
   address and port (or pick the host from **Refresh Netplay Host List**).
   RetroArch shows "You have joined as player 2".
3. Once the host is playing (out of the title screen), press **Start** on
   your controller to join. Start again leaves.

For breaks, use the game's own Start menu: RetroArch's pause is turned off
in netplay by default. Save in the game as usual; the host's save file is
the real one (the friend's copy goes to a separate `.netplay` save
folder).

### Settings checklist

| Setting | Value |
| --- | --- |
| RetroArch | 1.22.2 (same version on both sides is safest) |
| Core | Mesen (0.9.9) or FCEUmm, the same on both sides |
| ROM | the patched ROM, SHA-1 above, the same on both sides |
| Remove Sprite Limit | enabled (both) |
| Overclock | off (both) |
| Netplay port | 55435 (TCP), or the relay server |
| Netplay input latency, check frames | defaults |

### If something goes wrong

- *"Content not loaded" or the connection is refused*: the two ROMs or
  cores differ. Check the patched ROM's SHA-1 on both sides and that both
  picked the same core.
- *Player 2's controller does nothing*: the friend's controller must be
  mapped to their Port 1. Player 2 also has to press Start to join; they
  can't join on the title screen.
- *The game goes out of step (the two screens show different things)*:
  this hasn't happened in testing. RetroArch checks every 600 frames (10
  seconds) by default and repairs it by sending the host's game state
  (the "Netplay Check Frames" setting; leave it at the default). If it
  keeps happening, both should restart RetroArch and reconnect.

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

Tests for the co-op code are in `test/coop/` (Lua scripts for MesenCE and
Mesen 0.9.9; see each file's header). `test/coop/m4_determinism.lua` checks
that two runs of the same input give the same RAM, and that the co-op build
without player 2 plays exactly like the co-op-off build. The same-PC
netplay test needs RetroArch and Node.js:

```
test\coop\netplay\run.ps1 -RetroArch C:\path\to\RetroArch-Win64 -Rom release\crystalis-coop-v0.1.nes -Core mesen -Minutes 15
```
