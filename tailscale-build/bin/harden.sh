#!/bin/bash
# Privacy edits applied to an upstream source tree on every build (the checkout resets them).
#
# Usage: bin/harden.sh source <source-root>    before `pnpm install`
#        bin/harden.sh deps   <source-root>    after  `pnpm install`
#        bin/harden.sh stage  <staging-dir>    run by the desktop build after its own install
#
# source:
#   - product usage events: hard off (no environment variable turns them back on), and the
#     upstream endpoint (ingest.t3.codes) and its PostHog project key are removed;
#   - data folder: ~/.safecode instead of ~/.t3, so this build never shares state with an
#     official T3 Code install. T3CODE_HOME still overrides it.
# deps:
#   - the Cursor SDK ships a list of well-known connector domains; the PostHog and Sentry
#     entries are dropped from it.
#
# Every source edit must match exactly once. If upstream moves the code, the build stops
# instead of silently shipping without the edit.
set -euo pipefail

MODE="${1:?usage: harden.sh source|deps <source-root>}"
ROOT="$(cd "${2:?usage: harden.sh source|deps <source-root>}" && pwd)"
DATA_DIR=".safecode"

replace_once() { # replace_once <file> <old> <new>
  local file="$ROOT/$1" count
  [ -f "$file" ] || { echo "harden: $1 is missing (upstream changed?)" >&2; exit 1; }
  count="$(grep -cF -- "$2" "$file" || true)"
  if [ "$count" != "1" ]; then
    echo "harden: expected exactly one match in $1, found $count, for: $2" >&2
    exit 1
  fi
  OLD="$2" NEW="$3" perl -0pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/' "$file"
}

case "$MODE" in
  source)
    A="apps/server/src/telemetry/AnalyticsService.ts"
    replace_once "$A" 'Config.withDefault("phc_XOWci4oZP4VvLiEyrFqkFjP4CZn55mjYYBMREK5Wd6m")' 'Config.withDefault("")'
    replace_once "$A" 'Config.withDefault("https://ingest.t3.codes")' 'Config.withDefault("")'
    replace_once "$A" \
      'const enabledAtStartup = Option.getOrElse(telemetryConfig.enabled, () => enabledByDefault);' \
      'const enabledAtStartup = false as boolean;'

    # The desktop build installs production dependencies again in a staging folder, so the
    # dependency edits have to run there too, right after that install.
    replace_once "scripts/build-desktop-artifact.ts" \
      '  yield* stageClerkPasskeyNativeBinaries(stageAppDir, options.platform, options.arch);' \
      '  yield* runCommand(ChildProcess.make(process.env.PRIVACY_HARDEN_SCRIPT ?? "false", ["stage", stageAppDir], {}), { label: "privacy harden deps", verbose: options.verbose });
  yield* stageClerkPasskeyNativeBinaries(stageAppDir, options.platform, options.arch);'

    replace_once "apps/desktop/src/app/DesktopStatePaths.ts" \
      'input.joinPath(input.homeDirectory, ".t3")' "input.joinPath(input.homeDirectory, \"$DATA_DIR\")"
    replace_once "apps/server/src/os-jank.ts" \
      'join(yield* HostProcess.HomeDirectory, ".t3")' "join(yield* HostProcess.HomeDirectory, \"$DATA_DIR\")"
    replace_once "apps/server/src/cli/browser.ts" \
      'path.join(home, ".t3")' "path.join(home, \"$DATA_DIR\")"
    replace_once "apps/server/src/project/AgentSessionScanner.ts" \
      'normalized.includes("/.t3/worktrees/")' "normalized.includes(\"/$DATA_DIR/worktrees/\")"
    replace_once "apps/server/src/device/SshDeviceHost.ts" \
      'cd "$HOME/.t3/device/hosts/' "cd \"\$HOME/$DATA_DIR/device/hosts/"
    ;;
  deps|stage)
    patched=0
    while IFS= read -r file; do
      perl -0pi -e 's/"(?:posthog\.com|sentry\.dev|sentry\.io)",//g' "$file"
      patched=$((patched + 1))
    done < <(grep -rlE '"(posthog\.com|sentry\.dev|sentry\.io)",' "$ROOT/node_modules/.pnpm" \
               --include='*.js' --include='*.mjs' --include='*.cjs' 2>/dev/null \
             | grep '/@cursor/sdk/' || true)
    # Upstream's own patch for the Cursor SDK quotes that list as context and is packed into
    # the app. In the staging folder it has already been applied, so that copy can be edited
    # (the source tree's own copy must stay intact: the staging install applies it again).
    [ "$MODE" = "stage" ] && for file in "$ROOT"/patches/@cursor__sdk@*.patch; do
      [ -f "$file" ] && perl -0pi -e 's/"(?:posthog\.com|sentry\.dev|sentry\.io)",//g' "$file"
    done
    echo "harden: removed PostHog/Sentry domains from $patched Cursor SDK file(s)"
    ;;
  *) echo "usage: harden.sh source|deps <source-root>" >&2; exit 1 ;;
esac
