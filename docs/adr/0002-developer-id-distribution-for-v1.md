# Distribute v1 with Developer ID

Crypto Lens v1 ships outside the Mac App Store as a Hardened Runtime app signed with Developer ID, notarized by Apple, and distributed as a ZIP or DMG. App Sandbox remains disabled for v1 to reduce release and review uncertainty, while storage paths, Keychain access, and networking stay sandbox-compatible so a later Mac App Store build can add entitlements without redesigning the data layer.
