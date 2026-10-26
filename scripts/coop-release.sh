#!/bin/bash
# Builds the co-op release ROM from your own Crystalis ROM and makes the
# BPS patch that turns a clean ROM into it.  Nothing here contains ROM
# data except the outputs, which are gitignored (release/, *.nes, *.bps).
#
# Usage: scripts/coop-release.sh [source.nes] [out-dir]
#   source.nes  your US Crystalis ROM (default: Crystalis.nes in the repo)
#   out-dir     where to write the ROM and patch (default: release/)
#
# Checks: the source SHA-1, that two builds are byte-identical, and that
# applying the patch to the source reproduces the build byte for byte.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

SRC=${1:-Crystalis.nes}
OUT=${2:-release}
EXPECTED_SRC_SHA1=fd0dcde4f1708b30d5c3de1e463f1dde89c5cb64
FLAGS="Dn Vmsw Cp"   # co-op on; items, maps, shops and wild warp unshuffled
SEED=0
VERSION=$(sed -n "s/^export const COOP_VERSION = '\(.*\)';/\1/p" src/js/patch.ts)
NAME="crystalis-coop-v$VERSION"

sha1() { sha1sum "$1" | cut -c1-40; }

[ -f "$SRC" ] || { echo "source ROM not found: $SRC" >&2; exit 1; }
SRC_SHA1=$(sha1 "$SRC")
if [ "$SRC_SHA1" != "$EXPECTED_SRC_SHA1" ]; then
  echo "source ROM SHA-1 is $SRC_SHA1, expected $EXPECTED_SRC_SHA1" >&2
  echo "(this needs the US release of Crystalis, headered, 393232 bytes)" >&2
  exit 1
fi

# The build reads data from the ROM, looking for it in the repo root.
found=
for f in *.nes; do
  [ -f "$f" ] && [ "$(sha1 "$f")" = "$EXPECTED_SRC_SHA1" ] && found=1 && break
done
if [ -z "$found" ]; then
  cp "$SRC" crystalis-source.nes   # gitignored (*.nes)
fi

if command -v make > /dev/null; then
  make debug > /dev/null
else
  scripts/build-cli.sh > /dev/null
fi

mkdir -p "$OUT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for run in 1 2; do
  node target/debug/bin/cryr --flags="$FLAGS" --seed=$SEED \
    --output="$TMP/run$run" "$SRC" > "$TMP/run$run.log" 2>&1
done
if ! cmp -s "$TMP/run1.nes" "$TMP/run2.nes"; then
  echo "two builds differ: the build is not reproducible" >&2
  exit 1
fi
cp "$TMP/run1.nes" "$OUT/$NAME.nes"
node scripts/bps.js create "$SRC" "$OUT/$NAME.nes" "$OUT/$NAME.bps"
node scripts/bps.js apply "$SRC" "$OUT/$NAME.bps" "$TMP/applied.nes"
if ! cmp -s "$TMP/applied.nes" "$OUT/$NAME.nes"; then
  echo "applying the patch does not reproduce the build" >&2
  exit 1
fi

echo "co-op $VERSION, flags \"$FLAGS\", seed $SEED"
echo "source ROM SHA-1: $SRC_SHA1"
echo "output ROM SHA-1: $(sha1 "$OUT/$NAME.nes")  $OUT/$NAME.nes"
echo "patch SHA-1:      $(sha1 "$OUT/$NAME.bps")  $OUT/$NAME.bps ($(wc -c < "$OUT/$NAME.bps") bytes)"
echo "checks: two builds identical; patch applied to the source reproduces the output"
