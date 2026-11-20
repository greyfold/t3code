#!/bin/bash
# Nightly check: build the latest *stable* T3 Code release if it has not been
# built yet. Run by launchd (local.t3code.nightly-build); safe to run by hand.
#
#   bin/nightly.sh           only acts between 22:00 and 06:00
#   FORCE=1 bin/nightly.sh   act now, whatever the time
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$ROOT/state"
LOGS="$ROOT/logs"
LOCK="$STATE/nightly.lock"
REPO="pingdotgg/t3code"
KEEP_RELEASES=2

mkdir -p "$STATE" "$LOGS"
[ -f "$ROOT/config.env" ] && . "$ROOT/config.env"
AUTO_INSTALL="${AUTO_INSTALL:-0}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
notify() { # notify <title> <message>
  /usr/bin/osascript - "$1" "$2" >/dev/null 2>&1 <<'OSA' || true
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
OSA
}

# launchd replays a missed run when the Mac wakes up; keep it to the night.
hour=$((10#$(date +%H)))
if [ "${FORCE:-0}" != "1" ] && [ "$hour" -lt 22 ] && [ "$hour" -ge 6 ]; then
  log "Outside the 22:00-06:00 window, nothing to do."
  exit 0
fi

if ! mkdir "$LOCK" 2>/dev/null; then
  # Drop a lock left behind by a crash or reboot (older than 6 hours).
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +360 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null; mkdir "$LOCK" || exit 0
  else
    log "Another run is in progress."
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# releases/latest is GitHub's newest non-draft, non-prerelease release: nightlies are excluded.
latest="$(curl -fsSL --retry 3 --max-time 30 -H 'Accept: application/vnd.github+json' \
  "https://api.github.com/repos/$REPO/releases/latest" \
  | /usr/bin/python3 -I -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])' 2>/dev/null)"
if ! [[ "$latest" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  log "Could not read the latest stable release (got: '${latest:-nothing}')."
  exit 1
fi

built="$(cat "$STATE/built-version" 2>/dev/null || true)"

if [ "$latest" != "$built" ]; then
  # Do not hammer a release that keeps failing: one attempt per night.
  today="$(date +%Y-%m-%d)"
  if [ "${FORCE:-0}" != "1" ] && [ "$(cat "$STATE/last-failure" 2>/dev/null)" = "$latest $today" ]; then
    log "$latest already failed today, will retry tomorrow."
    exit 1
  fi
  buildlog="$LOGS/build-$latest.log"
  log "New stable release $latest (built: ${built:-none}). Building, log: $buildlog"
  if /usr/bin/caffeinate -i "$ROOT/bin/build.sh" "$latest" >"$buildlog" 2>&1; then
    echo "$latest" >"$STATE/built-version"
    echo "$latest" >"$STATE/pending-install"
    rm -f "$STATE/last-failure"
    log "Build of $latest succeeded."
    # Keep only the most recent builds.
    ls -1dt "$ROOT"/release/v* 2>/dev/null | tail -n +$((KEEP_RELEASES + 1)) | while IFS= read -r old; do
      rm -rf "$old"
    done
  else
    echo "$latest $today" >"$STATE/last-failure"
    log "Build of $latest FAILED. See $buildlog"
    notify "T3 Code: build failed" "Building $latest failed. Log: $buildlog"
    exit 1
  fi
else
  log "Latest stable release $latest is already built."
fi

pending="$(cat "$STATE/pending-install" 2>/dev/null || true)"
[ -n "$pending" ] || exit 0
dmg="$(find "$ROOT/release/$pending" -maxdepth 1 -name '*.dmg' 2>/dev/null | head -n 1)"
[ -n "$dmg" ] || { rm -f "$STATE/pending-install"; exit 0; }

if [ "$AUTO_INSTALL" = "1" ]; then
  if "$ROOT/bin/install.sh" "$dmg"; then
    rm -f "$STATE/pending-install"
    log "Installed $pending into /Applications."
    notify "T3 Code $pending installed" "Build without T3 Connect installed into /Applications."
  else
    log "Install of $pending postponed (app running?). Will retry on the next run."
    [ -f "$STATE/notified-$pending" ] || notify "T3 Code $pending ready" "Quit T3 Code: it will be installed on the next run."
    touch "$STATE/notified-$pending"
  fi
elif [ ! -f "$STATE/notified-$pending" ]; then
  notify "T3 Code $pending ready" "Build without T3 Connect: $dmg"
  touch "$STATE/notified-$pending"
fi
