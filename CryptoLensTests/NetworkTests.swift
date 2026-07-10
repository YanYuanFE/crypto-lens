import Foundation
import XCTest
@testable import CryptoLens

final class NetworkTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testMissingKeyDoesNotCreateHTTPRequest() async {
        let client = makeClient(key: nil)
        URLProtocolStub.handler = { _ in
            XCTFail("Missing key must not send HTTP")
            throw URLError(.badServerResponse)
        }

        await XCTAssertThrowsErrorAsync(try await client.search(query: "bit")) { error in
            XCTAssertEqual(error as? NetworkError, .missingAPIKey)
        }
    }

    func testSearchUsesDemoHeaderAndDecodesResults() async throws {
        let client = makeClient(key: "demo-secret")
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-cg-demo-api-key"), "demo-secret")
            XCTAssertEqual(request.url?.path, "/api/v3/search")
            XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "bit")
            return Self.response(
                request,
                status: 200,
                body: #"{"coins":[{"id":"bitcoin","name":"Bitcoin","symbol":"btc","market_cap_rank":1,"thumb":"https://example.com/btc.png"}]}"#
            )
        }

        let results = try await client.search(query: "bit")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].asset.assetID.rawValue, "bitcoin")
        XCTAssertEqual(results[0].marketCapRank, 1)
    }

    func testPricesTreatMissingIDsAsSoftMiss() async throws {
        let client = makeClient(key: "demo-secret")
        URLProtocolStub.handler = { request in
            Self.response(
                request,
                status: 200,
                body: #"{"bitcoin":{"usd":68000.25,"usd_24h_change":2.5,"last_updated_at":1720000000}}"#
            )
        }
        let ids = ["bitcoin", "ethereum"].map { AssetID(rawValue: $0, source: .coinGecko) }

        let quotes = try await client.prices(for: ids, currency: "usd")

        XCTAssertEqual(quotes.count, 1)
        XCTAssertEqual(quotes[0].assetID, ids[0])
        XCTAssertEqual(quotes[0].price, Decimal(string: "68000.25"))
    }

    func testRateLimitMapsRetryAfterAndClosesSharedGate() async {
        let client = makeClient(key: "demo-secret")
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

    private func makeClient(key: String?) -> CoinGeckoClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return CoinGeckoClient(
            apiKeyStore: MemoryAPIKeyStore(key: key),
            session: URLSession(configuration: configuration),
            rateLimiter: RequestRateLimiter(minimumInterval: .zero)
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
}

private final class MemoryAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private let key: String?

    init(key: String?) { self.key = key }
    func loadDemoKey() throws -> String? { key }
    func saveDemoKey(_ key: String) throws {}
    func deleteDemoKey() throws {}
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
