#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0-beta.3}"
BUILD_ROOT="$ROOT/.build/unnotarized-beta"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/CryptoLens.app"
STAGING_DIR="$BUILD_ROOT/dmg-root"
STAGED_APP="$STAGING_DIR/CryptoLens.app"
MOUNT_DIR="$BUILD_ROOT/mount"
DMG="$BUILD_ROOT/CryptoLens-$VERSION.dmg"
CHECKSUM="$DMG.sha256"
IS_MOUNTED=0

if [[ $# -gt 1 || ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Usage: $0 [version, for example 0.1.0-beta.2]" >&2
  exit 64
fi

if [[ "$VERSION" =~ -beta\.([0-9]+)$ ]]; then
  BUILD_NUMBER="${BASH_REMATCH[1]}"
else
  : "${CRYPTO_LENS_BUILD_NUMBER:?Set CRYPTO_LENS_BUILD_NUMBER for non-beta releases}"
  BUILD_NUMBER="$CRYPTO_LENS_BUILD_NUMBER"
fi
MARKETING_VERSION="${VERSION%%-*}"

cleanup() {
  if [[ "$IS_MOUNTED" -eq 1 ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet || true
  fi
}
trap cleanup EXIT

rm -rf "$BUILD_ROOT"
mkdir -p "$STAGING_DIR" "$MOUNT_DIR"

ruby "$ROOT/scripts/generate_xcodeproj.rb"
ruby "$ROOT/scripts/verify_scope.rb"
ruby "$ROOT/scripts/verify_assets.rb"

xcodebuild build -quiet \
  -project "$ROOT/CryptoLens.xcodeproj" \
  -scheme CryptoLens \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CODE_SIGNING_ALLOWED=NO

ditto "$BUILT_APP" "$STAGED_APP"
"$ROOT/scripts/sign_ad_hoc_app.sh" "$STAGED_APP"

ARCHS="$(lipo -archs "$STAGED_APP/Contents/MacOS/CryptoLens")"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || {
  echo "Unnotarized Beta must contain arm64 and x86_64; found: $ARCHS" >&2
  exit 1
}
[[ "$(plutil -extract LSUIElement raw "$STAGED_APP/Contents/Info.plist")" == "true" ]] || {
  echo "LSUIElement must remain true" >&2
  exit 1
}
[[ "$(plutil -extract LSMinimumSystemVersion raw "$STAGED_APP/Contents/Info.plist")" == "14.0" ]] || {
  echo "Minimum macOS version must remain 14.0" >&2
  exit 1
}
[[ -d "$STAGED_APP/Contents/Frameworks/Sparkle.framework" ]] || {
  echo "Sparkle framework is missing"
  exit 1
}

ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create \
  -volname "Crypto Lens" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG"
hdiutil verify "$DMG"

hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$DMG" >/dev/null
IS_MOUNTED=1
[[ -d "$MOUNT_DIR/CryptoLens.app" ]] || { echo "Mounted DMG is missing CryptoLens.app" >&2; exit 1; }
[[ -L "$MOUNT_DIR/Applications" ]] || { echo "Mounted DMG is missing Applications shortcut" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$MOUNT_DIR/CryptoLens.app"
MOUNTED_ARCHS="$(lipo -archs "$MOUNT_DIR/CryptoLens.app/Contents/MacOS/CryptoLens")"
[[ "$MOUNTED_ARCHS" == "$ARCHS" ]] || { echo "Mounted app architecture mismatch" >&2; exit 1; }
hdiutil detach "$MOUNT_DIR" -quiet
IS_MOUNTED=0

(cd "$BUILD_ROOT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$CHECKSUM")")
"$ROOT/scripts/generate_sparkle_appcast.sh" "$DMG" "$VERSION" "$DERIVED_DATA"
cp "$ROOT/.build/sparkle-archives/appcast.xml" "$BUILD_ROOT/appcast.xml"

echo "Unnotarized Beta DMG created at $DMG"
echo "SHA-256 written to $CHECKSUM"
echo "Sparkle appcast candidate written to $BUILD_ROOT/appcast.xml"
echo "Warning: this DMG is ad-hoc signed and not notarized; users must approve it in Privacy & Security."
