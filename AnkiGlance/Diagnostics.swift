import AppKit
import os

/// Recent events kept in memory (and sent to the system log), so "Copy logs" can give the user
/// something to paste into a bug report.
@MainActor
final class Diagnostics {
    private static let logger = Logger(subsystem: "com.guodawei.ankiglance", category: "app")
    private var events: [String] = []
    private let limit = 200

    func record(_ message: String) {
        Self.logger.notice("\(message, privacy: .public)")
        events.append("\(Date().formatted(.iso8601)) \(message)")
        if events.count > limit { events.removeFirst(events.count - limit) }
    }

    /// Copies a plain-text report: versions, AnkiConnect settings, the current problem and recent events.
    func copyReport(problem: String, port: Int, hasAPIKey: Bool) {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))"
        let ankiRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: AppModel.ankiBundleID).isEmpty
        let report = """
        Anki Glance \(version)
        \(ProcessInfo.processInfo.operatingSystemVersionString)
        AnkiConnect: 127.0.0.1:\(port), API key \(hasAPIKey ? "set" : "not set")
        Anki running: \(ankiRunning ? "yes" : "no")
        Problem: \(problem)

        Recent events:
        \(events.isEmpty ? "(none)" : events.joined(separator: "\n"))
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}
