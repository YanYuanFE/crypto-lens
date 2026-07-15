import XCTest
@testable import CryptoLens

@MainActor
final class PanelViewModelTests: XCTestCase {
    func testStableOpenRefreshesOnceWithoutPolling() async throws {
        let service = CountingMarketService()
        let model = try makeModel(service: service, items: [item("bitcoin")], openDebounce: .milliseconds(10))
        await model.bootstrap()

        model.panelVisibilityChanged(isVisible: true)
        try await Task.sleep(for: .milliseconds(150))

        let count = await service.priceRequestCount
        XCTAssertEqual(count, 1)
        model.panelVisibilityChanged(isVisible: false)
    }

    func testClosingBeforeOpenDebouncePreventsRequest() async throws {
        let service = CountingMarketService()
        let model = try makeModel(service: service, items: [item("bitcoin")], openDebounce: .milliseconds(80))
        await model.bootstrap()

        model.panelVisibilityChanged(isVisible: true)
        try await Task.sleep(for: .milliseconds(10))
        model.panelVisibilityChanged(isVisible: false)
        try await Task.sleep(for: .milliseconds(100))

        let count = await service.priceRequestCount
        XCTAssertEqual(count, 0)
    }

    func testClosingPanelCancelsPriceRetrySleepWithoutFailureBanner() async throws {
        let service = CountingMarketService(priceError: .serverError(status: 503))
        let model = try makeModel(
            service: service,
            items: [item("bitcoin")],
            openDebounce: .milliseconds(10)
        )
        await model.bootstrap()
        model.panelVisibilityChanged(isVisible: true)
        try await Task.sleep(for: .milliseconds(40))

        model.panelVisibilityChanged(isVisible: false)
        try await Task.sleep(for: .milliseconds(1_050))

        let requestCount = await service.priceRequestCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertNil(model.statusBanner)
        XCTAssertFalse(model.isRefreshing)
    }

    func testOneCharacterQueryNeverCallsSearch() async throws {
        let service = CountingMarketService()
        let model = try makeModel(service: service, items: [], openDebounce: .milliseconds(10))
        await model.bootstrap()
        model.panelVisibilityChanged(isVisible: true)

        model.query = "b"
        model.queryChanged()
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(model.mode, .watchlist)
        let count = await service.searchRequestCount
        XCTAssertEqual(count, 0)
        model.panelVisibilityChanged(isVisible: false)
    }

    func testDebounceCancelsEarlierQueryAndOnlyCommitsLatestGeneration() async throws {
        let ethereum = result("ethereum", symbol: "ETH", rank: 2)
        let service = CountingMarketService(searchResultsByQuery: ["eth": [ethereum]])
        let model = try makeModel(service: service, items: [], openDebounce: .milliseconds(10))
        await model.bootstrap()

        model.query = "bi"
        model.queryChanged()
        try await Task.sleep(for: .milliseconds(50))
        model.query = "eth"
        model.queryChanged()
        try await Task.sleep(for: .milliseconds(360))

        let queries = await service.searchQueries
        XCTAssertEqual(queries, ["eth"])
        XCTAssertEqual(model.searchResults.map(\.asset.assetID.rawValue), ["ethereum"])
    }

    func testSearchPromotesExactSymbolThenUsesRankAndStableSourceOrder() async throws {
        let service = CountingMarketService(searchResultsByQuery: [
            "eth": [
                result("ranked-first", symbol: "OTHER", rank: 1),
                result("exact-lower-rank", symbol: "ETH", rank: 900),
                result("exact-higher-rank", symbol: "eth", rank: 5),
                result("same-rank-a", symbol: "OTHER", rank: 10),
                result("same-rank-b", symbol: "OTHER", rank: 10)
            ]
        ])
        let model = try makeModel(service: service, items: [], openDebounce: .milliseconds(10))
        await model.bootstrap()
        model.query = "eth"
        model.queryChanged()
        try await Task.sleep(for: .milliseconds(360))

        XCTAssertEqual(model.searchResults.map(\.asset.assetID.rawValue), [
            "exact-higher-rank",
            "exact-lower-rank",
            "ranked-first",
            "same-rank-a",
            "same-rank-b"
        ])
    }

    func testSearchUnauthorizedMovesToSettingsAndInvalidatesConfiguredKey() async throws {
        let service = CountingMarketService(searchError: .unauthorized)
        let model = try makeModel(service: service, items: [], openDebounce: .milliseconds(10))
        await model.bootstrap()
        model.query = "btc"
        model.queryChanged()
        try await Task.sleep(for: .milliseconds(360))

        XCTAssertEqual(model.mode, .settings)
        XCTAssertEqual(model.query, "")
        XCTAssertFalse(model.configuredKeyIsValid)
        XCTAssertTrue(model.canSearch)
        XCTAssertEqual(model.statusBanner?.condition, .configuredKeyInvalid)
    }

    func testRateLimitDisablesSearchAndRequiresANewActionAfterDeadline() async throws {
        let deadline = Date().addingTimeInterval(60)
        let service = CountingMarketService(
            searchError: .rateLimited(retryAfter: 60),
            nextAllowedRequestAt: deadline
        )
        let model = try makeModel(service: service, items: [], openDebounce: .milliseconds(10))
        await model.bootstrap()
        model.query = "btc"
        model.retrySearch()
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertFalse(model.canSearch)
        XCTAssertEqual(model.statusBanner?.condition, .rateLimited)
        model.retrySearch()
        try await Task.sleep(for: .milliseconds(20))
        let requestCount = await service.searchRequestCount
        XCTAssertEqual(requestCount, 1)

        model.updatePresentationTime(deadline.addingTimeInterval(1))
        XCTAssertNil(model.statusBanner)
        XCTAssertTrue(model.canSearch)
        let countAfterTimelineUpdate = await service.searchRequestCount
        XCTAssertEqual(countAfterTimelineUpdate, 1)
    }

    func testSearchSuccessResolvesPreviousNetworkFailureWithoutPriceRequest() async throws {
        let service = CountingMarketService(
            searchResultsByQuery: ["btc": [result("bitcoin", symbol: "BTC", rank: 1)]],
            searchError: .offline(URLError(.notConnectedToInternet))
        )
        let model = try makeModel(service: service, items: [], openDebounce: .milliseconds(10))
        await model.bootstrap()
        model.query = "btc"
        model.queryChanged()
        try await Task.sleep(for: .milliseconds(360))

        XCTAssertEqual(model.mode, .search)
        XCTAssertEqual(model.query, "btc")
        XCTAssertEqual(model.statusBanner?.condition, .offline)
        XCTAssertEqual(model.localMessage, "当前网络不可用")

        await service.setSearchError(nil)
        model.retrySearch()
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertNil(model.statusBanner)
        XCTAssertNil(model.localMessage)
        XCTAssertEqual(model.searchResults.map(\.asset.assetID.rawValue), ["bitcoin"])
        let priceRequestCount = await service.priceRequestCount
        XCTAssertEqual(priceRequestCount, 0)
    }

    func testShowSettingsCancelsSearchAndClearsLoadingState() async throws {
        let service = CountingMarketService(searchDelay: .seconds(1))
        let model = try makeModel(service: service, items: [], openDebounce: .milliseconds(10))
        await model.bootstrap()
        model.query = "btc"
        model.retrySearch()
        XCTAssertTrue(model.isSearching)

        model.showSettings()

        XCTAssertEqual(model.mode, .settings)
        XCTAssertEqual(model.query, "")
        XCTAssertFalse(model.isSearching)
    }

    func testOpenBeforeBootstrapRefreshesOnceAfterReady() async throws {
        let service = CountingMarketService()
        let model = try makeModel(
            service: service,
            items: [item("bitcoin")],
            openDebounce: .milliseconds(10),
            loadDelay: .milliseconds(60)
        )

        model.panelVisibilityChanged(isVisible: true)
        let bootstrapTask = Task { await model.bootstrap() }
        try await Task.sleep(for: .milliseconds(140))
        await bootstrapTask.value

        let requestCount = await service.priceRequestCount
        XCTAssertEqual(requestCount, 1)
        model.panelVisibilityChanged(isVisible: false)
    }

    func testEmptyWatchlistNeverRequestsPricesOnOpen() async throws {
        let service = CountingMarketService()
        let model = try makeModel(service: service, items: [], openDebounce: .milliseconds(10))
        await model.bootstrap()
        model.panelVisibilityChanged(isVisible: true)
        try await Task.sleep(for: .milliseconds(40))

        let requestCount = await service.priceRequestCount
        XCTAssertEqual(requestCount, 0)
        model.panelVisibilityChanged(isVisible: false)
    }

    func testKeylessEmptyWatchlistStaysUsableAcrossPanelOpens() async throws {
        let service = CountingMarketService()
        let keyStore = RecordingAPIKeyStore(key: nil)
        let model = try makeModel(
            service: service,
            items: [],
            openDebounce: .milliseconds(10),
            keyStore: keyStore
        )
        await model.bootstrap()
        XCTAssertEqual(model.mode, .watchlist)
        XCTAssertTrue(model.canSearch)
        XCTAssertNil(model.statusBanner)

        model.panelVisibilityChanged(isVisible: true)
        XCTAssertEqual(model.mode, .watchlist)
        model.panelVisibilityChanged(isVisible: false)
        model.panelVisibilityChanged(isVisible: true)
        XCTAssertEqual(model.mode, .watchlist)
        model.panelVisibilityChanged(isVisible: false)
    }

    func testKeylessHistoryRefreshesOnOpenAndKeepsSearchEnabled() async throws {
        let service = CountingMarketService()
        let model = try makeModel(
            service: service,
            items: [item("bitcoin")],
            openDebounce: .milliseconds(10),
            keyStore: RecordingAPIKeyStore(key: nil)
        )
        await model.bootstrap()
        model.panelVisibilityChanged(isVisible: true)
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(model.mode, .watchlist)
        XCTAssertTrue(model.canSearch)
        XCTAssertNil(model.statusBanner)
        let requestCount = await service.priceRequestCount
        XCTAssertEqual(requestCount, 1)
        model.panelVisibilityChanged(isVisible: false)
    }

    func testAddWhileClosedPersistsAndCompletesWithoutNetworkRequest() async throws {
        let service = CountingMarketService()
        let model = try makeModel(service: service, items: [], openDebounce: .milliseconds(10))
        await model.bootstrap()
        model.mode = .search
        model.query = "btc"
        model.searchResults = [result("bitcoin", symbol: "BTC", rank: 1)]

        await model.add(result("bitcoin", symbol: "BTC", rank: 1))
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(model.items.map(\.asset.assetID.rawValue), ["bitcoin"])
        XCTAssertEqual(model.mode, .watchlist)
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.highlightedAssetID?.rawValue, "bitcoin")
        let requestCount = await service.priceRequestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testSelectingExistingSearchResultReturnsAndHighlightsWithoutNetwork() async throws {
        let bitcoin = item("bitcoin")
        let service = CountingMarketService()
        let model = try makeModel(
            service: service,
            items: [bitcoin],
            openDebounce: .milliseconds(10)
        )
        await model.bootstrap()
        model.mode = .search
        model.query = "btc"
        let existing = result("bitcoin", symbol: "BTC", rank: 1)
        model.searchResults = [existing]

        await model.add(existing)

        XCTAssertEqual(model.items.map(\.id), [bitcoin.id])
        XCTAssertEqual(model.mode, .watchlist)
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.highlightedAssetID, bitcoin.asset.assetID)
        let requestCount = await service.priceRequestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testWatchlistFullRaceKeepsSearchStateAndShowsLocalMessage() async throws {
        let initial = (0..<50).map { item("asset-\($0)") }
        let service = CountingMarketService()
        let model = try makeModel(service: service, items: initial, openDebounce: .milliseconds(10))
        await model.bootstrap()
        let candidate = result("asset-50", symbol: "A50", rank: nil)
        model.mode = .search
        model.query = "asset"
        model.searchResults = [candidate]

        await model.add(candidate)

        XCTAssertEqual(model.items.count, 50)
        XCTAssertEqual(model.mode, .search)
        XCTAssertEqual(model.query, "asset")
        XCTAssertEqual(model.searchResults, [candidate])
        XCTAssertEqual(model.localMessage, "关注列表最多 50 项")
    }

    func testConfiguredKeyCommitCancelsPendingOpenRefreshAndRefreshesOnce() async throws {
        let service = CountingMarketService()
        let keyStore = RecordingAPIKeyStore(key: "old-key")
        let model = try makeModel(
            service: service,
            items: [item("bitcoin")],
            openDebounce: .milliseconds(100),
            keyStore: keyStore
        )
        await model.bootstrap()
        model.panelVisibilityChanged(isVisible: true)
        model.showSettings()
        model.candidateKey = "new-key"

        model.beginValidateAndSaveKey()
        try await Task.sleep(for: .milliseconds(180))

        XCTAssertEqual(keyStore.storedKey, "new-key")
        XCTAssertEqual(model.candidateKey, "")
        XCTAssertEqual(model.mode, .watchlist)
        let validatedKeys = await service.validatedKeys
        let requestCount = await service.priceRequestCount
        XCTAssertEqual(validatedKeys, ["new-key"])
        XCTAssertEqual(requestCount, 1)
        model.panelVisibilityChanged(isVisible: false)
    }

    func testConfiguredKeyCommitReplacesInflightOldKeyRefresh() async throws {
        let service = CountingMarketService(
            priceDelay: .milliseconds(180),
            priceResults: [quote("bitcoin", price: "68000")]
        )
        let keyStore = RecordingAPIKeyStore(key: "old-key")
        let model = try makeModel(
            service: service,
            items: [item("bitcoin")],
            openDebounce: .milliseconds(10),
            keyStore: keyStore
        )
        await model.bootstrap()
        model.panelVisibilityChanged(isVisible: true)
        try await Task.sleep(for: .milliseconds(40))
        let initialRequestCount = await service.priceRequestCount
        XCTAssertEqual(initialRequestCount, 1)
        XCTAssertTrue(model.isRefreshing)

        model.showSettings()
        model.candidateKey = "new-key"
        model.beginValidateAndSaveKey()
        try await Task.sleep(for: .milliseconds(260))

        let requestIDs = await service.priceRequestIDs
        XCTAssertEqual(requestIDs, [
            [AssetID(rawValue: "bitcoin", source: .coinGecko)],
            [AssetID(rawValue: "bitcoin", source: .coinGecko)]
        ])
        XCTAssertEqual(model.quotes[AssetID(rawValue: "bitcoin", source: .coinGecko)]?.price, Decimal(68000))
        XCTAssertFalse(model.isRefreshing)
        model.panelVisibilityChanged(isVisible: false)
    }

    func testFailedCandidateValidationPreservesCandidateAndConfiguredKey() async throws {
        let service = CountingMarketService(validationError: .unauthorized)
        let keyStore = RecordingAPIKeyStore(key: "old-key")
        let model = try makeModel(
            service: service,
            items: [],
            openDebounce: .milliseconds(10),
            keyStore: keyStore
        )
        await model.bootstrap()
        model.showSettings()
        model.candidateKey = "candidate-key"

        model.beginValidateAndSaveKey()
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(keyStore.storedKey, "old-key")
        XCTAssertEqual(model.candidateKey, "candidate-key")
        XCTAssertEqual(model.mode, .settings)
        XCTAssertEqual(model.localMessage, "API Key 无效")
        XCTAssertNil(model.statusBanner)
    }

    func testClosingPanelCancelsCandidateValidationBeforeKeychainSave() async throws {
        let service = CountingMarketService(validationDelay: .milliseconds(150))
        let keyStore = RecordingAPIKeyStore(key: "old-key")
        let model = try makeModel(
            service: service,
            items: [],
            openDebounce: .milliseconds(10),
            keyStore: keyStore
        )
        await model.bootstrap()
        model.panelVisibilityChanged(isVisible: true)
        model.showSettings()
        model.candidateKey = "candidate-key"
        model.beginValidateAndSaveKey()
        try await Task.sleep(for: .milliseconds(20))

        model.panelVisibilityChanged(isVisible: false)
        try await Task.sleep(for: .milliseconds(180))

        XCTAssertEqual(keyStore.storedKey, "old-key")
        XCTAssertEqual(model.candidateKey, "candidate-key")
        XCTAssertFalse(model.isValidatingKey)
        XCTAssertNil(model.localMessage)
    }

    func testRemoveAPIKeyPreservesWatchlistAndQuotesAndClearsNetworkGate() async throws {
        let bitcoin = item("bitcoin")
        let keyStore = RecordingAPIKeyStore(key: "configured-key")
        let service = CountingMarketService(nextAllowedRequestAt: Date().addingTimeInterval(60))
        let model = try makeModel(
            service: service,
            items: [bitcoin],
            openDebounce: .milliseconds(10),
            keyStore: keyStore
        )
        await model.bootstrap()
        model.quotes = [bitcoin.asset.assetID: quote("bitcoin", price: "10")]
        model.nextAllowedRequestAt = Date().addingTimeInterval(60)

        await model.removeAPIKey()

        XCTAssertNil(keyStore.storedKey)
        XCTAssertNil(model.configuredKeySuffix)
        XCTAssertNil(model.nextAllowedRequestAt)
        XCTAssertEqual(model.items.map(\.id), [bitcoin.id])
        XCTAssertEqual(model.quotes[bitcoin.asset.assetID]?.price, Decimal(string: "10"))
        XCTAssertEqual(model.mode, .watchlist)
        XCTAssertNil(model.statusBanner)
        XCTAssertTrue(model.canSearch)
        XCTAssertTrue(model.canManualRefresh)
    }

    func testRemoveAPIKeyFailurePreservesConfiguredState() async throws {
        let keyStore = RecordingAPIKeyStore(key: "configured-key", failDelete: true)
        let service = CountingMarketService()
        let model = try makeModel(
            service: service,
            items: [],
            openDebounce: .milliseconds(10),
            keyStore: keyStore
        )
        await model.bootstrap()

        await model.removeAPIKey()

        XCTAssertEqual(keyStore.storedKey, "configured-key")
        XCTAssertEqual(model.configuredKeySuffix, "-key")
        XCTAssertTrue(model.configuredKeyIsValid)
        XCTAssertEqual(model.localMessage, "无法删除 API Key")
    }

    func testLeavingSettingsRemasksCandidateWithoutDiscardingIt() async throws {
        let service = CountingMarketService()
        let model = try makeModel(service: service, items: [], openDebounce: .milliseconds(10))
        await model.bootstrap()
        model.showSettings()
        model.candidateKey = "candidate-key"
        model.isCandidateKeyRevealed = true

        model.leaveSettings()

        XCTAssertEqual(model.candidateKey, "candidate-key")
        XCTAssertFalse(model.isCandidateKeyRevealed)
        XCTAssertEqual(model.mode, .watchlist)
    }

    func testQuitClearsCandidateAndRemovalBatchBeforeTermination() async throws {
        let initial = [item("a"), item("b")]
        let service = CountingMarketService()
        let termination = TerminationRecorder()
        let model = try makeModel(
            service: service,
            items: initial,
            openDebounce: .milliseconds(10),
            terminationHandler: { termination.wasCalled = true }
        )
        await model.bootstrap()
        await model.remove(initial[1])
        model.candidateKey = "candidate-key"

        model.beginQuit()
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(model.candidateKey, "")
        XCTAssertEqual(model.removalBatchCount, 0)
        XCTAssertTrue(termination.wasCalled)
    }

    func testStaleBoundaryUsesFetchedAtAndCurrentPresentationTime() async throws {
        let service = CountingMarketService()
        let model = try makeModel(service: service, items: [], openDebounce: .milliseconds(10))
        await model.bootstrap()
        let fetchedAt = Date(timeIntervalSince1970: 1_000)
        let quote = PriceQuote(
            assetID: AssetID(rawValue: "bitcoin", source: .coinGecko),
            currency: "usd",
            price: 1,
            change24hPercent: nil,
            fetchedAt: fetchedAt,
            lastUpdatedAt: nil,
            source: .coinGecko
        )

        model.now = fetchedAt.addingTimeInterval(300)
        XCTAssertFalse(model.isStale(quote))
        model.now = fetchedAt.addingTimeInterval(301)
        XCTAssertTrue(model.isStale(quote))
    }

    func testStaleTimelineUsesInjectedClockWithoutPollingAndStopsOnClose() async throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_000)
        let clock = FakeDateProvider(fetchedAt.addingTimeInterval(299))
        let bitcoin = item("bitcoin")
        let service = CountingMarketService()
        let model = try makeModel(
            service: service,
            items: [bitcoin],
            openDebounce: .milliseconds(5),
            staleTimelineInterval: .milliseconds(20),
            nowProvider: { clock.now }
        )
        await model.bootstrap()
        let cachedQuote = PriceQuote(
            assetID: bitcoin.asset.assetID,
            currency: "usd",
            price: 10,
            change24hPercent: nil,
            fetchedAt: fetchedAt,
            lastUpdatedAt: nil,
            source: .coinGecko
        )
        model.quotes = [bitcoin.asset.assetID: cachedQuote]
        XCTAssertFalse(model.isStale(cachedQuote))

        model.panelVisibilityChanged(isVisible: true)
        try await Task.sleep(for: .milliseconds(15))
        let countAfterOpen = await service.priceRequestCount
        XCTAssertEqual(countAfterOpen, 1)

        clock.now = fetchedAt.addingTimeInterval(301)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(model.isStale(cachedQuote))
        let countAfterTimeline = await service.priceRequestCount
        XCTAssertEqual(countAfterTimeline, countAfterOpen)

        let timeAtClose = model.now
        model.panelVisibilityChanged(isVisible: false)
        clock.now = fetchedAt.addingTimeInterval(600)
        try await Task.sleep(for: .milliseconds(45))
        XCTAssertEqual(model.now, timeAtClose)
        let countAfterClose = await service.priceRequestCount
        XCTAssertEqual(countAfterClose, countAfterOpen)
    }

    func testBulkSoftMissPreservesOldQuoteAndMarksPartialFreshness() async throws {
        let bitcoin = item("bitcoin")
        let ethereum = item("ethereum")
        let refreshedBitcoin = quote("bitcoin", price: "11")
        let service = CountingMarketService(priceResults: [refreshedBitcoin])
        let model = try makeModel(
            service: service,
            items: [bitcoin, ethereum],
            openDebounce: .milliseconds(10)
        )
        await model.bootstrap()
        model.quotes = [
            bitcoin.asset.assetID: quote("bitcoin", price: "10"),
            ethereum.asset.assetID: quote("ethereum", price: "20")
        ]

        model.panelVisibilityChanged(isVisible: true)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.quotes[bitcoin.asset.assetID]?.price, Decimal(string: "11"))
        XCTAssertEqual(model.quotes[ethereum.asset.assetID]?.price, Decimal(string: "20"))
        XCTAssertEqual(model.lastBulkMissingAssetIDs, [ethereum.asset.assetID])
        XCTAssertTrue(model.freshnessText.hasPrefix("部分更新 ·"))
        XCTAssertGreaterThan(model.manualRefreshRemaining, 0)
        model.panelVisibilityChanged(isVisible: false)
    }

    func testFailedBulkRefreshKeepsLastKnownQuoteAndDoesNotStartCooldown() async throws {
        let bitcoin = item("bitcoin")
        let service = CountingMarketService(priceError: .rateLimited(retryAfter: 60))
        let model = try makeModel(
            service: service,
            items: [bitcoin],
            openDebounce: .milliseconds(10)
        )
        await model.bootstrap()
        let oldQuote = quote("bitcoin", price: "10")
        model.quotes = [bitcoin.asset.assetID: oldQuote]

        model.panelVisibilityChanged(isVisible: true)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.quotes[bitcoin.asset.assetID], oldQuote)
        XCTAssertNil(model.lastSuccessfulWatchlistBulkAt)
        XCTAssertNil(model.lastBulkRefreshAt)
        XCTAssertEqual(model.statusBanner?.condition, .rateLimited)
        model.panelVisibilityChanged(isVisible: false)
    }

    func testAddPriceDoesNotChangeBulkFreshnessMetadata() async throws {
        let service = CountingMarketService(priceResults: [quote("bitcoin", price: "10")])
        let model = try makeModel(service: service, items: [], openDebounce: .milliseconds(10))
        await model.bootstrap()
        model.panelVisibilityChanged(isVisible: true)
        try await Task.sleep(for: .milliseconds(30))

        await model.add(result("bitcoin", symbol: "BTC", rank: 1))
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(model.quotes[AssetID(rawValue: "bitcoin", source: .coinGecko)]?.price, Decimal(string: "10"))
        XCTAssertNil(model.lastBulkRefreshAt)
        XCTAssertNil(model.lastSuccessfulWatchlistBulkAt)
        model.panelVisibilityChanged(isVisible: false)
    }

    func testAddsDuringInflightPriceRequestCoalesceIntoOneFollowUp() async throws {
        let service = CountingMarketService(priceDelay: .milliseconds(80))
        let model = try makeModel(service: service, items: [], openDebounce: .milliseconds(5))
        await model.bootstrap()
        model.panelVisibilityChanged(isVisible: true)
        try await Task.sleep(for: .milliseconds(15))

        await model.add(result("a", symbol: "A", rank: nil))
        try await Task.sleep(for: .milliseconds(10))
        await model.add(result("b", symbol: "B", rank: nil))
        await model.add(result("c", symbol: "C", rank: nil))
        try await Task.sleep(for: .milliseconds(190))

        let batches = await service.priceRequestIDs.map { Set($0.map(\.rawValue)) }
        XCTAssertEqual(batches.count, 2)
        XCTAssertEqual(batches[0], ["a"])
        XCTAssertEqual(batches[1], ["b", "c"])
        model.panelVisibilityChanged(isVisible: false)
    }

    func testClosingPanelCancelsTrackedAddPriceAndDropsPendingIDs() async throws {
        let service = CountingMarketService(priceDelay: .seconds(1))
        let model = try makeModel(service: service, items: [], openDebounce: .milliseconds(5))
        await model.bootstrap()
        model.panelVisibilityChanged(isVisible: true)
        try await Task.sleep(for: .milliseconds(15))
        await model.add(result("a", symbol: "A", rank: nil))
        try await Task.sleep(for: .milliseconds(10))
        await model.add(result("b", symbol: "B", rank: nil))

        model.panelVisibilityChanged(isVisible: false)
        try await Task.sleep(for: .milliseconds(50))

        let batches = await service.priceRequestIDs
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(Set(batches[0].map(\.rawValue)), ["a"])
        XCTAssertFalse(model.isRefreshing)
    }

    func testOpenRefreshIgnoresManualCooldown() async throws {
        let service = CountingMarketService()
        let model = try makeModel(
            service: service,
            items: [item("bitcoin")],
            openDebounce: .milliseconds(10)
        )
        await model.bootstrap()
        model.now = Date()
        model.lastSuccessfulWatchlistBulkAt = model.now
        XCTAssertFalse(model.canManualRefresh)

        model.panelVisibilityChanged(isVisible: true)
        try await Task.sleep(for: .milliseconds(50))

        let requestCount = await service.priceRequestCount
        XCTAssertEqual(requestCount, 1)
        model.panelVisibilityChanged(isVisible: false)
    }

    func testQuitWaitsForAcceptedLocalMutation() async throws {
        let service = CountingMarketService()
        let termination = TerminationRecorder()
        let model = try makeModel(
            service: service,
            items: [],
            openDebounce: .milliseconds(10),
            saveDelay: .milliseconds(100),
            terminationHandler: { termination.wasCalled = true }
        )
        await model.bootstrap()
        let asset = Asset(
            assetID: AssetID(rawValue: "bitcoin", source: .coinGecko),
            symbol: "BTC",
            name: "Bitcoin",
            kind: .crypto,
            platform: nil,
            contractAddress: nil
        )
        let result = SearchResult(asset: asset, marketCapRank: 1, thumbURL: nil)

        let addTask = Task { await model.add(result) }
        try await Task.sleep(for: .milliseconds(10))
        model.beginQuit()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(termination.wasCalled)

        await addTask.value
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(termination.wasCalled)
        XCTAssertTrue(model.isShuttingDown)
    }

    func testQuitTimesOutHangingLocalMutationAndStillTerminates() async throws {
        let service = CountingMarketService()
        let termination = TerminationRecorder()
        let model = try makeModel(
            service: service,
            items: [],
            openDebounce: .milliseconds(10),
            saveDelay: .milliseconds(180),
            shutdownDrainTimeout: .milliseconds(50),
            terminationHandler: { termination.wasCalled = true }
        )
        await model.bootstrap()
        let addTask = Task { await model.add(result("bitcoin", symbol: "BTC", rank: 1)) }
        try await Task.sleep(for: .milliseconds(10))

        model.beginQuit()
        try await Task.sleep(for: .milliseconds(90))

        XCTAssertTrue(termination.wasCalled)
        XCTAssertTrue(model.isShuttingDown)
        await addTask.value
    }

    func testSearchRetryBypassesDebounceAndCancelsPendingSearch() async throws {
        let service = CountingMarketService()
        let model = try makeModel(service: service, items: [], openDebounce: .milliseconds(10))
        await model.bootstrap()
        model.query = "bi"
        model.queryChanged()

        model.retrySearch()
        try await Task.sleep(for: .milliseconds(50))

        let count = await service.searchRequestCount
        XCTAssertEqual(count, 1)
    }

    func testClosingPanelRemasksCandidateKey() async throws {
        let service = CountingMarketService()
        let model = try makeModel(service: service, items: [], openDebounce: .milliseconds(10))
        await model.bootstrap()
        model.isCandidateKeyRevealed = true

        model.panelVisibilityChanged(isVisible: true)
        model.panelVisibilityChanged(isVisible: false)

        XCTAssertFalse(model.isCandidateKeyRevealed)
    }

    func testReorderFinalizesRemovalBatch() async throws {
        let service = CountingMarketService()
        let initial = [item("a"), item("b"), item("c")]
        let model = try makeModel(service: service, items: initial, openDebounce: .milliseconds(10))
        await model.bootstrap()
        await model.remove(initial[1])
        XCTAssertEqual(model.removalBatchCount, 1)

        await model.move(initial[0], by: 1)

        XCTAssertEqual(model.removalBatchCount, 0)
    }

    func testRemovalBatchUndoRestoresOriginalOrderAndQuotes() async throws {
        let initial = [item("a"), item("b"), item("c")]
        let service = CountingMarketService()
        let model = try makeModel(service: service, items: initial, openDebounce: .milliseconds(10))
        await model.bootstrap()
        model.quotes = Dictionary(uniqueKeysWithValues: initial.map {
            ($0.asset.assetID, quote($0.asset.assetID.rawValue, price: "10"))
        })

        await model.remove(initial[1])
        await model.remove(initial[2])
        XCTAssertEqual(model.removalBatchCount, 2)
        XCTAssertEqual(model.items.map(\.asset.assetID.rawValue), ["a"])

        await model.undoRemovalBatch()

        XCTAssertEqual(model.removalBatchCount, 0)
        XCTAssertEqual(model.items.map(\.asset.assetID.rawValue), ["a", "b", "c"])
        XCTAssertEqual(Set(model.quotes.keys.map(\.rawValue)), ["a", "b", "c"])
    }

    func testRemovalBatchSurvivesInterleavedAddAndRestoresRelativeOrder() async throws {
        let initial = [item("a"), item("b"), item("c")]
        let service = CountingMarketService()
        let model = try makeModel(service: service, items: initial, openDebounce: .milliseconds(10))
        await model.bootstrap()

        await model.remove(initial[1])
        await model.add(result("d", symbol: "D", rank: nil))
        await model.undoRemovalBatch()

        XCTAssertEqual(model.items.map(\.asset.assetID.rawValue), ["a", "b", "c", "d"])
    }

    func testClosingPanelFinalizesRemovalBatch() async throws {
        let initial = [item("a"), item("b")]
        let service = CountingMarketService()
        let model = try makeModel(service: service, items: initial, openDebounce: .milliseconds(10))
        await model.bootstrap()
        model.panelVisibilityChanged(isVisible: true)
        try await Task.sleep(for: .milliseconds(20))

        await model.remove(initial[1])
        XCTAssertEqual(model.removalBatchCount, 1)
        model.panelVisibilityChanged(isVisible: false)

        XCTAssertEqual(model.removalBatchCount, 0)
        XCTAssertEqual(model.items.map(\.asset.assetID.rawValue), ["a"])
    }

    func testUndoSaveFailureKeepsBatchRemovedAndAvailableUntilFinalized() async throws {
        let initial = [item("a"), item("b")]
        let store = PanelWatchlistStore(items: initial)
        let service = CountingMarketService()
        let model = try makeModel(
            service: service,
            items: initial,
            openDebounce: .milliseconds(10),
            store: store
        )
        await model.bootstrap()
        await model.remove(initial[1])
        await store.failNextSave()

        await model.undoRemovalBatch()

        XCTAssertEqual(model.items.map(\.asset.assetID.rawValue), ["a"])
        XCTAssertEqual(model.removalBatchCount, 1)
        XCTAssertEqual(model.statusBanner?.condition, .persistenceFailure)
    }

    func testCancelReorderPreviewRestoresOriginalOrder() async throws {
        let service = CountingMarketService()
        let initial = [item("a"), item("b"), item("c")]
        let model = try makeModel(service: service, items: initial, openDebounce: .milliseconds(10))
        await model.bootstrap()

        model.previewReorder(draggedID: initial[0].id, over: initial[2].id)
        XCTAssertEqual(model.items.map(\.id), [initial[1].id, initial[2].id, initial[0].id])

        model.cancelReorderPreview()
        XCTAssertEqual(model.items.map(\.id), initial.map(\.id))
    }

    func testCommitReorderPreviewPersistsFinalOrder() async throws {
        let service = CountingMarketService()
        let initial = [item("a"), item("b"), item("c")]
        let store = PanelWatchlistStore(items: initial)
        let model = try makeModel(
            service: service,
            items: initial,
            openDebounce: .milliseconds(10),
            store: store
        )
        await model.bootstrap()

        model.previewReorder(draggedID: initial[0].id, over: initial[2].id)
        await model.commitReorderPreview()

        let expectedIDs = [initial[1].id, initial[2].id, initial[0].id]
        XCTAssertEqual(model.items.map(\.id), expectedIDs)
        let persisted = try await store.load()
        XCTAssertEqual(persisted.map(\.id), expectedIDs)
        XCTAssertEqual(persisted.map(\.sortOrder), [0, 1, 2])
    }

    func testReorderTargetResolverChoosesNearestRowAndClampsAtEdges() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let rowFrames = [
            firstID: CGRect(x: 0, y: 0, width: 320, height: 56),
            secondID: CGRect(x: 0, y: 56, width: 320, height: 56),
            thirdID: CGRect(x: 0, y: 112, width: 320, height: 56)
        ]

        XCTAssertEqual(
            WatchlistReorderTargetResolver.targetID(atY: 90, rowFrames: rowFrames),
            secondID
        )
        XCTAssertEqual(
            WatchlistReorderTargetResolver.targetID(atY: -40, rowFrames: rowFrames),
            firstID
        )
        XCTAssertEqual(
            WatchlistReorderTargetResolver.targetID(atY: 220, rowFrames: rowFrames),
            thirdID
        )
    }

    func testSuccessfulWatchlistSaveResolvesPersistenceFailure() async throws {
        let service = CountingMarketService()
        let model = try makeModel(
            service: service,
            items: [],
            openDebounce: .milliseconds(10),
            failSaveCount: 1
        )
        await model.bootstrap()
        let asset = Asset(
            assetID: AssetID(rawValue: "bitcoin", source: .coinGecko),
            symbol: "BTC",
            name: "Bitcoin",
            kind: .crypto,
            platform: nil,
            contractAddress: nil
        )
        let result = SearchResult(asset: asset, marketCapRank: 1, thumbURL: nil)

        await model.add(result)
        XCTAssertEqual(model.statusBanner?.condition, .persistenceFailure)

        await model.add(result)
        XCTAssertNil(model.statusBanner)
    }

    func testClassificationUnavailableIsAcknowledgedOncePerViewModel() async throws {
        let service = CountingMarketService()
        let model = try makeModel(
            service: service,
            items: [],
            openDebounce: .milliseconds(10),
            classifier: UnavailableClassifier()
        )
        await model.bootstrap()
        XCTAssertEqual(model.statusBanner?.condition, .classificationUnavailable)
        XCTAssertTrue(model.statusBanner?.isAcknowledgable == true)

        model.acknowledgeStatusEvent()
        XCTAssertNil(model.statusBanner)
        model.acknowledgeStatusEvent()
        XCTAssertNil(model.statusBanner)
    }

    private func makeModel(
        service: CountingMarketService,
        items: [WatchlistItem],
        openDebounce: Duration,
        saveDelay: Duration = .zero,
        loadDelay: Duration = .zero,
        failSaveCount: Int = 0,
        keyStore: any APIKeyStoring = PanelAPIKeyStore(),
        store suppliedStore: PanelWatchlistStore? = nil,
        classifier: any StockTokenClassifying = CryptoOnlyClassifier(),
        staleTimelineInterval: Duration = .seconds(30),
        shutdownDrainTimeout: Duration = .seconds(2),
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        terminationHandler: @escaping @MainActor @Sendable () -> Void = {}
    ) throws -> PanelViewModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = suppliedStore ?? PanelWatchlistStore(
            items: items,
            loadDelay: loadDelay,
            saveDelay: saveDelay,
            failSaveCount: failSaveCount
        )
        let configuration = AppConfiguration(
            quoteCurrency: "usd",
            openRefreshDebounce: openDebounce,
            manualRefreshCooldown: .seconds(60),
            keylessMinimumRequestInterval: .seconds(3),
            authenticatedMinimumRequestInterval: .seconds(1),
            staleTimelineInterval: staleTimelineInterval,
            shutdownDrainTimeout: shutdownDrainTimeout,
            maxWatchlistCount: 50
        )
        return PanelViewModel(
            watchlist: WatchlistUseCase(store: store),
            cacheStore: PriceCacheStore(directoryURL: directory),
            apiKeyStore: keyStore,
            searcher: service,
            priceProvider: service,
            keyValidator: service,
            networkState: service,
            classifier: classifier,
            configuration: configuration,
            nowProvider: nowProvider,
            terminationHandler: terminationHandler
        )
    }

    private func item(_ id: String) -> WatchlistItem {
        let asset = Asset(
            assetID: AssetID(rawValue: id, source: .coinGecko),
            symbol: id.uppercased(),
            name: id,
            kind: .crypto,
            platform: nil,
            contractAddress: nil
        )
        return WatchlistItem(id: UUID(), asset: asset, sortOrder: 0, addedAt: Date())
    }

    private func result(_ id: String, symbol: String, rank: Int?) -> SearchResult {
        let asset = Asset(
            assetID: AssetID(rawValue: id, source: .coinGecko),
            symbol: symbol,
            name: id,
            kind: .crypto,
            platform: nil,
            contractAddress: nil
        )
        return SearchResult(asset: asset, marketCapRank: rank, thumbURL: nil)
    }

    private func quote(_ id: String, price: String) -> PriceQuote {
        PriceQuote(
            assetID: AssetID(rawValue: id, source: .coinGecko),
            currency: "usd",
            price: Decimal(string: price)!,
            change24hPercent: nil,
            fetchedAt: Date(),
            lastUpdatedAt: nil,
            source: .coinGecko
        )
    }
}

private actor CountingMarketService: AssetSearching, PriceProviding, APIKeyValidating, NetworkStateProviding {
    private(set) var searchRequestCount = 0
    private(set) var priceRequestCount = 0
    private(set) var priceRequestIDs: [[AssetID]] = []
    private(set) var searchQueries: [String] = []
    private(set) var validatedKeys: [String] = []
    private let searchResultsByQuery: [String: [SearchResult]]
    private var searchError: NetworkError?
    private let searchDelay: Duration
    private let priceError: NetworkError?
    private let priceDelay: Duration
    private let priceResults: [PriceQuote]
    private let validationError: NetworkError?
    private let validationDelay: Duration
    private(set) var nextAllowedRequestAt: Date?

    init(
        searchResultsByQuery: [String: [SearchResult]] = [:],
        searchError: NetworkError? = nil,
        searchDelay: Duration = .zero,
        priceError: NetworkError? = nil,
        priceDelay: Duration = .zero,
        priceResults: [PriceQuote] = [],
        validationError: NetworkError? = nil,
        validationDelay: Duration = .zero,
        nextAllowedRequestAt: Date? = nil
    ) {
        self.searchResultsByQuery = searchResultsByQuery
        self.searchError = searchError
        self.searchDelay = searchDelay
        self.priceError = priceError
        self.priceDelay = priceDelay
        self.priceResults = priceResults
        self.validationError = validationError
        self.validationDelay = validationDelay
        self.nextAllowedRequestAt = nextAllowedRequestAt
    }

    func search(query: String) async throws -> [SearchResult] {
        searchRequestCount += 1
        searchQueries.append(query)
        if searchDelay > .zero { try await Task.sleep(for: searchDelay) }
        if let searchError { throw searchError }
        return searchResultsByQuery[query] ?? []
    }

    func setSearchError(_ error: NetworkError?) {
        searchError = error
    }

    func prices(for assets: [Asset], currency: String) async throws -> [PriceQuote] {
        let ids = assets.map(\.assetID)
        priceRequestCount += 1
        priceRequestIDs.append(ids)
        if priceDelay > .zero { try await Task.sleep(for: priceDelay) }
        if let priceError { throw priceError }
        let requestedIDs = Set(ids)
        return priceResults.filter { requestedIDs.contains($0.assetID) }
    }

    func validate(candidateKey: String) async throws {
        validatedKeys.append(candidateKey)
        if validationDelay > .zero { try await Task.sleep(for: validationDelay) }
        if let validationError { throw validationError }
    }
    func resetNetworkState() async { nextAllowedRequestAt = nil }
}

private actor PanelWatchlistStore: WatchlistStoring {
    private var items: [WatchlistItem]
    private let loadDelay: Duration
    private let saveDelay: Duration
    private var failSaveCount: Int
    init(
        items: [WatchlistItem],
        loadDelay: Duration = .zero,
        saveDelay: Duration = .zero,
        failSaveCount: Int = 0
    ) {
        self.items = items
        self.loadDelay = loadDelay
        self.saveDelay = saveDelay
        self.failSaveCount = failSaveCount
    }
    func load() async throws -> [WatchlistItem] {
        if loadDelay > .zero { try await Task.sleep(for: loadDelay) }
        return items
    }
    func save(_ items: [WatchlistItem]) async throws {
        if saveDelay > .zero { try await Task.sleep(for: saveDelay) }
        if failSaveCount > 0 {
            failSaveCount -= 1
            throw PanelStoreError.saveFailed
        }
        self.items = items
    }

    func failNextSave() {
        failSaveCount += 1
    }
}

private enum PanelStoreError: Error {
    case saveFailed
}

private struct PanelAPIKeyStore: APIKeyStoring {
    func loadAPIKey() throws -> String? { "configured-api-key" }
    func saveAPIKey(_ key: String) throws {}
    func deleteAPIKey() throws {}
}

private final class RecordingAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?
    private let failDelete: Bool

    init(key: String?, failDelete: Bool = false) {
        self.key = key
        self.failDelete = failDelete
    }

    var storedKey: String? {
        lock.withLock { key }
    }

    func loadAPIKey() throws -> String? {
        lock.withLock { key }
    }

    func saveAPIKey(_ key: String) throws {
        lock.withLock { self.key = key }
    }

    func deleteAPIKey() throws {
        if failDelete { throw PanelStoreError.saveFailed }
        lock.withLock { key = nil }
    }
}

private struct CryptoOnlyClassifier: StockTokenClassifying {
    func kind(for asset: Asset) -> AssetKind { .crypto }
}

private struct UnavailableClassifier: StockTokenClassifying {
    let isAvailable = false
    func kind(for asset: Asset) -> AssetKind { .crypto }
}

@MainActor
private final class TerminationRecorder {
    var wasCalled = false
}

private final class FakeDateProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
