#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT/.build/LocalBetaDerivedData"
OUTPUT_DIR="$ROOT/.build/local-beta"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/CryptoLens.app"
OUTPUT_APP="$OUTPUT_DIR/CryptoLens.app"
ARCH="${CRYPTO_LENS_ARCH:-$(uname -m)}"
LOCAL_REQUIREMENT='=designated => identifier "app.cryptolens"'

case "$ARCH" in
  arm64|x86_64) ;;
  *) echo "Unsupported local architecture: $ARCH" >&2; exit 64 ;;
esac

ruby "$ROOT/scripts/generate_xcodeproj.rb"
ruby "$ROOT/scripts/verify_scope.rb"
ruby "$ROOT/scripts/verify_assets.rb"

xcodebuild build -quiet \
  -project "$ROOT/CryptoLens.xcodeproj" \
  -scheme CryptoLens \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="$ARCH" \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
ditto "$BUILT_APP" "$OUTPUT_APP"
codesign --force --deep --sign - --options runtime --requirements "$LOCAL_REQUIREMENT" "$OUTPUT_APP"
codesign --verify --deep --strict --verbose=2 "$OUTPUT_APP"
SIGNING_REQUIREMENT="$(codesign -d -r- "$OUTPUT_APP" 2>&1)"
grep -q 'designated => identifier "app.cryptolens"' <<<"$SIGNING_REQUIREMENT" || {
  echo "Local Beta signing requirement is not stable" >&2
  exit 1
}

[[ " $(lipo -archs "$OUTPUT_APP/Contents/MacOS/CryptoLens") " == *" $ARCH "* ]] || {
  echo "Local Beta is missing the current architecture: $ARCH" >&2
  exit 1
}
[[ "$(plutil -extract LSUIElement raw "$OUTPUT_APP/Contents/Info.plist")" == "true" ]] || {
  echo "Local Beta must remain an agent app without a Dock icon" >&2
  exit 1
}
[[ "$(plutil -extract LSMinimumSystemVersion raw "$OUTPUT_APP/Contents/Info.plist")" == "14.0" ]] || {
  echo "Local Beta must retain the macOS 14.0 deployment target" >&2
  exit 1
}
[[ -s "$OUTPUT_APP/Contents/Resources/Assets.car" ]] || { echo "Compiled assets are missing" >&2; exit 1; }
[[ -s "$OUTPUT_APP/Contents/Resources/CuratedStockTokens.json" ]] || { echo "Curated catalog is missing" >&2; exit 1; }

echo "Local Beta created at $OUTPUT_APP"
