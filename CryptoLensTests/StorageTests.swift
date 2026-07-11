import XCTest
@testable import CryptoLens

final class StorageTests: XCTestCase {
    func testCachedAPIKeyStoreReadsBackingOnlyOnce() throws {
        let backing = RecordingCachedAPIKeyBacking(key: "secret")
        let store = CachedAPIKeyStore(backing: backing)

        XCTAssertEqual(try store.loadAPIKey(), "secret")
        XCTAssertEqual(try store.loadAPIKey(), "secret")
        XCTAssertEqual(backing.loadCount, 1)
    }

    func testCachedAPIKeyStoreSynchronizesSuccessfulSaveAndDelete() throws {
        let backing = RecordingCachedAPIKeyBacking(key: "old")
        let store = CachedAPIKeyStore(backing: backing)
        XCTAssertEqual(try store.loadAPIKey(), "old")

        try store.saveAPIKey("new")
        XCTAssertEqual(try store.loadAPIKey(), "new")
        try store.deleteAPIKey()
        XCTAssertNil(try store.loadAPIKey())

        XCTAssertEqual(backing.loadCount, 1)
        XCTAssertEqual(backing.storedKey, nil)
    }

    func testCachedAPIKeyStoreKeepsCachedValueWhenMutationFails() throws {
        let backing = RecordingCachedAPIKeyBacking(key: "old")
        let store = CachedAPIKeyStore(backing: backing)
        XCTAssertEqual(try store.loadAPIKey(), "old")

        backing.failMutations = true
        XCTAssertThrowsError(try store.saveAPIKey("new"))
        XCTAssertThrowsError(try store.deleteAPIKey())
        XCTAssertEqual(try store.loadAPIKey(), "old")
        XCTAssertEqual(backing.loadCount, 1)
    }

    func testPriceQuoteEncodesDecimalAsStringAndDateAsISO8601() throws {
        let quote = PriceQuote(
            assetID: AssetID(rawValue: "bitcoin", source: .coinGecko),
            currency: "usd",
            price: Decimal(string: "1234.567890123456789")!,
            change24hPercent: Decimal(string: "-0.125")!,
            fetchedAt: Date(timeIntervalSince1970: 1_720_000_000),
            lastUpdatedAt: Date(timeIntervalSince1970: 1_719_999_900),
            source: .coinGecko
        )

        let data = try JSONCoding.encoder().encode(quote)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["price"] as? String, "1234.567890123456789")
        XCTAssertEqual(json["change24hPercent"] as? String, "-0.125")
        XCTAssertTrue(try XCTUnwrap(json["fetchedAt"] as? String).contains("T"))
        XCTAssertEqual(try JSONCoding.decoder().decode(PriceQuote.self, from: data), quote)
    }

    func testCorruptWatchlistIsBackedUpAndLoadsAsEmpty() async throws {
        let directory = try makeTemporaryDirectory()
        try Data("{half-written".utf8).write(to: directory.appendingPathComponent("watchlist.json"))
        let store = FileWatchlistStore(directoryURL: directory)

        let items = try await store.load()

        XCTAssertEqual(items, [])
        let recoveredOnce = await store.consumeRecoveredCorruption()
        let recoveredTwice = await store.consumeRecoveredCorruption()
        XCTAssertTrue(recoveredOnce)
        XCTAssertFalse(recoveredTwice)
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(backups.filter { $0.hasPrefix("watchlist.json.corrupt-") && $0.hasSuffix(".bak") }.count, 1)
    }

    func testPriceCachePrunesQuotesAndBulkMetadataToWatchlist() async throws {
        let directory = try makeTemporaryDirectory()
        let store = PriceCacheStore(directoryURL: directory)
        let bitcoin = AssetID(rawValue: "bitcoin", source: .coinGecko)
        let ether = AssetID(rawValue: "ethereum", source: .coinGecko)
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let cache = PriceCacheEnvelope(
            currency: "usd",
            lastBulkRefreshAt: now,
            lastBulkCoveredAssetIDs: [bitcoin, ether],
            lastBulkMissingAssetIDs: [ether],
            quotes: [quote(for: bitcoin, at: now), quote(for: ether, at: now)]
        )

        try await store.save(cache, keeping: [bitcoin])
        let loaded = try await store.load()

        XCTAssertEqual(loaded.quotes.map(\.assetID), [bitcoin])
        XCTAssertEqual(loaded.lastBulkCoveredAssetIDs, [bitcoin])
        XCTAssertEqual(loaded.lastBulkMissingAssetIDs, [])
        XCTAssertEqual(loaded.lastBulkRefreshAt, now)
    }

    func testAtomicReplacementKeepsSecondCompleteSnapshot() async throws {
        let directory = try makeTemporaryDirectory()
        let store = FileWatchlistStore(directoryURL: directory)
        let date = Date(timeIntervalSince1970: 1_720_000_000)
        let first = WatchlistItem(id: UUID(), asset: asset("bitcoin"), sortOrder: 0, addedAt: date)
        let second = WatchlistItem(id: UUID(), asset: asset("ethereum"), sortOrder: 0, addedAt: date)

        try await store.save([first])
        try await store.save([second])
        let loaded = try await store.load()

        XCTAssertEqual(loaded, [second])
    }

    func testInterruptedTemporaryWriteCannotReplaceExistingSnapshot() async throws {
        let directory = try makeTemporaryDirectory()
        let store = FileWatchlistStore(directoryURL: directory)
        let original = WatchlistItem(
            id: UUID(),
            asset: asset("bitcoin"),
            sortOrder: 0,
            addedAt: Date(timeIntervalSince1970: 1_720_000_000)
        )
        try await store.save([original])
        try Data("{half-written".utf8).write(
            to: directory.appendingPathComponent(".watchlist.json.interrupted.tmp")
        )

        let loaded = try await store.load()

        XCTAssertEqual(loaded, [original])
    }

    func testNonUSDCurrencyCacheIsQuarantinedAndReportedOnce() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appendingPathComponent("price-cache.json")
        let cache = PriceCacheEnvelope(currency: "eur")
        try JSONCoding.encoder().encode(cache).write(to: cacheURL)
        let store = PriceCacheStore(directoryURL: directory)

        let loaded = try await store.load()

        XCTAssertEqual(loaded, .empty())
        let recoveredOnce = await store.consumeRecoveredCorruption()
        let recoveredTwice = await store.consumeRecoveredCorruption()
        XCTAssertTrue(recoveredOnce)
        XCTAssertFalse(recoveredTwice)
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(backups.filter { $0.hasPrefix("price-cache.json.corrupt-") }.count, 1)
    }

    private func quote(for id: AssetID, at date: Date) -> PriceQuote {
        PriceQuote(
            assetID: id,
            currency: "usd",
            price: 1,
            change24hPercent: nil,
            fetchedAt: date,
            lastUpdatedAt: nil,
            source: .coinGecko
        )
    }

    private func asset(_ id: String) -> Asset {
        Asset(
            assetID: AssetID(rawValue: id, source: .coinGecko),
            symbol: id.uppercased(),
            name: id,
            kind: .crypto,
            platform: nil,
            contractAddress: nil
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

private enum CachedAPIKeyBackingError: Error {
    case mutationFailed
}

private final class RecordingCachedAPIKeyBacking: APIKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?
    private var reads = 0
    var failMutations = false

    init(key: String?) {
        self.key = key
    }

    var loadCount: Int {
        lock.withLock { reads }
    }

    var storedKey: String? {
        lock.withLock { key }
    }

    func loadAPIKey() throws -> String? {
        lock.withLock {
            reads += 1
            return key
        }
    }

    func saveAPIKey(_ key: String) throws {
        try lock.withLock {
            if failMutations { throw CachedAPIKeyBackingError.mutationFailed }
            self.key = key
        }
    }

    func deleteAPIKey() throws {
        try lock.withLock {
            if failMutations { throw CachedAPIKeyBackingError.mutationFailed }
            key = nil
        }
    }
}
