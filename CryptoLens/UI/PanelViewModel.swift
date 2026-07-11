import AppKit
import Foundation
import Observation
import OSLog

protocol APIKeyValidating: Sendable {
    func validate(candidateKey: String) async throws
}

extension CoinGeckoClient: APIKeyValidating {}

enum PanelMode: Equatable {
    case watchlist
    case search
    case settings
}

@MainActor
@Observable
final class PanelViewModel {
    private let watchlist: WatchlistUseCase
    private let cacheStore: PriceCacheStore
    private let apiKeyStore: any APIKeyStoring
    private let searcher: any AssetSearching
    private let priceProvider: any PriceProviding
    private let keyValidator: any APIKeyValidating
    private let networkState: any NetworkStateProviding
    private let classifier: any StockTokenClassifying
    private let configuration: AppConfiguration
    private let nowProvider: @Sendable () -> Date
    private let terminationHandler: @MainActor @Sendable () -> Void

    private var openTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshTaskToken: UUID?
    private var validationTask: Task<Void, Never>?
    private var timelineTask: Task<Void, Never>?
    private var removalFinalizeTask: Task<Void, Never>?
    private var highlightTask: Task<Void, Never>?
    private var pendingAddAssetIDs: Set<AssetID> = []
    private var removalBatch: [(entry: RemovedWatchlistEntry, quote: PriceQuote?)] = []
    private var reorderPreviewBase: [WatchlistItem]?
    private var searchGeneration = 0
    private var isPanelOpen = false
    private var activeLocalMutationCount = 0
    private var shutdownTask: Task<Void, Never>?

    var mode: PanelMode = .watchlist
    var isBootstrapping = true
    var items: [WatchlistItem] = []
    var quotes: [AssetID: PriceQuote] = [:]
    var query = ""
    var searchResults: [SearchResult] = []
    var isSearching = false
    var isRefreshing = false
    private var statusSelector = StatusSelector()
    var localMessage: String?
    var candidateKey = ""
    var isCandidateKeyRevealed = false
    var isValidatingKey = false
    var configuredKeySuffix: String?
    var configuredKeyIsValid = false
    var lastBulkRefreshAt: Date?
    var lastBulkCoveredAssetIDs: Set<AssetID> = []
    var lastBulkMissingAssetIDs: Set<AssetID> = []
    var now = Date()
    var lastSuccessfulWatchlistBulkAt: Date?
    var nextAllowedRequestAt: Date?
    var isShuttingDown = false
    var highlightedAssetID: AssetID?

    var statusBanner: StatusBannerPresentation? { statusSelector.presentation }

    var removalBatchCount: Int { removalBatch.count }

    init(
        watchlist: WatchlistUseCase,
        cacheStore: PriceCacheStore,
        apiKeyStore: any APIKeyStoring,
        searcher: any AssetSearching,
        priceProvider: any PriceProviding,
        keyValidator: any APIKeyValidating,
        networkState: any NetworkStateProviding,
        classifier: any StockTokenClassifying,
        configuration: AppConfiguration = .v1,
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        terminationHandler: @escaping @MainActor @Sendable () -> Void = {
            NSApplication.shared.terminate(nil)
        }
    ) {
        self.watchlist = watchlist
        self.cacheStore = cacheStore
        self.apiKeyStore = apiKeyStore
        self.searcher = searcher
        self.priceProvider = priceProvider
        self.keyValidator = keyValidator
        self.networkState = networkState
        self.classifier = classifier
        self.configuration = configuration
        self.nowProvider = nowProvider
        self.terminationHandler = terminationHandler
        self.now = nowProvider()
        if !classifier.isAvailable { statusSelector.activate(.classificationUnavailable) }
    }

    var canSearch: Bool {
        !(nextAllowedRequestAt.map { $0 > now } ?? false)
    }

    var canManualRefresh: Bool {
        !items.isEmpty && !isRefreshing && manualRefreshRemaining == 0
    }

    var manualRefreshRemaining: Int {
        let manualDeadline = lastSuccessfulWatchlistBulkAt?.addingTimeInterval(
            configuration.manualRefreshCooldown.timeInterval
        )
        let deadline = [manualDeadline, nextAllowedRequestAt].compactMap { $0 }.max()
        guard let deadline else { return 0 }
        return max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }

    var freshnessText: String {
        if isRefreshing { return String(localized: "正在更新...") }
        guard let lastBulkRefreshAt else { return String(localized: "尚未更新") }
        let seconds = max(0, now.timeIntervalSince(lastBulkRefreshAt))
        let relative = seconds < 60
            ? String(localized: "刚刚更新")
            : String(localized: "\(Int(seconds / 60)) 分钟前更新")
        let currentIDs = Set(items.map(\.asset.assetID))
        let fullyCovered = currentIDs.isSubset(of: lastBulkCoveredAssetIDs)
            && currentIDs.isDisjoint(with: lastBulkMissingAssetIDs)
        return fullyCovered ? relative : String(localized: "部分更新 · \(relative)")
    }

    func bootstrap() async {
        guard isBootstrapping else { return }
        do {
            async let loadedItems = watchlist.bootstrap()
            async let loadedCache = cacheStore.load()
            items = try await loadedItems
            let cache = try await loadedCache
            quotes = Dictionary(uniqueKeysWithValues: cache.quotes.map { ($0.assetID, $0) })
            lastBulkRefreshAt = cache.lastBulkRefreshAt
            lastBulkCoveredAssetIDs = Set(cache.lastBulkCoveredAssetIDs)
            lastBulkMissingAssetIDs = Set(cache.lastBulkMissingAssetIDs)
            refreshConfiguredKeyStatus()
            async let watchlistRecovered = watchlist.consumeRecoveredCorruption()
            async let cacheRecovered = cacheStore.consumeRecoveredCorruption()
            let recovered = await (watchlistRecovered, cacheRecovered)
            if recovered.0 || recovered.1 {
                statusSelector.activate(.corruptedStore)
            }
        } catch {
            statusSelector.activate(.persistenceFailure)
        }
        isBootstrapping = false
        if isPanelOpen { scheduleOpenRefresh() }
    }

    func panelVisibilityChanged(isVisible: Bool) {
        guard isVisible != isPanelOpen else { return }
        isPanelOpen = isVisible
        if isVisible {
            updatePresentationTime(nowProvider())
            scheduleOpenRefresh()
            startTimeline()
        } else {
            isCandidateKeyRevealed = false
            cancelOwnedTasks()
        }
    }

    func queryChanged() {
        guard mode != .settings else { return }
        searchGeneration += 1
        searchTask?.cancel()
        localMessage = nil
        searchResults = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            mode = .watchlist
            isSearching = false
            return
        }
        mode = .search
        if let deadline = nextAllowedRequestAt, deadline > now {
            localMessage = String(localized: "请求受限，请稍后再试")
            return
        }
        let generation = searchGeneration
        launchSearch(trimmed, generation: generation, debounce: true)
    }

    func retrySearch() {
        searchGeneration += 1
        searchTask?.cancel()
        localMessage = nil
        searchResults = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        if let deadline = nextAllowedRequestAt, deadline > now {
            localMessage = String(localized: "请求受限，请稍后再试")
            return
        }
        launchSearch(trimmed, generation: searchGeneration, debounce: false)
    }

    private func launchSearch(_ query: String, generation: Int, debounce: Bool) {
        isSearching = true
        searchTask = Task { [weak self] in
            do {
                if debounce { try await Task.sleep(for: .milliseconds(300)) }
                try Task.checkCancellation()
                guard let self else { return }
                let rawResults = try await self.searcher.search(query: query)
                try Task.checkCancellation()
                guard generation == self.searchGeneration else { return }
                self.searchResults = rawResults.enumerated()
                    .map { (index: $0.offset, result: self.classified($0.element)) }
                    .sorted { lhs, rhs in
                        let lhsExact = lhs.result.asset.symbol.caseInsensitiveCompare(query) == .orderedSame
                        let rhsExact = rhs.result.asset.symbol.caseInsensitiveCompare(query) == .orderedSame
                        if lhsExact != rhsExact { return lhsExact }
                        let lhsRank = lhs.result.marketCapRank ?? .max
                        let rhsRank = rhs.result.marketCapRank ?? .max
                        if lhsRank != rhsRank { return lhsRank < rhsRank }
                        return lhs.index < rhs.index
                    }
                    .map(\.result)
                self.isSearching = false
                self.statusSelector.resolveNetworkFailures()
            } catch is CancellationError {
            } catch {
                guard let self, generation == self.searchGeneration else { return }
                self.isSearching = false
                if (error as? NetworkError) == .unauthorized {
                    self.configuredKeyIsValid = false
                    self.query = ""
                    self.searchResults = []
                    self.mode = .settings
                }
                self.nextAllowedRequestAt = await self.networkState.nextAllowedRequestAt
                self.localMessage = self.message(for: error)
                self.activateNetworkStatus(for: error)
            }
        }
    }

    func add(_ result: SearchResult) async {
        guard beginLocalMutation() else { return }
        defer { endLocalMutation() }
        do {
            let existing = items.first { $0.asset.assetID == result.asset.assetID }
            if existing == nil {
                _ = try await watchlist.add(asset: result.asset)
                items = await watchlist.snapshot()
                statusSelector.resolve(.persistenceFailure)
                scheduleAddPrice(for: result.asset.assetID)
            }
            query = ""
            searchResults = []
            mode = .watchlist
            completeAdd(
                assetID: result.asset.assetID,
                message: existing == nil ? String(localized: "已添加") : String(localized: "已在列表中")
            )
        } catch let error as WatchlistMutationError {
            switch error {
            case .duplicate:
                query = ""
                mode = .watchlist
                completeAdd(assetID: result.asset.assetID, message: String(localized: "已在列表中"))
            case let .watchlistFull(max):
                localMessage = String(localized: "关注列表最多 \(max) 项")
            }
        } catch {
            localMessage = String(localized: "更改未保存")
            statusSelector.activate(.persistenceFailure)
        }
    }

    func remove(_ item: WatchlistItem) async {
        guard beginLocalMutation() else { return }
        defer { endLocalMutation() }
        do {
            let removed = try await watchlist.remove(id: item.id)
            statusSelector.resolve(.persistenceFailure)
            let quote = quotes[item.asset.assetID]
            items = await watchlist.snapshot()
            quotes[item.asset.assetID] = nil
            removalBatch.append((RemovedWatchlistEntry(item: removed.item, index: removed.index), quote))
            scheduleRemovalFinalization()
            do {
                try await saveCurrentCache()
            } catch {
                statusSelector.activate(.persistenceFailure)
            }
        } catch {
            statusSelector.activate(.persistenceFailure)
        }
    }

    func undoRemovalBatch() async {
        guard !removalBatch.isEmpty else { return }
        guard beginLocalMutation() else { return }
        defer { endLocalMutation() }
        removalFinalizeTask?.cancel()
        let batch = removalBatch
        do {
            items = try await watchlist.restore(batch.map(\.entry))
            statusSelector.resolve(.persistenceFailure)
            for removed in batch {
                if let quote = removed.quote { quotes[removed.entry.item.asset.assetID] = quote }
            }
            removalBatch.removeAll()
            do {
                try await saveCurrentCache()
            } catch {
                statusSelector.activate(.persistenceFailure)
            }
        } catch {
            statusSelector.activate(.persistenceFailure)
            scheduleRemovalFinalization()
        }
    }

    func move(_ item: WatchlistItem, by offset: Int) async {
        guard beginLocalMutation() else { return }
        defer { endLocalMutation() }
        finalizeRemovalBatch()
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let destination = index + offset
        guard items.indices.contains(destination) else { return }
        var ids = items.map(\.asset.assetID)
        ids.swapAt(index, destination)
        do {
            items = try await watchlist.reorder(assetIDs: ids)
            statusSelector.resolve(.persistenceFailure)
        } catch {
            items = await watchlist.snapshot()
            statusSelector.activate(.persistenceFailure)
        }
    }

    func previewReorder(draggedID: UUID, over targetID: UUID) {
        guard !isShuttingDown,
              let source = items.firstIndex(where: { $0.id == draggedID }),
              let target = items.firstIndex(where: { $0.id == targetID }),
              source != target else { return }
        if reorderPreviewBase == nil {
            finalizeRemovalBatch()
            reorderPreviewBase = items
        }
        let moved = items.remove(at: source)
        items.insert(moved, at: target)
    }

    func commitReorderPreview() async {
        guard reorderPreviewBase != nil else { return }
        guard beginLocalMutation() else {
            cancelReorderPreview()
            return
        }
        defer { endLocalMutation() }
        let ids = items.map(\.asset.assetID)
        do {
            items = try await watchlist.reorder(assetIDs: ids)
            reorderPreviewBase = nil
            statusSelector.resolve(.persistenceFailure)
        } catch {
            items = await watchlist.snapshot()
            reorderPreviewBase = nil
            statusSelector.activate(.persistenceFailure)
        }
    }

    func cancelReorderPreview() {
        if let reorderPreviewBase { items = reorderPreviewBase }
        reorderPreviewBase = nil
    }

    func manualRefresh() {
        guard canManualRefresh else { return }
        openTask?.cancel()
        launchRefreshTask(ids: items.map(\.asset.assetID), isBulk: true)
    }

    func showSettings() {
        searchTask?.cancel()
        isSearching = false
        query = ""
        searchResults = []
        localMessage = nil
        isCandidateKeyRevealed = false
        mode = .settings
    }

    func leaveSettings() {
        validationTask?.cancel()
        isValidatingKey = false
        isCandidateKeyRevealed = false
        mode = .watchlist
        updatePresentationTime(nowProvider())
    }

    func beginValidateAndSaveKey() {
        validationTask?.cancel()
        validationTask = Task { [weak self] in await self?.validateAndSaveKey() }
    }

    private func validateAndSaveKey() async {
        let candidate = candidateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            localMessage = String(localized: "请输入 Demo API Key")
            return
        }
        isValidatingKey = true
        localMessage = nil
        do {
            try await keyValidator.validate(candidateKey: candidate)
            try Task.checkCancellation()
            try apiKeyStore.saveDemoKey(candidate)
            await networkState.resetNetworkState()
            nextAllowedRequestAt = nil
            candidateKey = ""
            localMessage = nil
            refreshConfiguredKeyStatus()
            isValidatingKey = false
            mode = .watchlist
            statusSelector.resolve(.configuredKeyInvalid)
            statusSelector.resolveNetworkFailures()
            if !items.isEmpty {
                openTask?.cancel()
                pendingAddAssetIDs.removeAll()
                launchRefreshTask(ids: items.map(\.asset.assetID), isBulk: true, cancelExisting: true)
            }
        } catch is CancellationError {
            isValidatingKey = false
        } catch let error as NetworkError where error == .cancelled {
            isValidatingKey = false
        } catch {
            isValidatingKey = false
            nextAllowedRequestAt = await networkState.nextAllowedRequestAt
            localMessage = message(for: error)
        }
    }

    func removeAPIKey() async {
        do {
            cancelOwnedNetworkTasks()
            try apiKeyStore.deleteDemoKey()
            await networkState.resetNetworkState()
            nextAllowedRequestAt = nil
            configuredKeySuffix = nil
            configuredKeyIsValid = false
            statusSelector.resolve(.configuredKeyInvalid)
        } catch {
            localMessage = String(localized: "无法删除 API Key")
        }
    }

    func beginQuit() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        cancelOwnedTasks()
        candidateKey = ""
        shutdownTask = Task { [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: self.configuration.shutdownDrainTimeout)
            while self.activeLocalMutationCount > 0, clock.now < deadline {
                do { try await clock.sleep(for: .milliseconds(25)) } catch { break }
            }
            if self.activeLocalMutationCount > 0 {
                Logger(subsystem: "app.cryptolens", category: "shutdown")
                    .fault("Timed out waiting for \(self.activeLocalMutationCount) local mutations")
            }
            self.terminationHandler()
        }
    }

    func isStale(_ quote: PriceQuote) -> Bool {
        now.timeIntervalSince(quote.fetchedAt) > 300
    }

    func updatePresentationTime(_ date: Date) {
        now = date
        if let deadline = nextAllowedRequestAt, deadline <= now {
            nextAllowedRequestAt = nil
            statusSelector.resolve(.rateLimited)
        }
    }

    private func scheduleOpenRefresh() {
        openTask?.cancel()
        guard !isBootstrapping else { return }
        openTask = Task { [weak self] in
            do {
                guard let self else { return }
                try await Task.sleep(for: self.configuration.openRefreshDebounce)
                guard self.isPanelOpen else { return }
                self.launchRefreshTask(ids: self.items.map(\.asset.assetID), isBulk: true)
            } catch {}
        }
    }

    private func refresh(ids: [AssetID], isBulk: Bool) async {
        guard isPanelOpen, !ids.isEmpty else { return }
        if isRefreshing {
            if !isBulk { pendingAddAssetIDs.formUnion(ids) }
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let returned = try await requestPricesWithRetry(ids: ids)
            for quote in returned { quotes[quote.assetID] = quote }
            if isBulk {
                let returnedIDs = Set(returned.map(\.assetID))
                lastBulkCoveredAssetIDs = Set(ids)
                lastBulkMissingAssetIDs = Set(ids).subtracting(returnedIDs)
                lastBulkRefreshAt = nowProvider()
                lastSuccessfulWatchlistBulkAt = lastBulkRefreshAt
            }
            if beginLocalMutation() {
                defer { endLocalMutation() }
                try await saveCurrentCache()
            }
            statusSelector.resolve(.persistenceFailure)
            statusSelector.resolveNetworkFailures()
            statusSelector.resolve(.rateLimited)
            updatePresentationTime(nowProvider())
        } catch {
            if error is CancellationError || (error as? NetworkError) == .cancelled { return }
            if (error as? NetworkError) == .unauthorized { configuredKeyIsValid = false }
            nextAllowedRequestAt = await networkState.nextAllowedRequestAt
            activateNetworkStatus(for: error)
        }
    }

    private func requestPricesWithRetry(ids: [AssetID]) async throws -> [PriceQuote] {
        var attempt = 0
        while true {
            do {
                return try await priceProvider.prices(for: ids, currency: configuration.quoteCurrency)
            } catch {
                guard attempt < 2, isPanelOpen, isRetryablePriceError(error) else { throw error }
                let delay = attempt == 0 ? 1 : 2
                attempt += 1
                try await Task.sleep(for: .seconds(delay))
                try Task.checkCancellation()
            }
        }
    }

    private func isRetryablePriceError(_ error: Error) -> Bool {
        switch error as? NetworkError {
        case .offline, .timeout, .serverError: true
        default: false
        }
    }

    private func drainPendingAddPrices() {
        guard !pendingAddAssetIDs.isEmpty, isPanelOpen else {
            if !isPanelOpen { pendingAddAssetIDs.removeAll() }
            return
        }
        let ids = Array(pendingAddAssetIDs)
        pendingAddAssetIDs.removeAll()
        launchRefreshTask(ids: ids, isBulk: false)
    }

    private func scheduleAddPrice(for assetID: AssetID) {
        guard isPanelOpen else { return }
        if isRefreshing || refreshTask != nil {
            pendingAddAssetIDs.insert(assetID)
            return
        }
        launchRefreshTask(ids: [assetID], isBulk: false)
    }

    private func launchRefreshTask(ids: [AssetID], isBulk: Bool, cancelExisting: Bool = false) {
        let previousTask = refreshTask
        if cancelExisting {
            previousTask?.cancel()
        } else if previousTask != nil {
            if !isBulk { pendingAddAssetIDs.formUnion(ids) }
            return
        }
        let token = UUID()
        refreshTaskToken = token
        refreshTask = Task { [weak self] in
            guard let self else { return }
            if let previousTask { await previousTask.value }
            guard !Task.isCancelled else { return }
            await self.refresh(ids: ids, isBulk: isBulk)
            if self.refreshTaskToken == token {
                self.refreshTask = nil
                self.refreshTaskToken = nil
                self.drainPendingAddPrices()
            }
        }
    }

    private func saveCurrentCache() async throws {
        let cache = PriceCacheEnvelope(
            currency: configuration.quoteCurrency,
            lastBulkRefreshAt: lastBulkRefreshAt,
            lastBulkCoveredAssetIDs: Array(lastBulkCoveredAssetIDs),
            lastBulkMissingAssetIDs: Array(lastBulkMissingAssetIDs),
            quotes: Array(quotes.values)
        )
        try await cacheStore.save(cache, keeping: items.map(\.asset.assetID))
    }

    private func classified(_ result: SearchResult) -> SearchResult {
        let raw = result.asset
        let asset = Asset(
            assetID: raw.assetID,
            symbol: raw.symbol,
            name: raw.name,
            kind: classifier.kind(for: raw),
            platform: raw.platform,
            contractAddress: raw.contractAddress
        )
        return SearchResult(asset: asset, marketCapRank: result.marketCapRank, thumbURL: result.thumbURL)
    }

    private func refreshConfiguredKeyStatus() {
        let key = try? apiKeyStore.loadDemoKey()
        configuredKeySuffix = key.flatMap { value in
            guard !value.isEmpty else { return nil }
            return String(value.suffix(4))
        }
        configuredKeyIsValid = configuredKeySuffix != nil
    }

    private func startTimeline() {
        timelineTask?.cancel()
        let interval = configuration.staleTimelineInterval
        timelineTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard let self, self.isPanelOpen else { return }
                self.updatePresentationTime(self.nowProvider())
            }
        }
    }

    private func scheduleRemovalFinalization() {
        removalFinalizeTask?.cancel()
        removalFinalizeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.removalBatch.removeAll()
        }
    }

    private func completeAdd(assetID: AssetID, message: String) {
        localMessage = message
        highlightedAssetID = assetID
        highlightTask?.cancel()
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
        highlightTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1_200)) } catch { return }
            if self?.highlightedAssetID == assetID { self?.highlightedAssetID = nil }
        }
    }

    private func finalizeRemovalBatch() {
        removalFinalizeTask?.cancel()
        removalBatch.removeAll()
    }

    private func cancelOwnedNetworkTasks() {
        openTask?.cancel()
        searchTask?.cancel()
        refreshTask?.cancel()
        refreshTask = nil
        refreshTaskToken = nil
        validationTask?.cancel()
        pendingAddAssetIDs.removeAll()
        isSearching = false
        isRefreshing = false
        isValidatingKey = false
    }

    private func cancelOwnedTasks() {
        cancelOwnedNetworkTasks()
        timelineTask?.cancel()
        highlightTask?.cancel()
        highlightedAssetID = nil
        cancelReorderPreview()
        removalFinalizeTask?.cancel()
        finalizeRemovalBatch()
    }

    private func beginLocalMutation() -> Bool {
        guard !isShuttingDown else { return false }
        activeLocalMutationCount += 1
        return true
    }

    private func endLocalMutation() {
        activeLocalMutationCount = max(0, activeLocalMutationCount - 1)
    }

    private func message(for error: Error) -> String {
        switch error as? NetworkError {
        case .missingAPIKey: String(localized: "请输入 Demo API Key")
        case .unauthorized: String(localized: "API Key 无效")
        case .rateLimited: String(localized: "请求过于频繁，请稍后再试")
        case .offline: String(localized: "当前网络不可用")
        case .timeout: String(localized: "请求超时")
        case .serverError: String(localized: "CoinGecko 暂时不可用")
        case .decoding: String(localized: "行情数据格式异常")
        case .cancelled: ""
        default: String(localized: "请求失败，请重试")
        }
    }

    func acknowledgeStatusEvent() {
        guard let condition = statusBanner?.condition, condition.isAcknowledgable else { return }
        statusSelector.resolve(condition)
    }

    private func activateNetworkStatus(for error: Error) {
        switch error as? NetworkError {
        case .unauthorized:
            statusSelector.activate(.configuredKeyInvalid)
        case .rateLimited:
            statusSelector.activate(.rateLimited)
        case .offline:
            statusSelector.activate(.offline)
        case .timeout:
            statusSelector.activate(.timeout)
        case .serverError:
            statusSelector.activate(.serverError)
        case .cancelled:
            break
        default:
            statusSelector.activate(.refreshFailed)
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
