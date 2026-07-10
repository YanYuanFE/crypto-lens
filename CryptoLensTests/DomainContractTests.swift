import XCTest
@testable import CryptoLens

final class DomainContractTests: XCTestCase {
    func testV1ConfigurationMatchesTheProductContract() {
        let configuration = AppConfiguration.v1

        XCTAssertEqual(configuration.quoteCurrency, "usd")
        XCTAssertEqual(configuration.openRefreshDebounce, .milliseconds(200))
        XCTAssertEqual(configuration.manualRefreshCooldown, .seconds(60))
        XCTAssertEqual(configuration.demoMinimumRequestInterval, .milliseconds(750))
        XCTAssertEqual(configuration.maxWatchlistCount, 50)
    }

    func testAssetIDRoundTripsThroughJSON() throws {
        let original = AssetID(rawValue: "bitcoin", source: .coinGecko)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AssetID.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }
}
