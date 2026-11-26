#!/bin/bash
# Regenerate brand/out/* (all raster icons) from brand/mark.svg. Needs ImageMagick.
# Run after editing mark.svg; bin/rebrand.sh copies the results into a source tree.
set -euo pipefail
cd "$(dirname "$0")"
OUT=out; rm -rf "$OUT"; mkdir -p "$OUT"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

glyph() { # glyph <box px> <out>  — white mark on transparent, mark.svg's 128 box scaled to <box>
  magick -background none -density "$(awk "BEGIN{print 72*$1/128}")" mark.svg -resize "$1x$1" "$2"
}
rounded() { # rounded <size> <radius> <out> — opaque black rounded square on transparent
  magick -size "$1x$1" xc:none -fill black -draw "roundrectangle 0,0 $(($1-1)),$(($1-1)) $2,$2" "$3"
}
compose_icon() { # compose_icon <size> <radius> <glyph-box> <out>
  rounded "$1" "$2" "$TMP/bg.png"; glyph "$3" "$TMP/g.png"
  magick "$TMP/bg.png" "$TMP/g.png" -gravity center -composite "$4"
}

# macOS: classic 824px body inset 100px, soft shadow in the transparent margin.
rounded 824 185 "$TMP/body.png"; glyph 824 "$TMP/g.png"
magick "$TMP/body.png" "$TMP/g.png" -gravity center -composite "$TMP/macbody.png"
magick -size 1024x1024 xc:none \
  \( "$TMP/macbody.png" -background black -shadow 40x14+0+10 \) -gravity center -composite \
  "$TMP/macbody.png" -gravity center -composite "$OUT/macos-1024.png"

compose_icon 1024 230 1024 "$OUT/universal-1024.png"
# iOS applies its own mask and rejects transparency: opaque full-bleed square.
glyph 1024 "$TMP/g.png"
magick -size 1024x1024 xc:black "$TMP/g.png" -gravity center -composite -alpha off "$OUT/ios-1024.png"
glyph 180 "$TMP/g.png"
magick -size 180x180 xc:black "$TMP/g.png" -gravity center -composite -alpha off "$OUT/apple-touch-180.png"
for s in 16 32 192 512; do
  name=icon-$s; [ "$s" -le 32 ] && name=favicon-$s
  compose_icon "$s" "$((s/5))" "$s" "$OUT/$name.png"
done
for s in 16 32 48 64 128 256; do compose_icon "$s" "$((s/5))" "$s" "$TMP/ico-$s.png"; done
magick "$TMP/ico-16.png" "$TMP/ico-32.png" "$TMP/ico-48.png" "$OUT/favicon.ico"
magick "$TMP/ico-16.png" "$TMP/ico-32.png" "$TMP/ico-48.png" "$TMP/ico-64.png" "$TMP/ico-128.png" "$TMP/ico-256.png" "$OUT/windows.ico"

# Android: adaptive foreground must stay inside the central 288px of the 432px canvas.
glyph 340 "$TMP/g.png"
magick -size 432x432 xc:none "$TMP/g.png" -gravity center -composite "$OUT/android-foreground.png"
cp "$OUT/android-foreground.png" "$OUT/android-mark.png"
glyph 100 "$TMP/g.png"
magick -size 96x96 xc:none "$TMP/g.png" -gravity center -composite "$OUT/android-notification.png"
glyph 540 "$TMP/g.png"
magick -size 1152x1152 xc:black "$TMP/g.png" -gravity center -composite "$OUT/android-splash.png"
ls "$OUT"
