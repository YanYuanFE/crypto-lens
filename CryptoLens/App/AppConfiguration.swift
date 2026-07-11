import Foundation

struct AppConfiguration: Sendable, Equatable {
    let quoteCurrency: String
    let openRefreshDebounce: Duration
    let manualRefreshCooldown: Duration
    let keylessMinimumRequestInterval: Duration
    let authenticatedMinimumRequestInterval: Duration
    let staleTimelineInterval: Duration
    let shutdownDrainTimeout: Duration
    let maxWatchlistCount: Int

    static let v1 = AppConfiguration(
        quoteCurrency: "usd",
        openRefreshDebounce: .milliseconds(200),
        manualRefreshCooldown: .seconds(60),
        keylessMinimumRequestInterval: .seconds(3),
        authenticatedMinimumRequestInterval: .seconds(1),
        staleTimelineInterval: .seconds(30),
        shutdownDrainTimeout: .seconds(2),
        maxWatchlistCount: 50
    )
}
