#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/CryptoLens.app" >&2
  exit 64
fi

APP="$1"
BINARY="$APP/Contents/MacOS/CryptoLens"
INFO="$APP/Contents/Info.plist"
RESOURCES="$APP/Contents/Resources"

[[ -d "$APP" ]] || { echo "App bundle not found: $APP" >&2; exit 1; }
[[ -x "$BINARY" ]] || { echo "App binary missing: $BINARY" >&2; exit 1; }
[[ -s "$RESOURCES/CuratedStockTokens.json" ]] || { echo "Curated catalog missing from app bundle" >&2; exit 1; }
[[ -s "$RESOURCES/Assets.car" ]] || { echo "Compiled asset catalog missing from app bundle" >&2; exit 1; }

ARCHS="$(lipo -archs "$BINARY")"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || {
  echo "Release must contain arm64 and x86_64; found: $ARCHS" >&2
  exit 1
}

[[ "$(plutil -extract LSUIElement raw "$INFO")" == "true" ]] || { echo "LSUIElement must be true" >&2; exit 1; }
[[ "$(plutil -extract LSMinimumSystemVersion raw "$INFO")" == "14.0" ]] || { echo "Minimum macOS version must be 14.0" >&2; exit 1; }

codesign --verify --deep --strict --verbose=2 "$APP"
SIGNING_DETAILS="$(codesign -dvv "$APP" 2>&1)"
grep -Eq '^CodeDirectory .*flags=.*runtime' <<<"$SIGNING_DETAILS" || { echo "Hardened Runtime is missing" >&2; exit 1; }
TEAM_IDENTIFIER="$(sed -n 's/^TeamIdentifier=//p' <<<"$SIGNING_DETAILS")"
grep -q '^Authority=Developer ID Application:' <<<"$SIGNING_DETAILS" || { echo "Developer ID Application signature is required" >&2; exit 1; }
[[ -n "$TEAM_IDENTIFIER" && "$TEAM_IDENTIFIER" != "not set" ]] || { echo "Signing TeamIdentifier is missing" >&2; exit 1; }

ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
if grep -q "com.apple.security.get-task-allow" <<<"$ENTITLEMENTS"; then
  echo "Release contains get-task-allow" >&2
  exit 1
fi

xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo "Release artifact gate passed: universal, Developer ID signed, hardened, stapled, and Gatekeeper accepted"
