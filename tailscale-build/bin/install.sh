#!/bin/bash
# Install a built DMG into /Applications, replacing the existing T3 Code app.
# Refuses while the app is running. The replaced app goes to the Trash.
# Usage: bin/install.sh <path/to.dmg>
set -euo pipefail

DMG="${1:?usage: install.sh <dmg>}"

mount="$(mktemp -d)"
cleanup() { hdiutil detach "$mount" -quiet -force 2>/dev/null || true; rmdir "$mount" 2>/dev/null || true; }
trap cleanup EXIT
hdiutil attach "$DMG" -nobrowse -readonly -quiet -mountpoint "$mount"

app="$(find "$mount" -maxdepth 1 -name '*.app' | head -n 1)"
[ -n "$app" ] || { echo "install: no .app inside $DMG" >&2; exit 1; }
name="$(basename "$app")"
dest="/Applications/$name"

if pgrep -f "$dest/Contents/MacOS/" >/dev/null 2>&1; then
  echo "install: $name is running, quit it first" >&2
  exit 2
fi

staging="/Applications/.${name}.installing"
rm -rf "$staging"
ditto "$app" "$staging"
if [ -e "$dest" ]; then
  mv "$dest" "$HOME/.Trash/${name%.app} $(date +%Y%m%d-%H%M%S).app"
fi
mv "$staging" "$dest"
echo "install: $dest updated from $(basename "$DMG")"
