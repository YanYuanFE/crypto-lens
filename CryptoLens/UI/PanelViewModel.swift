import AppKit
import Foundation
import Observation

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
    private let classifier: any StockTokenClassifying
    private let configuration: AppConfiguration

    private var openTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var validationTask: Task<Void, Never>?
    private var timelineTask: Task<Void, Never>?
    private var removalFinalizeTask: Task<Void, Never>?
    private var pendingAddAssetIDs: Set<AssetID> = []
    private var removalBatch: [(entry: RemovedWatchlistEntry, quote: PriceQuote?)] = []
    private var searchGeneration = 0
    private var isPanelOpen = false

    var mode: PanelMode = .watchlist
    var isBootstrapping = true
    var items: [WatchlistItem] = []
    var quotes: [AssetID: PriceQuote] = [:]
    var query = ""
    var searchResults: [SearchResult] = []
    var isSearching = false
    var isRefreshing = false
    var bannerMessage: String?
    var localMessage: String?
    var candidateKey = ""
    var isValidatingKey = false
    var configuredKeySuffix: String?
    var configuredKeyIsValid = false
    var lastBulkRefreshAt: Date?
    var lastBulkCoveredAssetIDs: Set<AssetID> = []
    var lastBulkMissingAssetIDs: Set<AssetID> = []
    var now = Date()
    var lastSuccessfulWatchlistBulkAt: Date?

    var removalBatchCount: Int { removalBatch.count }

    init(
        watchlist: WatchlistUseCase,
        cacheStore: PriceCacheStore,
        apiKeyStore: any APIKeyStoring,
        searcher: any AssetSearching,
        priceProvider: any PriceProviding,
        keyValidator: any APIKeyValidating,
        classifier: any StockTokenClassifying,
        configuration: AppConfiguration = .v1
    ) {
        self.watchlist = watchlist
        self.cacheStore = cacheStore
        self.apiKeyStore = apiKeyStore
        self.searcher = searcher
        self.priceProvider = priceProvider
        self.keyValidator = keyValidator
        self.classifier = classifier
        self.configuration = configuration
    }

    var canSearch: Bool { configuredKeySuffix != nil && configuredKeyIsValid }

    var canManualRefresh: Bool {
        !items.isEmpty && configuredKeySuffix != nil && configuredKeyIsValid && !isRefreshing && manualRefreshRemaining == 0
    }

    var manualRefreshRemaining: Int {
        guard let lastSuccessfulWatchlistBulkAt else { return 0 }
        let deadline = lastSuccessfulWatchlistBulkAt.addingTimeInterval(60)
        return max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }

    var freshnessText: String {
        if isRefreshing { return "正在更新..." }
        guard let lastBulkRefreshAt else { return "尚未更新" }
        let seconds = max(0, now.timeIntervalSince(lastBulkRefreshAt))
        let relative = seconds < 60 ? "刚刚更新" : "\(Int(seconds / 60)) 分钟前更新"
        let currentIDs = Set(items.map(\.asset.assetID))
        let fullyCovered = currentIDs.isSubset(of: lastBulkCoveredAssetIDs)
            && currentIDs.isDisjoint(with: lastBulkMissingAssetIDs)
        return fullyCovered ? relative : "部分更新 · \(relative)"
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
            if configuredKeySuffix == nil && items.isEmpty { mode = .settings }
            if await cacheStore.consumeRecoveredCorruption() {
                bannerMessage = "行情缓存已重置"
            }
        } catch {
            bannerMessage = "无法读取本地数据"
        }
        isBootstrapping = false
        if isPanelOpen { scheduleOpenRefresh() }
    }

    func panelVisibilityChanged(isVisible: Bool) {
        guard isVisible != isPanelOpen else { return }
        isPanelOpen = isVisible
        if isVisible {
            now = Date()
            scheduleOpenRefresh()
            startTimeline()
        } else {
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
        guard canSearch else {
            localMessage = "请先配置 API Key"
            return
        }
        let generation = searchGeneration
        isSearching = true
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                try Task.checkCancellation()
                guard let self else { return }
                let rawResults = try await self.searcher.search(query: trimmed)
                try Task.checkCancellation()
                guard generation == self.searchGeneration else { return }
                self.searchResults = rawResults.map(self.classified)
                    .sorted { ($0.marketCapRank ?? .max) < ($1.marketCapRank ?? .max) }
                self.isSearching = false
                self.bannerMessage = nil
            } catch is CancellationError {
            } catch {
                guard let self, generation == self.searchGeneration else { return }
                self.isSearching = false
                if (error as? NetworkError) == .unauthorized { self.configuredKeyIsValid = false }
                self.localMessage = self.message(for: error)
                self.bannerMessage = self.localMessage
            }
        }
    }

    func retrySearch() {
        let current = query
        query = ""
        query = current
        queryChanged()
    }

    func add(_ result: SearchResult) async {
        do {
            let existing = items.first { $0.asset.assetID == result.asset.assetID }
            if existing == nil {
                _ = try await watchlist.add(asset: result.asset)
                items = await watchlist.snapshot()
                refreshTask = Task { [weak self] in
                    await self?.refresh(ids: [result.asset.assetID], isBulk: false)
                }
            }
            query = ""
            searchResults = []
            mode = .watchlist
            localMessage = existing == nil ? "已添加" : "已在列表中"
        } catch let error as WatchlistMutationError {
            switch error {
            case .duplicate:
                query = ""
                mode = .watchlist
                localMessage = "已在列表中"
            case let .watchlistFull(max):
                localMessage = "关注列表最多 \(max) 项"
            }
        } catch {
            localMessage = "更改未保存"
            bannerMessage = localMessage
        }
    }

    func remove(_ item: WatchlistItem) async {
        do {
            let removed = try await watchlist.remove(id: item.id)
            let quote = quotes[item.asset.assetID]
            items = await watchlist.snapshot()
            quotes[item.asset.assetID] = nil
            removalBatch.append((RemovedWatchlistEntry(item: removed.item, index: removed.index), quote))
            scheduleRemovalFinalization()
            do {
                try await saveCurrentCache()
            } catch {
                bannerMessage = "行情缓存未保存"
            }
        } catch {
            bannerMessage = "更改未保存"
        }
    }

    func undoRemovalBatch() async {
        guard !removalBatch.isEmpty else { return }
        removalFinalizeTask?.cancel()
        let batch = removalBatch
        do {
            items = try await watchlist.restore(batch.map(\.entry))
            for removed in batch {
                if let quote = removed.quote { quotes[removed.entry.item.asset.assetID] = quote }
            }
            removalBatch.removeAll()
            do {
                try await saveCurrentCache()
            } catch {
                bannerMessage = "行情缓存未保存"
            }
        } catch {
            bannerMessage = "撤销未保存"
            scheduleRemovalFinalization()
        }
    }

    func move(_ item: WatchlistItem, by offset: Int) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let destination = index + offset
        guard items.indices.contains(destination) else { return }
        var ids = items.map(\.asset.assetID)
        ids.swapAt(index, destination)
        do {
            items = try await watchlist.reorder(assetIDs: ids)
        } catch {
            items = await watchlist.snapshot()
            bannerMessage = "更改未保存"
        }
    }

    func manualRefresh() {
        guard canManualRefresh else { return }
        refreshTask = Task { [weak self] in await self?.refreshAll() }
    }

    func showSettings() {
        searchTask?.cancel()
        query = ""
        searchResults = []
        localMessage = nil
        mode = .settings
    }

    func leaveSettings() {
        validationTask?.cancel()
        isValidatingKey = false
        mode = .watchlist
        now = Date()
    }

    func beginValidateAndSaveKey() {
        validationTask?.cancel()
        validationTask = Task { [weak self] in await self?.validateAndSaveKey() }
    }

    private func validateAndSaveKey() async {
        let candidate = candidateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            localMessage = "请输入 Demo API Key"
            return
        }
        isValidatingKey = true
        localMessage = nil
        do {
            try await keyValidator.validate(candidateKey: candidate)
            try apiKeyStore.saveDemoKey(candidate)
            candidateKey = ""
            localMessage = nil
            refreshConfiguredKeyStatus()
            isValidatingKey = false
            mode = .watchlist
            bannerMessage = nil
            if !items.isEmpty {
                refreshTask?.cancel()
                refreshTask = Task { [weak self] in await self?.refreshAll() }
            }
        } catch {
            isValidatingKey = false
            localMessage = message(for: error)
        }
    }

    func removeAPIKey() {
        do {
            cancelOwnedNetworkTasks()
            try apiKeyStore.deleteDemoKey()
            configuredKeySuffix = nil
            configuredKeyIsValid = false
            if items.isEmpty { mode = .settings }
        } catch {
            localMessage = "无法删除 API Key"
        }
    }

    func quit() {
        cancelOwnedTasks()
        NSApplication.shared.terminate(nil)
    }

    func isStale(_ quote: PriceQuote) -> Bool {
        now.timeIntervalSince(quote.fetchedAt) > 300
    }

    private func scheduleOpenRefresh() {
        openTask?.cancel()
        guard !isBootstrapping else { return }
        openTask = Task { [weak self] in
            do {
                guard let self else { return }
                try await Task.sleep(for: self.configuration.openRefreshDebounce)
                guard self.isPanelOpen else { return }
                await self.refreshAll()
            } catch {}
        }
    }

    private func refreshAll() async {
        guard isPanelOpen, !items.isEmpty, configuredKeySuffix != nil, configuredKeyIsValid, !isRefreshing else { return }
        await refresh(ids: items.map(\.asset.assetID), isBulk: true)
    }

    private func refresh(ids: [AssetID], isBulk: Bool) async {
        guard isPanelOpen, !ids.isEmpty, configuredKeySuffix != nil, configuredKeyIsValid else { return }
        if isRefreshing {
            if !isBulk { pendingAddAssetIDs.formUnion(ids) }
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            drainPendingAddPrices()
        }
        do {
            let returned = try await requestPricesWithRetry(ids: ids)
            for quote in returned { quotes[quote.assetID] = quote }
            if isBulk {
                let returnedIDs = Set(returned.map(\.assetID))
                lastBulkCoveredAssetIDs = Set(ids)
                lastBulkMissingAssetIDs = Set(ids).subtracting(returnedIDs)
                lastBulkRefreshAt = Date()
                lastSuccessfulWatchlistBulkAt = lastBulkRefreshAt
            }
            try await saveCurrentCache()
            bannerMessage = nil
            now = Date()
        } catch {
            if (error as? NetworkError) != .cancelled {
                if (error as? NetworkError) == .unauthorized { configuredKeyIsValid = false }
                bannerMessage = message(for: error)
            }
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
        refreshTask = Task { [weak self] in await self?.refresh(ids: ids, isBulk: false) }
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
        timelineTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, self.isPanelOpen else { return }
                self.now = Date()
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

    private func cancelOwnedNetworkTasks() {
        openTask?.cancel()
        searchTask?.cancel()
        refreshTask?.cancel()
        validationTask?.cancel()
        pendingAddAssetIDs.removeAll()
        isSearching = false
        isRefreshing = false
    }

    private func cancelOwnedTasks() {
        cancelOwnedNetworkTasks()
        timelineTask?.cancel()
        removalFinalizeTask?.cancel()
        removalBatch.removeAll()
    }

    private func message(for error: Error) -> String {
        switch error as? NetworkError {
        case .missingAPIKey: "请先配置 API Key"
        case .unauthorized: "API Key 无效"
        case .rateLimited: "请求过于频繁，请稍后再试"
        case .offline: "当前网络不可用"
        case .timeout: "请求超时"
        case .serverError: "CoinGecko 暂时不可用"
        case .decoding: "行情数据格式异常"
        case .cancelled: ""
        default: "请求失败，请重试"
        }
    }
}
