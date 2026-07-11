import XCTest
@testable import CryptoLens

final class ClassificationTests: XCTestCase {
    func testBundledCatalogMeetsSchemaGate() throws {
        let catalog = try CuratedStockTokenCatalog.load(bundle: .main)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(catalog.version, 1)
        XCTAssertGreaterThanOrEqual(catalog.entries.count, 500)
        XCTAssertEqual(Set(catalog.entries.map(\.coinGeckoId)).count, catalog.entries.count)
        XCTAssertGreaterThanOrEqual(catalog.entries.filter { $0.issuer == .backed }.count, 100)
        XCTAssertGreaterThanOrEqual(catalog.entries.filter { $0.issuer == .ondo }.count, 400)
        XCTAssertTrue(catalog.entries.allSatisfy { !$0.symbol.isEmpty && !$0.name.isEmpty })
        XCTAssertTrue(catalog.entries.allSatisfy { $0.verification.coinGeckoURL.scheme == "https" })
        XCTAssertTrue(catalog.entries.allSatisfy { $0.verification.issuerURL.scheme == "https" })
        XCTAssertTrue(catalog.entries.allSatisfy { $0.verification.coinGeckoURL.lastPathComponent == $0.coinGeckoId })
        XCTAssertTrue(catalog.entries.allSatisfy { dateFormatter.date(from: $0.verification.verifiedAt) != nil })
        XCTAssertTrue(catalog.entries.allSatisfy { entry in
            switch entry.issuer {
            case .backed: entry.verification.issuerURL.absoluteString == "https://assets.backed.fi/products"
            case .ondo: entry.verification.issuerURL.absoluteString == "https://docs.ondo.finance/ondo-stocks/available-assets"
            case .other: false
            }
        })
    }

    func testClassifierUsesCuratedIDAndDefaultsUnknownToCrypto() throws {
        let classifier = CuratedStockTokenClassifier(catalog: try CuratedStockTokenCatalog.load(bundle: .main))
        XCTAssertEqual(classifier.kind(for: asset("apple-ondo-tokenized-stock")), .stockToken)
        XCTAssertEqual(
            classifier.kind(
                for: Asset(
                    assetID: AssetID(rawValue: "99999", source: .coinMarketCap),
                    symbol: "AAPLON",
                    name: "Apple (Ondo Tokenized Stock)",
                    kind: .crypto,
                    platform: nil,
                    contractAddress: nil
                )
            ),
            .stockToken
        )
        XCTAssertEqual(classifier.kind(for: asset("bitcoin")), .crypto)
    }

    func testMissingCatalogFallsBackToUnavailableCryptoOnlyClassifier() throws {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        let info: [String: Any] = [
            "CFBundleIdentifier": "app.cryptolens.tests.empty-bundle",
            "CFBundleName": "EmptyBundle",
            "CFBundlePackageType": "BNDL"
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: bundleURL.appendingPathComponent("Info.plist"))
        let bundle = try XCTUnwrap(Bundle(path: bundleURL.path))

        let classifier = CuratedStockTokenClassifier(bundle: bundle)

        XCTAssertFalse(classifier.isAvailable)
        XCTAssertEqual(classifier.kind(for: asset("apple-ondo-tokenized-stock")), .crypto)
    }

    private func asset(_ id: String) -> Asset {
        Asset(assetID: AssetID(rawValue: id, source: .coinGecko), symbol: "X", name: "X", kind: .crypto, platform: nil, contractAddress: nil)
    }
}
