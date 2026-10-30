import Foundation
import Testing
@testable import GlanceCore

@MainActor
final class FakeAnkiApp: AnkiApp {
    var isInstalled = true
    var isRunning = false
    private(set) var launches = 0
    /// What a launch does to AnkiConnect, e.g. make `decks()` start answering.
    var onLaunch: () -> Void = {}

    func launchHidden() async throws {
        launches += 1
        onLaunch()
    }
}

@MainActor
final class MemoryLastDeck: LastDeckStore {
    var lastDeck: String?
}

@MainActor
struct PanelTests {
    let anki = FakeAnki()
    let ankiApp = FakeAnkiApp()
    let store = MemoryLastDeck()
    let sync = FakeSync()

    init() {
        anki.deckList = [Deck(id: "1", name: "General"), Deck(id: "2", name: "Language")]
        anki.set(counts: DeckCounts(new: 1, learning: 0, review: 2, total: 9))
    }

    func panel(_ steps: [QueueStep] = [.card("C1"), .card("C2")]) -> Panel {
        Panel(anki: anki, sync: sync, ankiApp: ankiApp, store: store, queue: ScriptedQueue(steps),
              launchPollInterval: .milliseconds(1), syncPollInterval: .milliseconds(1))
    }

    // MARK: Opening

    @Test func firstOpenAfterRestartResumesTheLastDeck() async {
        store.lastDeck = "General"
        let panel = panel()
        await panel.opened()
        #expect(panel.screen == .review)
        #expect(panel.session?.deck == "General")
    }

    @Test func firstOpenStaysOnDecksWhenNoDeckWasSaved() async {
        let panel = panel()
        await panel.opened()
        #expect(panel.screen == .decks)
        #expect(panel.totalDue == 6)
    }

    @Test func goingBackToDecksStopsResuming() async {
        let panel = panel()
        await panel.startReview("General")
        await panel.showDecks()
        #expect(store.lastDeck == nil)
        await panel.opened()
        #expect(panel.screen == .decks)
    }

    @Test func reopeningKeepsTheScreenYouLeft() async {
        let panel = panel()
        await panel.opened()
        panel.openSettings()
        await panel.closed()
        await panel.opened()
        #expect(panel.screen == .settings)
    }

    @Test func reopeningKeepsTheCardYouWereOn() async {
        let panel = panel()
        await panel.startReview("General")
        let card = panel.session?.phase
        await panel.closed()
        await panel.opened()
        #expect(panel.session?.phase == card)
    }

    @Test func backFromSettingsReturnsToTheReview() async {
        let panel = panel()
        await panel.startReview("General")
        panel.openSettings()
        await panel.back()
        #expect(panel.screen == .review)
    }

    // MARK: Status

    @Test func unreachableAnkiIsNotRunningWhenClosed() async {
        anki.decksError = AnkiConnectError.unreachable
        let panel = panel()
        await panel.refresh()
        #expect(panel.status == .notRunning)
        #expect(panel.totalDue == nil)
    }

    @Test func unreachableAnkiThatIsRunningLacksAnkiConnect() async {
        anki.decksError = AnkiConnectError.unreachable
        ankiApp.isRunning = true
        let panel = panel()
        await panel.refresh()
        #expect(panel.status == .noAnkiConnect)
    }

    @Test func missingAnkiIsNotInstalled() async {
        anki.decksError = AnkiConnectError.unreachable
        ankiApp.isInstalled = false
        let panel = panel()
        await panel.refresh()
        #expect(panel.status == .notInstalled)
    }

    @Test func noCollectionMeansNotReady() async {
        anki.decksError = AnkiConnectError.rpc(code: 1, type: "collectionUnavailable", message: "Collection is not available.")
        let panel = panel()
        await panel.refresh()
        #expect(panel.status == .notReady)
    }

    @Test func otherErrorsFailWithTheirMessage() async {
        anki.decksError = AnkiConnectError.rpc(code: 1, type: "other", message: "Boom")
        let panel = panel()
        await panel.refresh()
        #expect(panel.status == .failed("Boom"))
    }

    @Test func launchingWaitsForAnkiConnect() async {
        anki.decksError = AnkiConnectError.unreachable
        ankiApp.onLaunch = { [anki] in anki.decksError = nil }
        let panel = panel()
        await panel.refresh()
        await panel.launchAnki()
        #expect(ankiApp.launches == 1)
        #expect(panel.connection == .connected)
        #expect(panel.status == nil)
    }

    // MARK: Reviewing

    @Test func keysRevealThenGrade() async {
        let panel = panel()
        await panel.startReview("General")
        #expect(panel.action(for: .number(3)) == nil)
        await panel.action(for: .space)?()
        await panel.action(for: .number(3))?()
        #expect(anki.answers.map(\.rating) == [.good])
        #expect(panel.action(for: .number(9)) == nil)
    }

    @Test func keysAreIgnoredOutsideReviews() {
        #expect(panel().action(for: .space) == nil)
    }

    @Test func undoKeyUndoesTheLastAnswer() async {
        let panel = panel()
        await panel.startReview("General")
        panel.reveal()
        await panel.grade(.again)
        await panel.action(for: .undo)?()
        #expect(anki.undoCount == 1)
    }

    @Test func finishingADeckSyncs() async {
        let panel = panel([.card("C1")])
        await panel.startReview("General")
        panel.reveal()
        await panel.grade(.good)
        #expect(panel.session?.phase == .done)
        #expect(sync.started == 1)
    }

    @Test func closingAfterAnsweringSyncs() async {
        let panel = panel()
        await panel.startReview("General")
        panel.reveal()
        await panel.grade(.good)
        #expect(sync.started == 0)
        await panel.closed()
        #expect(sync.started == 1)
    }

    @Test func closingWithoutAnsweringDoesNotSync() async {
        let panel = panel()
        await panel.startReview("General")
        await panel.closed()
        #expect(sync.started == 0)
    }

    @Test func cardsLeftCountsTheReviewedDeck() async {
        let panel = panel()
        await panel.opened()
        await panel.startReview("General")
        #expect(panel.cardsLeft == 3)
    }
}
