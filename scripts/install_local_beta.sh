#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT/.build/local-beta/CryptoLens.app"
INSTALL_DIR="${CRYPTO_LENS_INSTALL_DIR:-$HOME/Applications}"
DESTINATION_APP="$INSTALL_DIR/CryptoLens.app"
SHOULD_BUILD=1
SHOULD_LAUNCH=1

for argument in "$@"; do
  case "$argument" in
    --skip-build) SHOULD_BUILD=0 ;;
    --no-launch) SHOULD_LAUNCH=0 ;;
    *) echo "Usage: $0 [--skip-build] [--no-launch]" >&2; exit 64 ;;
  esac
done

if [[ "$SHOULD_BUILD" -eq 1 ]]; then
  "$ROOT/scripts/build_local_beta.sh"
fi
[[ -d "$SOURCE_APP" ]] || { echo "Local Beta not found; run scripts/build_local_beta.sh first" >&2; exit 1; }

if pgrep -x CryptoLens >/dev/null 2>&1; then
  osascript -e 'tell application id "app.cryptolens" to quit' >/dev/null 2>&1 || true
  for _ in {1..30}; do
    pgrep -x CryptoLens >/dev/null 2>&1 || break
    sleep 0.1
  done
  pgrep -x CryptoLens >/dev/null 2>&1 && {
    echo "Crypto Lens is still running; quit it and retry the installation" >&2
    exit 1
  }
fi

mkdir -p "$INSTALL_DIR"
TEMP_APP="$INSTALL_DIR/.CryptoLens.installing.$$"
BACKUP_APP="$INSTALL_DIR/.CryptoLens.backup.$$"

cleanup() {
  rm -rf "$TEMP_APP"
  if [[ -d "$BACKUP_APP" && ! -e "$DESTINATION_APP" ]]; then
    mv "$BACKUP_APP" "$DESTINATION_APP"
  fi
}
trap cleanup EXIT

ditto "$SOURCE_APP" "$TEMP_APP"
codesign --verify --deep --strict --verbose=2 "$TEMP_APP"
if [[ -e "$DESTINATION_APP" ]]; then
  mv "$DESTINATION_APP" "$BACKUP_APP"
fi
mv "$TEMP_APP" "$DESTINATION_APP"
rm -rf "$BACKUP_APP"
trap - EXIT

if [[ "$SHOULD_LAUNCH" -eq 1 ]]; then
  open "$DESTINATION_APP"
fi

echo "Local Beta installed at $DESTINATION_APP"
