import AppKit
import SwiftUI

struct RootPanelView: View {
    @Bindable var model: PanelViewModel
    @State private var confirmKeyRemoval = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 50)
            Divider()

            if let message = model.bannerMessage, !message.isEmpty {
                statusBanner(message)
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
        .background {
            PanelWindowObserver { visible in
                model.panelVisibilityChanged(isVisible: visible)
            }
        }
        .task { await model.bootstrap() }
        .confirmationDialog(
            "移除 API Key？",
            isPresented: $confirmKeyRemoval,
            titleVisibility: .visible
        ) {
            Button("移除 API Key", role: .destructive) { model.removeAPIKey() }
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    private var refreshHelp: String {
        if model.items.isEmpty { return "暂无关注资产" }
        if model.configuredKeySuffix == nil { return "请先配置 API Key" }
        if model.manualRefreshRemaining > 0 { return "\(model.manualRefreshRemaining) 秒后可刷新" }
        return "刷新行情"
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message).lineLimit(2)
            Spacer(minLength: 0)
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
            TextField("搜索 CoinGecko 资产", text: $model.query)
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
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.items) { item in
                        WatchlistRow(
                            item: item,
                            quote: model.quotes[item.asset.assetID],
                            isStale: model.quotes[item.asset.assetID].map(model.isStale) ?? false,
                            canMoveUp: item.id != model.items.first?.id,
                            canMoveDown: item.id != model.items.last?.id,
                            moveUp: { Task { await model.move(item, by: -1) } },
                            moveDown: { Task { await model.move(item, by: 1) } },
                            remove: { Task { await model.remove(item) } }
                        )
                        Divider().padding(.leading, 52)
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
                    Text("CoinGecko Demo API Key").font(.headline)
                    if let suffix = model.configuredKeySuffix {
                        Label("已配置 ····\(suffix)", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    SecureField("输入新的 Demo API Key", text: $model.candidateKey)
                        .textFieldStyle(.roundedBorder)
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
                    Text("股票代币标记来自随包审核目录；行情由 CoinGecko 提供。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            Link("Data by CoinGecko", destination: URL(string: "https://www.coingecko.com")!)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("退出 Crypto Lens", systemImage: "power") { model.quit() }
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
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.asset.kind == .stockToken ? "building.columns" : "bitcoinsign.circle")
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(item.asset.symbol).font(.system(.body, design: .rounded).weight(.semibold))
                    if item.asset.kind == .stockToken {
                        Text("股票代币")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(item.asset.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
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
            Menu("更多", systemImage: "ellipsis") {
                Button("上移", systemImage: "arrow.up", action: moveUp).disabled(!canMoveUp)
                Button("下移", systemImage: "arrow.down", action: moveDown).disabled(!canMoveDown)
                Divider()
                Button("移除", systemImage: "trash", role: .destructive, action: remove)
            }
            .labelStyle(.iconOnly)
            .menuStyle(.borderlessButton)
            .frame(width: 22)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .help(isStale ? "行情可能已过时" : item.asset.name)
    }

    private var changeColor: Color {
        guard let change = quote?.change24hPercent else { return .secondary }
        return change < 0 ? .red : .green
    }
}

private struct SearchResultRow: View {
    let result: SearchResult
    let isAdded: Bool
    let isFull: Bool
    let add: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: result.thumbURL) { image in image.resizable().scaledToFit() } placeholder: {
                Image(systemName: "circle.dotted")
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(result.asset.symbol).fontWeight(.semibold)
                    if result.asset.kind == .stockToken { Text("股票代币").font(.caption2).foregroundStyle(.secondary) }
                }
                Text(result.asset.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 5)
            if let rank = result.marketCapRank {
                Text("#\(rank)").font(.caption).foregroundStyle(.secondary)
            }
            Button(isAdded ? "已添加" : "添加", systemImage: isAdded ? "checkmark" : "plus", action: add)
                .labelStyle(.iconOnly)
                .disabled(isAdded || isFull)
                .help(isAdded ? "已在列表中" : (isFull ? "关注列表已满" : "添加"))
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }
}

#Preview {
    RootPanelView(model: AppEnvironment.live().panelViewModel)
        .frame(width: 360, height: 480)
}
