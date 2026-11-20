#!/bin/bash
# Sign the built app with a Developer ID identity and rebuild the DMG from it.
# Optionally notarize when NOTARY_PROFILE names a notarytool keychain profile.
#
# Usage: bin/sign.sh <release-dir> <identity> [notary-profile]
# Expects node on PATH (build.sh sets it).
set -euo pipefail

OUT="${1:?usage: sign.sh <release-dir> <identity> [notary-profile]}"
IDENTITY="${2:?missing signing identity}"
NOTARY_PROFILE="${3:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$ROOT/bin/entitlements.mac.plist"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
# codesign can block forever on a keychain permission dialog; cap every step.
limit() { /usr/bin/perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$@"; }

zip="$(find "$OUT" -maxdepth 1 -name '*.zip' | head -n 1)"
dmg="$(find "$OUT" -maxdepth 1 -name '*.dmg' | head -n 1)"
[ -n "$zip" ] && [ -n "$dmg" ] || { echo "sign: no zip/dmg in $OUT" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/stage"
ditto -x -k "$zip" "$work/stage"
app="$(find "$work/stage" -maxdepth 1 -name '*.app' | head -n 1)"
[ -n "$app" ] || { echo "sign: no .app inside $zip" >&2; exit 1; }

log "Signing $(basename "$app") as $IDENTITY"
limit 900 node "$ROOT/bin/sign-app.mjs" "$ROOT/src" "$app" "$IDENTITY" "$ENTITLEMENTS"
codesign --verify --deep --strict "$app"

if [ -n "$NOTARY_PROFILE" ]; then
  log "Notarizing (keychain profile: $NOTARY_PROFILE)"
  ditto -c -k --keepParent "$app" "$work/notarize.zip"
  xcrun notarytool submit "$work/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
fi

log "Rebuilding DMG"
ln -s /Applications "$work/stage/Applications"
volname="$(basename "$app" .app)"
rm -f "$dmg"
hdiutil create -quiet -volname "$volname" -srcfolder "$work/stage" -ov -format UDZO "$dmg"
limit 300 codesign --force --sign "$IDENTITY" --timestamp "$dmg"

# The zip and blockmaps only serve electron-updater, which this build does not use.
rm -f "$zip" "$OUT"/*.blockmap
log "Signed: $dmg"
