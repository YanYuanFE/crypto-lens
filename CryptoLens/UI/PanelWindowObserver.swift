import AppKit
import SwiftUI

struct PanelWindowObserver: NSViewRepresentable {
    let visibilityChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(visibilityChanged: visibilityChanged)
    }

    func makeNSView(context: Context) -> NSView {
        let view = WindowReaderView()
        view.windowChanged = { window in context.coordinator.observe(window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        private let visibilityChanged: (Bool) -> Void
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        init(visibilityChanged: @escaping (Bool) -> Void) {
            self.visibilityChanged = visibilityChanged
        }

        func observe(_ window: NSWindow?) {
            guard self.window !== window else { return }
            stop()
            self.window = window
            guard let window else { return }
            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didMiniaturizeNotification
            ]
            observers = names.map { name in
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.publish() }
                }
            }
            publish()
        }

        func stop() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            if window != nil { visibilityChanged(false) }
            window = nil
        }

        private func publish() {
            guard let window else { return }
            visibilityChanged(window.isVisible && window.occlusionState.contains(.visible))
        }
    }
}

private final class WindowReaderView: NSView {
    var windowChanged: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowChanged?(window)
    }
}
