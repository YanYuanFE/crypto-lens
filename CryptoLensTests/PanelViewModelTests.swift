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

    private func makeModel(
        service: CountingMarketService,
        items: [WatchlistItem],
        openDebounce: Duration
    ) throws -> PanelViewModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = PanelWatchlistStore(items: items)
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
            classifier: CryptoOnlyClassifier(),
            configuration: configuration
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

private actor CountingMarketService: AssetSearching, PriceProviding, APIKeyValidating {
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
}

private actor PanelWatchlistStore: WatchlistStoring {
    private var items: [WatchlistItem]
    init(items: [WatchlistItem]) { self.items = items }
    func load() async throws -> [WatchlistItem] { items }
    func save(_ items: [WatchlistItem]) async throws { self.items = items }
}

private struct PanelAPIKeyStore: APIKeyStoring {
    func loadDemoKey() throws -> String? { "configured-demo-key" }
    func saveDemoKey(_ key: String) throws {}
    func deleteDemoKey() throws {}
}

private struct CryptoOnlyClassifier: StockTokenClassifying {
    func kind(for asset: Asset) -> AssetKind { .crypto }
}
