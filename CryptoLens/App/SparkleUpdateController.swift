import Sparkle

@MainActor
final class SparkleUpdateController: NSObject, SPUStandardUserDriverDelegate {
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    override init() {
        super.init()
        _ = updaterController
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
