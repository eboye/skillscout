#!/usr/bin/env bash
# Renders the Linux app icon from the Icon Composer layers in Skillscout/AppIcon.icon, following
# its icon.json: the gradient fill, then the Cards group (Codex, Claude, Cursor, Lines at 80%), then
# the Lens group (Lens, Sparkle), each group with a soft shadow. Needs ImageMagick 7.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
assets="$root/Skillscout/AppIcon.icon/Assets"
out="$root/Linux/icons"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

size=1024
inset=88
tile=$((size - 2 * inset))
radius=$((tile * 22 / 100))

magick -size "${tile}x${tile}" gradient:'#191c33-#30356b' \
  \( -size "${tile}x${tile}" xc:none -fill white -draw "roundrectangle 0,0 $((tile - 1)),$((tile - 1)) $radius,$radius" \) \
  -alpha off -compose copy_opacity -composite "$work/tile.png"

magick "$assets/codex.png" "$assets/claude.png" -composite "$assets/cursor.png" -composite \
  \( "$assets/lines.png" -channel A -evaluate multiply 0.8 +channel \) -composite "$work/cards.png"
magick "$assets/lens.png" "$assets/sparkle.png" -composite "$work/lens.png"

shadowed() {
  magick "$1" \( +clone -background black -shadow 50x14+0+10 \) +swap -background none -layers merge +repage \
    -gravity center -extent "${size}x${size}" "$2"
}
shadowed "$work/cards.png" "$work/cards-shadow.png"
shadowed "$work/lens.png" "$work/lens-shadow.png"

magick -size "${size}x${size}" xc:none "$work/tile.png" -gravity center -composite \
  \( "$work/cards-shadow.png" -resize "${tile}x${tile}" \) -gravity center -composite \
  \( "$work/lens-shadow.png" -resize "${tile}x${tile}" \) -gravity center -composite \
  "$work/icon.png"

mkdir -p "$out"
for px in 512 256 128 64 48 32 16; do
  mkdir -p "$out/${px}x${px}"
  magick "$work/icon.png" -resize "${px}x${px}" "$out/${px}x${px}/com.flaviocopes.skillscout.png"
done
echo "$out"
