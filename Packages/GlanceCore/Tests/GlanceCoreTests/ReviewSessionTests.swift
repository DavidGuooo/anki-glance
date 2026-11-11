import Foundation
import Testing
@testable import GlanceCore

@MainActor
struct ReviewSessionTests {
    let clock = TestClock()
    let anki = FakeAnki()

    func session(_ steps: [QueueStep]) -> ReviewSession {
        ReviewSession(deck: "General", anki: anki, queue: ScriptedQueue(steps),
                      timer: AnswerTimer(now: clock.closure), now: clock.closure)
    }

    func shownID(_ phase: ReviewPhase) -> CardID? {
        switch phase {
        case .question(let card), .answer(let card): card.id
        default: nil
        }
    }

    @Test func startsOnTheQuestion() async {
        let session = session([.card("C1")])
        await session.start()
        guard case .question(let card) = session.phase else { Issue.record("expected question"); return }
        #expect(card.questionHtml == "Q C1")
    }

    @Test func gradingIsIgnoredBeforeReveal() async {
        let session = session([.card("C1")])
        await session.start()
        await session.grade(.good)
        #expect(anki.answers.isEmpty)
    }

    @Test func gradeSendsTokenAndElapsedTimeThenAdvances() async {
        let session = session([.card("C1"), .card("C2")])
        await session.start()
        clock.advance(4)
        session.reveal()
        await session.grade(.good)
        #expect(anki.answers.count == 1)
        #expect(anki.answers[0].id == "C1")
        #expect(anki.answers[0].rating == .good)
        #expect(anki.answers[0].token == "token-C1-1")
        #expect(anki.answers[0].elapsedMs == 4000)
        #expect(shownID(session.phase) == "C2")
        #expect(session.reviewedCount == 1)
    }

    @Test func timerExcludesTimeThePanelWasClosed() async {
        let session = session([.card("C1")])
        await session.start()
        clock.advance(2)
        session.pause()
        clock.advance(600)
        session.resume()
        clock.advance(1)
        session.reveal()
        await session.grade(.hard)
        #expect(anki.answers.first?.elapsedMs == 3000)
    }

    @Test func refreshesTokenOlderThanNineMinutes() async {
        let session = session([.card("C1")])
        await session.start()
        clock.advance(10 * 60)
        session.reveal()
        await session.grade(.good)
        #expect(anki.answers.first?.token == "token-C1-2")
    }

    @Test func undoShowsThePreviousCardAgain() async {
        let session = session([.card("C1"), .card("C2")])
        await session.start()
        session.reveal()
        await session.grade(.again)
        #expect(session.canUndo)
        await session.undo()
        #expect(anki.undoCount == 1)
        #expect(shownID(session.phase) == "C1")
        #expect(session.reviewedCount == 0)
        #expect(!session.canUndo)
    }

    @Test func conflictSkipsToNextCardWithoutCounting() async {
        anki.answerError = AnkiConnectError.rpc(code: 1, type: "conflict", message: "stale")
        let session = session([.card("C1"), .card("C2")])
        await session.start()
        session.reveal()
        await session.grade(.good)
        #expect(shownID(session.phase) == "C2")
        #expect(session.reviewedCount == 0)
    }

    @Test func waitingRechecksOnceTheTimeHasPassed() async {
        let session = session([.waiting(until: clock.now + 60), .card("L1")])
        await session.start()
        #expect(session.phase == .waiting(until: clock.now + 60))
        await session.refreshIfWaiting(now: clock.now + 30)
        #expect(shownID(session.phase) == nil)
        await session.refreshIfWaiting(now: clock.now + 61)
        #expect(shownID(session.phase) == "L1")
    }

    @Test func doneWhenQueueIsEmpty() async {
        let session = session([])
        await session.start()
        #expect(session.phase == .done)
    }

    @Test func finishedDeckPicksUpNewlyDueCards() async {
        let session = session([.done, .card("C9")])
        await session.start()
        #expect(session.phase == .done)
        await session.recheckIfFinished()
        #expect(shownID(session.phase) == "C9")
    }

    // MARK: Prefetching the next card

    func prefetchingSession(_ steps: [QueueStep], peeks: [CardID?]) -> (ReviewSession, PeekingQueue) {
        let queue = PeekingQueue(steps, peeks: peeks)
        return (ReviewSession(deck: "General", anki: anki, queue: queue,
                              timer: AnswerTimer(now: clock.closure), now: clock.closure), queue)
    }

    @Test func showsPrefetchedCardWithoutAskingTheQueueAgain() async {
        anki.notes = ["C1": "N1"]
        let (session, queue) = prefetchingSession([.card("C1")], peeks: ["C2"])
        await session.start()
        session.reveal()
        await session.grade(.hard)
        #expect(anki.answers.map(\.id) == ["C1"])
        #expect(shownID(session.phase) == "C2")
        #expect(await queue.nextCalls == 1)
        // Showing C2 starts the prefetch of the card after it.
        #expect(await queue.peeked.first == PendingCard(id: "C1", noteId: "N1"))
        #expect(await queue.taken == ["C2"])
        #expect(session.reviewedCount == 1)
    }

    @Test func prefetchedCardGetsItsOwnToken() async {
        let (session, _) = prefetchingSession([.card("C1")], peeks: ["C2"])
        await session.start()
        session.reveal()
        await session.grade(.good)
        session.reveal()
        await session.grade(.good)
        #expect(anki.answers.map(\.id) == ["C1", "C2"])
        #expect(anki.answers[1].token.hasPrefix("token-C2-"))
    }

    @Test func fallsBackToTheQueueWhenNothingWasPrefetched() async {
        let (session, queue) = prefetchingSession([.card("C1"), .card("C3")], peeks: [nil])
        await session.start()
        session.reveal()
        await session.grade(.good)
        #expect(shownID(session.phase) == "C3")
        #expect(await queue.nextCalls == 2)
        #expect(await queue.taken.isEmpty)
    }

    @Test func prefetchesWhileTheQuestionIsOnScreen() async {
        anki.notes = ["C1": "N1"]
        let (session, queue) = prefetchingSession([.card("C1")], peeks: ["C2"])
        var reported: [CardID] = []
        session.onPrefetched = { reported.append($0.id) }
        await session.start()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await queue.peeked == [PendingCard(id: "C1", noteId: "N1")])
        #expect(reported == ["C2"])
    }

    @Test func usesThePrefetchHoweverLongTheCardWasOnScreen() async {
        let (session, queue) = prefetchingSession([.card("C1"), .card("C3")], peeks: ["C2"])
        await session.start()
        try? await Task.sleep(for: .milliseconds(50))
        clock.advance(5 * 60)
        session.reveal()
        await session.grade(.good)
        #expect(shownID(session.phase) == "C2")
        #expect(await queue.taken == ["C2"])
    }

    @Test func conflictIgnoresThePrefetch() async {
        anki.answerError = AnkiConnectError.rpc(code: 1, type: "conflict", message: "stale")
        let (session, _) = prefetchingSession([.card("C1"), .card("C3")], peeks: ["C2"])
        await session.start()
        session.reveal()
        await session.grade(.good)
        #expect(shownID(session.phase) == "C3")
        #expect(session.reviewedCount == 0)
    }

    @Test func undoDropsThePrefetch() async {
        let (session, queue) = prefetchingSession([.card("C1")], peeks: ["C2", "C3"])
        await session.start()
        session.reveal()
        await session.grade(.good)
        session.reveal()
        await session.undo()
        #expect(shownID(session.phase) == "C1")
        session.reveal()
        await session.grade(.good)
        // The undone card's next card is picked again rather than reusing the dropped prefetch.
        #expect(await queue.peeked.map(\.id) == ["C1", "C2", "C1"])
    }

    @Test func reportsPrefetchedCardsForImageLoading() async {
        let (session, _) = prefetchingSession([.card("C1")], peeks: ["C2"])
        var reported: [CardID] = []
        session.onPrefetched = { reported.append($0.id) }
        await session.start()
        session.reveal()
        await session.grade(.good)
        #expect(reported == ["C2"])
    }

    @Test func unreachableAnkiFails() async {
        anki.answerError = AnkiConnectError.unreachable
        let session = session([.card("C1")])
        await session.start()
        session.reveal()
        await session.grade(.good)
        guard case .failed = session.phase else { Issue.record("expected failure"); return }
    }
}
