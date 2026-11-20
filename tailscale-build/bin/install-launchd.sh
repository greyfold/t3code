#!/bin/bash
# Install (or refresh) the launchd agent that runs bin/nightly.sh at night.
# Usage: bin/install-launchd.sh            install
#        bin/install-launchd.sh --remove   uninstall
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="local.t3code.nightly-build"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
if [ "${1:-}" = "--remove" ]; then
  rm -f "$PLIST"
  echo "Removed $LABEL"
  exit 0
fi

mkdir -p "$ROOT/logs" "$HOME/Library/LaunchAgents"
# Several slots through the night: a slot missed while the Mac sleeps is replayed
# on wake, and nightly.sh ignores anything outside 22:00-06:00.
cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$ROOT/bin/nightly.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <array>
    <dict><key>Hour</key><integer>22</integer><key>Minute</key><integer>30</integer></dict>
    <dict><key>Hour</key><integer>0</integer><key>Minute</key><integer>30</integer></dict>
    <dict><key>Hour</key><integer>2</integer><key>Minute</key><integer>30</integer></dict>
    <dict><key>Hour</key><integer>4</integer><key>Minute</key><integer>30</integer></dict>
  </array>
  <key>StandardOutPath</key>
  <string>$ROOT/logs/nightly.log</string>
  <key>StandardErrorPath</key>
  <string>$ROOT/logs/nightly.log</string>
  <key>ProcessType</key>
  <string>Background</string>
  <key>LowPriorityIO</key>
  <true/>
</dict>
</plist>
PLIST
plutil -lint "$PLIST" >/dev/null
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Installed $LABEL -> $ROOT/bin/nightly.sh (22:30, 00:30, 02:30, 04:30)"
