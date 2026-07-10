import XCTest
@testable import CryptoLens

final class WatchlistUseCaseTests: XCTestCase {
    func testAddRejectsDuplicateAssetID() async throws {
        let store = MemoryWatchlistStore()
        let useCase = WatchlistUseCase(store: store, maximumCount: 50)
        _ = try await useCase.bootstrap()
        _ = try await useCase.add(asset: asset("bitcoin"), at: Date())

        await XCTAssertThrowsErrorAsync(
            try await useCase.add(asset: asset("bitcoin"), at: Date())
        ) { error in
            XCTAssertEqual(error as? WatchlistMutationError, .duplicate(AssetID(rawValue: "bitcoin", source: .coinGecko)))
        }
        let saved = await store.savedSnapshots
        XCTAssertEqual(saved.count, 1)
    }

    func testAddEnforcesConfiguredMaximum() async throws {
        let initial = (0..<2).map { item("coin-\($0)", order: $0) }
        let useCase = WatchlistUseCase(store: MemoryWatchlistStore(initial: initial), maximumCount: 2)
        _ = try await useCase.bootstrap()

        await XCTAssertThrowsErrorAsync(try await useCase.add(asset: asset("coin-2"), at: Date())) { error in
            XCTAssertEqual(error as? WatchlistMutationError, .watchlistFull(max: 2))
        }
    }

    func testSaveFailureLeavesPersistedSnapshotUnchanged() async throws {
        let original = [item("bitcoin", order: 0)]
        let store = MemoryWatchlistStore(initial: original, failSaves: true)
        let useCase = WatchlistUseCase(store: store, maximumCount: 50)
        _ = try await useCase.bootstrap()

        await XCTAssertThrowsErrorAsync(try await useCase.add(asset: asset("ethereum"), at: Date())) { _ in }

        let snapshot = await useCase.snapshot()
        XCTAssertEqual(snapshot, original)
    }

    func testRemoveAndReorderSaveFailuresLeavePersistedSnapshotUnchanged() async throws {
        let original = [item("a", order: 0), item("b", order: 1)]

        let removeUseCase = WatchlistUseCase(
            store: MemoryWatchlistStore(initial: original, failSaves: true),
            maximumCount: 50
        )
        _ = try await removeUseCase.bootstrap()
        await XCTAssertThrowsErrorAsync(try await removeUseCase.remove(id: original[0].id)) { _ in }
        let removeSnapshot = await removeUseCase.snapshot()
        XCTAssertEqual(removeSnapshot, original)

        let reorderUseCase = WatchlistUseCase(
            store: MemoryWatchlistStore(initial: original, failSaves: true),
            maximumCount: 50
        )
        _ = try await reorderUseCase.bootstrap()
        await XCTAssertThrowsErrorAsync(
            try await reorderUseCase.reorder(assetIDs: original.reversed().map(\.asset.assetID))
        ) { _ in }
        let reorderSnapshot = await reorderUseCase.snapshot()
        XCTAssertEqual(reorderSnapshot, original)
    }

    func testRestoreSaveFailureKeepsItemsRemoved() async throws {
        let original = [item("a", order: 0), item("b", order: 1)]
        let store = MemoryWatchlistStore(initial: original)
        let useCase = WatchlistUseCase(store: store, maximumCount: 50)
        _ = try await useCase.bootstrap()
        let removed = try await useCase.remove(id: original[1].id)
        await store.failNextSave()

        await XCTAssertThrowsErrorAsync(
            try await useCase.restore([RemovedWatchlistEntry(item: removed.item, index: removed.index)])
        ) { _ in }

        let snapshot = await useCase.snapshot()
        XCTAssertEqual(snapshot.map(\.asset.assetID.rawValue), ["a"])
    }

    func testReorderNormalizesSortOrderAndPersistsOnce() async throws {
        let initial = [item("a", order: 0), item("b", order: 1), item("c", order: 2)]
        let store = MemoryWatchlistStore(initial: initial)
        let useCase = WatchlistUseCase(store: store, maximumCount: 50)
        _ = try await useCase.bootstrap()

        let result = try await useCase.reorder(assetIDs: [initial[2].asset.assetID, initial[0].asset.assetID, initial[1].asset.assetID])

        XCTAssertEqual(result.map(\.asset.assetID.rawValue), ["c", "a", "b"])
        XCTAssertEqual(result.map(\.sortOrder), [0, 1, 2])
        let saved = await store.savedSnapshots
        XCTAssertEqual(saved.count, 1)
    }

    func testBatchRestoreReinsertsInReverseRemovalOrder() async throws {
        let initial = [item("a", order: 0), item("b", order: 1), item("c", order: 2)]
        let store = MemoryWatchlistStore(initial: initial)
        let useCase = WatchlistUseCase(store: store, maximumCount: 50)
        _ = try await useCase.bootstrap()
        let first = try await useCase.remove(id: initial[1].id)
        let second = try await useCase.remove(id: initial[2].id)

        let restored = try await useCase.restore([
            RemovedWatchlistEntry(item: first.item, index: first.index),
            RemovedWatchlistEntry(item: second.item, index: second.index)
        ])

        XCTAssertEqual(restored.map(\.asset.assetID.rawValue), ["a", "b", "c"])
        let saved = await store.savedSnapshots
        XCTAssertEqual(saved.count, 3)
    }

    private func asset(_ id: String) -> Asset {
        Asset(
            assetID: AssetID(rawValue: id, source: .coinGecko),
            symbol: id.uppercased(),
            name: id,
            kind: .crypto,
            platform: nil,
            contractAddress: nil
        )
    }

    private func item(_ id: String, order: Int) -> WatchlistItem {
        WatchlistItem(id: UUID(), asset: asset(id), sortOrder: order, addedAt: Date(timeIntervalSince1970: TimeInterval(order)))
    }
}

private actor MemoryWatchlistStore: WatchlistStoring {
    private let initial: [WatchlistItem]
    private let failSaves: Bool
    private var shouldFailNextSave = false
    private(set) var savedSnapshots: [[WatchlistItem]] = []

    init(initial: [WatchlistItem] = [], failSaves: Bool = false) {
        self.initial = initial
        self.failSaves = failSaves
    }

    func load() async throws -> [WatchlistItem] { initial }

    func save(_ items: [WatchlistItem]) async throws {
        if failSaves || shouldFailNextSave {
            shouldFailNextSave = false
            throw CocoaError(.fileWriteUnknown)
        }
        savedSnapshots.append(items)
    }

    func failNextSave() {
        shouldFailNextSave = true
    }
}
