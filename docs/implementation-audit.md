# Implementation Audit

Audit date: 2026-07-11  
Specification: `docs/design/macos-menu-bar-app.md` R57
Scope note: all keyboard behavior, including T34 and T35, is deferred by product decision and is not a v1 release blocker.

## Status Legend

- **Verified**: covered by an automated test or repository gate.
- **Partial**: implementation and some evidence exist, but a manual UI, accessibility, or installed-app check remains.
- **Deferred**: explicitly removed from the v1 acceptance scope.
- **External**: cannot be completed from the repository without release ownership, credentials, signing, notarization, or a clean target machine.

## T1-T66 Evidence Matrix

| ID | Status | Evidence / remaining check |
| --- | --- | --- |
| T1 | Verified | `StorageTests.testPriceQuoteEncodesDecimalAsStringAndDateAsISO8601` |
| T2 | Verified | `StorageTests.testInterruptedTemporaryWriteCannotReplaceExistingSnapshot` and atomic replacement tests |
| T3 | Verified | `WatchlistUseCaseTests` duplicate and 50-item cap tests |
| T4 | Verified | Configuration test covers CMC Keyless 3s and authenticated 1s intervals |
| T5 | Verified | Classifier tests cover legacy curated slug, CMC exact symbol, and unknown crypto fallback |
| T6 | Verified | `PanelViewModelTests.testOneCharacterQueryNeverCallsSearch` |
| T7 | Verified | Debounce/latest-generation tests in `PanelViewModelTests` |
| T8 | Verified | Shared 429 gate tests in `NetworkTests` and `PanelViewModelTests` |
| T9 | Verified | Bulk soft-miss tests in `NetworkTests` and `PanelViewModelTests` |
| T10 | Verified | `PanelViewModelTests.testStaleBoundaryUsesFetchedAtAndCurrentPresentationTime` |
| T11 | Verified | Open debounce, stable-open, and close-before-debounce tests in `PanelViewModelTests` |
| T12 | Verified | Tests require CMC `/public-api` without auth and keyed root with `X-CMC_PRO_API_KEY`; live map/price smoke passed without a key |
| T13 | Verified | Search/open/price cancellation and retry-sleep cancellation tests |
| T14 | Verified | Bootstrap race and empty-watchlist open tests |
| T15 | Verified | Closed-panel Add and in-flight Add coalescing tests |
| T16 | Verified | Mutation rollback tests in `WatchlistUseCaseTests` and `PanelViewModelTests` |
| T17 | Verified | Dynamic CMC Keyless/keyed spacing, cancellation, and cross-endpoint 429 gate tests |
| T18 | Partial | Query-driven Watchlist/Search transitions are tested; Esc is deferred with T34/T35 |
| T19 | Verified | Add success, duplicate selection, and full/save-failure state tests |
| T20 | Verified | Entering Settings cancels search and leaves through the same panel model without a refresh |
| T21 | Verified | Empty and historical Watchlists remain usable without a key; historical lists refresh on open through Keyless |
| T22 | Verified | Candidate validation and failed-commit preservation tests |
| T23 | Verified | Candidate errors do not commit; quit discards in-memory candidate |
| T24 | Verified | Successful key commit replaces pending or in-flight old-key refresh and performs one full-list refresh |
| T25 | Verified | Removal save/undo-save/finalize behavior tests |
| T26 | Verified | Multi-removal batch restores original order and quotes |
| T27 | Verified | Interleaved Add/Undo and reorder-finalizes-batch tests |
| T28 | Partial | Shared reorder command and persistence rollback are tested; drag/menu/VoiceOver interaction needs manual UI verification |
| T29 | Partial | 320/360/380 snapshot stress coverage exists; header refresh is right-aligned; final hover, tooltip, VoiceOver, and visual overlap review remains |
| T30 | Verified | Boundary, scientific notation, sign, nil-change, and accessibility formatter tests |
| T31 | Verified | Injected-clock stale timeline test proves no price polling and stop-on-close |
| T32 | Verified | `StatusSelectorTests` priority, recovery, and acknowledgement coverage |
| T33 | Verified | Network/persistence/key recovery and one-time corruption/classification behavior tests |
| T34 | Deferred | All keyboard operations deferred by product decision |
| T35 | Deferred | All keyboard operations deferred by product decision |
| T36 | Partial | Search-row stress snapshots include long labels, missing rank, and fixed logo slots; final visual/a11y review remains |
| T37 | Verified | Query identity, immediate result clearing, cancellation, and generation tests |
| T38 | Verified | Search retry, failure recovery, 429 disablement, and 401-to-Settings tests |
| T39 | Partial | Mode/disable/progress logic is implemented, including no-key availability; tooltip and live in-flight presentation need manual UI verification |
| T40 | Verified | Open/manual/key bulk cooldown rules, failure exclusions, and open-bypass behavior are covered |
| T41 | Partial | Fixed production frame and stress-width snapshots exist; banner/Undo live geometry needs final visual verification |
| T42 | Verified | Cache-first bulk success, soft-miss, and failure-preservation tests |
| T43 | Verified | Bulk metadata, partial freshness, Add-price isolation, and stale timeline tests |
| T44 | Partial | Frozen kind/classifier behavior and stock-token snapshot data are covered; final badge color/a11y review remains |
| T45 | Verified | Catalog schema/count/fixture gate, unavailable fallback, and CMC symbol compatibility tests |
| T46 | Partial | Keyless empty state and batch Undo behavior are implemented; delete-last/Undo live visual check remains |
| T47 | Verified | Full-list race and existing-result selection behavior tests |
| T48 | Partial | Success/failure state preservation and return to Keyless are tested; destructive confirmation interaction needs manual UI verification |
| T49 | Partial | Fixed footer implementation is snapshot-covered; external-link close cleanup and live layout need manual verification |
| T50 | Verified | Local-drain success and configurable 2-second timeout termination tests |
| T51 | Partial | Mask/remask and candidate lifecycle tests exist; final VoiceOver/log privacy inspection remains |
| T52 | External | `build_release.sh` and strict artifact gate exist; Developer ID, notarization, stapling, Gatekeeper, and installed-app proof require release credentials |
| T53 | Verified | About version/build is implemented; `verify_scope.rb` rejects Sparkle/updater scope |
| T54 | External | Deployment target 14.0 and macOS 14 CI are gated; clean Sonoma-compatible launch test remains external |
| T55 | Partial | `verify_assets.rb` validates all ten AppIcon slots; status-item visual states and installed Finder/Gatekeeper appearance remain manual/external |
| T56 | Partial | String Catalog extraction gate covers all visible keys and stress snapshots cover long text; final live truncation/a11y review remains |
| T57 | Verified | USD request, validation, cache-envelope, configuration, and formatter gates |
| T58 | Verified | Tests cover CMC roots/header, candidate isolation, stored-key 401 fallback, simple-price mapping, and legacy CoinGecko slug plus long-tail symbol compatibility; scope rejects CoinGecko runtime URLs |
| T59 | Partial | Single icon-only `MenuBarExtra` is scope-gated; final status-item accessibility/selected-state check remains manual |
| T60 | Verified | `verify_scope.rb` rejects notifications and background-task APIs/entitlements |
| T61 | Verified | Local Application Support stores plus CloudKit/iCloud negative scope gate |
| T62 | External | `verify_release.rb` intentionally blocks while Release Owner and CoinMarketCap shipping/display conclusion are missing |
| T63 | Partial | About copy and HTTPS source links are implemented; installed external-link behavior needs manual verification |
| T64 | Verified | `verify_scope.rb` requires exactly one `MenuBarExtra`; no Settings scene exists |
| T65 | Verified | `verify_scope.rb` rejects `SMAppService`; no login-item UI, entitlement, helper, or model exists |
| T66 | Verified | Scope gate rejects package references/`Package.resolved`; runtime uses Apple SDK and tests use XCTest/URLProtocol |

## Release Boundary

Repository implementation can be considered code-complete only after the full Debug test suite, localization/scope/asset gates, universal Release build, and snapshot review pass on the current revision. Distribution remains blocked until T52, T54, T55, and T62 external evidence is complete and the remaining Partial rows are checked on the signed installed artifact.

Personal use follows `docs/local-beta.md`: an ad-hoc signed Release build may be installed and upgraded in `~/Applications` without changing the public distribution status.

## Current Repository Evidence

- XCTest: 82 passed, 0 failed, 0 skipped on macOS 26.5.1.
- Repository gates: 74 extracted localization keys, Apple/local/CoinMarketCap scope, and all 10 macOS AppIcon slots passed.
- Live CMC Keyless smoke: unauthenticated `/v1/cryptocurrency/map?symbol=BTC` and `/v1/simple/price?ids=1` returned valid CMC envelopes and Bitcoin data.
- Release structure: unsigned local build succeeded as a universal `arm64` + `x86_64` app with deployment target 14.0, `LSUIElement=true`, compiled assets, and the curated catalog.
- Visual stress review: Watchlist, Search, and Settings were reviewed at 320/360/380pt; long names truncate while quote, rank, and action columns remain visible.
- Local Beta: arm64 Release build, ad-hoc Hardened Runtime signature, stable designated requirement, installation, relaunch, and in-place upgrade passed at `~/Applications/CryptoLens.app`.
- Expected release blocks: preflight rejects the unassigned Release Owner; final evidence requires explicit `READY`; artifact verification rejects non-Developer-ID signing.
