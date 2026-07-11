protocol AssetSearching: Sendable {
    func search(query: String) async throws -> [SearchResult]
}

protocol PriceProviding: Sendable {
    func prices(for assets: [Asset], currency: String) async throws -> [PriceQuote]
}

protocol WatchlistStoring: Sendable {
    func load() async throws -> [WatchlistItem]
    func save(_ items: [WatchlistItem]) async throws
}

protocol APIKeyStoring: Sendable {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ key: String) throws
    func deleteAPIKey() throws
}

protocol CorruptionRecoveryReporting: Sendable {
    func consumeRecoveredCorruption() async -> Bool
}
