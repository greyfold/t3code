#!/bin/bash
# Build T3 Code desktop (macOS) from a release tag, with T3 Connect disabled.
#
# Usage: bin/build.sh <tag>        e.g. bin/build.sh v0.1.11
#
# T3 Connect is switched off the way upstream documents it for source builds
# (docs/operations/connect-setup.md): no Clerk / relay public config at build
# time. Tailscale, SSH and local-network access do not depend on it.
# No update feed is baked in either, so the app never replaces itself with an
# official (T3 Connect enabled) release.
set -euo pipefail

# The braces make bash read the whole script before running it, so an edit to this
# file during a multi-minute build cannot corrupt the run in progress.
{
TAG="${1:?usage: build.sh <tag>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src"
TOOLCHAIN="$ROOT/toolchain"
OUT="$ROOT/release/$TAG"
REPO_URL="https://github.com/pingdotgg/t3code.git"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

case "$(uname -m)" in
  arm64) ARCH=arm64 ;;
  x86_64) ARCH=x64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# --- Source -----------------------------------------------------------------
if [ ! -d "$SRC/.git" ]; then
  log "Cloning $REPO_URL"
  git clone --quiet "$REPO_URL" "$SRC"
fi
cd "$SRC"
log "Checking out $TAG"
git fetch --quiet --tags --force origin
git checkout --quiet --force --detach "refs/tags/$TAG"
git reset --quiet --hard "refs/tags/$TAG"
# A repo-root .env is what turns T3 Connect on. Never let one survive.
rm -f .env .env.local

# Product usage events (ingest.t3.codes) are on by default upstream. Flip the default
# to off; T3CODE_TELEMETRY_ENABLED=true in the environment still turns them back on.
# The checkout above resets this patch, so it is reapplied on every build.
TELEMETRY_SRC="apps/server/src/telemetry/AnalyticsService.ts"
# One known form per upstream layout: "<on>|<off>". Exactly one must match.
TELEMETRY_FORMS=(
  'const enabledByDefault = !isCiEnvironment(hostEnvironment);|const enabledByDefault = false;'
  'enabled: Config.Boolean("T3CODE_TELEMETRY_ENABLED").pipe(Config.withDefault(true)),|enabled: Config.Boolean("T3CODE_TELEMETRY_ENABLED").pipe(Config.withDefault(false)),'
)
telemetry_patched=0
for form in "${TELEMETRY_FORMS[@]}"; do
  on="${form%%|*}"; off="${form#*|}"
  if [ "$(grep -cF "$on" "$TELEMETRY_SRC")" = "1" ]; then
    ON="$on" OFF="$off" perl -0pi -e 's/\Q$ENV{ON}\E/$ENV{OFF}/' "$TELEMETRY_SRC"
    grep -qF "$off" "$TELEMETRY_SRC" && telemetry_patched=1
    break
  fi
done
if [ "$telemetry_patched" != "1" ]; then
  echo "build: telemetry default not found in $TELEMETRY_SRC (upstream changed?). Refusing to build with telemetry on." >&2
  exit 1
fi
log "Telemetry default patched to off"

# Usage events hard off with the upstream endpoint and key removed, and ~/.safecode as the
# data folder. See bin/harden.sh.
"$ROOT/bin/harden.sh" source "$SRC"
log "Usage-events endpoint removed, data folder set to ~/.safecode"

# Optional display name (PRODUCT_NAME in config.env). productName drives the .app name,
# menu bar and Dock label. The bundle id does not change. Empty = keep upstream's name.
PRODUCT_NAME="$( [ -f "$ROOT/config.env" ] && . "$ROOT/config.env"; printf '%s' "${PRODUCT_NAME:-}")"
if [ -n "$PRODUCT_NAME" ]; then
  PRODUCT_JSON="apps/desktop/package.json"
  if [ "$(grep -cE '^ *"productName": "[^"]*",?$' "$PRODUCT_JSON")" != "1" ]; then
    echo "build: productName not found in $PRODUCT_JSON (upstream changed?)" >&2
    exit 1
  fi
  NAME="$PRODUCT_NAME" perl -pi -e 's/^( *)"productName": "[^"]*"(,?)$/$1"productName": "$ENV{NAME}"$2/' "$PRODUCT_JSON"
  grep -qF "\"productName\": \"$PRODUCT_NAME\"" "$PRODUCT_JSON" || { echo "build: rename patch did not apply" >&2; exit 1; }
  log "Product name set to $PRODUCT_NAME"
fi

# --- Toolchain (versions pinned by the checked-out release) -----------------
json_field() { # json_field <file> <dotted.path>
  /usr/bin/python3 -I - "$1" "$2" <<'PY'
import json, sys
value = json.load(open(sys.argv[1]))
for key in sys.argv[2].split("."):
    value = value[key]
print(value)
PY
}
NODE_VERSION="$(json_field package.json engines.node)"
PNPM_VERSION="$(json_field package.json packageManager | sed -E 's/^pnpm@([^+]+).*/\1/')"
NODE_HOME="$TOOLCHAIN/node-v$NODE_VERSION-darwin-$ARCH"

if [ ! -x "$NODE_HOME/bin/node" ]; then
  log "Installing Node $NODE_VERSION"
  mkdir -p "$TOOLCHAIN"
  tmp="$(mktemp -d)"
  tarball="node-v$NODE_VERSION-darwin-$ARCH.tar.xz"
  curl -fsSL --retry 3 -o "$tmp/$tarball" "https://nodejs.org/dist/v$NODE_VERSION/$tarball"
  curl -fsSL --retry 3 -o "$tmp/SHASUMS256.txt" "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt"
  (cd "$tmp" && grep " $tarball\$" SHASUMS256.txt | shasum -a 256 -c - >/dev/null)
  tar -xJf "$tmp/$tarball" -C "$TOOLCHAIN"
  rm -rf "$tmp"
fi

# node_modules/.bin provides `vp` (vite-plus), which the build script spawns by name.
export PATH="$SRC/node_modules/.bin:$NODE_HOME/bin:$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

if [ "$(pnpm --version 2>/dev/null || true)" != "$PNPM_VERSION" ]; then
  log "Installing pnpm $PNPM_VERSION"
  npm install --global --silent "pnpm@$PNPM_VERSION"
fi

# Signing settings are read before the environment is scrubbed below.
[ -f "$ROOT/config.env" ] && . "$ROOT/config.env"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# --- Environment: T3 Connect off, no update feed, unsigned ------------------
while IFS='=' read -r name _; do
  case "$name" in
    T3CODE_*|VITE_*|EXPO_PUBLIC_*|CLERK_*|CSC_*|APPLE_API_*|GITHUB_REPOSITORY) unset "$name" ;;
  esac
done < <(env)
export CI=1
export PRIVACY_HARDEN_SCRIPT="$ROOT/bin/harden.sh"

# --- Build ------------------------------------------------------------------
log "Installing dependencies (node $(node --version), pnpm $(pnpm --version))"
pnpm install --frozen-lockfile
"$ROOT/bin/harden.sh" deps "$SRC"

log "Building desktop artifact $TAG ($ARCH)"
rm -rf "$OUT"
mkdir -p "$OUT"
node scripts/build-desktop-artifact.ts \
  --platform mac --target dmg --arch "$ARCH" \
  --build-version "${TAG#v}" \
  --output-dir "$OUT"

DMG="$(find "$OUT" -maxdepth 1 -name '*.dmg' | head -n 1)"
[ -n "$DMG" ] || { echo "build finished without producing a DMG in $OUT" >&2; exit 1; }

# --- Sign (optional, see config.env) ----------------------------------------
if [ -n "$SIGN_IDENTITY" ]; then
  "$ROOT/bin/sign.sh" "$OUT" "$SIGN_IDENTITY" "$NOTARY_PROFILE"
else
  log "SIGN_IDENTITY not set: leaving the build unsigned."
fi

"$ROOT/bin/verify.sh" "$DMG"
log "Done: $DMG"
exit 0
}
