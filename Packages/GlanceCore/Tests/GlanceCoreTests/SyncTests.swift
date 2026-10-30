import Foundation
import Testing
@testable import GlanceCore

final class FakeSync: SyncService, @unchecked Sendable {
    var states: [OperationState] = [.running, .succeeded]
    private(set) var started = 0
    func startSync() async throws -> String { started += 1; return "op" }
    func operationState(_ id: String) async throws -> OperationState { states.isEmpty ? .succeeded : states.removeFirst() }
}

struct SyncThrottleTests {
    let start = Date(timeIntervalSince1970: 0)

    @Test func noSyncWithoutAnswers() {
        #expect(!SyncThrottle().shouldSync(now: start))
    }

    @Test func atMostOncePerFiveMinutes() {
        var throttle = SyncThrottle()
        throttle.noteAnswered()
        #expect(throttle.shouldSync(now: start))
        throttle.didStart(at: start)
        throttle.noteAnswered()
        #expect(!throttle.shouldSync(now: start + 299))
        #expect(throttle.shouldSync(now: start + 300))
    }

    @Test func failedSyncStaysPending() {
        var throttle = SyncThrottle()
        throttle.noteAnswered()
        throttle.didStart(at: start)
        throttle.didFail()
        #expect(throttle.shouldSync(now: start + 300))
    }
}

@MainActor
struct SyncCoordinatorTests {
    @Test func syncsOnceAndWaitsForCompletion() async {
        let service = FakeSync()
        let coordinator = SyncCoordinator(service: service, pollInterval: .milliseconds(1))
        coordinator.noteAnswered()
        #expect(await coordinator.syncIfDue(now: Date(timeIntervalSince1970: 0)) == true)
        #expect(service.started == 1)
        #expect(await coordinator.syncIfDue(now: Date(timeIntervalSince1970: 10)) == nil)
        #expect(service.started == 1)
    }
}

struct AnswerTimerTests {
    @Test func pausesAndResumes() {
        let clock = TestClock()
        var timer = AnswerTimer(now: clock.closure)
        timer.restart()
        clock.advance(1.5)
        timer.pause()
        clock.advance(100)
        #expect(timer.elapsedMs == 1500)
        timer.resume()
        clock.advance(0.5)
        #expect(timer.elapsedMs == 2000)
        timer.restart()
        #expect(timer.elapsedMs == 0)
    }
}

struct DeckOverviewTests {
    @Test func totalCountsOnlyTopLevelDecks() {
        let summaries = [
            DeckSummary(deck: Deck(id: "1", name: "Lang"), counts: DeckCounts(new: 2, learning: 1, review: 3)),
            DeckSummary(deck: Deck(id: "2", name: "Lang::French"), counts: DeckCounts(new: 2, learning: 0, review: 1)),
            DeckSummary(deck: Deck(id: "3", name: "Code"), counts: DeckCounts(new: 0, learning: 0, review: 4)),
        ]
        #expect(DeckOverview.totalDue(summaries) == 10)
    }

    @Test func hidesEmptyDefaultDeckThatHasNoCounts() async throws {
        let anki = FakeAnki()
        anki.deckList = [Deck(id: "1", name: "Default"), Deck(id: "2", name: "General")]
        anki.decksWithoutCounts = ["Default"]
        anki.set(counts: DeckCounts(new: 1, learning: 0, review: 2, total: 9))
        let summaries = try await DeckOverview.load(from: anki)
        #expect(summaries.map(\.deck.name) == ["General"])
        #expect(DeckOverview.totalDue(summaries) == 3)
    }

    @Test func sortsLikeAnkiTree() {
        let names = ["b", "A::z", "a", "A::b"].sorted(by: DeckOverview.treeOrder)
        #expect(names == ["a", "A::b", "A::z", "b"])
    }
}
