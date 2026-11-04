#!/bin/bash
# Copies the App Store screenshots from the latest CI results into docs/app-store/screenshots.
# CI captures them on a 6.9" simulator (1320 x 2868). Run from the repository root.
set -euo pipefail
git fetch -q origin ci-results
OUT=docs/app-store/screenshots
mkdir -p "$OUT"
copy() { git show "origin/ci-results:screenshots/$1.png" > "$OUT/$2.png"; }
copy 02-game-light 1-game
copy 03-hint-light 2-hint
copy 04-win-light 3-win
copy 01-home-light 4-home
copy 02-game-dark 5-dark
echo "screenshots from CI run of $(git show origin/ci-results:SHA)"
python3 -c "
import struct, sys, glob
for p in sorted(glob.glob('$OUT/*.png')):
    w, h = struct.unpack('>II', open(p, 'rb').read()[16:24])
    print(f'{p}: {w}x{h}')"
