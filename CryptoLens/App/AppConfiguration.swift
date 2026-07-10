import Foundation

struct AppConfiguration: Sendable, Equatable {
    let quoteCurrency: String
    let openRefreshDebounce: Duration
    let manualRefreshCooldown: Duration
    let demoMinimumRequestInterval: Duration
    let maxWatchlistCount: Int

    static let v1 = AppConfiguration(
        quoteCurrency: "usd",
        openRefreshDebounce: .milliseconds(200),
        manualRefreshCooldown: .seconds(60),
        demoMinimumRequestInterval: .milliseconds(750),
        maxWatchlistCount: 50
    )
}
