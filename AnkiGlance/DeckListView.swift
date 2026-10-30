import GlanceCore
import SwiftUI

struct DeckListView: View {
    @Environment(AppModel.self) private var model
    /// Measured height of the rows, so the list is exactly as tall as its decks (up to 300 points, then it scrolls).
    @State private var rowsHeight: CGFloat = 0

    var body: some View {
        if model.panel.connection == .unknown {
            ProgressView().controlSize(.small)
        } else if model.panel.summaries.isEmpty {
            MessageView(symbol: "tray", title: "No decks", detail: "Create a deck in Anki to start reviewing.") {}
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.panel.summaries) { summary in
                        DeckRow(summary: summary) {
                            Task { await model.panel.startReview(summary.deck.name) }
                        }
                    }
                }
                .padding(5)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
            }
            .frame(height: min(rowsHeight, 300))
        }
    }
}

struct DeckRow: View {
    let summary: DeckSummary
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Text(summary.deck.shortName)
                    .lineLimit(1)
                    .foregroundStyle(summary.counts.due > 0 ? .primary : .secondary)
                    .padding(.leading, CGFloat(summary.deck.depth) * 12)
                Spacer()
                CountsView(counts: summary.counts)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Anki's new · learning · review counts, in Anki's colors.
struct CountsView: View {
    let counts: DeckCounts

    var body: some View {
        HStack(spacing: 6) {
            count(counts.new, .blue)
            count(counts.learning, .red)
            count(counts.review, .green)
        }
        .font(.body.monospacedDigit())
    }

    private func count(_ value: Int, _ color: Color) -> some View {
        Text("\(value)")
            .foregroundStyle(value > 0 ? color : .secondary.opacity(0.5))
            .frame(minWidth: 20, alignment: .trailing)
    }
}
