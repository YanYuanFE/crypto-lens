import Foundation

actor RequestRateLimiter {
    private let defaultMinimumInterval: TimeInterval
    private let clock = ContinuousClock()
    private var lastRequestAt: ContinuousClock.Instant?
    private(set) var nextAllowedRequestAt: Date?

    init(minimumInterval: Duration) {
        self.defaultMinimumInterval = minimumInterval.timeInterval
    }

    func acquire(minimumInterval: Duration? = nil) async throws {
        try Task.checkCancellation()

        if let deadline = nextAllowedRequestAt, deadline > Date() {
            throw NetworkError.rateLimited(retryAfter: deadline.timeIntervalSinceNow)
        }
        nextAllowedRequestAt = nil

        if let lastRequestAt {
            let interval = minimumInterval?.timeInterval ?? defaultMinimumInterval
            let deadline = lastRequestAt.advanced(by: .seconds(interval))
            if deadline > clock.now {
                try await clock.sleep(until: deadline)
            }
        }

        try Task.checkCancellation()
        lastRequestAt = clock.now
    }

    func block(for interval: TimeInterval) {
        let proposed = Date().addingTimeInterval(max(0, interval))
        if nextAllowedRequestAt == nil || proposed > nextAllowedRequestAt! {
            nextAllowedRequestAt = proposed
        }
    }

    func reset() {
        lastRequestAt = nil
        nextAllowedRequestAt = nil
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
