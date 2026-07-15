#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/CryptoLens.app" >&2
  exit 64
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$1"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
VERSIONED_FRAMEWORK="$FRAMEWORK/Versions/B"
ENTITLEMENTS="$ROOT/CryptoLens/Resources/CryptoLensAdHoc.entitlements"
LOCAL_REQUIREMENT='=designated => identifier "app.cryptolens"'

[[ -d "$APP" ]] || { echo "App bundle not found: $APP" >&2; exit 1; }
[[ -d "$FRAMEWORK" ]] || { echo "Sparkle framework missing: $FRAMEWORK" >&2; exit 1; }
[[ -f "$ENTITLEMENTS" ]] || { echo "Ad-hoc entitlements missing: $ENTITLEMENTS" >&2; exit 1; }

sign_nested() {
  codesign \
    --force \
    --sign - \
    --options runtime \
    --preserve-metadata=entitlements \
    "$1"
}

sign_nested "$VERSIONED_FRAMEWORK/XPCServices/Downloader.xpc"
sign_nested "$VERSIONED_FRAMEWORK/XPCServices/Installer.xpc"
sign_nested "$VERSIONED_FRAMEWORK/Autoupdate"
sign_nested "$VERSIONED_FRAMEWORK/Updater.app"
sign_nested "$FRAMEWORK"

codesign \
  --force \
  --sign - \
  --options runtime \
  --requirements "$LOCAL_REQUIREMENT" \
  --entitlements "$ENTITLEMENTS" \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
ENTITLEMENTS_OUTPUT="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
grep -q 'com.apple.security.cs.disable-library-validation' <<<"$ENTITLEMENTS_OUTPUT" || {
  echo "Ad-hoc app must disable library validation so Sparkle can load" >&2
  exit 1
}

echo "Ad-hoc Sparkle signing completed for $APP"
