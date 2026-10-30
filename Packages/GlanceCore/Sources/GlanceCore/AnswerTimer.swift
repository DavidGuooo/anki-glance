import Foundation

/// Time spent looking at the current card, excluding time the panel was closed.
public struct AnswerTimer: Sendable {
    private let now: @Sendable () -> Date
    private var startedAt: Date?
    private var accumulated: TimeInterval = 0

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public mutating func restart() {
        accumulated = 0
        startedAt = now()
    }

    public mutating func pause() {
        guard let startedAt else { return }
        accumulated += now().timeIntervalSince(startedAt)
        self.startedAt = nil
    }

    public mutating func resume() {
        if startedAt == nil { startedAt = now() }
    }

    public var elapsedMs: Int {
        let running = startedAt.map { now().timeIntervalSince($0) } ?? 0
        return Int(((accumulated + running) * 1000).rounded())
    }
}
