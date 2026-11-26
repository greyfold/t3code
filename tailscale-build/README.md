# privacy-code — Privacy Code build scripts (unofficial, macOS and iOS)

Repository: `privacy-code`. The app it builds is called **Privacy Code**.

An unofficial fork based on the T3 Code source code. These scripts build the
desktop app (macOS) and an iOS app from upstream's **stable** release tags with
T3 Connect switched off, product usage events, crash reports and traces removed,
and the app renamed to **Privacy Code**, for people who reach their machines
over Tailscale (or SSH / the local network) and do not want the cloud relay.

**This project is unofficial.** It is not affiliated with, endorsed by, or
maintained by T3 Tools, Inc. "T3 Code", "T3 Connect" and the T3 logos are their
trademarks; upstream's `TRADEMARK.md` explains what forks may and may not do with
them. Nothing is distributed from this repository except the build scripts: you
build the app yourself, from upstream's source, on your own Mac. The builds are
already renamed "Privacy Code" and use their own icon (see *Rename*), as that
policy asks; if you pass a build on to anyone else, keep it that way.

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
| **Renamed to "Privacy Code"** | `bin/rebrand.sh` runs on the checkout after every reset: `productName` becomes "Privacy Code" (`.app` name, menu bar, Dock), display names and UI text are renamed, "T3 Connect" reads "Privacy Connect", the in-app logo and app icon are replaced ("PC" mark in `brand/`, rasters from `brand/make-icons.sh`), and DMG files are named `Privacy-Code-<version>-<arch>.dmg`. | `build.sh` fails if the product name line is not found exactly once or the rename did not apply. |
| **Your own code signature** (optional) | Upstream's signing needs their provisioning profile, so `bin/sign.sh` signs with your Developer ID instead, with upstream's entitlements minus the passkey ones that only T3 Connect uses. | `codesign --verify --deep --strict` in `sign.sh`. |

Tailscale, SSH and local-network access are untouched.

### The iOS app

`bin/build-ios.sh [simulator|device]` builds the iOS app (upstream's React Native/Expo
client, `apps/mobile`) from an `ios/` working copy of the same release, with every
connection to upstream's own infrastructure removed. It still talks to **your**
server over LAN, Tailscale, an SSH tunnel or a direct URL. The app is named
"Privacy Code" with its own identity (bundle `local.t3code.private`, scheme
`t3code-private`), so it is a separate sandbox: the official app and its data are
untouched, and the new app starts empty and must be paired with a server again.
Details are in `ios/PRIVACY.md`.

| Removed | How |
| --- | --- |
| **T3 Connect** (Clerk sign-in, relay, device approval, cloud environments) | The cloud config is constant-null; `@clerk/expo` resolves to an inert stub; the Clerk plugin and native module are dropped and excluded from native autolinking. The repo `.env` is deleted before every build. |
| **Crash and startup reports** (expo-observe, via the relay to Axiom) | The reporter is a no-op, `expo-observe` resolves to a stub and is excluded from native autolinking, the render error boundary no longer reports, and the "Send crash reports" toggle never shows. |
| **Relay trace export** (OTLP to Axiom) | Trace config is constant-null: no endpoint, dataset or token. |
| **Over-the-air updates** (`u.expo.dev`) | Updates disabled, no URL, check set to never. |
| **Remote and Live Activity push** (relay-backed) | Widget push disabled; no relay to register with. |
| **Associated domains** (`clerk.t3.codes`, `app.t3.codes`) | Removed from the entitlements and Android intent filters. |
| **Upstream identity** | No upstream team ID or EAS project. |

`bin/verify-ios.sh` fails the build if the app contains `relay.t3.codes`,
`clerk.t3.codes`, `ingest.t3.codes`, `api.axiom.co`, `u.expo.dev`, `observe.expo`,
a live Clerk key, PostHog, Sentry, or the Google / GitHub favicon services; if an
update URL is configured or updates are not disabled; or if the remote-push
entitlement is present.

Kept on purpose, all local: a startup-crash log with a manual "Copy report"
button; camera (pairing QR), microphone (voice input), photo save and local
network, each behind its own prompt; and `NSAllowsArbitraryLoads`, because
self-hosted servers on a LAN are often plain `http://`.

Not possible without T3 Connect: push notifications while the app is closed.
On a device build signed with a personal team, the App Group cannot be
registered, so there are no home-screen widgets and no share extension.

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

### What the rename does not touch

Renaming would break builds or move user data, so these stay as upstream has
them: identifiers (`@t3tools`, `T3CODE_*`, bundle ids, URL schemes), the
`t3code-v2` Electron data folder and legacy profile names, upstream URLs and
domains, and docs and marketing pages.

### What this build does not change

- **The store versions of the mobile apps.** The iOS and Android apps from the
  stores are upstream's own builds and still send crash reports, startup timings and
  connection traces through upstream's relay. Use the Privacy Code iOS build above
  instead. There is no Android build here.
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

macOS with Xcode command line tools, `git`, `curl` and Rust (`cargo`). Xcode and CocoaPods for the iOS build. Node and
pnpm are downloaded into `toolchain/` at the versions the release pins.

## Use

```sh
cd privacy-code
cp config.example.env config.env   # optional: signing, auto-install
bin/build.sh v0.1.11               # -> release/v0.1.11/*.dmg
bin/build-ios.sh                   # iOS simulator build (device: bin/build-ios.sh device)
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
