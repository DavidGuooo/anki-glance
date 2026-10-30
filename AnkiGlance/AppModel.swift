import AppKit
import GlanceCore
import Observation
import ServiceManagement

/// App-level wiring around the `Panel`: settings, the AnkiConnect client, diagnostics and the background refresh.
@MainActor @Observable
final class AppModel {
    static let ankiBundleID = "net.ankiweb.anki"

    private(set) var panel: Panel
    private(set) var media: MediaCache
    @ObservationIgnored private(set) var client: AnkiConnectClient
    let diagnostics = Diagnostics()
    #if DEBUG
    /// Set by `--preview-status` to show a status screen regardless of Anki's real state.
    var forcedStatus: AnkiStatus?
    #endif

    var port: Int {
        didSet { defaults.set(port, forKey: "port"); rebuildPanel() }
    }
    var apiKey: String {
        didSet { defaults.set(apiKey, forKey: "apiKey"); rebuildPanel() }
    }
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let ankiApp = WorkspaceAnki()
    @ObservationIgnored private let lastDeck = DefaultsLastDeck()

    init() {
        let port = UserDefaults.standard.object(forKey: "port") as? Int ?? 8765
        let apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        self.port = port
        self.apiKey = apiKey
        (client, panel, media) = Self.makePanel(port: port, apiKey: apiKey, ankiApp: ankiApp, lastDeck: lastDeck, diagnostics: diagnostics)
        setUpLoginItemOnFirstLaunch()
        Task { await refreshLoop() }
    }

    /// The status screen to show, if any.
    var status: AnkiStatus? {
        #if DEBUG
        if let forcedStatus { return forcedStatus }
        #endif
        return panel.status
    }

    func copyLogs(problem: String) {
        diagnostics.copyReport(problem: problem, port: port, hasAPIKey: !apiKey.isEmpty)
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            await panel.tick()
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// A new port or API key means a new client, so start a fresh panel and stay on Settings.
    private func rebuildPanel() {
        (client, panel, media) = Self.makePanel(port: port, apiKey: apiKey, ankiApp: ankiApp, lastDeck: lastDeck, diagnostics: diagnostics)
        panel.openSettings()
        Task { await panel.refresh() }
    }

    private static func makePanel(port: Int, apiKey: String, ankiApp: AnkiApp, lastDeck: LastDeckStore,
                                  diagnostics: Diagnostics) -> (AnkiConnectClient, Panel, MediaCache) {
        let client = AnkiConnectClient(transport: URLSessionTransport(port: port, apiKey: apiKey.isEmpty ? nil : apiKey))
        let panel = Panel(anki: client, sync: client, ankiApp: ankiApp, store: lastDeck)
        panel.onEvent = { [diagnostics] in diagnostics.record($0) }
        return (client, panel, MediaCache { try await client.media($0) })
    }

    private func setUpLoginItemOnFirstLaunch() {
        guard !defaults.bool(forKey: "didSetUpLoginItem") else { return }
        defaults.set(true, forKey: "didSetUpLoginItem")
        try? SMAppService.mainApp.register()
    }
}

/// The real Anki desktop app, found and launched through NSWorkspace.
@MainActor
final class WorkspaceAnki: AnkiApp {
    private var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppModel.ankiBundleID) }

    var isInstalled: Bool { url != nil }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: AppModel.ankiBundleID).isEmpty
    }

    func launchHidden() async throws {
        guard let url else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}

/// Remembers the deck being reviewed in UserDefaults.
@MainActor
final class DefaultsLastDeck: LastDeckStore {
    var lastDeck: String? {
        get { UserDefaults.standard.string(forKey: "lastDeck") }
        set { UserDefaults.standard.set(newValue, forKey: "lastDeck") }
    }
}
