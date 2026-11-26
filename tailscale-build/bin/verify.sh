#!/bin/bash
# Check that a built DMG really has Privacy Connect off and no update feed.
# Usage: bin/verify.sh <path/to.dmg>
set -euo pipefail

DMG="${1:?usage: verify.sh <dmg>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLE="$ROOT/src/.env.example"

mount="$(mktemp -d)"
cleanup() { hdiutil detach "$mount" -quiet -force 2>/dev/null || true; rmdir "$mount" 2>/dev/null || true; }
trap cleanup EXIT
hdiutil attach "$DMG" -nobrowse -readonly -quiet -mountpoint "$mount"

app="$(find "$mount" -maxdepth 1 -name '*.app' | head -n 1)"
[ -n "$app" ] || { echo "verify: no .app inside $DMG" >&2; exit 1; }

fail=0

# 1. No update feed: the app must not pull official builds over itself.
if [ -e "$app/Contents/Resources/app-update.yml" ]; then
  echo "verify: FAIL app-update.yml is present (auto-update feed baked in)" >&2
  fail=1
fi

# 2. None of upstream's public Connect identifiers may be baked in.
needles=()
if [ -f "$EXAMPLE" ]; then
  while IFS= read -r value; do
    [ -n "$value" ] && needles+=("$value")
  done < <(sed -n -E 's/^(T3CODE_CLERK_PUBLISHABLE_KEY|T3CODE_CLERK_CLI_OAUTH_CLIENT_ID|T3CODE_RELAY_URL)=(https:\/\/)?(.+)$/\3/p' "$EXAMPLE")
fi
[ "${#needles[@]}" -gt 0 ] || { echo "verify: no identifiers to check ($EXAMPLE missing or changed)" >&2; exit 1; }
for needle in "${needles[@]}"; do
  if grep -rqaF -- "$needle" "$app/Contents/Resources"; then
    echo "verify: FAIL found Connect identifier '$needle' in the bundle" >&2
    fail=1
  fi
done

# 3. Product usage events must default to off (see the patch in build.sh).
asar="$app/Contents/Resources/app.asar"
# Either upstream "on" form surviving in the bundle means a patch did not apply.
for on_form in 'enabledByDefault = !isCiEnvironment(' 'getOrElse(telemetryConfig.enabled'; do
  if grep -qaF -- "$on_form" "$asar"; then
    echo "verify: FAIL telemetry can still be switched on in the bundle ($on_form)" >&2
    fail=1
  fi
done

# 4. Reporting addresses removed by bin/harden.sh must not be anywhere in the bundle.
for needle in 'ingest.t3.codes' 'phc_XOWci4' 'posthog.com' 'sentry.io' 'sentry.dev'; do
  if grep -rqaF -- "$needle" "$app/Contents"; then
    echo "verify: FAIL found '$needle' in the bundle" >&2
    fail=1
  fi
done

# 5. The data folder must be ~/.safecode, not the official app's ~/.t3.
if ! grep -qaF 'homeDirectory, ".safecode")' "$asar" && ! grep -qaE 'homeDirectory, ?[`"'"'"']\.safecode' "$asar"; then
  echo "verify: FAIL data folder is not .safecode in the bundle" >&2
  fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "verify: OK $(basename "$app") — Privacy Connect config absent, no update feed, usage events removed, data folder ~/.safecode"
