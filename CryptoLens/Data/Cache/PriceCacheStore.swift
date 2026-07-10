import Foundation

struct PriceCacheEnvelope: Codable, Hashable, Sendable {
    let version: Int
    var currency: String
    var lastBulkRefreshAt: Date?
    var lastBulkCoveredAssetIDs: [AssetID]
    var lastBulkMissingAssetIDs: [AssetID]
    var quotes: [PriceQuote]

    init(
        version: Int = 1,
        currency: String,
        lastBulkRefreshAt: Date? = nil,
        lastBulkCoveredAssetIDs: [AssetID] = [],
        lastBulkMissingAssetIDs: [AssetID] = [],
        quotes: [PriceQuote] = []
    ) {
        self.version = version
        self.currency = currency
        self.lastBulkRefreshAt = lastBulkRefreshAt
        self.lastBulkCoveredAssetIDs = lastBulkCoveredAssetIDs
        self.lastBulkMissingAssetIDs = lastBulkMissingAssetIDs
        self.quotes = quotes
    }

    static func empty(currency: String = AppConfiguration.v1.quoteCurrency) -> PriceCacheEnvelope {
        PriceCacheEnvelope(currency: currency)
    }
}

actor PriceCacheStore: CorruptionRecoveryReporting {
    private let fileURL: URL
    private var recoveredCorruption = false

    init(directoryURL: URL? = nil) {
        let directory = directoryURL ?? (try? ApplicationSupportDirectory.cryptoLens())
        precondition(directory != nil, "Application Support directory must be available")
        fileURL = directory!.appendingPathComponent("price-cache.json")
    }

    func load() async throws -> PriceCacheEnvelope {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty() }
        do {
            let cache = try AtomicJSONFile.read(PriceCacheEnvelope.self, from: fileURL)
            guard cache.version == 1, cache.currency == AppConfiguration.v1.quoteCurrency else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return cache
        } catch {
            try AtomicJSONFile.quarantineCorruptFile(at: fileURL)
            recoveredCorruption = true
            return .empty()
        }
    }

    func save(_ cache: PriceCacheEnvelope, keeping assetIDs: [AssetID]) async throws {
        let allowed = Set(assetIDs)
        var pruned = cache
        pruned.quotes.removeAll { !allowed.contains($0.assetID) }
        pruned.lastBulkCoveredAssetIDs.removeAll { !allowed.contains($0) }
        pruned.lastBulkMissingAssetIDs.removeAll { !allowed.contains($0) }
        try AtomicJSONFile.write(pruned, to: fileURL)
    }

    func consumeRecoveredCorruption() async -> Bool {
        defer { recoveredCorruption = false }
        return recoveredCorruption
    }
}
