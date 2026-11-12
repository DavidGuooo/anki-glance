#if SPARKLE
import Observation
import Sparkle

/// Self-update for the direct-download build. The Mac App Store build compiles this file to
/// nothing: the store updates that copy, and Sparkle must not be in its binary.
@MainActor @Observable
final class Updater {
    static let shared = Updater()

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var checksAutomatically: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    private init() {
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
#endif
