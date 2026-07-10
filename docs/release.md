# Release Evidence

Status: **BLOCKED**

This file is a release gate, not a statement that distribution is currently approved.

## Ownership

- Release Owner: **Unassigned**
- Evidence review date: **2026-07-10**
- Intended release: Crypto Lens 0.1.0, Developer ID distribution outside the Mac App Store

## CoinGecko Review

- API Terms: https://www.coingecko.com/en/api_terms
- Website Terms: https://www.coingecko.com/en/terms
- API Pricing: https://www.coingecko.com/en/api/pricing
- API attribution destination: https://www.coingecko.com/en/api
- Selected plan: Demo, using only `https://api.coingecko.com/api/v3` and `x-cg-demo-api-key`
- Shipping/display conclusion: **Pending Release Owner approval.** The current pricing page marks Demo as attribution-required. The owner must confirm that shipping a downloadable desktop application displaying the selected CoinGecko assets is permitted under the then-current API Terms.
- In-app attribution: `Data by CoinGecko`, linked to the API page.

## Distribution Checklist

- [ ] Release Owner is named and has recorded the CoinGecko shipping/display conclusion.
- [x] Curated Backed xStocks and Ondo Global Markets coverage is release-complete per `docs/data/stock-token-coverage.md`.
- [ ] Archive uses a valid Developer ID Application identity.
- [ ] Hardened Runtime is enabled and App Sandbox remains intentionally disabled.
- [ ] Archive is notarized and stapled successfully.
- [ ] ZIP or DMG is tested on a clean Sonoma-compatible Mac.
- [ ] Installed app has no Dock icon, exposes one icon-only menu bar item, and opens the 360x480 panel.
- [ ] Finder icon is non-empty and Gatekeeper accepts the installed artifact.
- [ ] `Data by CoinGecko` opens the reviewed attribution destination.

No release artifact may be published while this document remains `BLOCKED` or any checklist item is unchecked.
