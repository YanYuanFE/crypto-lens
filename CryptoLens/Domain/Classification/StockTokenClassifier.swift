import Foundation
import OSLog

protocol StockTokenClassifying: Sendable {
    var isAvailable: Bool { get }
    func kind(for asset: Asset) -> AssetKind
}

extension StockTokenClassifying {
    var isAvailable: Bool { true }
}

struct CuratedStockTokenClassifier: StockTokenClassifying {
    let isAvailable: Bool
    private let coinGeckoIDs: Set<String>
    private let contracts: Set<String>

    init(catalog: CuratedStockTokenCatalog) {
        self.init(
            isAvailable: true,
            coinGeckoIDs: Set(catalog.entries.map { $0.coinGeckoId.lowercased() }),
            contracts: Set(catalog.entries.compactMap { entry in
            guard let platform = entry.platform, let address = entry.contractAddress else { return nil }
            return "\(platform.lowercased()):\(address.lowercased())"
            })
        )
    }

    init(bundle: Bundle = .main) {
        do {
            self.init(catalog: try CuratedStockTokenCatalog.load(bundle: bundle))
        } catch {
            Logger(subsystem: "app.cryptolens", category: "classification")
                .fault("Curated stock-token catalog unavailable: \(error.localizedDescription, privacy: .public)")
            self.init(isAvailable: false, coinGeckoIDs: [], contracts: [])
        }
    }

    private init(isAvailable: Bool, coinGeckoIDs: Set<String>, contracts: Set<String>) {
        self.isAvailable = isAvailable
        self.coinGeckoIDs = coinGeckoIDs
        self.contracts = contracts
    }

    func kind(for asset: Asset) -> AssetKind {
        if coinGeckoIDs.contains(asset.assetID.rawValue.lowercased()) { return .stockToken }
        if let platform = asset.platform, let address = asset.contractAddress,
           contracts.contains("\(platform.lowercased()):\(address.lowercased())") {
            return .stockToken
        }
        return .crypto
    }
}

struct CuratedStockTokenCatalog: Codable, Sendable {
    let version: Int
    let updatedAt: String
    let entries: [Entry]

    struct Entry: Codable, Sendable {
        let coinGeckoId: String
        let symbol: String
        let name: String
        let issuer: Issuer
        let platform: String?
        let contractAddress: String?
        let verification: Verification
        let notes: String?
    }

    enum Issuer: String, Codable, Sendable {
        case backed, ondo, other
    }

    struct Verification: Codable, Sendable {
        let verifiedAt: String
        let coinGeckoURL: URL
        let issuerURL: URL
    }

    static func load(bundle: Bundle) throws -> CuratedStockTokenCatalog {
        guard let url = bundle.url(forResource: "CuratedStockTokens", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(CuratedStockTokenCatalog.self, from: Data(contentsOf: url))
    }
}
