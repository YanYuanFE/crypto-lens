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

    let assetID: AssetID
    let symbol: String
    let name: String
    let kind: AssetKind
    let platform: String?
    let contractAddress: String?
}

struct SearchResult: Identifiable, Hashable, Sendable {
    var id: AssetID { asset.assetID }

    let asset: Asset
    let marketCapRank: Int?
    let thumbURL: URL?
}
