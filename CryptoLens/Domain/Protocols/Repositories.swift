protocol AssetSearching: Sendable {
    func search(query: String) async throws -> [SearchResult]
}

protocol PriceProviding: Sendable {
    func prices(for ids: [AssetID], currency: String) async throws -> [PriceQuote]
}

protocol WatchlistStoring: Sendable {
    func load() async throws -> [WatchlistItem]
    func save(_ items: [WatchlistItem]) async throws
}

protocol APIKeyStoring: Sendable {
    func loadDemoKey() throws -> String?
    func saveDemoKey(_ key: String) throws
    func deleteDemoKey() throws
}

protocol CorruptionRecoveryReporting: Sendable {
    func consumeRecoveredCorruption() async -> Bool
}
