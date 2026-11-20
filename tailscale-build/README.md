# T3 Code without T3 Connect (macOS)

Scripts that build the T3 Code desktop app from upstream's **stable** release
tags with T3 Connect switched off, for people who reach their machines over
Tailscale (or SSH / the local network) and do not want the cloud relay.

Nothing in the app is patched. Upstream ships T3 Connect disabled in a source
build unless the Clerk and relay identifiers are provided at build time
([`docs/operations/connect-setup.md`](../docs/operations/connect-setup.md)).
These scripts build with those identifiers absent and then check the result:

- no Clerk publishable key, OAuth client id or relay URL in the bundle, so the
  sign-in, relay and managed-tunnel UI and CLI paths stay off;
- no update feed (`app-update.yml`), so the app never replaces itself with an
  official build. New versions come from the nightly job below.

Tailscale, SSH and local-network access are untouched.

This is an unofficial build, not affiliated with or supported by T3 Tools.

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

`bin/build.sh` clones upstream into `src/`, checks out the tag, builds the DMG,
optionally signs it, and runs `bin/verify.sh` on the result.

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
