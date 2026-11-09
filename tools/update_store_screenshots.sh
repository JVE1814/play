#!/bin/bash
# Copies the App Store screenshots from the latest CI results into docs/app-store/screenshots.
# CI captures them on a 6.9" simulator (1320 x 2868). Run from the repository root.
set -euo pipefail
git fetch -q origin ci-results
OUT=docs/app-store/screenshots
mkdir -p "$OUT"
copy() { git show "origin/ci-results:screenshots/$1.png" > "$OUT/$2.png"; }
rm -f "$OUT"/*.png
copy 02-game-light 1-solitaire
copy 41-bubbles-aim-light 2-bubbles
copy 52-archery-aim-light 3-archery
copy 03-hint-light 4-hint
copy 43-bubbles-cleared-light 5-bubbles-cleared
copy 54-archery-night-light 6-archery-night
copy 04-win-light 7-win
copy 50-home-three-games-light 8-home
copy 41-bubbles-aim-dark 9-dark
echo "screenshots from CI run of $(git show origin/ci-results:SHA)"
python3 -c "
import struct, sys, glob
for p in sorted(glob.glob('$OUT/*.png')):
    w, h = struct.unpack('>II', open(p, 'rb').read()[16:24])
    print(f'{p}: {w}x{h}')"
