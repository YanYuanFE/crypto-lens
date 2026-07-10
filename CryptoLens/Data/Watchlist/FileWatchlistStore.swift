import Foundation

actor FileWatchlistStore: WatchlistStoring, CorruptionRecoveryReporting {
    private let fileURL: URL
    private var recoveredCorruption = false

    init(directoryURL: URL? = nil) {
        let directory = directoryURL ?? (try? ApplicationSupportDirectory.cryptoLens())
        precondition(directory != nil, "Application Support directory must be available")
        fileURL = directory!.appendingPathComponent("watchlist.json")
    }

    func load() async throws -> [WatchlistItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            return try AtomicJSONFile.read([WatchlistItem].self, from: fileURL)
                .sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            try AtomicJSONFile.quarantineCorruptFile(at: fileURL)
            recoveredCorruption = true
            return []
        }
    }

    func save(_ items: [WatchlistItem]) async throws {
        try AtomicJSONFile.write(items, to: fileURL)
    }

    func consumeRecoveredCorruption() async -> Bool {
        defer { recoveredCorruption = false }
        return recoveredCorruption
    }
}
