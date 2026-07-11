# Release Evidence

Status: **BLOCKED**

This file is a release gate, not a statement that distribution is currently approved.

The supported no-membership workflow is the personal Local Beta documented in `docs/local-beta.md`. This `BLOCKED` status applies to public binary distribution and does not prevent local builds or upgrades on the developer's Mac.

## Ownership

- Release Owner: **Unassigned**
- Evidence review date: **2026-07-10**
- Intended release: Crypto Lens 0.1.0, Developer ID distribution outside the Mac App Store

## CoinMarketCap Review

- Commercial API agreement: https://pro.coinmarketcap.com/user-agreement-commercial/
- API Pricing: https://coinmarketcap.com/api/pricing/
- API Documentation: https://coinmarketcap.com/api/documentation/
- Keyless Public API: https://coinmarketcap.com/api/documentation/pro-api-reference/keyless-public-api
- API attribution destination: https://coinmarketcap.com/
- Selected access: CoinMarketCap Keyless Public API by default, with an optional user-supplied API key. Keyless uses `https://pro-api.coinmarketcap.com/public-api`; keyed requests use `https://pro-api.coinmarketcap.com` and `X-CMC_PRO_API_KEY`.
- Shipping/display conclusion: **Pending Release Owner approval.** The owner must confirm that shipping a downloadable desktop application with this low-frequency access pattern, selected plan, attribution, and displayed assets is permitted under the then-current CoinMarketCap agreement.
- In-app attribution: `Data by CoinMarketCap`, linked to the CoinMarketCap website.

## Distribution Checklist

- [ ] Release Owner is named and has recorded the CoinMarketCap shipping/display conclusion.
- [x] Curated Backed xStocks and Ondo Global Markets coverage is release-complete per `docs/data/stock-token-coverage.md`.
- [ ] Archive uses a valid Developer ID Application identity.
- [ ] Hardened Runtime is enabled and App Sandbox remains intentionally disabled.
- [ ] Archive is notarized and stapled successfully.
- [ ] ZIP or DMG is tested on a clean Sonoma-compatible Mac.
- [ ] Installed app has no Dock icon, exposes one icon-only menu bar item, and opens the 360x480 panel.
- [ ] Finder icon is non-empty and Gatekeeper accepts the installed artifact.
- [ ] `Data by CoinMarketCap` opens the reviewed attribution destination.

## Release Commands

Configure a Developer ID Application identity and a `notarytool` keychain profile, then run:

```bash
DEVELOPER_ID_APPLICATION='Developer ID Application: Example Corp (TEAMID)' \
DEVELOPMENT_TEAM='TEAMID' \
NOTARYTOOL_PROFILE='crypto-lens-notary' \
scripts/build_release.sh
```

The script first requires a named Release Owner and an approved CoinMarketCap shipping/display conclusion. It then archives a universal binary, submits it for notarization, staples the app, runs strict code-signing/Gatekeeper checks, and writes the candidate ZIP to `.build/distribution/`.

After the clean-machine and installed-app checks, complete the checklist, set `Status: **READY**`, then run `ruby scripts/verify_release.rb` as the final publication gate. No release artifact may be published while this document remains `BLOCKED` or any checklist item is unchecked.
