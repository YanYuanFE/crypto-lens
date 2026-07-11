import AppKit
import SwiftUI
import XCTest
@testable import CryptoLens

@MainActor
final class PanelSnapshotTests: XCTestCase {
    func testPanelModesRenderAtStressWidths() throws {
        let defaultOutputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CryptoLensPanelSnapshots", isDirectory: true)
        let outputDirectory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["CRYPTO_LENS_SNAPSHOT_DIR"]
                ?? defaultOutputDirectory.path
        )
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for width in [320, 360, 380] {
            for mode in [PanelMode.watchlist, .search, .settings] {
                let model = makeModel(mode: mode)
                let bitmap = try render(model: model, width: width)

                XCTAssertEqual(bitmap.pixelsWide, width * 2)
                XCTAssertEqual(bitmap.pixelsHigh, 960)
                assertOpaque(bitmap)
                XCTAssertGreaterThan(try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).count, 10_000)

                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: outputDirectory.appendingPathComponent("panel-\(mode.name)-\(width).png"))
            }
        }
    }

    private func assertOpaque(_ bitmap: NSBitmapImageRep) {
        var sampledPixelCount = 0
        var blackPixelCount = 0
        for x in stride(from: 2, to: bitmap.pixelsWide, by: 80) {
            for y in stride(from: 2, to: bitmap.pixelsHigh, by: 80) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    XCTFail("Unable to read snapshot pixel")
                    continue
                }
                sampledPixelCount += 1
                XCTAssertGreaterThan(color.alphaComponent, 0.99)
                if color.redComponent + color.greenComponent + color.blueComponent < 0.1 {
                    blackPixelCount += 1
                }
            }
        }
        XCTAssertLessThan(blackPixelCount, sampledPixelCount / 4)
    }

    private func render(model: PanelViewModel, width: Int) throws -> NSBitmapImageRep {
        let size = NSSize(width: width, height: 480)
        let hostingView = NSHostingView(
            rootView: ZStack {
                Color(nsColor: .windowBackgroundColor)
                RootPanelView(model: model, bootstrapsOnAppear: false)
            }
            .frame(width: size.width, height: size.height)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.contentView = hostingView
        hostingView.appearance = window.appearance
        hostingView.frame = NSRect(origin: .zero, size: size)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        hostingView.displayIfNeeded()

        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width * 2,
                pixelsHigh: 960,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: [],
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSGraphicsContext.restoreGraphicsState()
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        window.orderOut(nil)
        window.contentView = nil
        window.close()
        return bitmap
    }

    private func makeModel(mode: PanelMode) -> PanelViewModel {
        let service = SnapshotMarketService()
        let model = PanelViewModel(
            watchlist: WatchlistUseCase(store: SnapshotWatchlistStore()),
            cacheStore: PriceCacheStore(directoryURL: FileManager.default.temporaryDirectory),
            apiKeyStore: SnapshotAPIKeyStore(),
            searcher: service,
            priceProvider: service,
            keyValidator: service,
            networkState: service,
            classifier: SnapshotClassifier(),
            terminationHandler: {}
        )
        let bitcoin = asset(id: "bitcoin", symbol: "BTC", name: "Bitcoin", kind: .crypto)
        let apple = asset(
            id: "apple-xstock",
            symbol: "AAPLX",
            name: "Apple Incorporated Tokenized Equity With A Very Long Display Name",
            kind: .stockToken
        )
        model.isBootstrapping = false
        model.items = [
            WatchlistItem(id: UUID(), asset: bitcoin, sortOrder: 0, addedAt: Date()),
            WatchlistItem(id: UUID(), asset: apple, sortOrder: 1, addedAt: Date())
        ]
        model.quotes = [
            bitcoin.assetID: quote(bitcoin.assetID, price: "68234.12", change: "2.14"),
            apple.assetID: quote(apple.assetID, price: "231.45", change: "-0.32")
        ]
        model.mode = mode
        if mode == .search {
            model.query = "app"
            model.searchResults = [
                SearchResult(asset: apple, marketCapRank: 1_214, thumbURL: nil),
                SearchResult(
                    asset: asset(
                        id: "ethereum",
                        symbol: "ETH",
                        name: "Ethereum With A Very Long Search Result Name",
                        kind: .crypto
                    ),
                    marketCapRank: nil,
                    thumbURL: nil
                )
            ]
        }
        return model
    }

    private func asset(id: String, symbol: String, name: String, kind: AssetKind) -> Asset {
        Asset(
            assetID: AssetID(rawValue: id, source: .coinGecko),
            symbol: symbol,
            name: name,
            kind: kind,
            platform: nil,
            contractAddress: nil
        )
    }

    private func quote(_ id: AssetID, price: String, change: String) -> PriceQuote {
        PriceQuote(
            assetID: id,
            currency: "usd",
            price: Decimal(string: price)!,
            change24hPercent: Decimal(string: change),
            fetchedAt: Date(),
            lastUpdatedAt: Date(),
            source: .coinGecko
        )
    }
}

private extension PanelMode {
    var name: String {
        switch self {
        case .watchlist: "watchlist"
        case .search: "search"
        case .settings: "settings"
        }
    }
}

private actor SnapshotMarketService: AssetSearching, PriceProviding, APIKeyValidating, NetworkStateProviding {
    func search(query: String) async throws -> [SearchResult] { [] }
    func prices(for assets: [Asset], currency: String) async throws -> [PriceQuote] { [] }
    func validate(candidateKey: String) async throws {}
    var nextAllowedRequestAt: Date? { nil }
    func resetNetworkState() async {}
}

private actor SnapshotWatchlistStore: WatchlistStoring {
    func load() async throws -> [WatchlistItem] { [] }
    func save(_ items: [WatchlistItem]) async throws {}
}

private struct SnapshotAPIKeyStore: APIKeyStoring {
    func loadAPIKey() throws -> String? { "snapshot-key" }
    func saveAPIKey(_ key: String) throws {}
    func deleteAPIKey() throws {}
}

private struct SnapshotClassifier: StockTokenClassifying {
    func kind(for asset: Asset) -> AssetKind { asset.kind }
}
