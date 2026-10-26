#!/bin/bash
# Builds target/debug/bin/cryr (the command-line randomizer) without GNU
# Make, by running the same steps as the Makefile's debug CLI recipe.
# Run it from the repo root, with your Crystalis ROM in the repo root (the
# build reads data from it; see BUILD.md).
set -e
cd "$(dirname "$0")/.."
B=target/build
D=$B/data
mkdir -p "$D" target/debug/bin
install -m 755 src/js/tools/brotli.js "$B/brotli"
npx esbuild --bundle --platform=node --log-level=warning \
  --outfile="$B/extract-refs" src/js/tools/extract-refs.ts
npx esbuild --bundle --platform=node --log-level=warning \
  --outfile="$B/extract-symbols" src/js/tools/extract-symbols.ts
ASM=$(find src/asm -type f -name '*.s' | sort)
node "$B/extract-symbols" -o "$B/symbols.json" $ASM
node "$B/extract-refs" -s "$B/symbols.json" -o "$D/refs.json" vanilla/crystalis.s
FILES=""
for f in $ASM; do
  r=${f#src/asm/}
  mkdir -p "$D/$(dirname "$r")"
  cp "$f" "$D/$r"
  FILES="$FILES $r"
done
for f in $(find src/images/spritesheets -type f -name '*.nss' | sort); do
  r=${f#src/images/spritesheets/}
  mkdir -p "$D/$(dirname "$r")"
  cp "$f" "$D/$r"
  FILES="$FILES $r"
done
FILES="$FILES refs.json"
(cd "$D"; COPYFILE_DISABLE=1 tar c $FILES) > "$B/data.tar"
node "$B/brotli" "$B/data.tar" -o "$B/data.tar.br"
sh scripts/build_info.sh > /dev/null 2>&1
npx esbuild --bundle --platform=node --sourcemap=inline --loader:.br=binary \
  --log-level=warning --outfile=target/debug/bin/cryr src/js/cli.ts
echo "built target/debug/bin/cryr"
