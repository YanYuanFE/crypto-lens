# Stock Token Coverage

Status: implementation seed, not release-complete.

Verified on 2026-07-10 against the [Ondo available-assets documentation](https://docs.ondo.finance/ondo-stocks/available-assets) and individual CoinGecko asset pages recorded in `CuratedStockTokens.json`.

## Included

- Ondo Global Markets: 20 high-visibility stocks with confirmed CoinGecko IDs.
- Backed xStocks: none yet.

## Excluded

- The remainder of Ondo's 100+ inventory is pending a reproducible inventory export and per-ID verification.
- Backed xStocks is pending an authoritative issuer inventory that can be paired with CoinGecko IDs.
- Entries without both an issuer source and an HTTPS CoinGecko asset page remain deliberately classified as crypto.

The release checklist must remain blocked until the selected issuer scopes are near-complete and every known omission is explained.
