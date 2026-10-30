import Foundation
@testable import GlanceCore

/// In-memory Anki for queue and session tests. Searches are matched by query text.
final class FakeAnki: AnkiService, @unchecked Sendable {
    private let lock = NSLock()
    private var _counts = DeckCounts(new: 0, learning: 0, review: 0)
    private var _results: [String: [CardID]] = [:]
    private var _schedules: [CardSchedule] = []
    private(set) var answers: [(id: CardID, rating: Rating, token: String, elapsedMs: Int)] = []
    private(set) var predictions: [CardID] = []
    private(set) var undoCount = 0
    var nextDay = Date(timeIntervalSince1970: 1_000_000)
    var answerError: Error?
    var deckList: [Deck] = []
    /// Thrown by `decks()`, to act like Anki being closed or busy.
    var decksError: Error?
    /// Decks whose counts fail the way AnkiConnect does for an empty "Default" deck.
    var decksWithoutCounts: Set<String> = []

    func set(counts: DeckCounts) { lock.withLock { _counts = counts } }
    func set(_ query: String, _ ids: [CardID]) { lock.withLock { _results[query] = ids } }
    func set(schedules: [CardSchedule]) { lock.withLock { _schedules = schedules } }

    func decks() async throws -> [Deck] {
        if let decksError { throw decksError }
        return deckList
    }
    func counts(deck: String) async throws -> DeckCounts {
        if decksWithoutCounts.contains(deck) {
            throw AnkiConnectError.rpc(code: 1001, type: "notFound", message: "Deck counts unavailable.")
        }
        return lock.withLock { _counts }
    }
    func searchCards(_ query: String, limit: Int, sortByDue: Bool) async throws -> [CardID] {
        lock.withLock { Array((_results[query] ?? []).prefix(limit)) }
    }
    func schedules(_ ids: [CardID]) async throws -> [CardSchedule] {
        lock.withLock { _schedules.filter { ids.contains($0.id) } }
    }
    func nextDayStarts() async throws -> Date { nextDay }
    func render(_ id: CardID) async throws -> RenderedCard {
        RenderedCard(cardId: id, questionHtml: "Q \(id)", answerHtml: "A \(id)")
    }
    func predict(_ id: CardID) async throws -> Prediction {
        let count = lock.withLock { predictions.append(id); return predictions.count }
        return Prediction(stateToken: "token-\(id)-\(count)", answers: Rating.allCases.map { .init(rating: $0, label: "\u{2068}1\u{2069}d") })
    }
    func answer(_ id: CardID, rating: Rating, stateToken: String, elapsedMs: Int) async throws {
        if let answerError { throw answerError }
        lock.withLock { answers.append((id, rating, stateToken, elapsedMs)) }
    }
    func undo() async throws { lock.withLock { undoCount += 1 } }
}

/// A queue that hands out a fixed list of steps.
actor ScriptedQueue: QueueSource {
    private var steps: [QueueStep]
    init(_ steps: [QueueStep]) { self.steps = steps }
    func next(deck: String) async throws -> QueueStep { steps.isEmpty ? .done : steps.removeFirst() }
}

/// A clock tests can move forward.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 0)) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
    var closure: @Sendable () -> Date { { self.now } }
}
