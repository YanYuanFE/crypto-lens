# Unnotarized Beta

Crypto Lens can be distributed as a downloadable DMG without Apple Developer Program membership. This lane is intentionally separate from the Developer ID release process in `docs/release.md`.

## User Experience

The application inside the DMG is ad-hoc signed with Hardened Runtime, but it is not signed with an Apple-issued Developer ID certificate and is not notarized. Gatekeeper therefore does not treat it as software from an identified developer.

After downloading and dragging Crypto Lens to Applications, the user must:

1. Try to open Crypto Lens once and dismiss the warning.
2. Open **System Settings → Privacy & Security**.
3. Find the blocked Crypto Lens message and click **Open Anyway**.
4. Confirm **Open** in the system dialog.

Do not instruct users to disable Gatekeeper or remove quarantine attributes globally.

## Build

```bash
scripts/build_unnotarized_dmg.sh 0.1.0-beta.3
```

The script:

- runs the product scope and icon gates;
- builds a universal `arm64` + `x86_64` Release app;
- applies an ad-hoc Hardened Runtime signature with a stable local requirement;
- creates a compressed DMG containing the app and an Applications shortcut;
- mounts the completed DMG and verifies its app, signature, and architectures;
- writes a SHA-256 checksum next to the DMG;
- signs the update enclosure with the Sparkle EdDSA key in the maintainer's login Keychain and produces an appcast candidate.

Artifacts are written to `.build/unnotarized-beta/`. The generated `appcast.xml` is a candidate only and must not be copied to the repository yet.

## Sparkle Publication Order

The first Sparkle-enabled build is a bootstrap release: users install Beta 3 manually, then Sparkle can deliver later versions. Sparkle's EdDSA key verifies the downloaded DMG independently of Apple code signing; it does not provide a Developer ID identity or notarization.

Publish each update in this order:

1. Commit and push the code used to build the version.
2. Create the matching GitHub prerelease and upload the DMG plus checksum.
3. Confirm the release asset URL is reachable.
4. Copy `.build/unnotarized-beta/appcast.xml` to the repository root, commit, and push it.
5. Check for updates from an older installed build and verify Sparkle reports the new version.

The EdDSA private key is stored only in the maintainer's login Keychain by Sparkle's `generate_keys` tool. Never export it into the repository or CI secrets unless the release process is deliberately migrated to a protected signing runner.

## Publication Rules

- Use a prerelease tag such as `v0.1.0-beta.3`.
- Mark the GitHub Release as a **pre-release**.
- Include both the DMG and its `.sha256` file.
- State prominently that the build is not Developer ID signed or notarized.
- Include the Privacy & Security approval steps in the release notes.
- Never describe this artifact as Gatekeeper-approved, notarized, or a stable production release.

The formal public release remains blocked until the checklist in `docs/release.md` is complete.
