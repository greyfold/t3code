# Privacy Code iOS — privacy build

A working copy of `apps/mobile` (the Privacy Code iOS app, release v0.1.11) with every connection to
Privacy Code's own infrastructure removed. The app still talks to **your** Privacy Code servers over LAN,
Tailscale, SSH tunnels or a direct URL, so threads, review, terminal, files, git, browser preview,
voice input, usage, widgets and the share extension all work as upstream.

## What was removed, and where

| Removed | How |
| --- | --- |
| **Privacy Connect** (Clerk sign-in, relay, device approval, cloud environments) | `features/cloud/publicConfig.ts` is constant-null; `@clerk/expo` is resolved by Metro to an inert stub (`src/privacy/clerk*.ts*`); Clerk plugin and native module dropped (`app.config.ts`, `expo.autolinking.exclude`). The repo `.env` is never read. |
| **Crash / startup reports** (expo-observe → relay → Axiom) | `features/observability/observe.ts` is a no-op; `expo-observe` resolves to a stub and is excluded from native autolinking; `RenderErrorBoundary` no longer reports. The "Send crash reports" toggle never renders. |
| **Relay trace export** (OTLP to Axiom) | Trace config is constant-null (`publicConfig.ts`); no endpoint, dataset or token in `extra`. |
| **OTA updates** (`u.expo.dev`) | `updates.enabled=false`, no URL, check `NEVER` (verified in `Expo.plist`). |
| **Remote push / Live Activity push** (relay-backed) | Widget `enablePushNotifications=false`; relay registration is unreachable without a relay. |
| **Associated domains** (`clerk.t3.codes`, `app.t3.codes`) | Removed from entitlements and Android intent filters. |
| **Identity** | Bundle `local.t3code.private`, scheme `t3code-private`, no upstream team ID or EAS project. |

## Intentionally kept (local only)

- Settings → Diagnostics shows a *local* startup-crash log with a manual "Copy report" button.
- Camera (pairing QR), microphone (voice input), photo save, local network — each prompts first.
- `NSAllowsArbitraryLoads` stays on because self-hosted servers on a LAN are often plain `http://`.

## Not possible without Privacy Connect

- Push notifications to the phone while the app is closed. Upstream delivers these only through the
  Privacy Connect relay, so they cannot exist in a build with no relay.

## Build and verify

```bash
bin/build-ios.sh          # simulator build
bin/verify-ios.sh         # fails if any Connect/telemetry/update endpoint is in the bundle
```
