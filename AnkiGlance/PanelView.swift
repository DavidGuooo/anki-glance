import GlanceCore
import SwiftUI

/// The window under the menu bar icon. Home is the deck list with Settings and Quit at the bottom;
/// a review or settings gets a header with a back button instead.
struct PanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private var panel: Panel { model.panel }

    var body: some View {
        VStack(spacing: 0) {
            if panel.screen != .decks {
                header
                Divider()
            }
            content
                .frame(maxWidth: .infinity)
                .frame(height: contentHeight)
            if panel.screen == .decks {
                Divider()
                footer
            }
        }
        .frame(width: width)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down, action: handleKey)
        .background(WindowObserver(
            onOpen: {
                focused = true
                Task { await panel.opened() }
            },
            onClose: { Task { await panel.closed() } }
        ))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                Task { await panel.back() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("Back")
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if panel.screen == .review, let left = panel.cardsLeft {
                Text(left == 1 ? "1 card left" : "\(left) cards left")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Button("Settings") { panel.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(FooterButtonStyle())
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
    }

    /// Cards and settings get a fixed height; the deck list and status screens size themselves (`nil`).
    private var contentHeight: CGFloat? {
        switch panel.screen {
        case .settings: 285
        case .review where model.status == nil: 220
        default: nil
        }
    }

    /// The deck list is narrow; status screens need room for the one-line tagline; cards and settings get the most.
    private var width: CGFloat {
        if model.status != nil { return 300 }
        return panel.screen == .decks ? 240 : 340
    }

    private var title: String {
        switch panel.screen {
        case .decks: ""
        case .review: panel.session?.deck.components(separatedBy: "::").last ?? "Review"
        case .settings: "Settings"
        }
    }

    @ViewBuilder private var content: some View {
        if panel.screen == .settings {
            SettingsView()
        } else if let status = model.status {
            StatusScreen(status: status)
        } else if panel.screen == .review, let session = panel.session {
            ReviewView(session: session)
        } else {
            DeckListView()
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape {
            dismiss()
            return .handled
        }
        let key: PanelKey? = switch (press.key, press.modifiers) {
        case (.space, []): .space
        case (.return, []): .returnKey
        case (_, .command) where press.characters == "z": .undo
        case (_, []): Int(press.characters).map(PanelKey.number)
        default: nil
        }
        guard let key, let action = panel.action(for: key) else { return .ignored }
        Task { await action() }
        return .handled
    }
}

/// Footer actions: plain text that highlights on hover like the deck rows, so it reads as clickable.
struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FooterButton(configuration: configuration)
    }

    private struct FooterButton: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.primary.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.07 : 0),
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

struct MessageView<Actions: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actions.padding(.top, 2)
        }
        .padding(16)
    }
}

/// Reports when the MenuBarExtra window opens (becomes key) and closes (resigns key).
struct WindowObserver: NSViewRepresentable {
    let onOpen: @MainActor () -> Void
    let onClose: @MainActor () -> Void

    func makeNSView(context: Context) -> ObservingView {
        ObservingView(onOpen: onOpen, onClose: onClose)
    }

    func updateNSView(_ view: ObservingView, context: Context) {}

    final class ObservingView: NSView {
        let onOpen: @MainActor () -> Void
        let onClose: @MainActor () -> Void
        private var observers: [NSObjectProtocol] = []

        init(onOpen: @escaping @MainActor () -> Void, onClose: @escaping @MainActor () -> Void) {
            self.onOpen = onOpen
            self.onClose = onClose
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [onOpen] _ in
                MainActor.assumeIsolated { onOpen() }
            })
            observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [onClose] _ in
                MainActor.assumeIsolated { onClose() }
            })
            if window.isKeyWindow { onOpen() }
        }
    }
}
