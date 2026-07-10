import Foundation

enum NetworkError: Error, Equatable, Sendable {
    case missingAPIKey
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case clientError(status: Int)
    case serverError(status: Int)
    case offline(URLError)
    case timeout
    case decoding(message: String)
    case cancelled
    case unknown(message: String)

    static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.missingAPIKey, .missingAPIKey), (.unauthorized, .unauthorized),
             (.timeout, .timeout), (.cancelled, .cancelled):
            true
        case let (.rateLimited(a), .rateLimited(b)):
            a == b
        case let (.clientError(a), .clientError(b)), let (.serverError(a), .serverError(b)):
            a == b
        case let (.offline(a), .offline(b)):
            a.code == b.code
        case let (.decoding(a), .decoding(b)), let (.unknown(a), .unknown(b)):
            a == b
        default:
            false
        }
    }
}
