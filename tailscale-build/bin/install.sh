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

# Fixed-string match on a captured list: the app name contains parentheses (a regex
# group for pgrep), and piping ps into `grep -q` fails under pipefail when grep exits early.
processes="$(ps -axo comm)"
if grep -qF "$dest/Contents/MacOS/" <<<"$processes"; then
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
