import SwiftUI

@main
struct CryptoLensApp: App {
    @State private var model = AppEnvironment.live().panelViewModel

    var body: some Scene {
        MenuBarExtra {
            RootPanelView(model: model)
                .frame(width: 360, height: 480)
        } label: {
            Label("Crypto Lens", systemImage: "chart.line.uptrend.xyaxis")
                .labelStyle(.iconOnly)
                .accessibilityLabel("Crypto Lens")
        }
        .menuBarExtraStyle(.window)
    }
}
