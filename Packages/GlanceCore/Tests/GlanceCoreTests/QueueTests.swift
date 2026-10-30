import Foundation
import Testing
@testable import GlanceCore

struct QueueTests {
    let scope = #"deck:"General""#
    var learnDue: String { "\(scope) is:learn is:due" }
    var new: String { "\(scope) is:new -is:suspended -is:buried" }
    var review: String { "\(scope) is:review is:due" }
    var learning: String { "\(scope) is:learn -is:suspended -is:buried" }

    @Test func dueLearningCardsComeFirst() async throws {
        let anki = FakeAnki()
        anki.set(counts: DeckCounts(new: 5, learning: 1, review: 5))
        anki.set(learnDue, ["L1"])
        anki.set(new, ["N1"])
        anki.set(review, ["R1"])
        #expect(try await LocalQueueSource(anki: anki).next(deck: "General") == .card("L1"))
    }

    @Test func spreadsNewCardsEvenlyBetweenReviews() async throws {
        let anki = FakeAnki()
        anki.set(counts: DeckCounts(new: 2, learning: 0, review: 4))
        anki.set(new, ["N1"])
        anki.set(review, ["R1"])
        let queue = LocalQueueSource(anki: anki)
        var shown: [QueueStep] = []
        for _ in 0..<6 { shown.append(try await queue.next(deck: "General")) }
        #expect(shown == [.card("R1"), .card("R1"), .card("N1"), .card("R1"), .card("R1"), .card("N1")])
    }

    @Test func respectsNewLimitOfZero() async throws {
        let anki = FakeAnki()
        anki.set(counts: DeckCounts(new: 0, learning: 0, review: 0))
        anki.set(new, ["N1"])
        #expect(try await LocalQueueSource(anki: anki).next(deck: "General") == .done)
    }

    @Test func onlyNewCardsLeft() async throws {
        let anki = FakeAnki()
        anki.set(counts: DeckCounts(new: 3, learning: 0, review: 0))
        anki.set(new, ["N1"])
        #expect(try await LocalQueueSource(anki: anki).next(deck: "General") == .card("N1"))
    }

    @Test func showsLearningCardEarlyWithinTwentyMinutes() async throws {
        let clock = TestClock()
        let anki = FakeAnki()
        anki.set(learning, ["L1", "L2"])
        anki.set(schedules: [
            CardSchedule(id: "L1", queue: "learning", due: .timestamp(clock.now + 30 * 60)),
            CardSchedule(id: "L2", queue: "learning", due: .timestamp(clock.now + 10 * 60)),
        ])
        #expect(try await LocalQueueSource(anki: anki, now: clock.closure).next(deck: "General") == .card("L2"))
    }

    @Test func waitsForLaterLearningCardToday() async throws {
        let clock = TestClock()
        let anki = FakeAnki()
        anki.nextDay = clock.now + 6 * 3600
        anki.set(learning, ["L1"])
        anki.set(schedules: [CardSchedule(id: "L1", queue: "learning", due: .timestamp(clock.now + 45 * 60))])
        #expect(try await LocalQueueSource(anki: anki, now: clock.closure).next(deck: "General") == .waiting(until: clock.now + 45 * 60))
    }

    @Test func doneWhenLearningCardIsDueTomorrow() async throws {
        let clock = TestClock()
        let anki = FakeAnki()
        anki.nextDay = clock.now + 3600
        anki.set(learning, ["L1"])
        anki.set(schedules: [CardSchedule(id: "L1", queue: "learning", due: .timestamp(clock.now + 2 * 3600))])
        #expect(try await LocalQueueSource(anki: anki, now: clock.closure).next(deck: "General") == .done)
    }

    @Test func escapesDeckNamesInSearches() {
        #expect(LocalQueueSource.deckQuery("My_Deck::\"A*\"") == #"deck:"My\_Deck::\"A\*\"""#)
    }
}
