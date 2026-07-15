#!/bin/bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 /path/to/CryptoLens-version.dmg version /path/to/DerivedData" >&2
  exit 64
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="$1"
VERSION="$2"
DERIVED_DATA="$3"
ARCHIVE_DIR="$ROOT/.build/sparkle-archives"
GENERATE_APPCAST="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
OUTPUT_APPCAST="$ARCHIVE_DIR/appcast.xml"

[[ -f "$DMG" ]] || { echo "Update DMG not found: $DMG" >&2; exit 1; }
[[ -x "$GENERATE_APPCAST" ]] || { echo "Sparkle generate_appcast tool not found: $GENERATE_APPCAST" >&2; exit 1; }

if [[ "$VERSION" =~ -beta\.([0-9]+)$ ]]; then
  BUILD_NUMBER="${BASH_REMATCH[1]}"
else
  : "${CRYPTO_LENS_BUILD_NUMBER:?Set CRYPTO_LENS_BUILD_NUMBER for non-beta releases}"
  BUILD_NUMBER="$CRYPTO_LENS_BUILD_NUMBER"
fi

mkdir -p "$ARCHIVE_DIR"
if [[ -f "$ROOT/appcast.xml" ]]; then
  cp "$ROOT/appcast.xml" "$OUTPUT_APPCAST"
else
  rm -f "$OUTPUT_APPCAST"
fi

ARCHIVE_NAME="$(basename "$DMG")"
cp "$DMG" "$ARCHIVE_DIR/$ARCHIVE_NAME"
RELEASE_NOTES="$ROOT/docs/releases/v$VERSION.md"
[[ -f "$RELEASE_NOTES" ]] || { echo "Release notes not found: $RELEASE_NOTES" >&2; exit 1; }
cp "$RELEASE_NOTES" "$ARCHIVE_DIR/${ARCHIVE_NAME%.dmg}.md"

"$GENERATE_APPCAST" \
  --download-url-prefix "https://github.com/YanYuanFE/crypto-lens/releases/download/v$VERSION/" \
  --embed-release-notes \
  --link "https://github.com/YanYuanFE/crypto-lens/releases/tag/v$VERSION" \
  --maximum-deltas 0 \
  --versions "$BUILD_NUMBER" \
  "$ARCHIVE_DIR"

[[ -s "$OUTPUT_APPCAST" ]] || { echo "Sparkle appcast was not generated" >&2; exit 1; }
echo "Sparkle appcast candidate created at $OUTPUT_APPCAST"
echo "Publish it as appcast.xml only after the matching GitHub Release asset is available."
