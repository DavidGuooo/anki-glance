#if DEBUG
import AppKit
import GlanceCore
import SwiftUI

/// Debug builds only: `--preview-panel` shows the panel in an ordinary window, so it can be checked and
/// screenshotted without clicking the menu bar.
///   `--preview-card <id>` shows one card (read-only: render and predict, never answer).
///   `--preview-reveal` also reveals its answer.
///   `--preview-dark` forces dark mode.
///   `--preview-settings` opens the Settings screen.
///   `--preview-status <notInstalled|notRunning|launching|noAnkiConnect|notReady|failed>` forces a status screen.
@MainActor
enum PanelPreviewWindow {
    private static var window: NSWindow?

    static func show(model: AppModel) {
        DispatchQueue.main.async {
            if CommandLine.arguments.contains("--preview-dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
            let window = NSWindow(contentViewController: NSHostingController(rootView: PanelView().environment(model)))
            window.title = "Anki Glance Panel Preview"
            window.styleMask = [.titled, .closable]
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            Self.window = window
            model.forcedStatus = switch argument(after: "--preview-status") {
            case "notInstalled": .notInstalled
            case "notRunning": .notRunning
            case "launching": .launching
            case "noAnkiConnect": .noAnkiConnect
            case "notReady": .notReady
            case "failed": .failed("Deck counts unavailable.")
            default: nil
            }
            if CommandLine.arguments.contains("--preview-settings") { model.panel.openSettings() }
            if let id = argument(after: "--preview-card") {
                Task { await model.previewCard(id, reveal: CommandLine.arguments.contains("--preview-reveal")) }
            }
        }
    }

    private static func argument(after flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag), index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }
}

/// Hands out one card, then reports the deck as done.
private actor SingleCardQueue: QueueSource {
    private var card: CardID?
    init(_ card: CardID) { self.card = card }
    func next(deck: String) async throws -> QueueStep {
        defer { card = nil }
        return card.map(QueueStep.card) ?? .done
    }
}

extension AppModel {
    func previewCard(_ id: CardID, reveal: Bool) async {
        await panel.show(ReviewSession(deck: "Preview", anki: client, queue: SingleCardQueue(id)))
        if reveal { panel.reveal() }
    }
}
#endif
