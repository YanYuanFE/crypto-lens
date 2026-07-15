import XCTest
@testable import CryptoLens

final class DomainContractTests: XCTestCase {
    func testV1ConfigurationMatchesTheProductContract() {
        let configuration = AppConfiguration.v1

        XCTAssertEqual(configuration.quoteCurrency, "usd")
        XCTAssertEqual(configuration.openRefreshDebounce, .milliseconds(200))
        XCTAssertEqual(configuration.manualRefreshCooldown, .seconds(60))
        XCTAssertEqual(configuration.keylessMinimumRequestInterval, .seconds(3))
        XCTAssertEqual(configuration.authenticatedMinimumRequestInterval, .seconds(1))
        XCTAssertEqual(configuration.staleTimelineInterval, .seconds(30))
        XCTAssertEqual(configuration.shutdownDrainTimeout, .seconds(2))
        XCTAssertEqual(configuration.maxWatchlistCount, 50)
    }

    func testSparkleConfigurationMatchesTheUpdateContract() {
        let info = Bundle.main.infoDictionary

        XCTAssertEqual(
            info?["SUFeedURL"] as? String,
            "https://raw.githubusercontent.com/YanYuanFE/crypto-lens/main/appcast.xml"
        )
        XCTAssertEqual(
            info?["SUPublicEDKey"] as? String,
            "j4Pb4f886ym9R8BIAUKZ4KQMH6j2VnbN+CLKp/s8/ec="
        )
        XCTAssertEqual(info?["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(info?["SUAllowsAutomaticUpdates"] as? Bool, true)
        XCTAssertEqual(info?["SUAutomaticallyUpdate"] as? Bool, false)
        XCTAssertEqual(info?["SUScheduledCheckInterval"] as? Int, 86_400)
        XCTAssertEqual(info?["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
    }

    func testAssetIDRoundTripsThroughJSON() throws {
        let original = AssetID(rawValue: "bitcoin", source: .coinGecko)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AssetID.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }

    func testCoinMarketCapAssetBuildsOfficialLogoURL() {
        let asset = Asset(
            assetID: AssetID(rawValue: "1", source: .coinMarketCap),
            symbol: "BTC",
            name: "Bitcoin",
            kind: .crypto,
            platform: nil,
            contractAddress: nil
        )

        XCTAssertEqual(
            asset.logoURL?.absoluteString,
            "https://s2.coinmarketcap.com/static/img/coins/64x64/1.png"
        )
        XCTAssertNil(Asset.coinMarketCapLogoURL(for: "bitcoin"))
    }
}
