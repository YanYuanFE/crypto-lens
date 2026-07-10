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

    private func makeModel(
        service: CountingMarketService,
        items: [WatchlistItem],
        openDebounce: Duration,
        saveDelay: Duration = .zero,
        failSaveCount: Int = 0,
        terminationHandler: @escaping @MainActor @Sendable () -> Void = {}
    ) throws -> PanelViewModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = PanelWatchlistStore(items: items, saveDelay: saveDelay, failSaveCount: failSaveCount)
        let configuration = AppConfiguration(
            quoteCurrency: "usd",
            openRefreshDebounce: openDebounce,
            manualRefreshCooldown: .seconds(60),
            demoMinimumRequestInterval: .milliseconds(750),
            maxWatchlistCount: 50
        )
        return PanelViewModel(
            watchlist: WatchlistUseCase(store: store),
            cacheStore: PriceCacheStore(directoryURL: directory),
            apiKeyStore: PanelAPIKeyStore(),
            searcher: service,
            priceProvider: service,
            keyValidator: service,
            networkState: service,
            classifier: CryptoOnlyClassifier(),
            configuration: configuration,
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
}

private actor CountingMarketService: AssetSearching, PriceProviding, APIKeyValidating, NetworkStateProviding {
    private(set) var searchRequestCount = 0
    private(set) var priceRequestCount = 0

    func search(query: String) async throws -> [SearchResult] {
        searchRequestCount += 1
        return []
    }

    func prices(for ids: [AssetID], currency: String) async throws -> [PriceQuote] {
        priceRequestCount += 1
        return []
    }

    func validate(candidateKey: String) async throws {}
    var nextAllowedRequestAt: Date? { nil }
    func resetNetworkState() async {}
}

private actor PanelWatchlistStore: WatchlistStoring {
    private var items: [WatchlistItem]
    private let saveDelay: Duration
    private var failSaveCount: Int
    init(items: [WatchlistItem], saveDelay: Duration = .zero, failSaveCount: Int = 0) {
        self.items = items
        self.saveDelay = saveDelay
        self.failSaveCount = failSaveCount
    }
    func load() async throws -> [WatchlistItem] { items }
    func save(_ items: [WatchlistItem]) async throws {
        if saveDelay > .zero { try await Task.sleep(for: saveDelay) }
        if failSaveCount > 0 {
            failSaveCount -= 1
            throw PanelStoreError.saveFailed
        }
        self.items = items
    }
}

private enum PanelStoreError: Error {
    case saveFailed
}

private struct PanelAPIKeyStore: APIKeyStoring {
    func loadDemoKey() throws -> String? { "configured-demo-key" }
    func saveDemoKey(_ key: String) throws {}
    func deleteDemoKey() throws {}
}

private struct CryptoOnlyClassifier: StockTokenClassifying {
    func kind(for asset: Asset) -> AssetKind { .crypto }
}

@MainActor
private final class TerminationRecorder {
    var wasCalled = false
}
