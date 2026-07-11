import Foundation

protocol NetworkStateProviding: Sendable {
    var nextAllowedRequestAt: Date? { get async }
    func resetNetworkState() async
}

struct CMCAPIConfiguration: Sendable {
    let keyedBaseURL: URL
    let keylessBaseURL: URL
    let apiKeyHeaderName: String
    let keylessMinimumRequestInterval: Duration
    let authenticatedMinimumRequestInterval: Duration

    static let v1 = CMCAPIConfiguration(
        keyedBaseURL: URL(string: "https://pro-api.coinmarketcap.com")!,
        keylessBaseURL: URL(string: "https://pro-api.coinmarketcap.com/public-api")!,
        apiKeyHeaderName: "X-CMC_PRO_API_KEY",
        keylessMinimumRequestInterval: AppConfiguration.v1.keylessMinimumRequestInterval,
        authenticatedMinimumRequestInterval: AppConfiguration.v1.authenticatedMinimumRequestInterval
    )
}

actor CoinMarketCapClient: AssetSearching, PriceProviding, NetworkStateProviding {
    private let apiKeyStore: any APIKeyStoring
    private let session: URLSession
    private let rateLimiter: RequestRateLimiter
    private let configuration: CMCAPIConfiguration
    private var storedKeyIsDisabled = false
    private var cachedMap: [CMCMapAsset]?

    init(
        apiKeyStore: any APIKeyStoring,
        session: URLSession = .shared,
        rateLimiter: RequestRateLimiter = RequestRateLimiter(
            minimumInterval: AppConfiguration.v1.keylessMinimumRequestInterval
        ),
        configuration: CMCAPIConfiguration = .v1
    ) {
        self.apiKeyStore = apiKeyStore
        self.session = session
        self.rateLimiter = rateLimiter
        self.configuration = configuration
    }

    var nextAllowedRequestAt: Date? {
        get async { await rateLimiter.nextAllowedRequestAt }
    }

    func resetNetworkState() async {
        storedKeyIsDisabled = false
        await rateLimiter.reset()
    }

    func search(query: String) async throws -> [SearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return [] }

        var assets = try await cryptocurrencyMap()
        var matches = Self.matches(in: assets, query: normalized)
        if matches.isEmpty, normalized.count <= 16, !normalized.contains(where: \Character.isWhitespace) {
            let exact = try await mapAssets(symbol: normalized.uppercased(), ignoresMissingSymbol: true)
            if !exact.isEmpty {
                let knownIDs = Set(assets.map(\.id))
                assets.append(contentsOf: exact.filter { !knownIDs.contains($0.id) })
                cachedMap = assets
                matches = Self.matches(in: assets, query: normalized)
            }
        }

        return matches.map { item in
            SearchResult(
                asset: Asset(
                    assetID: AssetID(rawValue: String(item.id), source: .coinMarketCap),
                    symbol: item.symbol.uppercased(),
                    name: item.name,
                    kind: .crypto,
                    platform: item.platform?.slug,
                    contractAddress: item.platform?.tokenAddress
                ),
                marketCapRank: item.rank,
                thumbURL: nil
            )
        }
    }

    func prices(for assets: [Asset], currency: String) async throws -> [PriceQuote] {
        guard !assets.isEmpty else { return [] }
        guard currency.lowercased() == "usd" else {
            throw NetworkError.clientError(status: 400)
        }

        let resolved = try await resolvedCMCIDs(for: assets)
        guard !resolved.isEmpty else { return [] }
        let data = try await request(
            path: "v1/simple/price",
            queryItems: [
                URLQueryItem(name: "ids", value: resolved.keys.sorted().joined(separator: ",")),
                URLQueryItem(name: "include_percent_change_24h", value: "true"),
                URLQueryItem(name: "include_last_updated", value: "true")
            ]
        )

        do {
            let payload = try JSONDecoder().decode(CMCSimplePricePayload.self, from: data)
            let fetchedAt = Date()
            return payload.data.flatMap { item in
                resolved[String(item.id), default: []].map { assetID in
                    PriceQuote(
                        assetID: assetID,
                        currency: currency,
                        price: item.price,
                        change24hPercent: item.percentChange24h,
                        fetchedAt: fetchedAt,
                        lastUpdatedAt: item.lastUpdated.flatMap(Self.parseDate),
                        source: .coinMarketCap
                    )
                }
            }
            .sorted { $0.assetID.rawValue < $1.assetID.rawValue }
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.decoding(message: error.localizedDescription)
        }
    }

    func validate(candidateKey: String) async throws {
        let data = try await request(
            path: "v1/simple/price",
            queryItems: [URLQueryItem(name: "ids", value: "1")],
            explicitKey: candidateKey
        )
        do {
            let payload = try JSONDecoder().decode(CMCSimplePricePayload.self, from: data)
            guard payload.data.contains(where: { $0.id == 1 }) else {
                throw NetworkError.decoding(message: "Validation response is missing Bitcoin")
            }
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.decoding(message: error.localizedDescription)
        }
    }

    private func cryptocurrencyMap() async throws -> [CMCMapAsset] {
        if let cachedMap { return cachedMap }
        let assets = try await mapAssets(symbol: nil, ignoresMissingSymbol: false)
        cachedMap = assets
        return assets
    }

    private func mapAssets(symbol: String?, ignoresMissingSymbol: Bool) async throws -> [CMCMapAsset] {
        var queryItems = [
            URLQueryItem(name: "sort", value: "cmc_rank"),
            URLQueryItem(name: "aux", value: "platform")
        ]
        if let symbol {
            queryItems.append(URLQueryItem(name: "symbol", value: symbol))
        } else {
            queryItems.append(URLQueryItem(name: "limit", value: "5000"))
        }

        do {
            let data = try await request(path: "v1/cryptocurrency/map", queryItems: queryItems)
            return try JSONDecoder().decode(CMCMapPayload.self, from: data).data
        } catch NetworkError.clientError(status: 400) where ignoresMissingSymbol {
            return []
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.decoding(message: error.localizedDescription)
        }
    }

    private func resolvedCMCIDs(for assets: [Asset]) async throws -> [String: [AssetID]] {
        var resolved: [String: [AssetID]] = [:]
        let legacyAssets = assets.filter { $0.assetID.source == .coinGecko }
        var legacyBySlug: [String: CMCMapAsset] = [:]
        if !legacyAssets.isEmpty {
            for asset in try await cryptocurrencyMap() {
                legacyBySlug[asset.slug.lowercased()] = asset
            }
        }

        var unresolvedLegacy: [Asset] = []
        for asset in assets {
            let assetID = asset.assetID
            switch assetID.source {
            case .coinMarketCap:
                resolved[assetID.rawValue, default: []].append(assetID)
            case .coinGecko:
                if let match = legacyBySlug[assetID.rawValue.lowercased()] {
                    resolved[String(match.id), default: []].append(assetID)
                } else {
                    unresolvedLegacy.append(asset)
                }
            }
        }

        if !unresolvedLegacy.isEmpty {
            let symbols = Set(unresolvedLegacy.map { $0.symbol.uppercased() }).sorted()
            let candidates = try await mapAssets(
                symbol: symbols.joined(separator: ","),
                ignoresMissingSymbol: true
            )
            for asset in unresolvedLegacy {
                let match = candidates
                    .filter { $0.symbol.caseInsensitiveCompare(asset.symbol) == .orderedSame }
                    .min { ($0.rank ?? .max) < ($1.rank ?? .max) }
                if let match {
                    resolved[String(match.id), default: []].append(asset.assetID)
                }
            }
        }
        return resolved
    }

    private func request(
        path: String,
        queryItems: [URLQueryItem],
        explicitKey: String? = nil
    ) async throws -> Data {
        let isExplicitKey = explicitKey != nil
        let key: String?
        if let explicitKey {
            let candidate = explicitKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { throw NetworkError.missingAPIKey }
            key = candidate
        } else if storedKeyIsDisabled {
            key = nil
        } else {
            key = (try? apiKeyStore.loadAPIKey())?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }

        let minimumInterval = key == nil
            ? configuration.keylessMinimumRequestInterval
            : configuration.authenticatedMinimumRequestInterval
        try await rateLimiter.acquire(minimumInterval: minimumInterval)
        try Task.checkCancellation()

        let baseURL = key == nil ? configuration.keylessBaseURL : configuration.keyedBaseURL
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        if let key {
            request.setValue(key, forHTTPHeaderField: configuration.apiKeyHeaderName)
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.unknown(message: "Non-HTTP response")
            }
            return try await validate(response: httpResponse, data: data)
        } catch is CancellationError {
            throw NetworkError.cancelled
        } catch let error as NetworkError {
            if error == .unauthorized, !isExplicitKey, key != nil {
                storedKeyIsDisabled = true
            }
            throw error
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw NetworkError.timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                throw NetworkError.offline(error)
            case .cancelled:
                throw NetworkError.cancelled
            default:
                throw NetworkError.unknown(message: error.localizedDescription)
            }
        } catch {
            throw NetworkError.unknown(message: error.localizedDescription)
        }
    }

    private func validate(response: HTTPURLResponse, data: Data) async throws -> Data {
        switch response.statusCode {
        case 200..<300:
            return data
        case 401:
            throw NetworkError.unauthorized
        case 429:
            let retryAfter = Self.retryAfter(from: response)
            await rateLimiter.block(for: retryAfter ?? 60)
            throw NetworkError.rateLimited(retryAfter: retryAfter)
        case 400..<500:
            throw NetworkError.clientError(status: response.statusCode)
        case 500..<600:
            throw NetworkError.serverError(status: response.statusCode)
        default:
            throw NetworkError.unknown(message: "HTTP \(response.statusCode)")
        }
    }

    private static func matches(in assets: [CMCMapAsset], query: String) -> [CMCMapAsset] {
        assets.filter {
            $0.symbol.lowercased().contains(query)
                || $0.name.lowercased().contains(query)
                || $0.slug.lowercased().contains(query)
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(value)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private struct CMCMapPayload: Decodable {
    let data: [CMCMapAsset]
}

private struct CMCMapAsset: Decodable {
    let id: Int
    let rank: Int?
    let name: String
    let symbol: String
    let slug: String
    let platform: CMCPlatform?
}

private struct CMCPlatform: Decodable {
    let slug: String?
    let tokenAddress: String?

    enum CodingKeys: String, CodingKey {
        case slug
        case tokenAddress = "token_address"
    }
}

private struct CMCSimplePricePayload: Decodable {
    let data: [CMCSimplePrice]
}

private struct CMCSimplePrice: Decodable {
    let id: Int
    let price: Decimal
    let percentChange24h: Decimal?
    let lastUpdated: String?

    enum CodingKeys: String, CodingKey {
        case id, price
        case percentChange24h = "percent_change_24h"
        case lastUpdated = "last_updated"
    }
}
