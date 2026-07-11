import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RootPanelView: View {
    @Bindable var model: PanelViewModel
    var bootstrapsOnAppear = true
    @State private var confirmKeyRemoval = false
    @State private var draggedWatchlistItemID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 50)
            Divider()

            if let banner = model.statusBanner {
                statusBanner(banner)
            }

            if model.mode != .settings {
                searchField
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                Divider()
            }

            Group {
                switch model.mode {
                case .watchlist: watchlistBody
                case .search: searchBody
                case .settings: settingsBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.removalBatchCount > 0 {
                HStack {
                    Text("已移除 \(model.removalBatchCount) 项")
                    Spacer()
                    Button("撤销", systemImage: "arrow.uturn.backward") {
                        Task { await model.undoRemovalBatch() }
                    }
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Color(nsColor: .controlBackgroundColor))
            }

            Divider()
            footer
                .frame(height: 42)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background {
            PanelWindowObserver { visible in
                model.panelVisibilityChanged(isVisible: visible)
            }
        }
        .task {
            if bootstrapsOnAppear {
                await model.bootstrap()
            }
        }
        .disabled(model.isShuttingDown)
        .overlay {
            if model.isShuttingDown {
                ProgressView().controlSize(.small)
            }
        }
        .confirmationDialog(
            "移除 API Key？",
            isPresented: $confirmKeyRemoval,
            titleVisibility: .visible
        ) {
            Button("移除 API Key", role: .destructive) { Task { await model.removeAPIKey() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("关注列表和本地行情缓存会保留。")
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            if model.mode == .settings {
                Button("返回", systemImage: "chevron.left") { model.leaveSettings() }
                    .labelStyle(.iconOnly)
                    .help("返回关注列表")
                Text("设置").font(.headline)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.mode == .search ? "搜索资产" : "Crypto Lens")
                        .font(.headline)
                    if model.mode == .watchlist {
                        Text(model.freshnessText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.mode == .watchlist {
                    Button("刷新行情", systemImage: "arrow.clockwise") { model.manualRefresh() }
                        .labelStyle(.iconOnly)
                        .disabled(!model.canManualRefresh)
                        .help(refreshHelp)
                        .overlay {
                            if model.isRefreshing { ProgressView().controlSize(.small) }
                        }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var refreshHelp: String {
        if model.items.isEmpty { return String(localized: "暂无关注资产") }
        if let deadline = model.nextAllowedRequestAt, deadline > model.now {
            return String(localized: "请求受限，\(model.manualRefreshRemaining) 秒后可刷新")
        }
        if model.manualRefreshRemaining > 0 { return String(localized: "\(model.manualRefreshRemaining) 秒后可刷新") }
        return String(localized: "刷新行情")
    }

    private func statusBanner(_ banner: StatusBannerPresentation) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(banner.message).lineLimit(2)
            Spacer(minLength: 0)
            if banner.isAcknowledgable {
                Button("确认", systemImage: "xmark") { model.acknowledgeStatusEvent() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("确认")
            }
        }
        .font(.caption)
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索 CoinMarketCap 资产", text: $model.query)
                .textFieldStyle(.plain)
                .disabled(!model.canSearch)
                .onChange(of: model.query) { _, _ in model.queryChanged() }
            if !model.query.isEmpty {
                Button("清空", systemImage: "xmark.circle.fill") { model.query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
    }

    @ViewBuilder
    private var watchlistBody: some View {
        if model.isBootstrapping {
            ProgressView().controlSize(.small)
        } else if model.items.isEmpty {
            ContentUnavailableView("暂无关注资产", systemImage: "star")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.items) { item in
                            WatchlistRow(
                                item: item,
                                quote: model.quotes[item.asset.assetID],
                                isStale: model.quotes[item.asset.assetID].map(model.isStale) ?? false,
                                isHighlighted: model.highlightedAssetID == item.asset.assetID,
                                canMoveUp: item.id != model.items.first?.id,
                                canMoveDown: item.id != model.items.last?.id,
                                moveUp: { Task { await model.move(item, by: -1) } },
                                moveDown: { Task { await model.move(item, by: 1) } },
                                remove: { Task { await model.remove(item) } }
                            )
                            .id(item.asset.assetID)
                            .onDrag {
                                draggedWatchlistItemID = item.id
                                return NSItemProvider(object: item.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: WatchlistDropDelegate(
                                    targetID: item.id,
                                    draggedID: $draggedWatchlistItemID,
                                    preview: model.previewReorder,
                                    cancel: model.cancelReorderPreview,
                                    commit: { Task { await model.commitReorderPreview() } }
                                )
                            )
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .onChange(of: model.highlightedAssetID) { _, assetID in
                    guard let assetID else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(assetID, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var searchBody: some View {
        if model.isSearching {
            ProgressView("正在搜索...").controlSize(.small)
        } else if let message = model.localMessage, model.searchResults.isEmpty {
            VStack(spacing: 10) {
                Text(message).foregroundStyle(.secondary)
                Button("重试", systemImage: "arrow.clockwise") { model.retrySearch() }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.searchResults) { result in
                        SearchResultRow(
                            result: result,
                            isAdded: model.items.contains { $0.asset.assetID == result.asset.assetID },
                            isFull: model.items.count >= 50,
                            add: { Task { await model.add(result) } }
                        )
                        Divider().padding(.leading, 52)
                    }
                }
            }
        }
    }

    private var settingsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("CoinMarketCap API").font(.headline)
                    if let suffix = model.configuredKeySuffix {
                        if model.configuredKeyIsValid {
                            Label("API Key 已配置 ····\(suffix)", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("API Key 无效 · 当前使用公共 API", systemImage: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Label("当前使用 CoinMarketCap 公共 API", systemImage: "network")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Group {
                            if model.isCandidateKeyRevealed {
                                TextField("可选的 CoinMarketCap API Key", text: $model.candidateKey)
                            } else {
                                SecureField("可选的 CoinMarketCap API Key", text: $model.candidateKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        Button(model.isCandidateKeyRevealed ? "隐藏 API Key" : "显示 API Key", systemImage: model.isCandidateKeyRevealed ? "eye.slash" : "eye") {
                            model.isCandidateKeyRevealed.toggle()
                        }
                        .labelStyle(.iconOnly)
                        .help(model.isCandidateKeyRevealed ? "隐藏 API Key" : "显示 API Key")
                    }
                    if let message = model.localMessage {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                    HStack {
                        Button("验证并保存") { model.beginValidateAndSaveKey() }
                            .disabled(model.candidateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isValidatingKey)
                        if model.isValidatingKey { ProgressView().controlSize(.small) }
                        Spacer()
                        if model.configuredKeySuffix != nil {
                            Button("移除", role: .destructive) { confirmKeyRemoval = true }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("关于").font(.headline)
                    Text("Crypto Lens \(appVersion)").foregroundStyle(.secondary)
                    Text("股票代币标记来自随包审核目录；行情由 CoinMarketCap 提供。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("仅供信息，不构成投资建议。股票代币不是传统股票，其结构、权利、价格及可用地区取决于发行方，价格可能偏离标的资产。Crypto Lens 不提供交易服务。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Link("Backed xStocks", destination: URL(string: "https://assets.backed.fi/products")!)
                        Link("Ondo Global Markets", destination: URL(string: "https://docs.ondo.finance/ondo-stocks/available-assets")!)
                    }
                    .font(.caption)
                }
            }
            .padding(14)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var footer: some View {
        HStack {
            Button("设置", systemImage: "gearshape") { model.showSettings() }
                .labelStyle(.iconOnly)
                .help("设置")
                .opacity(model.mode == .settings ? 0 : 1)
                .disabled(model.mode == .settings)
                .frame(width: 32)
            Spacer()
            Link("Data by CoinMarketCap", destination: URL(string: "https://coinmarketcap.com/")!)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("退出 Crypto Lens", systemImage: "power") { model.beginQuit() }
                .labelStyle(.iconOnly)
                .help("退出 Crypto Lens")
                .frame(width: 32)
        }
        .padding(.horizontal, 8)
    }
}

private struct WatchlistRow: View {
    let item: WatchlistItem
    let quote: PriceQuote?
    let isStale: Bool
    let isHighlighted: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            AssetLogo(
                url: quote?.logoURL ?? item.asset.logoURL,
                fallbackSystemName: item.asset.kind == .stockToken ? "building.columns" : "bitcoinsign.circle"
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(item.asset.symbol).font(.system(.body, design: .rounded).weight(.semibold))
                    if item.asset.kind == .stockToken {
                        Text("股票代币")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                            .accessibilityLabel("股票代币")
                    }
                }
                Text(item.asset.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 4) {
                    if isStale { Image(systemName: "clock").font(.caption2) }
                    Text(quote.map { PriceFormatter.price($0.price) } ?? "—")
                }
                Text(PriceFormatter.change(quote?.change24hPercent))
                    .foregroundStyle(changeColor)
                    .frame(minHeight: 14)
            }
            .font(.system(.body, design: .monospaced))
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            Group {
                if isHovering {
                    Button("移除", systemImage: "trash", role: .destructive, action: remove)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .help("移除")
                } else {
                    Menu("更多", systemImage: "ellipsis") {
                        reorderCommands
                        Divider()
                        Button("移除", systemImage: "trash", role: .destructive, action: remove)
                    }
                    .labelStyle(.iconOnly)
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }
            }
            .frame(width: 22)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(isHighlighted ? Color.accentColor.opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            reorderCommands
            Divider()
            Button("移除", systemImage: "trash", role: .destructive, action: remove)
        }
        .help(tooltip)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var changeColor: Color {
        guard let change = quote?.change24hPercent else { return .secondary }
        return change < 0 ? .red : .green
    }

    @ViewBuilder
    private var reorderCommands: some View {
        Button("上移", systemImage: "arrow.up", action: moveUp).disabled(!canMoveUp)
        Button("下移", systemImage: "arrow.down", action: moveDown).disabled(!canMoveDown)
    }

    private var tooltip: String {
        guard let quote else { return item.asset.name }
        let stale = isStale ? String(localized: "，行情可能已过时") : ""
        var price = quote.price
        let priceText = NSDecimalString(&price, Locale(identifier: "en_US_POSIX"))
        return String(localized: "\(item.asset.name)：\(priceText) USD\(stale)")
    }

    private var accessibilityLabel: String {
        let kind = item.asset.kind == .stockToken ? String(localized: "，股票代币") : ""
        guard let quote else {
            return String(localized: "\(item.asset.name)，\(item.asset.symbol)\(kind)，暂无行情")
        }
        let stale = isStale ? String(localized: "，行情可能已过时") : ""
        let price = PriceFormatter.accessibilityPrice(quote.price)
        let change = PriceFormatter.accessibilityChange(quote.change24hPercent)
        return String(localized: "\(item.asset.name)，\(item.asset.symbol)\(kind)，\(price)，\(change)\(stale)")
    }
}

private struct WatchlistDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?
    let preview: (UUID, UUID) -> Void
    let cancel: () -> Void
    let commit: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedID else { return }
        preview(draggedID, targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggedID != nil else { return false }
        draggedID = nil
        commit()
        return true
    }

    func dropExited(info: DropInfo) {
        cancel()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct SearchResultRow: View {
    let result: SearchResult
    let isAdded: Bool
    let isFull: Bool
    let add: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AssetLogo(url: result.thumbURL, fallbackSystemName: "circle.dotted")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(result.asset.symbol).fontWeight(.semibold)
                    if result.asset.kind == .stockToken { Text("股票代币").font(.caption2).foregroundStyle(.secondary) }
                }
                Text(result.asset.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            if let rank = result.marketCapRank {
                Text("#\(rank)").font(.caption).foregroundStyle(.secondary).fixedSize()
            }
            Button(isAdded ? "已添加" : "添加", systemImage: isAdded ? "checkmark" : "plus", action: add)
                .labelStyle(.iconOnly)
                .disabled(!isAdded && isFull)
                .help(isAdded ? "已在列表中" : (isFull ? "关注列表已满" : "添加"))
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }
}

private struct AssetLogo: View {
    let url: URL?
    let fallbackSystemName: String

    var body: some View {
        AsyncImage(url: url) { image in
            image
                .resizable()
                .scaledToFit()
                .clipShape(Circle())
        } placeholder: {
            Image(systemName: fallbackSystemName)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(width: 28, height: 28)
    }
}

#Preview {
    RootPanelView(model: AppEnvironment.live().panelViewModel)
        .frame(width: 360, height: 480)
}
