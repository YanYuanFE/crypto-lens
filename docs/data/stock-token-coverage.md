# Stock Token Coverage

Status: release-complete inventory snapshot for the selected v1 issuer scopes.

Verified on 2026-07-10 against the [Ondo available-assets documentation](https://docs.ondo.finance/ondo-stocks/available-assets), the [Backed xStocks products directory](https://assets.backed.fi/products), and the issuer-specific CoinGecko category inventories recorded below. Each catalog entry also records its exact HTTPS CoinGecko asset page.

## Source Inventory

- Ondo Global Markets: 439 unique CoinGecko IDs from `ondo-tokenized-assets` (`/coins/markets`, 250 rows per page, pages 1-2).
- Backed xStocks: 132 unique CoinGecko IDs from `xstocks-ecosystem` (`/coins/markets`, 250 rows per page, page 1).
- Reproduction: `CATALOG_VERIFIED_AT=2026-07-10 ruby scripts/update_stock_token_catalog.rb`.

## Included

- Ondo Global Markets: all 439 IDs in the verified issuer category snapshot.
- Backed xStocks: all 132 IDs in the verified issuer category snapshot.
- Total: 571 unique entries; every entry has a non-empty symbol/name, issuer directory URL, exact CoinGecko page URL, and verification date.

## Excluded

- No known IDs from either selected CoinGecko issuer category were excluded at verification time.
- Official issuer products not yet indexed in the corresponding CoinGecko category remain excluded from this curated classification snapshot. Runtime discovery and quotes now depend on CoinMarketCap coverage; exact curated symbols provide the compatibility bridge for CMC assets.
- Assets added after the verification date require rerunning the updater and reviewing the diff; they remain conservatively classified as crypto until shipped in a later catalog.

The CI count floors are regression guards, not the completeness definition. Release completeness is established by matching all IDs in both dated category snapshots and documenting the only deliberate exclusion above.
