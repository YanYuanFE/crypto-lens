#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build/distribution"
ARCHIVE="$BUILD_DIR/CryptoLens.xcarchive"
UNSTAPLED_ZIP="$BUILD_DIR/CryptoLens-notarization.zip"
FINAL_ZIP="$BUILD_DIR/CryptoLens-0.1.0.zip"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the Developer ID Application identity}"
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to the Apple Developer team ID}"
: "${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE to an xcrun notarytool keychain profile}"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
ruby "$ROOT/scripts/generate_xcodeproj.rb"
ruby "$ROOT/scripts/verify_release.rb" --preflight
ruby "$ROOT/scripts/verify_assets.rb"

xcodebuild archive \
  -project "$ROOT/CryptoLens.xcodeproj" \
  -scheme CryptoLens \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"

APP="$ARCHIVE/Products/Applications/CryptoLens.app"
ditto -c -k --keepParent "$APP" "$UNSTAPLED_ZIP"
xcrun notarytool submit "$UNSTAPLED_ZIP" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
xcrun stapler staple "$APP"
"$ROOT/scripts/verify_release_artifact.sh" "$APP"
ditto -c -k --keepParent "$APP" "$FINAL_ZIP"

echo "Release artifact created at $FINAL_ZIP"
