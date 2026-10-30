import SwiftUI

/// Plain text that gets a soft rounded highlight on hover, like the deck rows. For quiet actions:
/// the back arrow, Settings, Quit.
struct QuietButtonStyle: ButtonStyle {
    var horizontal: CGFloat = 8
    var vertical: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
        Hovering { hovering in
            configuration.label
                .foregroundStyle(.primary.opacity(0.85))
                .padding(.horizontal, horizontal)
                .padding(.vertical, vertical)
                .background(Color.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.07 : 0),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
    }
}

/// A filled rounded button that lightens on hover and darkens when pressed. `prominent` uses the accent color,
/// for the one main action on a screen.
struct FilledButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        Hovering { hovering in
            configuration.label
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: 28)
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(fill(pressed: configuration.isPressed, hovering: hovering),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
    }

    private func fill(pressed: Bool, hovering: Bool) -> AnyShapeStyle {
        if prominent {
            let tint = Color.accentColor
            return AnyShapeStyle(pressed ? tint.opacity(0.75) : hovering ? tint.opacity(0.88) : tint)
        }
        return AnyShapeStyle(Color.primary.opacity(pressed ? 0.17 : hovering ? 0.11 : 0.06))
    }
}

/// Accent-colored text that underlines on hover: Try Again, Copy Logs, Undo.
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Hovering { hovering in
            configuration.label
                .foregroundStyle(Color.accentColor.opacity(configuration.isPressed ? 0.7 : 1))
                .underline(hovering)
                .contentShape(Rectangle())
        }
    }
}

/// Tracks whether the pointer is over its content.
private struct Hovering<Content: View>: View {
    @ViewBuilder var content: (Bool) -> Content
    @State private var hovering = false

    var body: some View {
        content(hovering).onHover { hovering = $0 }
    }
}
