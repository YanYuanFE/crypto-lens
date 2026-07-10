import Foundation

struct PriceQuote: Hashable, Codable, Sendable {
    let assetID: AssetID
    let currency: String
    let price: Decimal
    let change24hPercent: Decimal?
    let fetchedAt: Date
    let lastUpdatedAt: Date?
    let source: PriceSource

    private enum CodingKeys: String, CodingKey {
        case assetID
        case currency
        case price
        case change24hPercent
        case fetchedAt
        case lastUpdatedAt
        case source
    }

    init(
        assetID: AssetID,
        currency: String,
        price: Decimal,
        change24hPercent: Decimal?,
        fetchedAt: Date,
        lastUpdatedAt: Date?,
        source: PriceSource
    ) {
        self.assetID = assetID
        self.currency = currency
        self.price = price
        self.change24hPercent = change24hPercent
        self.fetchedAt = fetchedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assetID = try container.decode(AssetID.self, forKey: .assetID)
        currency = try container.decode(String.self, forKey: .currency)
        price = try Self.decodeDecimal(from: container, forKey: .price)
        change24hPercent = try Self.decodeOptionalDecimal(from: container, forKey: .change24hPercent)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)
        source = try container.decode(PriceSource.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(assetID, forKey: .assetID)
        try container.encode(currency, forKey: .currency)
        try container.encode(Self.string(from: price), forKey: .price)
        try container.encodeIfPresent(change24hPercent.map(Self.string(from:)), forKey: .change24hPercent)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encodeIfPresent(lastUpdatedAt, forKey: .lastUpdatedAt)
        try container.encode(source, forKey: .source)
    }

    private static func string(from value: Decimal) -> String {
        var value = value
        return NSDecimalString(&value, Locale(identifier: "en_US_POSIX"))
    }

    private static func decodeDecimal(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Decimal {
        let string = try container.decode(String.self, forKey: key)
        guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Invalid decimal string: \(string)"
            )
        }
        return value
    }

    private static func decodeOptionalDecimal(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Decimal? {
        guard container.contains(key), try !container.decodeNil(forKey: key) else { return nil }
        return try decodeDecimal(from: container, forKey: key)
    }
}
