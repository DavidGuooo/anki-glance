import AppKit
import GlanceCore
import SwiftUI

/// The app's identity, then what's wrong, then the one thing to do about it.
struct StatusScreen: View {
    @Environment(AppModel.self) private var model
    let status: AnkiStatus
    @State private var copiedLogs = false

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 5) {
                AppMark()
                    .padding(.bottom, 3)
                Text("Anki Glance")
                    .font(.headline)
                Text("Review your Anki cards from the menu bar.")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            statusBox
            actions
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var statusBox: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                if status == .launching {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle().fill(tint).frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.callout.weight(.medium))
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder private var actions: some View {
        switch status {
        case .notInstalled:
            primary("Get Anki") { NSWorkspace.shared.open(URL(string: "https://apps.ankiweb.net")!) }
        case .notRunning:
            primary("Launch Anki") { Task { await model.panel.launchAnki() } }
        case .launching:
            EmptyView()
        case .noAnkiConnect:
            VStack(spacing: 6) {
                primary("Get AnkiConnect") {
                    NSWorkspace.shared.open(URL(string: "https://ankiweb.net/shared/info/2055492159")!)
                }
                Button("Try Again") { Task { await model.panel.refresh() } }
                    .buttonStyle(LinkButtonStyle())
                    .font(.callout)
            }
        case .notReady:
            primary("Try Again") { Task { await model.panel.refresh() } }
        case .failed(let message):
            VStack(spacing: 6) {
                primary("Try Again") { Task { await model.panel.refresh() } }
                Button(copiedLogs ? "Copied" : "Copy Logs") {
                    model.copyLogs(problem: message)
                    copiedLogs = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedLogs = false
                    }
                }
                .buttonStyle(LinkButtonStyle())
                .font(.callout)
            }
        }
    }

    private func primary(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).padding(.horizontal, 6)
        }
        .buttonStyle(FilledButtonStyle(prominent: true))
        .keyboardShortcut(.defaultAction)
    }

    private var title: String {
        switch status {
        case .notInstalled: "Anki isn't installed"
        case .notRunning: "Anki isn't running"
        case .launching: "Opening Anki…"
        case .noAnkiConnect: "AnkiConnect isn't set up"
        case .notReady: "Anki isn't ready"
        case .failed: "Something went wrong"
        }
    }

    private var detail: String? {
        switch status {
        case .noAnkiConnect: "Add it in Anki with code 2055492159,\nthen restart Anki."
        case .failed(let message): message
        case .notInstalled, .notRunning, .launching, .notReady: nil
        }
    }

    private var tint: Color {
        switch status {
        case .notInstalled, .failed: .red
        case .notRunning, .noAnkiConnect: .orange
        case .launching, .notReady: .yellow
        }
    }
}

/// A small app-icon-style mark using the same symbol as the menu bar item.
struct AppMark: View {
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.38, green: 0.58, blue: 1.0), Color(red: 0.33, green: 0.31, blue: 0.86)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}
