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
scripts/build_unnotarized_dmg.sh 0.1.0-beta.2
```

The script:

- runs the product scope and icon gates;
- builds a universal `arm64` + `x86_64` Release app;
- applies an ad-hoc Hardened Runtime signature with a stable local requirement;
- creates a compressed DMG containing the app and an Applications shortcut;
- mounts the completed DMG and verifies its app, signature, and architectures;
- writes a SHA-256 checksum next to the DMG.

Artifacts are written to `.build/unnotarized-beta/`.

## Publication Rules

- Use a prerelease tag such as `v0.1.0-beta.2`.
- Mark the GitHub Release as a **pre-release**.
- Include both the DMG and its `.sha256` file.
- State prominently that the build is not Developer ID signed or notarized.
- Include the Privacy & Security approval steps in the release notes.
- Never describe this artifact as Gatekeeper-approved, notarized, or a stable production release.

The formal public release remains blocked until the checklist in `docs/release.md` is complete.
