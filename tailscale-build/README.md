# Privacy Code build scripts (unofficial, macOS)

An unofficial fork based on the T3 Code source code. These scripts build the
desktop app from upstream's **stable** release tags with T3 Connect switched off
and product usage events removed, for people who reach their machines
over Tailscale (or SSH / the local network) and do not want the cloud relay.

**This project is unofficial.** It is not affiliated with, endorsed by, or
maintained by T3 Tools, Inc. "T3 Code", "T3 Connect" and the T3 logos are their
trademarks; upstream's `TRADEMARK.md` explains what forks may and may not do with
them. Nothing is distributed from this repository except the build scripts: you
build the app yourself, from upstream's source, on your own Mac. If you pass a
build on to anyone else, give it your own name (`PRODUCT_NAME` below) and replace
the icons first, as that policy asks.

## What differs from the official app

Every difference is listed here. Each one is applied by `bin/build.sh` (which calls
`bin/harden.sh` for the source and dependency edits) at build
time and checked on the finished DMG by `bin/verify.sh`, which fails the build if
a check does not hold.

| Change | How it is done | What `verify.sh` checks |
| --- | --- | --- |
| **T3 Connect is off** (cloud sign-in, relay, managed tunnel) | No source change. Upstream disables it in any build made without the Clerk and relay identifiers ([`docs/operations/connect-setup.md`](../docs/operations/connect-setup.md)). The script deletes any repo-root `.env` and clears `T3CODE_*`, `VITE_*`, `EXPO_PUBLIC_*` and `CLERK_*` from the environment before building. | Upstream's Clerk publishable key, OAuth client id and relay host are absent from the bundle. |
| **No self-update** | No source change. No update repository is given to the build, so no update feed is written. | `Contents/Resources/app-update.yml` does not exist. |
| **Product usage events are removed** | Source patches in `apps/server/src/telemetry/AnalyticsService.ts`: the default is turned off, the startup switch is fixed to off so no environment variable turns it back on, and the default endpoint (`ingest.t3.codes`) and PostHog project key are replaced by empty strings. | The upstream "on" forms, `ingest.t3.codes` and the key are absent from the whole app bundle. |
| **PostHog and Sentry domains removed** | The Cursor SDK dependency carries a list of well-known connector domains. `posthog.com`, `sentry.io` and `sentry.dev` are deleted from it after each dependency install, including the one the desktop build runs in its staging folder (one line is added to `scripts/build-desktop-artifact.ts` to call `harden.sh` there), and from the copy of upstream's SDK patch file that is packed into the app. | None of the three strings is anywhere in the app bundle. |
| **Separate data folder: `~/.safecode`** | Source patches replace the default home `~/.t3` in `apps/desktop/src/app/DesktopStatePaths.ts`, `apps/server/src/os-jank.ts`, `apps/server/src/cli/browser.ts`, `apps/server/src/project/AgentSessionScanner.ts` and `apps/server/src/device/SshDeviceHost.ts`. `T3CODE_HOME` still overrides it. | The desktop code inside `app.asar` joins the home directory with `.safecode`. |
| **Optional display name** | Only if `PRODUCT_NAME` is set in `config.env`: `productName` in `apps/desktop/package.json` is replaced. The bundle id stays the same. | Not checked. |
| **Your own code signature** (optional) | Upstream's signing needs their provisioning profile, so `bin/sign.sh` signs with your Developer ID instead, with upstream's entitlements minus the passkey ones that only T3 Connect uses. | `codesign --verify --deep --strict` in `sign.sh`. |

Tailscale, SSH and local-network access are untouched.

### The telemetry patches, exactly

`bin/build.sh` first turns the default off, handling both layouts of the upstream
file:

```diff
 # v0.1.12 and later
-  const enabledByDefault = !isCiEnvironment(hostEnvironment);
+  const enabledByDefault = false;

 # v0.1.11
-  enabled: Config.Boolean("T3CODE_TELEMETRY_ENABLED").pipe(Config.withDefault(true)),
+  enabled: Config.Boolean("T3CODE_TELEMETRY_ENABLED").pipe(Config.withDefault(false)),
```

`bin/harden.sh source` then removes the switch and the destination (v0.1.12 layout):

```diff
-    Config.withDefault("phc_…"),               # upstream's PostHog project key
+    Config.withDefault(""),
-    Config.withDefault("https://ingest.t3.codes"),
+    Config.withDefault(""),
-  const enabledAtStartup = Option.getOrElse(telemetryConfig.enabled, () => enabledByDefault);
+  const enabledAtStartup = false as boolean;
```

Every edit must match exactly once. If a line is not found (upstream rewrote the
file), the build stops with an error instead of producing an app without the
edit. There is no setting that turns the events back on in this build.

What upstream sends when the events are on is described in
[`docs/user/telemetry.md`](../docs/user/telemetry.md).

### The data folder

This build keeps threads, settings, tools and worktrees in `~/.safecode`, so it
never reads or writes the official app's `~/.t3`. A first launch therefore starts
empty. To carry existing data over, quit both apps and copy it before the first
launch:

```sh
mkdir -m 700 ~/.safecode
cp -a ~/.t3/userdata ~/.t3/tools ~/.safecode/
```

Threads that already have a worktree keep using it at its old path under
`~/.t3/worktrees`. Two things still share a location with the official app
because the bundle id is unchanged: Electron's own data in
`~/Library/Application Support/t3code-v2`, and the `t3code://` URL scheme.

### What this build does not change

- **The mobile apps.** The iOS and Android apps from the stores are upstream's
  own builds. They send their own crash reports, startup timings and connection
  traces through upstream's relay, whatever desktop build they connect to.
- **Provider traffic.** Prompts, code and responses go from your machine to the
  provider you use (Anthropic, OpenAI, ...), as in the official app.
- **Other outbound requests** the server makes on its own, such as provider CLI
  version checks and model lists.
- **Other upstream addresses left in the code**, such as `app.t3.codes` (thread
  links, allowed sign-in return address) and documentation links. The T3 Connect,
  updater and relay-tracing code is also still in the bundle; it has no
  configuration to run with.
- **Windows/WSL paths** still name `~/.t3`; these scripts only build for macOS.
  The remote device host feature (simulators on another Mac over SSH) now looks
  under `~/.safecode` on that Mac and has not been tested.
- **A web client opened in a browser** does not read the server's telemetry
  setting.

## Requirements

macOS with Xcode command line tools, `git`, `curl` and Rust (`cargo`). Node and
pnpm are downloaded into `toolchain/` at the versions the release pins.

## Use

```sh
cd tailscale-build
cp config.example.env config.env   # optional: signing, auto-install
bin/build.sh v0.1.11               # -> release/v0.1.11/*.dmg
bin/install.sh release/v0.1.11/*.dmg
```

`bin/build.sh` clones upstream into `src/`, checks out the tag, applies the
changes listed above, builds the DMG, optionally signs it, and runs
`bin/verify.sh` on the result. The checkout is reset to the tag on every run, so
the patches never accumulate.

## Nightly rebuild

```sh
bin/install-launchd.sh             # bin/install-launchd.sh --remove to undo
```

A launchd agent runs `bin/nightly.sh` at 22:30, 00:30, 02:30 and 04:30. It asks
GitHub for the latest stable release (nightlies and pre-releases are ignored)
and builds it if it has not been built yet. Outside 22:00–06:00 it does
nothing; `FORCE=1 bin/nightly.sh` runs it now. A failed build is retried the
next night. Logs are in `logs/`.

## Signing

Set `SIGN_IDENTITY` in `config.env` to sign with your own Developer ID
(hardened runtime, upstream's entitlements minus the passkey ones that only
T3 Connect uses). A signed app keeps its keychain and privacy permissions
across rebuilds. The first run shows a keychain prompt for `codesign`: choose
**Always Allow**, or the nightly job will wait on that prompt.

Notarization is optional and only matters if the app is copied to another Mac;
see `NOTARY_PROFILE` in `config.example.env`.
