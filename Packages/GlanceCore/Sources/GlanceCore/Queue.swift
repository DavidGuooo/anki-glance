import Foundation

public enum QueueStep: Sendable, Equatable {
    case card(CardID)
    /// Nothing is due now, but a learning card comes back at this time today.
    case waiting(until: Date)
    case done
}

/// Picks the next card to show for a deck. v1 approximates Anki's order locally; the M2 add-on returns Anki's exact queue.
public protocol QueueSource: Sendable {
    func next(deck: String) async throws -> QueueStep
}

/// Approximates Anki's v3 queue from searches. The limits are exact (they come from `decks.getCounts`); only the order is approximate:
/// due learning cards first, then reviews with new cards spread evenly between them, then learning cards up to 20 minutes early.
public actor LocalQueueSource: QueueSource {
    private let anki: AnkiService
    private let now: @Sendable () -> Date
    /// Anki's default "learn ahead limit" (`collapseTime`).
    private let learnAhead: TimeInterval = 20 * 60
    private var reviewsSinceNew = 0

    public init(anki: AnkiService, now: @escaping @Sendable () -> Date = { Date() }) {
        self.anki = anki
        self.now = now
    }

    public func next(deck: String) async throws -> QueueStep {
        let scope = Self.deckQuery(deck)

        if let id = try await anki.searchCards("\(scope) is:learn is:due", limit: 1, sortByDue: true).first {
            return .card(id)
        }

        let counts = try await anki.counts(deck: deck)
        let newQuery = "\(scope) is:new -is:suspended -is:buried"
        let reviewsPerNew = counts.new > 0 ? max(1, counts.review / counts.new) : .max
        if counts.new > 0, counts.review == 0 || reviewsSinceNew >= reviewsPerNew,
           let id = try await anki.searchCards(newQuery, limit: 1, sortByDue: false).first {
            reviewsSinceNew = 0
            return .card(id)
        }
        if counts.review > 0, let id = try await anki.searchCards("\(scope) is:review is:due", limit: 1, sortByDue: true).first {
            reviewsSinceNew += 1
            return .card(id)
        }
        if counts.new > 0, let id = try await anki.searchCards(newQuery, limit: 1, sortByDue: false).first {
            reviewsSinceNew = 0
            return .card(id)
        }

        let learning = try await anki.searchCards("\(scope) is:learn -is:suspended -is:buried", limit: 100, sortByDue: true)
        let upcoming = try await anki.schedules(learning).compactMap { schedule -> (CardID, Date)? in
            guard case .timestamp(let date) = schedule.due else { return nil }
            return (schedule.id, date)
        }
        guard let (id, due) = upcoming.min(by: { $0.1 < $1.1 }) else { return .done }
        if due.timeIntervalSince(now()) <= learnAhead { return .card(id) }
        return due < (try await anki.nextDayStarts()) ? .waiting(until: due) : .done
    }

    /// `deck:"…"` with Anki's search wildcards (`*`, `_`) and quotes escaped. Includes sub-decks, like Anki.
    static func deckQuery(_ deck: String) -> String {
        var escaped = ""
        for character in deck {
            if character == "\\" || character == "\"" || character == "*" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return "deck:\"\(escaped)\""
    }
}
