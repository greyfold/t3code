#!/bin/bash
# Fail if the built iOS app contains any Privacy Connect / telemetry / update-feed endpoint.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Optional argument: path to a .app (defaults to the simulator build, then the device build).
app="${1:-$(find "$ROOT/ios/build/Build/Products" "$ROOT/ios/build-device/Build/Products" -maxdepth 2 -name 'PrivacyCode.app' 2>/dev/null | head -1)}"
[ -n "$app" ] || { echo "verify-ios: no built app found" >&2; exit 1; }
# Hostnames/identifiers that must not appear in the shipped bundle or binary.
bad='relay\.t3\.codes|clerk\.t3\.codes|ingest\.t3\.codes|api\.axiom\.co|u\.expo\.dev|observe\.expo|pk_live_[A-Za-z0-9]{20,}|posthog|sentry\.io|google\.com/s2/favicons|githubassets\.com/favicons'
if hits="$(grep -raEo "$bad" "$app" 2>/dev/null | sort | uniq -c)" && [ -n "$hits" ]; then
  echo "verify-ios: FAIL forbidden endpoints in $app" >&2; echo "$hits" >&2; exit 1
fi
plist="$(plutil -p "$app/Expo.plist")"
if grep -q "EXUpdatesURL" <<<"$plist" || ! grep -qE '"EXUpdatesEnabled" => (0|false)' <<<"$plist"; then
  echo "verify-ios: FAIL update feed configured or updates not disabled" >&2; exit 1
fi
if ent="$(codesign -d --entitlements - "$app" 2>/dev/null)" && grep -aq "aps-environment" <<<"$ent"; then
  echo "verify-ios: FAIL remote-push entitlement present" >&2; exit 1
fi
echo "verify-ios: OK $(basename "$app") — no Connect/relay, crash-report, trace or update-feed endpoints"
