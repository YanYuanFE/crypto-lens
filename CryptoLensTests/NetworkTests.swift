import Foundation
import XCTest
@testable import CryptoLens

final class NetworkTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testMissingKeyUsesCMCPublicAPIWithoutAuthenticationHeader() async throws {
        let client = makeClient(key: nil)
        URLProtocolStub.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "X-CMC_PRO_API_KEY"))
            XCTAssertEqual(request.url?.path, "/public-api/v1/cryptocurrency/map")
            return Self.response(request, status: 200, body: Self.mapBody)
        }

        let results = try await client.search(query: "bit")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].asset.assetID, AssetID(rawValue: "1", source: .coinMarketCap))
        XCTAssertEqual(results[0].marketCapRank, 1)
    }

    func testSearchUsesCMCHeaderAndKeyedBase() async throws {
        let client = makeClient(key: "cmc-secret")
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-CMC_PRO_API_KEY"), "cmc-secret")
            XCTAssertEqual(request.url?.path, "/v1/cryptocurrency/map")
            return Self.response(request, status: 200, body: Self.mapBody)
        }

        let results = try await client.search(query: "BTC")

        XCTAssertEqual(results.map(\.asset.symbol), ["BTC"])
    }

    func testPricesUseCMCSimplePriceAndTreatMissingIDsAsSoftMiss() async throws {
        let client = makeClient(key: "cmc-secret")
        URLProtocolStub.handler = { request in
            let query = try Self.queryItems(in: request)
            XCTAssertEqual(request.url?.path, "/v1/simple/price")
            XCTAssertEqual(query["ids"], "1,1027")
            XCTAssertEqual(query["include_percent_change_24h"], "true")
            XCTAssertEqual(query["include_last_updated"], "true")
            return Self.response(request, status: 200, body: Self.priceBody)
        }
        let assets = [
            Self.asset(id: "1", source: .coinMarketCap, symbol: "BTC", name: "Bitcoin"),
            Self.asset(id: "1027", source: .coinMarketCap, symbol: "ETH", name: "Ethereum")
        ]

        let quotes = try await client.prices(for: assets, currency: "usd")

        XCTAssertEqual(quotes.count, 1)
        XCTAssertEqual(quotes[0].assetID, assets[0].assetID)
        XCTAssertEqual(quotes[0].price, Decimal(string: "68000.25"))
        XCTAssertEqual(quotes[0].change24hPercent, Decimal(string: "2.5"))
        XCTAssertEqual(quotes[0].source, .coinMarketCap)
        XCTAssertNotNil(quotes[0].lastUpdatedAt)
    }

    func testLegacyCoinGeckoSlugResolvesThroughCMCMap() async throws {
        let client = makeClient(key: "cmc-secret")
        let recorder = RequestRecorder()
        URLProtocolStub.handler = { request in
            recorder.record(request)
            if request.url?.path == "/v1/cryptocurrency/map" {
                return Self.response(request, status: 200, body: Self.mapBody)
            }
            XCTAssertEqual(try Self.queryItems(in: request)["ids"], "1")
            return Self.response(request, status: 200, body: Self.priceBody)
        }
        let legacy = Self.asset(id: "bitcoin", source: .coinGecko, symbol: "BTC", name: "Bitcoin")

        let quotes = try await client.prices(for: [legacy], currency: "usd")

        XCTAssertEqual(quotes.first?.assetID, legacy.assetID)
        XCTAssertEqual(recorder.paths, ["/v1/cryptocurrency/map", "/v1/simple/price"])
    }

    func testLegacyLongTailAssetFallsBackToExactSymbolMap() async throws {
        let client = makeClient(key: "cmc-secret")
        let recorder = RequestRecorder()
        URLProtocolStub.handler = { request in
            recorder.record(request)
            if recorder.count == 1 {
                return Self.response(request, status: 200, body: Self.mapBody)
            }
            if recorder.count == 2 {
                XCTAssertEqual(try Self.queryItems(in: request)["symbol"], "AAPLON")
                let body = #"{"data":[{"id":99999,"rank":null,"name":"Apple (Ondo Tokenized Stock)","symbol":"AAPLON","slug":"apple-ondo","platform":null}],"status":{}}"#
                return Self.response(request, status: 200, body: body)
            }
            XCTAssertEqual(try Self.queryItems(in: request)["ids"], "99999")
            let body = #"{"data":[{"id":99999,"price":212.5}],"status":{}}"#
            return Self.response(request, status: 200, body: body)
        }
        let legacy = Self.asset(
            id: "apple-ondo-tokenized-stock",
            source: .coinGecko,
            symbol: "AAPLON",
            name: "Apple (Ondo Tokenized Stock)"
        )

        let quotes = try await client.prices(for: [legacy], currency: "usd")

        XCTAssertEqual(quotes.first?.assetID, legacy.assetID)
        XCTAssertEqual(quotes.first?.price, Decimal(string: "212.5"))
        XCTAssertEqual(
            recorder.paths,
            ["/v1/cryptocurrency/map", "/v1/cryptocurrency/map", "/v1/simple/price"]
        )
    }

    func testRateLimitMapsRetryAfterAndClosesSharedGate() async {
        let client = makeClient(key: "cmc-secret")
        URLProtocolStub.handler = { request in
            Self.response(request, status: 429, body: "{}", headers: ["Retry-After": "12"])
        }

        await XCTAssertThrowsErrorAsync(try await client.search(query: "bit")) { error in
            guard case let NetworkError.rateLimited(retryAfter) = error else {
                return XCTFail("Expected rateLimited, got \(error)")
            }
            XCTAssertEqual(retryAfter, 12)
        }

        let deadline = await client.nextAllowedRequestAt
        XCTAssertGreaterThan(try! XCTUnwrap(deadline), Date().addingTimeInterval(10))
    }

    func testRateLimitGateAppliesAcrossSearchAndPriceWithoutAutomaticRetry() async {
        let client = makeClient(key: nil)
        let recorder = RequestRecorder()
        URLProtocolStub.handler = { request in
            recorder.record(request)
            return Self.response(request, status: 429, body: "{}", headers: ["Retry-After": "60"])
        }

        await XCTAssertThrowsErrorAsync(try await client.search(query: "bit")) { error in
            guard case NetworkError.rateLimited = error else {
                return XCTFail("Expected rateLimited, got \(error)")
            }
        }
        await XCTAssertThrowsErrorAsync(
            try await client.prices(
                for: [Self.asset(id: "1", source: .coinMarketCap, symbol: "BTC", name: "Bitcoin")],
                currency: "usd"
            )
        ) { error in
            guard case NetworkError.rateLimited = error else {
                return XCTFail("Expected shared rateLimited gate, got \(error)")
            }
        }

        XCTAssertEqual(recorder.count, 1)
    }

    func testRateLimiterEnforcesMinimumIntervalAndWaitIsCancellable() async throws {
        let limiter = RequestRateLimiter(minimumInterval: .milliseconds(100))
        try await limiter.acquire()
        let startedAt = Date()
        try await limiter.acquire()
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(startedAt), 0.08)

        let slowLimiter = RequestRateLimiter(minimumInterval: .seconds(1))
        try await slowLimiter.acquire()
        let waitingTask = Task { try await slowLimiter.acquire() }
        try await Task.sleep(for: .milliseconds(20))
        waitingTask.cancel()
        await XCTAssertThrowsErrorAsync(try await waitingTask.value) { error in
            XCTAssertTrue(error is CancellationError)
        }

        let dynamicLimiter = RequestRateLimiter(minimumInterval: .zero)
        try await dynamicLimiter.acquire()
        let dynamicStartedAt = Date()
        try await dynamicLimiter.acquire(minimumInterval: .milliseconds(100))
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(dynamicStartedAt), 0.08)
    }

    func testUnauthorizedStoredKeyFallsBackToCMCPublicAPIOnNextUserAction() async throws {
        let client = makeClient(key: "expired-key")
        let recorder = RequestRecorder()
        URLProtocolStub.handler = { request in
            recorder.record(request)
            if recorder.count == 1 {
                return Self.response(request, status: 401, body: "{}")
            }
            return Self.response(request, status: 200, body: Self.mapBody)
        }

        await XCTAssertThrowsErrorAsync(try await client.search(query: "bit")) { error in
            XCTAssertEqual(error as? NetworkError, .unauthorized)
        }
        let results = try await client.search(query: "eth")

        XCTAssertEqual(results.map(\.asset.symbol), ["ETH"])
        XCTAssertEqual(recorder.apiKeys, ["expired-key", nil])
        XCTAssertEqual(recorder.paths, ["/v1/cryptocurrency/map", "/public-api/v1/cryptocurrency/map"])
    }

    func testCandidateValidationUsesExplicitCMCKeyAndBitcoinID() async throws {
        let client = makeClient(key: "stored-key")
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-CMC_PRO_API_KEY"), "candidate-key")
            XCTAssertEqual(request.url?.path, "/v1/simple/price")
            XCTAssertEqual(try Self.queryItems(in: request)["ids"], "1")
            return Self.response(request, status: 200, body: Self.priceBody)
        }

        try await client.validate(candidateKey: "candidate-key")

        URLProtocolStub.handler = { request in
            Self.response(request, status: 200, body: #"{"data":[],"status":{}}"#)
        }
        await XCTAssertThrowsErrorAsync(try await client.validate(candidateKey: "candidate-key")) { error in
            guard case NetworkError.decoding = error else {
                return XCTFail("Expected decoding failure, got \(error)")
            }
        }
    }

    func testUnauthorizedCandidateDoesNotDisableStoredCMCKey() async throws {
        let client = makeClient(key: "stored-key")
        let recorder = RequestRecorder()
        URLProtocolStub.handler = { request in
            recorder.record(request)
            if recorder.count == 1 {
                return Self.response(request, status: 401, body: "{}")
            }
            return Self.response(request, status: 200, body: Self.mapBody)
        }

        await XCTAssertThrowsErrorAsync(try await client.validate(candidateKey: "bad-candidate")) { error in
            XCTAssertEqual(error as? NetworkError, .unauthorized)
        }
        _ = try await client.search(query: "bit")

        XCTAssertEqual(recorder.apiKeys, ["bad-candidate", "stored-key"])
    }

    func testResetNetworkStateClearsRateLimitGate() async throws {
        let client = makeClient(key: "cmc-secret")
        URLProtocolStub.handler = { request in
            Self.response(request, status: 429, body: "{}", headers: ["Retry-After": "60"])
        }
        await XCTAssertThrowsErrorAsync(try await client.search(query: "bit")) { _ in }

        await client.resetNetworkState()
        URLProtocolStub.handler = { request in
            Self.response(request, status: 200, body: Self.mapBody)
        }

        let results = try await client.search(query: "bit")
        XCTAssertEqual(results.map(\.asset.symbol), ["BTC"])
        let deadline = await client.nextAllowedRequestAt
        XCTAssertNil(deadline)
    }

    private func makeClient(key: String?) -> CoinMarketCapClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return CoinMarketCapClient(
            apiKeyStore: MemoryAPIKeyStore(key: key),
            session: URLSession(configuration: configuration),
            rateLimiter: RequestRateLimiter(minimumInterval: .zero),
            configuration: CMCAPIConfiguration(
                keyedBaseURL: URL(string: "https://pro-api.coinmarketcap.com")!,
                keylessBaseURL: URL(string: "https://pro-api.coinmarketcap.com/public-api")!,
                apiKeyHeaderName: "X-CMC_PRO_API_KEY",
                keylessMinimumRequestInterval: .zero,
                authenticatedMinimumRequestInterval: .zero
            )
        )
    }

    private static let mapBody = #"{"data":[{"id":1,"rank":1,"name":"Bitcoin","symbol":"BTC","slug":"bitcoin","platform":null},{"id":1027,"rank":2,"name":"Ethereum","symbol":"ETH","slug":"ethereum","platform":null}],"status":{}}"#
    private static let priceBody = #"{"data":[{"id":1,"price":68000.25,"percent_change_24h":2.5,"last_updated":"2026-07-11T01:00:00.000Z"}],"status":{}}"#

    private static func asset(id: String, source: PriceSource, symbol: String, name: String) -> Asset {
        Asset(
            assetID: AssetID(rawValue: id, source: source),
            symbol: symbol,
            name: name,
            kind: .crypto,
            platform: nil,
            contractAddress: nil
        )
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        body: String,
        headers: [String: String] = [:]
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
        return (response, Data(body.utf8))
    }

    private static func queryItems(in request: URLRequest) throws -> [String: String] {
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }
}

private final class MemoryAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private let key: String?

    init(key: String?) { self.key = key }
    func loadAPIKey() throws -> String? { key }
    func saveAPIKey(_ key: String) throws {}
    func deleteAPIKey() throws {}
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    var count: Int { lock.withLock { requests.count } }
    var apiKeys: [String?] {
        lock.withLock { requests.map { $0.value(forHTTPHeaderField: "X-CMC_PRO_API_KEY") } }
    }
    var paths: [String] { lock.withLock { requests.compactMap(\.url?.path) } }

    func record(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }
}

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error")
    } catch {
        errorHandler(error)
    }
}
