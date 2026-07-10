import Foundation

protocol NetworkStateProviding: Sendable {
    var nextAllowedRequestAt: Date? { get async }
    func resetNetworkState() async
}

struct APIConfiguration: Sendable {
    let baseURL: URL
    let apiKeyHeaderName: String

    static let demo = APIConfiguration(
        baseURL: URL(string: "https://api.coingecko.com/api/v3")!,
        apiKeyHeaderName: "x-cg-demo-api-key"
    )
}

actor CoinGeckoClient: AssetSearching, PriceProviding, NetworkStateProviding {
    private let apiKeyStore: any APIKeyStoring
    private let session: URLSession
    private let rateLimiter: RequestRateLimiter
    private let configuration: APIConfiguration

    init(
        apiKeyStore: any APIKeyStoring,
        session: URLSession = .shared,
        rateLimiter: RequestRateLimiter = RequestRateLimiter(
            minimumInterval: AppConfiguration.v1.demoMinimumRequestInterval
        ),
        configuration: APIConfiguration = .demo
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
        await rateLimiter.reset()
    }

    func search(query: String) async throws -> [SearchResult] {
        let data = try await request(path: "search", queryItems: [URLQueryItem(name: "query", value: query)])
        do {
            let payload = try JSONDecoder().decode(SearchPayload.self, from: data)
            return payload.coins.map { coin in
                SearchResult(
                    asset: Asset(
                        assetID: AssetID(rawValue: coin.id, source: .coinGecko),
                        symbol: coin.symbol.uppercased(),
                        name: coin.name,
                        kind: .crypto,
                        platform: nil,
                        contractAddress: nil
                    ),
                    marketCapRank: coin.marketCapRank,
                    thumbURL: coin.thumb.flatMap(Self.secureURL(from:))
                )
            }
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.decoding(message: error.localizedDescription)
        }
    }

    func prices(for ids: [AssetID], currency: String) async throws -> [PriceQuote] {
        guard !ids.isEmpty else { return [] }
        let requested = Dictionary(uniqueKeysWithValues: ids.map { ($0.rawValue, $0) })
        let data = try await request(
            path: "simple/price",
            queryItems: [
                URLQueryItem(name: "ids", value: ids.map(\.rawValue).joined(separator: ",")),
                URLQueryItem(name: "vs_currencies", value: currency),
                URLQueryItem(name: "include_24hr_change", value: "true"),
                URLQueryItem(name: "include_last_updated_at", value: "true")
            ]
        )

        do {
            let payload = try JSONDecoder().decode([String: [String: Decimal]].self, from: data)
            let fetchedAt = Date()
            return payload.compactMap { rawID, values in
                guard let assetID = requested[rawID], let price = values[currency] else { return nil }
                let timestamp = values["last_updated_at"].map { NSDecimalNumber(decimal: $0).doubleValue }
                return PriceQuote(
                    assetID: assetID,
                    currency: currency,
                    price: price,
                    change24hPercent: values["\(currency)_24h_change"],
                    fetchedAt: fetchedAt,
                    lastUpdatedAt: timestamp.map(Date.init(timeIntervalSince1970:)),
                    source: .coinGecko
                )
            }
            .sorted { $0.assetID.rawValue < $1.assetID.rawValue }
        } catch {
            throw NetworkError.decoding(message: error.localizedDescription)
        }
    }

    func validate(candidateKey: String) async throws {
        let bitcoin = AssetID(rawValue: "bitcoin", source: .coinGecko)
        let data = try await request(
            path: "simple/price",
            queryItems: [
                URLQueryItem(name: "ids", value: bitcoin.rawValue),
                URLQueryItem(name: "vs_currencies", value: "usd")
            ],
            explicitKey: candidateKey
        )
        do {
            let payload = try JSONDecoder().decode([String: [String: Decimal]].self, from: data)
            guard payload[bitcoin.rawValue]?["usd"] != nil else {
                throw NetworkError.decoding(message: "Validation response is missing bitcoin.usd")
            }
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.decoding(message: error.localizedDescription)
        }
    }

    private func request(
        path: String,
        queryItems: [URLQueryItem],
        explicitKey: String? = nil
    ) async throws -> Data {
        let key = try explicitKey ?? apiKeyStore.loadDemoKey()
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkError.missingAPIKey
        }

        try await rateLimiter.acquire()
        try Task.checkCancellation()

        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: configuration.apiKeyHeaderName)
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
            await rateLimiter.block(for: retryAfter ?? 300)
            throw NetworkError.rateLimited(retryAfter: retryAfter)
        case 403 where String(decoding: data, as: UTF8.self).contains("1020"):
            await rateLimiter.block(for: 300)
            throw NetworkError.rateLimited(retryAfter: nil)
        case 400..<500:
            throw NetworkError.clientError(status: response.statusCode)
        case 500..<600:
            throw NetworkError.serverError(status: response.statusCode)
        default:
            throw NetworkError.unknown(message: "HTTP \(response.statusCode)")
        }
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(value)
    }

    private static func secureURL(from string: String) -> URL? {
        guard let url = URL(string: string), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }
}

private struct SearchPayload: Decodable {
    let coins: [SearchCoin]
}

private struct SearchCoin: Decodable {
    let id: String
    let name: String
    let symbol: String
    let marketCapRank: Int?
    let thumb: String?

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, thumb
        case marketCapRank = "market_cap_rank"
    }
}
