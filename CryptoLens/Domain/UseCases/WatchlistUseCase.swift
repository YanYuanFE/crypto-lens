import Foundation

enum WatchlistUseCaseError: Error, Equatable {
    case invalidOrder
    case itemNotFound(UUID)
}

struct RemovedWatchlistEntry: Sendable {
    let item: WatchlistItem
    let index: Int
}

actor WatchlistUseCase {
    private let store: any WatchlistStoring
    private let maximumCount: Int
    private var persistedSnapshot: [WatchlistItem] = []
    private var isBootstrapped = false
    private var mutationLocked = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []

    init(store: any WatchlistStoring, maximumCount: Int = AppConfiguration.v1.maxWatchlistCount) {
        self.store = store
        self.maximumCount = maximumCount
    }

    func bootstrap() async throws -> [WatchlistItem] {
        await acquireMutationLock()
        defer { releaseMutationLock() }
        if isBootstrapped { return persistedSnapshot }
        persistedSnapshot = try await store.load().normalizedSortOrder()
        isBootstrapped = true
        return persistedSnapshot
    }

    func snapshot() -> [WatchlistItem] {
        persistedSnapshot
    }

    @discardableResult
    func add(asset: Asset, at date: Date = Date()) async throws -> WatchlistItem {
        await acquireMutationLock()
        defer { releaseMutationLock() }

        if persistedSnapshot.contains(where: { $0.asset.assetID == asset.assetID }) {
            throw WatchlistMutationError.duplicate(asset.assetID)
        }
        guard persistedSnapshot.count < maximumCount else {
            throw WatchlistMutationError.watchlistFull(max: maximumCount)
        }

        let item = WatchlistItem(
            id: UUID(),
            asset: asset,
            sortOrder: persistedSnapshot.count,
            addedAt: date
        )
        let candidate = persistedSnapshot + [item]
        try await store.save(candidate)
        persistedSnapshot = candidate
        return item
    }

    @discardableResult
    func remove(id: UUID) async throws -> (item: WatchlistItem, index: Int) {
        await acquireMutationLock()
        defer { releaseMutationLock() }

        guard let index = persistedSnapshot.firstIndex(where: { $0.id == id }) else {
            throw WatchlistUseCaseError.itemNotFound(id)
        }
        let item = persistedSnapshot[index]
        var candidate = persistedSnapshot
        candidate.remove(at: index)
        candidate = candidate.normalizedSortOrder()
        try await store.save(candidate)
        persistedSnapshot = candidate
        return (item, index)
    }

    @discardableResult
    func reorder(assetIDs: [AssetID]) async throws -> [WatchlistItem] {
        await acquireMutationLock()
        defer { releaseMutationLock() }

        let currentIDs = persistedSnapshot.map(\.asset.assetID)
        guard assetIDs.count == currentIDs.count,
              Set(assetIDs) == Set(currentIDs) else {
            throw WatchlistUseCaseError.invalidOrder
        }
        let itemsByID = Dictionary(uniqueKeysWithValues: persistedSnapshot.map { ($0.asset.assetID, $0) })
        let candidate = assetIDs.compactMap { itemsByID[$0] }.normalizedSortOrder()
        try await store.save(candidate)
        persistedSnapshot = candidate
        return candidate
    }

    @discardableResult
    func restore(_ removedEntries: [RemovedWatchlistEntry]) async throws -> [WatchlistItem] {
        await acquireMutationLock()
        defer { releaseMutationLock() }

        var candidate = persistedSnapshot
        for entry in removedEntries.reversed() {
            guard !candidate.contains(where: { $0.id == entry.item.id || $0.asset.assetID == entry.item.asset.assetID }) else {
                continue
            }
            guard candidate.count < maximumCount else {
                throw WatchlistMutationError.watchlistFull(max: maximumCount)
            }
            candidate.insert(entry.item, at: min(max(0, entry.index), candidate.count))
        }
        candidate = candidate.normalizedSortOrder()
        try await store.save(candidate)
        persistedSnapshot = candidate
        return candidate
    }

    private func acquireMutationLock() async {
        if !mutationLocked {
            mutationLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            mutationWaiters.append(continuation)
        }
    }

    private func releaseMutationLock() {
        guard !mutationWaiters.isEmpty else {
            mutationLocked = false
            return
        }
        mutationWaiters.removeFirst().resume()
    }
}

private extension Array where Element == WatchlistItem {
    func normalizedSortOrder() -> [WatchlistItem] {
        enumerated().map { index, item in
            var item = item
            item.sortOrder = index
            return item
        }
    }
}
