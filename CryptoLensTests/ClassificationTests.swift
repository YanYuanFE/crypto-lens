import XCTest
@testable import CryptoLens

final class ClassificationTests: XCTestCase {
    func testBundledCatalogMeetsSchemaGate() throws {
        let catalog = try CuratedStockTokenCatalog.load(bundle: .main)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(catalog.version, 1)
        XCTAssertGreaterThanOrEqual(catalog.entries.count, 20)
        XCTAssertEqual(Set(catalog.entries.map(\.coinGeckoId)).count, catalog.entries.count)
        XCTAssertTrue(catalog.entries.allSatisfy { $0.verification.coinGeckoURL.scheme == "https" })
        XCTAssertTrue(catalog.entries.allSatisfy { $0.verification.issuerURL.scheme == "https" })
        XCTAssertTrue(catalog.entries.allSatisfy { dateFormatter.date(from: $0.verification.verifiedAt) != nil })
    }

    func testClassifierUsesCuratedIDAndDefaultsUnknownToCrypto() throws {
        let classifier = CuratedStockTokenClassifier(catalog: try CuratedStockTokenCatalog.load(bundle: .main))
        XCTAssertEqual(classifier.kind(for: asset("apple-ondo-tokenized-stock")), .stockToken)
        XCTAssertEqual(classifier.kind(for: asset("bitcoin")), .crypto)
    }

    private func asset(_ id: String) -> Asset {
        Asset(assetID: AssetID(rawValue: id, source: .coinGecko), symbol: "X", name: "X", kind: .crypto, platform: nil, contractAddress: nil)
    }
}
