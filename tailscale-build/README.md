# Privacy Code build scripts (unofficial, macOS)

An unofficial fork based on the T3 Code source code. These scripts build the
desktop app from upstream's **stable** release tags with T3 Connect switched off
and product usage events off by default, for people who reach their machines
over Tailscale (or SSH / the local network) and do not want the cloud relay.

**This project is unofficial.** It is not affiliated with, endorsed by, or
maintained by T3 Tools, Inc. "T3 Code", "T3 Connect" and the T3 logos are their
trademarks; upstream's `TRADEMARK.md` explains what forks may and may not do with
them. Nothing is distributed from this repository except the build scripts: you
build the app yourself, from upstream's source, on your own Mac. If you pass a
build on to anyone else, give it your own name (`PRODUCT_NAME` below) and replace
the icons first, as that policy asks.

## What differs from the official app

Every difference is listed here. Each one is applied by `bin/build.sh` at build
time and checked on the finished DMG by `bin/verify.sh`, which fails the build if
a check does not hold.

| Change | How it is done | What `verify.sh` checks |
| --- | --- | --- |
| **T3 Connect is off** (cloud sign-in, relay, managed tunnel) | No source change. Upstream disables it in any build made without the Clerk and relay identifiers ([`docs/operations/connect-setup.md`](../docs/operations/connect-setup.md)). The script deletes any repo-root `.env` and clears `T3CODE_*`, `VITE_*`, `EXPO_PUBLIC_*` and `CLERK_*` from the environment before building. | Upstream's Clerk publishable key, OAuth client id and relay host are absent from the bundle. |
| **No self-update** | No source change. No update repository is given to the build, so no update feed is written. | `Contents/Resources/app-update.yml` does not exist. |
| **Product usage events are off by default** | **One-line source patch** in `apps/server/src/telemetry/AnalyticsService.ts`: the default for sending events to `ingest.t3.codes` is changed from on to off. | The server code inside `app.asar` carries the "off" default. |
| **Optional display name** | Only if `PRODUCT_NAME` is set in `config.env`: `productName` in `apps/desktop/package.json` is replaced. The bundle id and data directories stay the same. | Not checked. |
| **Your own code signature** (optional) | Upstream's signing needs their provisioning profile, so `bin/sign.sh` signs with your Developer ID instead, with upstream's entitlements minus the passkey ones that only T3 Connect uses. | `codesign --verify --deep --strict` in `sign.sh`. |

Tailscale, SSH and local-network access are untouched.

### The telemetry patch, exactly

The script handles both layouts of the upstream file and applies whichever one
is present:

```diff
 # v0.1.12 and later
-  const enabledByDefault = !isCiEnvironment(hostEnvironment);
+  const enabledByDefault = false;

 # v0.1.11
-  enabled: Config.Boolean("T3CODE_TELEMETRY_ENABLED").pipe(Config.withDefault(true)),
+  enabled: Config.Boolean("T3CODE_TELEMETRY_ENABLED").pipe(Config.withDefault(false)),
```

If neither line is found (upstream rewrote the file again), the build stops
with an error instead of producing an app with telemetry on. To turn the events
back on, set `T3CODE_TELEMETRY_ENABLED=true` in your shell profile.

What upstream sends when the events are on is described in
[`docs/user/telemetry.md`](../docs/user/telemetry.md).

### What this build does not change

- **The mobile apps.** The iOS and Android apps from the stores are upstream's
  own builds. They send their own crash reports, startup timings and connection
  traces through upstream's relay, whatever desktop build they connect to.
- **Provider traffic.** Prompts, code and responses go from your machine to the
  provider you use (Anthropic, OpenAI, ...), as in the official app.
- **Other outbound requests** the server makes on its own, such as provider CLI
  version checks and model lists.
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
