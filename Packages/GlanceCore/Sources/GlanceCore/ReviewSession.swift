import Foundation
import Observation

public struct ShownCard: Sendable, Equatable {
    public let id: CardID
    public let questionHtml: String
    public let answerHtml: String
    public let prediction: Prediction
    /// When `prediction` was fetched. AnkiConnect rejects its `stateToken` after 10 minutes.
    public let predictedAt: Date
}

public enum ReviewPhase: Sendable, Equatable {
    case loading
    case question(ShownCard)
    case answer(ShownCard)
    case waiting(until: Date)
    case done
    case failed(String)
}

/// One sitting in one deck: show the question, reveal, grade 1–4, undo the last answer.
@MainActor @Observable
public final class ReviewSession {
    public let deck: String
    public private(set) var phase: ReviewPhase = .loading
    /// Cards answered since this session started, shown on the "done" screen.
    public private(set) var reviewedCount = 0
    public private(set) var canUndo = false

    private let anki: AnkiService
    private let queue: QueueSource
    private var timer: AnswerTimer
    private var lastAnswered: CardID?
    private var busy = false
    private let now: @Sendable () -> Date

    public init(deck: String, anki: AnkiService, queue: QueueSource, timer: AnswerTimer = AnswerTimer(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.deck = deck
        self.anki = anki
        self.queue = queue
        self.timer = timer
        self.now = now
    }

    public func start() async {
        await perform { try await self.advance() }
    }

    public func reveal() {
        if case .question(let card) = phase { phase = .answer(card) }
    }

    public func grade(_ rating: Rating) async {
        guard case .answer(let card) = phase else { return }
        await perform {
            var token = card.prediction.stateToken
            if self.now().timeIntervalSince(card.predictedAt) > Self.tokenLifetime {
                token = try await self.anki.predict(card.id).stateToken
            }
            do {
                try await self.anki.answer(card.id, rating: rating, stateToken: token, elapsedMs: self.timer.elapsedMs)
            } catch AnkiConnectError.rpc(_, let type, _) where type == "conflict" || type == "staleSession" || type == "invalidState" {
                // The card changed in Anki since it was shown (answered on another device, for example): move on without counting it.
                try await self.advance()
                return
            }
            self.reviewedCount += 1
            self.lastAnswered = card.id
            self.canUndo = true
            try await self.advance()
        }
    }

    public func undo() async {
        guard canUndo, let id = lastAnswered else { return }
        await perform {
            try await self.anki.undo()
            self.reviewedCount -= 1
            self.lastAnswered = nil
            self.canUndo = false
            try await self.show(id)
        }
    }

    /// Re-checks the queue once a waiting period has passed.
    public func refreshIfWaiting(now: Date = Date()) async {
        guard case .waiting(let until) = phase, until <= now else { return }
        await perform { try await self.advance() }
    }

    /// Re-checks a finished or failed deck, for example after a new day starts or Anki comes back.
    public func recheckIfFinished() async {
        switch phase {
        case .done, .failed: await perform { try await self.advance() }
        default: return
        }
    }

    /// Refresh tokens a minute before AnkiConnect's 10-minute expiry.
    static let tokenLifetime: TimeInterval = 9 * 60

    public func pause() { timer.pause() }
    public func resume() { timer.resume() }

    private func perform(_ work: @escaping @MainActor () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await work()
        } catch AnkiConnectError.unreachable {
            phase = .failed("Can't reach Anki. Is it still running?")
        } catch AnkiConnectError.rpc(_, _, let message) {
            phase = .failed(message)
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    private func advance() async throws {
        switch try await queue.next(deck: deck) {
        case .card(let id): try await show(id)
        case .waiting(let until): phase = .waiting(until: until)
        case .done: phase = .done
        }
    }

    private func show(_ id: CardID) async throws {
        async let rendered = anki.render(id)
        async let prediction = anki.predict(id)
        let card = try await ShownCard(id: id, questionHtml: rendered.questionHtml, answerHtml: rendered.answerHtml,
                                       prediction: prediction, predictedAt: now())
        phase = .question(card)
        timer.restart()
    }
}
