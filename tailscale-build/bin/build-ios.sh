#!/bin/bash
# Build the privacy-hardened Privacy Code iOS app (ios/apps/mobile) for the iOS Simulator.
#
# Usage: bin/build-ios.sh [simulator|device]     (default: simulator)
#
# The hardening lives in the ios/ working copy (a clone of src/ at the release tag):
# no Privacy Connect (Clerk, relay), no crash/startup reporting (expo-observe), no OTLP traces,
# no OTA update feed, no associated domains, no remote push. See ios/PRIVACY.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/ios/apps/mobile"
export PATH="$ROOT/toolchain/node-v26.13.1-darwin-arm64/bin:$PATH" LANG=en_US.UTF-8
TARGET="${1:-simulator}"

cd "$APP"
# A repo-root .env is what turns Privacy Connect on. Never let one survive.
rm -f "$ROOT/ios/.env" "$ROOT/ios/.env.local"

APP_VARIANT=production EXPO_NO_GIT_STATUS=1 CI=1 npx expo prebuild --clean --platform ios --no-install
(cd ios && pod install)

SDK=iphonesimulator; DEST="generic/platform=iOS Simulator"
if [ "$TARGET" = device ]; then SDK=iphoneos; DEST="generic/platform=iOS"; fi

cd ios
xcodebuild -workspace PrivacyCode.xcworkspace -scheme PrivacyCode \
  -configuration Release -sdk "$SDK" -destination "$DEST" \
  -derivedDataPath "$ROOT/ios/build" \
  CODE_SIGNING_ALLOWED=NO build | tail -30

"$ROOT/bin/verify-ios.sh"
