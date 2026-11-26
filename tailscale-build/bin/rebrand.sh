#!/bin/bash
# Rename the app to "Privacy Code" inside an upstream T3 Code source tree: display names,
# user-facing text, the app icon and the in-app logo.
#
# Usage: bin/rebrand.sh <source-root>        e.g. bin/rebrand.sh src
#
# Run by bin/build.sh after every checkout (the checkout resets src/, so the rename is
# reapplied each time) and once on the ios/ working copy.
#
# Deliberately NOT renamed, because renaming would break pairing, builds or move user data:
#   - identifiers: npm scopes (@t3tools), env vars (T3CODE_*), bundle ids, URL schemes,
#     the data folder (t3code-v2) and the legacy profile names used to find old data;
#   - upstream URLs and domains (t3.codes, github.com/pingdotgg), and "T3 Tools" legal text;
#   - docs, evals, infra, packaging and the marketing site (not part of the app).
set -euo pipefail

ROOT="$(cd "${1:?usage: rebrand.sh <source-root>}" && pwd)"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
BRAND="$HERE/brand"
NAME="Privacy Code"

# --- Text ---------------------------------------------------------------------
# Order matters: the longer names go first.
list_files() {
  find "$ROOT/apps" "$ROOT/packages" "$ROOT/scripts" "$ROOT/native" \
    \( -name node_modules -o -name dist -o -name dist-electron -o -name .repos -o -name build \
       -o -name Pods -o -name .git -o -name marketing -o -name docs \) -prune -o \
    -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.mts' -o -name '*.cts' -o -name '*.js' \
       -o -name '*.mjs' -o -name '*.cjs' -o -name '*.json' -o -name '*.html' -o -name '*.webmanifest' \
       -o -name '*.plist' -o -name '*.swift' -o -name '*.kt' -o -name '*.xml' -o -name '*.svg' \
       -o -name '*.yml' -o -name '*.yaml' -o -name '*.strings' -o -name '*.storyboard' \) \
    ! -name 'installer.nsh' ! -name 'package-lock.json' ! -name 'pnpm-lock.yaml' -print 2>/dev/null
}

export NAME
list_files | while IFS= read -r f; do
  grep -qE 'T3( |-|\b)' "$f" 2>/dev/null || continue
  case "$f" in
    */i18n/translations/*.json) bare=all ;;
    */modules/*|*/native/*) bare=none ;;
    *) bare=phrases ;;
  esac
  BARE="$bare" perl -pi -e '
    # Legacy profile / data-folder names must keep matching existing data on disk.
    next if /\(Alpha\)|legacy:|V1_PROFILE_NAMES|Application Support/;
    s/T3 Safe Code \(Beta\)|T3 Code \(Beta\)|T3 Safe Code|T3 Code Private/$ENV{NAME}/g;
    s/T3 Code/$ENV{NAME}/g;
    s/T3 Connect/Privacy Connect/g;
    if ($ENV{BARE} eq "all") {
      s/(?<![A-Za-z0-9_\$])T3(?![A-Za-z0-9_\$])/$ENV{NAME}/g;
    } elsif ($ENV{BARE} eq "phrases") {
      s/(?<![A-Za-z0-9_\$<.])T3(?=\x27s|\x{2019}s| (?:team|home|server|Account|connection|folder)\b)/$ENV{NAME}/g;
      s/\b(Open|in|to) T3\b(?![A-Za-z0-9_])/$1 $ENV{NAME}/g;
      s/"T3"/"$ENV{NAME}"/g;
    }
  ' "$f"
done

# Release file names (T3-Code-<version>-<arch>.dmg).
perl -pi -e 's/"T3-Code(-Nightly)?-/"Privacy-Code$1-/g' "$ROOT/scripts/build-desktop-artifact.ts"

# --- In-app logo (the "T3" wordmark SVG paths) ------------------------------------
MARK_D="M17.5 37H39A20.5 20.5 0 0 1 39 78H30.5V94H17.5ZM30.5 49.5V65.5H39A8 8 0 0 0 39 49.5ZM112.15 45.35A28.5 28.5 0 1 0 112.15 85.65L102.96 76.46A15.5 15.5 0 1 1 102.96 54.54Z"
OLD_D="M33.4509 93V47.56H15.5309V37H64.3309V47.56H46.4109V93H33.4509ZM86.7253 93.96C82.832 93.96 78.9653 93.4533 75.1253 92.44C71.2853 91.3733 68.032 89.88 65.3653 87.96L70.4053 78.04C72.5386 79.5867 75.0186 80.8133 77.8453 81.72C80.672 82.6267 83.5253 83.08 86.4053 83.08C89.6586 83.08 92.2186 82.44 94.0853 81.16C95.952 79.88 96.8853 78.12 96.8853 75.88C96.8853 73.7467 96.0586 72.0667 94.4053 70.84C92.752 69.6133 90.0853 69 86.4053 69H80.4853V60.44L96.0853 42.76L97.5253 47.4H68.1653V37H107.365V45.4L91.8453 63.08L85.2853 59.32H89.0453C95.9253 59.32 101.125 60.8667 104.645 63.96C108.165 67.0533 109.925 71.0267 109.925 75.88C109.925 79.0267 109.099 81.9867 107.445 84.76C105.792 87.48 103.259 89.6933 99.8453 91.4C96.432 93.1067 92.0586 93.96 86.7253 93.96Z"
export MARK_D OLD_D
grep -rlF "$OLD_D" "$ROOT/apps" "$ROOT/assets" "$ROOT/packages" \
  --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.git --exclude-dir=Pods --exclude-dir=build 2>/dev/null |
while IFS= read -r f; do
  perl -0pi -e 's/\Q$ENV{OLD_D}\E/$ENV{MARK_D}/g; s/viewBox="15\.5309 37 94\.3941 56\.96"/viewBox="17.5 37 94.65 57"/g; s/viewBox="7 29 111 74"/viewBox="9.5 29 111 74"/g' "$f"
done

# --- Icons --------------------------------------------------------------------
copy_icon() { # copy_icon <generated name> <path relative to ROOT>
  [ -f "$ROOT/$2" ] && cp "$BRAND/out/$1" "$ROOT/$2"
  return 0
}
for dir in assets/prod; do
  copy_icon macos-1024.png        "$dir/black-macos-1024.png"
  copy_icon universal-1024.png    "$dir/black-universal-1024.png"
  copy_icon ios-1024.png          "$dir/black-ios-1024.png"
  copy_icon apple-touch-180.png   "$dir/t3-black-web-apple-touch-180.png"
  copy_icon favicon-16.png        "$dir/t3-black-web-favicon-16x16.png"
  copy_icon favicon-32.png        "$dir/t3-black-web-favicon-32x32.png"
  copy_icon icon-192.png          "$dir/t3-black-web-icon-192x192.png"
  copy_icon icon-512.png          "$dir/t3-black-web-icon-512x512.png"
  copy_icon favicon.ico           "$dir/t3-black-web-favicon.ico"
  copy_icon windows.ico           "$dir/t3-black-windows.ico"
  cp "$BRAND/logo.svg" "$ROOT/$dir/logo.svg" 2>/dev/null || true
done
for pub in apps/web/public apps/marketing/public; do
  copy_icon apple-touch-180.png "$pub/apple-touch-icon.png"
  copy_icon favicon-16.png      "$pub/favicon-16x16.png"
  copy_icon favicon-32.png      "$pub/favicon-32x32.png"
  copy_icon icon-192.png        "$pub/icon-192x192.png"
  copy_icon icon-512.png        "$pub/icon-512x512.png"
  copy_icon favicon.ico         "$pub/favicon.ico"
done
copy_icon android-foreground.png   apps/mobile/assets/android-icon-foreground.png
copy_icon android-mark.png         apps/mobile/assets/android-icon-mark.png
copy_icon android-notification.png apps/mobile/assets/android-notification-icon.png
copy_icon android-splash.png       apps/mobile/assets/android-splash-icon-prod.png

# Icon Composer projects (iOS app icon source): swap the glyph layer.
for icon in "$ROOT"/assets/*/app-icon.icon "$ROOT"/apps/mobile/ios/*/app-icon.icon; do
  [ -f "$icon/Assets/text.svg" ] && cp "$BRAND/mark.svg" "$icon/Assets/text.svg"
done

echo "rebrand: $ROOT is now $NAME"
