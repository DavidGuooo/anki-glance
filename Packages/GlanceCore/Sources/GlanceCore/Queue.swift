import Foundation

public enum QueueStep: Sendable, Equatable {
    case card(CardID)
    /// Nothing is due now, but a learning card comes back at this time today.
    case waiting(until: Date)
    case done
}

/// The card on screen, which `peek` leaves out while it waits to be graded.
public struct PendingCard: Sendable, Equatable {
    public let id: CardID
    public let noteId: String

    public init(id: CardID, noteId: String) {
        self.id = id
        self.noteId = noteId
    }
}

/// Picks the next card to show for a deck. v1 approximates Anki's order locally; the M2 add-on returns Anki's exact queue.
public protocol QueueSource: Sendable {
    func next(deck: String) async throws -> QueueStep
    /// The card that comes after `current` however `current` is graded, or `nil` when that depends on the grade.
    /// Lets the next card load while the answer is on screen. Changes nothing until `take` is called with the card.
    func peek(deck: String, after current: PendingCard) async throws -> CardID?
    /// Records that a card from `peek` is now on screen, as `next` would have.
    func take(_ id: CardID) async
}

public extension QueueSource {
    func peek(deck: String, after current: PendingCard) async throws -> CardID? { nil }
    func take(_ id: CardID) async {}
}

/// Approximates Anki's v3 queue from searches. The limits are exact (they come from `decks.getCounts`); only the order is approximate:
/// due learning cards first, then reviews with new cards spread evenly between them, then learning cards up to 20 minutes early.
public actor LocalQueueSource: QueueSource {
    private let anki: AnkiService
    private let now: @Sendable () -> Date
    /// Anki's default "learn ahead limit" (`collapseTime`).
    private let learnAhead: TimeInterval = 20 * 60
    private var reviewsSinceNew = 0
    /// Which part of the queue each picked card came from, for `take` and for the limits `peek` adjusts.
    private var kinds: [CardID: Kind] = [:]

    enum Kind { case dueLearning, new, review, learnAhead }

    private enum Pick {
        case card(CardID, Kind)
        case waiting(until: Date)
        case done
    }

    public init(anki: AnkiService, now: @escaping @Sendable () -> Date = { Date() }) {
        self.anki = anki
        self.now = now
    }

    public func next(deck: String) async throws -> QueueStep {
        switch try await pick(deck: deck, excluding: nil) {
        case .card(let id, let kind):
            record(id, kind)
            return .card(id)
        case .waiting(let until): return .waiting(until: until)
        case .done: return .done
        }
    }

    public func peek(deck: String, after current: PendingCard) async throws -> CardID? {
        // Without knowing which limit the current card counts against, the limits can't be adjusted for it.
        guard let currentKind = kinds[current.id] else { return nil }
        guard case .card(let id, let kind) = try await pick(deck: deck, excluding: (current.noteId, currentKind)) else { return nil }
        // Learning cards shown early are compared by due time, and the graded card may come back sooner than this one.
        guard kind != .learnAhead else { return nil }
        kinds[id] = kind
        return id
    }

    public func take(_ id: CardID) async {
        guard let kind = kinds[id] else { return }
        record(id, kind)
    }

    private func record(_ id: CardID, _ kind: Kind) {
        kinds[id] = kind
        switch kind {
        case .new: reviewsSinceNew = 0
        case .review: reviewsSinceNew += 1
        case .dueLearning, .learnAhead: break
        }
    }

    /// Picks without changing any state. `excluding` leaves out a note's cards (the one being graded, and siblings
    /// that grading may bury) and counts that card as already answered against its daily limit.
    private func pick(deck: String, excluding: (noteId: String, kind: Kind)?) async throws -> Pick {
        let scope = Self.deckQuery(deck) + (excluding.map { " -nid:\($0.noteId)" } ?? "")

        if let id = try await anki.searchCards("\(scope) is:learn is:due", limit: 1, sortByDue: true).first {
            return .card(id, .dueLearning)
        }

        var counts = try await anki.counts(deck: deck)
        switch excluding?.kind {
        case .new: counts = DeckCounts(new: max(0, counts.new - 1), learning: counts.learning, review: counts.review)
        case .review: counts = DeckCounts(new: counts.new, learning: counts.learning, review: max(0, counts.review - 1))
        default: break
        }
        let newQuery = "\(scope) is:new -is:suspended -is:buried"
        let reviewsPerNew = counts.new > 0 ? max(1, counts.review / counts.new) : .max
        if counts.new > 0, counts.review == 0 || reviewsSinceNew >= reviewsPerNew,
           let id = try await anki.searchCards(newQuery, limit: 1, sortByDue: false).first {
            return .card(id, .new)
        }
        if counts.review > 0, let id = try await anki.searchCards("\(scope) is:review is:due", limit: 1, sortByDue: true).first {
            return .card(id, .review)
        }
        if counts.new > 0, let id = try await anki.searchCards(newQuery, limit: 1, sortByDue: false).first {
            return .card(id, .new)
        }

        let learning = try await anki.searchCards("\(scope) is:learn -is:suspended -is:buried", limit: 100, sortByDue: true)
        let upcoming = try await anki.schedules(learning).compactMap { schedule -> (CardID, Date)? in
            guard case .timestamp(let date) = schedule.due else { return nil }
            return (schedule.id, date)
        }
        guard let (id, due) = upcoming.min(by: { $0.1 < $1.1 }) else { return .done }
        if due.timeIntervalSince(now()) <= learnAhead { return .card(id, .learnAhead) }
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
