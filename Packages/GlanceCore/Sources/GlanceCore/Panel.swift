import Foundation
import Observation

public enum PanelScreen: Sendable {
    case decks, review, settings
}

/// Whether AnkiConnect answers, as far as the panel is concerned.
public enum Connection: Equatable, Sendable {
    case unknown
    case connected
    /// Nothing answers on the AnkiConnect port: Anki is closed, missing, or lacks the add-on.
    case unreachable
    /// Anki answers but has no collection open: starting, closing, or at its profile window.
    case notReady
    case failed(String)

    init(_ error: Error) {
        switch error {
        case AnkiConnectError.unreachable: self = .unreachable
        case AnkiConnectError.rpc(_, .some("collectionUnavailable"), _): self = .notReady
        case AnkiConnectError.rpc(_, _, let message), AnkiConnectError.badResponse(let message): self = .failed(message)
        default: self = .failed(String(describing: error))
        }
    }
}

/// Why the panel shows a status screen instead of decks or a card.
public enum AnkiStatus: Equatable, Sendable {
    case notInstalled
    case notRunning
    case launching
    case noAnkiConnect
    case notReady
    case failed(String)
}

/// The Anki desktop app, seen from outside: whether it's there and running, and opening it hidden.
@MainActor
public protocol AnkiApp: AnyObject {
    var isInstalled: Bool { get }
    var isRunning: Bool { get }
    func launchHidden() async throws
}

/// Where the panel remembers the deck being reviewed, so it survives an app restart.
@MainActor
public protocol LastDeckStore: AnyObject {
    var lastDeck: String? { get set }
}

/// Keys the panel reacts to while reviewing. Esc (close) is left to the window.
public enum PanelKey: Sendable, Equatable {
    case space, returnKey, undo
    case number(Int)
}

/// Everything the menu bar panel does: which screen it shows, whether Anki is reachable, reviewing a deck,
/// keyboard shortcuts, and when to sync. Views only render it and forward clicks and keys.
@MainActor @Observable
public final class Panel {
    public private(set) var screen: PanelScreen = .decks
    public private(set) var connection: Connection = .unknown {
        didSet { if connection != oldValue { onEvent?("connection: \(connection)") } }
    }
    public private(set) var summaries: [DeckSummary] = []
    public private(set) var session: ReviewSession?
    public private(set) var isLaunchingAnki = false
    /// Reports notable events (connection changes, launches, syncs) for diagnostics.
    @ObservationIgnored public var onEvent: ((String) -> Void)?

    private let anki: AnkiService
    private let queue: QueueSource
    private let sync: SyncCoordinator
    private let ankiApp: AnkiApp
    private let store: LastDeckStore
    private let launchPollInterval: Duration
    private var restoredLastDeck = false

    public init(anki: AnkiService, sync: SyncService, ankiApp: AnkiApp, store: LastDeckStore,
                queue: QueueSource? = nil, launchPollInterval: Duration = .seconds(2),
                syncPollInterval: Duration = .milliseconds(500)) {
        self.anki = anki
        self.queue = queue ?? LocalQueueSource(anki: anki)
        self.sync = SyncCoordinator(service: sync, pollInterval: syncPollInterval)
        self.ankiApp = ankiApp
        self.store = store
        self.launchPollInterval = launchPollInterval
    }

    // MARK: What to show

    /// Due across all decks, for the menu bar; `nil` unless Anki is connected.
    public var totalDue: Int? {
        connection == .connected ? DeckOverview.totalDue(summaries) : nil
    }

    /// Due today in the deck being reviewed, sub-decks included.
    public var cardsLeft: Int? {
        guard let deck = session?.deck else { return nil }
        return summaries.first { $0.deck.name == deck }?.counts.due
    }

    /// The status screen to show instead of decks or a card, or `nil`. A failure during a review is shown by the review itself.
    public var status: AnkiStatus? {
        if isLaunchingAnki { return .launching }
        switch connection {
        case .unknown, .connected: return nil
        case .notReady: return .notReady
        case .failed(let message): return session == nil ? .failed(message) : nil
        case .unreachable:
            guard ankiApp.isInstalled else { return .notInstalled }
            return ankiApp.isRunning ? .noAnkiConnect : .notRunning
        }
    }

    // MARK: Opening and closing

    /// Reopens exactly where the panel was left. The app keeps running through sleep, so that state is in memory;
    /// after an app restart, the first open resumes the deck that was being reviewed.
    public func opened() async {
        await refresh()
        guard connection == .connected else { return }
        if let session {
            session.resume()
            await session.refreshIfWaiting()
            await session.recheckIfFinished()
            return
        }
        guard !restoredLastDeck else { return }
        restoredLastDeck = true
        if let deck = store.lastDeck, summaries.contains(where: { $0.deck.name == deck }) {
            await startReview(deck)
        }
    }

    public func closed() async {
        session?.pause()
        await syncIfDue()
    }

    /// The periodic background refresh: menu bar count, plus a sync if one was held back by the throttle.
    public func tick() async {
        await refresh()
        await syncIfDue()
    }

    public func refresh() async {
        do {
            summaries = try await DeckOverview.load(from: anki)
            connection = .connected
        } catch {
            connection = Connection(error)
        }
    }

    // MARK: Navigation

    public func startReview(_ deck: String) async {
        store.lastDeck = deck
        await show(ReviewSession(deck: deck, anki: anki, queue: queue))
    }

    /// Shows a review session that's already set up. Debug previews use this to show a single card.
    public func show(_ session: ReviewSession) async {
        self.session = session
        screen = .review
        await session.start()
    }

    /// Going back to the deck list means "stop resuming that deck", so later opens stay on the list.
    public func showDecks() async {
        store.lastDeck = nil
        session?.pause()
        session = nil
        screen = .decks
        await refresh()
    }

    public func openSettings() {
        screen = .settings
    }

    /// From settings, back to wherever you were; from a review, back to the deck list.
    public func back() async {
        if screen == .settings {
            screen = session == nil ? .decks : .review
        } else {
            await showDecks()
        }
    }

    // MARK: Reviewing

    public func reveal() {
        session?.reveal()
    }

    public func grade(_ rating: Rating) async {
        guard let session else { return }
        let before = session.reviewedCount
        await session.grade(rating)
        guard session.reviewedCount != before else { return }
        await answered()
        if session.phase == .done { await syncIfDue() }
    }

    public func undo() async {
        guard let session, session.canUndo else { return }
        await session.undo()
        await answered()
    }

    /// The action for a key while reviewing: Space or Return reveals, 1–4 grade once revealed, ⌘Z undoes.
    /// `nil` means the key isn't used, so the window can handle it.
    public func action(for key: PanelKey) -> (() async -> Void)? {
        guard screen == .review, let session else { return nil }
        switch (key, session.phase) {
        case (.undo, _) where session.canUndo:
            return { await self.undo() }
        case (.space, .question), (.returnKey, .question):
            return { self.reveal() }
        case (.number(let number), .answer):
            guard let rating = Rating(number: number) else { return nil }
            return { await self.grade(rating) }
        default:
            return nil
        }
    }

    // MARK: Anki

    /// Opens Anki hidden in the background, then waits up to 30 polls for AnkiConnect to answer.
    public func launchAnki() async {
        guard ankiApp.isInstalled, !isLaunchingAnki else { return }
        isLaunchingAnki = true
        defer { isLaunchingAnki = false }
        onEvent?("launching Anki")
        do {
            try await ankiApp.launchHidden()
        } catch {
            onEvent?("launching Anki failed: \(error.localizedDescription)")
        }
        for _ in 0..<30 {
            try? await Task.sleep(for: launchPollInterval)
            await refresh()
            if connection == .connected { return }
        }
        onEvent?("AnkiConnect didn't answer after launching Anki")
    }

    private func answered() async {
        sync.noteAnswered()
        await refresh()
    }

    private func syncIfDue() async {
        guard let succeeded = await sync.syncIfDue() else { return }
        onEvent?(succeeded ? "synced with AnkiWeb" : "AnkiWeb sync failed")
        if succeeded { await refresh() }
    }
}
