import XCTest
@testable import CryptoLens

final class StorageTests: XCTestCase {
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

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
