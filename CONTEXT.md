# Crypto Lens Context

Crypto Lens provides a compact view of locally tracked crypto assets and stock tokens. This glossary defines the product language shared by design and implementation.

## Asset Tracking

**Asset**:
A provider-identified crypto instrument that can be discovered and tracked by Crypto Lens.
_Avoid_: Security, holding

**Crypto Asset**:
An Asset not classified as a Stock Token; this is the conservative default when classification is uncertain.
_Avoid_: Coin when referring to all asset types

**Stock Token**:
An on-chain tradable token representing exposure to an underlying stock or ETF, distinct from the traditional security itself.
_Avoid_: Stock, share, brokerage asset

**Classification Unavailable**:
The condition where the bundled Stock Token classification data cannot be loaded, causing all unconfirmed Assets to fall back to Crypto Asset classification.
_Avoid_: Unknown asset kind, heuristic mode

**Curated Stock Token Catalog**:
The release-versioned set of verified CoinGecko Assets from the Stock Token issuers explicitly supported by Crypto Lens.
_Avoid_: Sample list, heuristic list

**Search Result**:
A transient provider-discovered asset candidate that is not locally persisted until added to the Watchlist.
_Avoid_: Watchlist item, search coin

**Watchlist**:
The locally persisted, user-ordered set of assets tracked by Crypto Lens.
_Avoid_: Portfolio, holdings

**Watchlist Removal**:
The removal of an asset from the local Watchlist, effective once persisted but reversible as part of a Removal Batch.
_Avoid_: Delete asset, delete coin

**Removal Batch**:
One or more consecutive Watchlist Removals grouped within a rolling five-second undo window and restored together by a single Undo action.
_Avoid_: Delete queue, removal toast

**Watchlist Reorder**:
A user-directed change to the order of Watchlist items without changing Watchlist membership.
_Avoid_: Sort, rank assets

**Stale Quote**:
A Last-Known Quote whose local fetch time is more than five minutes old; it remains displayable but must be marked as potentially outdated.
_Avoid_: Invalid price, expired price

**Last-Known Quote**:
The most recent successfully fetched quote retained for immediate and offline display; it may be fresh or stale but is not guaranteed to be live.
_Avoid_: Live price, current market price

## Panel Modes

**Setup Required**:
The condition where Crypto Lens has neither a Configured API Key nor any assets in the Watchlist, so price discovery cannot begin.
_Avoid_: First-run onboarding, welcome state

**Configured API Key**:
A user-provided CoinGecko Demo credential that has passed provider validation and was then committed to Keychain.
_Avoid_: Entered key, candidate key, saved input

**Candidate API Key**:
An unpersisted credential entered for validation that exists only in the current app process and cannot replace the Configured API Key until validation succeeds.
_Avoid_: Pending key, temporary saved key

**Watchlist Mode**:
The panel's default mode for viewing and managing the Watchlist.
_Avoid_: Home view, list view

**Search Mode**:
The temporary panel mode for finding assets, which replaces the Watchlist area with search results.
_Avoid_: Search overlay, results dropdown

**Settings Mode**:
The panel mode for configuring Crypto Lens and viewing product information, replacing the asset-tracking controls within the same panel.
_Avoid_: Settings window, settings accordion

**Status Banner**:
The single panel region that presents the highest-priority active condition requiring user awareness or action.
_Avoid_: Error stack, toast stack

## Release

**Release Owner**:
The person performing a Crypto Lens release who records and signs the evidence-based API terms, attribution, signing, and distribution checklist.
_Avoid_: Developer in general, app user
