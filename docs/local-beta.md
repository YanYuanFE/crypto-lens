# Local Beta

Crypto Lens can be built and used on the current Mac without Apple Developer Program membership. This workflow is for personal development and testing, not public binary distribution.

## Requirements

- macOS 14 or later
- Xcode with the macOS SDK and command-line tools
- No Apple Developer account, certificate, or notarization profile
- No API key is required; a CoinMarketCap API key remains an optional enhancement

## Build

```bash
scripts/build_local_beta.sh
```

The script runs the scope and icon gates, creates a Release build for the current Mac architecture, embeds the pinned Sparkle framework, and applies an ad-hoc Hardened Runtime signature with a stable local designated requirement. Because Sparkle contains nested executables, the ad-hoc lane signs them in dependency order and grants only the main app the library-validation exception required for this unsigned local workflow. The resulting app is written to:

```text
.build/local-beta/CryptoLens.app
```

## Install Or Upgrade

```bash
scripts/install_local_beta.sh
```

The app is installed to `~/Applications/CryptoLens.app` and launched. Running the same command upgrades the existing local installation. The installer asks the running app to quit, verifies the replacement, and swaps the bundle atomically. Watchlist/cache data in Application Support and the CoinMarketCap API Key in Keychain are preserved; the stable local signing requirement prevents each rebuild from receiving a new cdhash-only identity.

The first migration from an older Xcode or cdhash-only ad-hoc build may require one Keychain approval or re-entry of an optional CoinMarketCap API Key. Subsequent builds made by this Local Beta workflow keep the same designated requirement.

Local builds can use **Settings → About → Check for Updates**, but an update is available only after a matching GitHub prerelease asset and signed `appcast.xml` entry have both been published. The Sparkle EdDSA private key remains in the maintainer's login Keychain and is never stored in the repository.

Available options:

```bash
scripts/install_local_beta.sh --no-launch
scripts/install_local_beta.sh --skip-build
```

Set `CRYPTO_LENS_INSTALL_DIR` to use another user-writable installation directory.

## Distribution Boundary

The ad-hoc signature does not identify a verified developer and cannot be notarized. Do not publish this app bundle as a normal download. Public binary distribution remains governed by `docs/release.md` and requires Apple Developer Program membership, Developer ID signing, notarization, and clean-machine verification.

To remove the local app, quit Crypto Lens and move `~/Applications/CryptoLens.app` to the Trash. Local watchlist and Keychain data are intentionally left intact.
