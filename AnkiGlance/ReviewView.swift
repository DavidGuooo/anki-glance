import GlanceCore
import SwiftUI

struct ReviewView: View {
    @Environment(AppModel.self) private var model
    let session: ReviewSession

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                ProgressView().controlSize(.small)
            case .question(let card):
                cardView(html: card.questionHtml) {
                    Button { model.panel.reveal() } label: {
                        Text("Show Answer").frame(maxWidth: .infinity)
                    }
                    .help("Space")
                }
            case .answer(let card):
                cardView(html: card.answerHtml) {
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
                        .keyboardShortcut(.defaultAction)
                }
            case .failed(let message):
                MessageView(symbol: "exclamationmark.triangle", title: "Couldn't load the card", detail: message) {
                    Button("Try Again") { Task { await model.panel.startReview(session.deck) } }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cardView(html: String, @ViewBuilder controls: () -> some View) -> some View {
        VStack(spacing: 0) {
            CardWebView(html: html, media: model.media)
            Divider()
            VStack(spacing: 3) {
                controls()
                if session.canUndo {
                    Button("Undo last answer (⌘Z)") { Task { await model.panel.undo() } }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            .padding(7)
        }
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
            .padding(.vertical, 1)
        }
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
