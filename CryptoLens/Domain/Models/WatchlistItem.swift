import Foundation

struct WatchlistItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var asset: Asset
    var sortOrder: Int
    var addedAt: Date
}

enum WatchlistMutationError: Error, Equatable {
    case duplicate(AssetID)
    case watchlistFull(max: Int)
}
