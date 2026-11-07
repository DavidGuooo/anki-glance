import GlanceCore
import SwiftUI

struct ReviewView: View {
    /// Everything shows at the lower bound; an answer grows the panel to fit, up to the upper bound, then scrolls.
    static let heights: ClosedRange<CGFloat> = 320...640

    @Environment(AppModel.self) private var model
    let session: ReviewSession

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                ProgressView().controlSize(.small)
            case .question(let card):
                CardPanel(html: card.questionHtml, media: model.media, grows: false) {
                    Button { model.panel.reveal() } label: {
                        Text("Show Answer").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledButtonStyle())
                    .help("Space")
                }
            case .answer(let card):
                CardPanel(html: card.answerHtml, media: model.media, grows: true) {
                    HStack(spacing: 4) {
                        ForEach(Rating.allCases, id: \.self) { rating in
                            GradeButton(rating: rating, interval: card.prediction.label(for: rating)) {
                                Task { await model.panel.grade(rating) }
                            }
                        }
                    }
                }
            case .waiting(let until):
                WaitingView(until: until)
                    .task(id: until) {
                        try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow) + 1))
                        await session.refreshIfWaiting()
                    }
            case .done:
                MessageView(symbol: "checkmark.seal", title: "Done for today 🎉",
                            detail: session.reviewedCount == 1 ? "You reviewed 1 card." : "You reviewed \(session.reviewedCount) cards.") {
                    Button("Back to Decks") { Task { await model.panel.showDecks() } }
                        .buttonStyle(FilledButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                }
            case .failed(let message):
                MessageView(symbol: "exclamationmark.triangle", title: "Couldn't load the card", detail: message) {
                    Button("Try Again") { Task { await model.panel.startReview(session.deck) } }
                        .buttonStyle(FilledButtonStyle(prominent: true))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isAnswer ? nil : Self.heights.lowerBound)
    }

    private var isAnswer: Bool {
        if case .answer = session.phase { true } else { false }
    }
}

/// A card with its buttons below. A growing one is as tall as its content within `ReviewView.heights`.
/// Each phase gets its own instance, so a new answer starts measuring from scratch.
struct CardPanel<Controls: View>: View {
    let html: String
    let media: MediaCache
    let grows: Bool
    @ViewBuilder var controls: Controls
    @State private var cardHeight: CGFloat = 0
    @State private var controlsHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            CardWebView(html: html, media: media) { cardHeight = $0 }
            Divider()
            controls
                .padding(7)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
        }
        .frame(height: grows ? fittedHeight : nil)
    }

    private var fittedHeight: CGFloat {
        let content = (cardHeight + 1 + controlsHeight).rounded(.up)
        return min(max(content, ReviewView.heights.lowerBound), ReviewView.heights.upperBound)
    }
}

struct GradeButton: View {
    let rating: Rating
    let interval: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(interval)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(rating.title)
                    .fontWeight(.medium)
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(FilledButtonStyle())
        .help("\(rating.number)")
    }

    private var color: Color {
        switch rating {
        case .again: .red
        case .hard: .secondary
        case .good: .green
        case .easy: .blue
        }
    }
}

struct WaitingView: View {
    let until: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            MessageView(symbol: "hourglass", title: "Next card in \(remaining(from: context.date))",
                        detail: "Learning cards come back after their step. This panel continues by itself.") {}
        }
    }

    private func remaining(from now: Date) -> String {
        let seconds = max(0, Int(until.timeIntervalSince(now)))
        return seconds >= 60 ? "\(Int((Double(seconds) / 60).rounded(.up)))m" : "\(seconds)s"
    }
}
