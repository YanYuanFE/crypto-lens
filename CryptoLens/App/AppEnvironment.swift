import Foundation

@MainActor
struct AppEnvironment {
    let panelViewModel: PanelViewModel

    static func live() -> AppEnvironment {
        let keyStore = DevelopmentAPIKeyStore()
        let watchlistStore = FileWatchlistStore()
        let cacheStore = PriceCacheStore()
        let client = CoinGeckoClient(apiKeyStore: keyStore)
        let useCase = WatchlistUseCase(store: watchlistStore)
        let classifier = CuratedStockTokenClassifier()
        return AppEnvironment(
            panelViewModel: PanelViewModel(
                watchlist: useCase,
                cacheStore: cacheStore,
                apiKeyStore: keyStore,
                searcher: client,
                priceProvider: client,
                keyValidator: client,
                networkState: client,
                classifier: classifier
            )
        )
    }
}
