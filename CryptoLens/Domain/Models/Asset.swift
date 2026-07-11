import Foundation

enum PriceSource: String, Codable, Sendable {
    case coinGecko
    case coinMarketCap
}

enum AssetKind: String, Codable, Sendable {
    case crypto
    case stockToken
}

struct AssetID: Hashable, Codable, Sendable {
    let rawValue: String
    let source: PriceSource
}

struct Asset: Identifiable, Hashable, Codable, Sendable {
    var id: AssetID { assetID }
    var logoURL: URL? {
        guard assetID.source == .coinMarketCap else { return nil }
        return Self.coinMarketCapLogoURL(for: assetID.rawValue)
    }

    let assetID: AssetID
    let symbol: String
    let name: String
    let kind: AssetKind
    let platform: String?
    let contractAddress: String?

    static func coinMarketCapLogoURL(for rawID: String) -> URL? {
        guard !rawID.isEmpty, rawID.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://s2.coinmarketcap.com/static/img/coins/64x64/\(rawID).png")
    }
}

struct SearchResult: Identifiable, Hashable, Sendable {
    var id: AssetID { asset.assetID }

    let asset: Asset
    let marketCapRank: Int?
    let thumbURL: URL?
}
