import Foundation

/// Sync only after something was answered, and at most once every five minutes.
public struct SyncThrottle: Sendable {
    public let minimumInterval: TimeInterval
    public private(set) var lastSync: Date?
    public private(set) var pending = false

    public init(minimumInterval: TimeInterval = 5 * 60) {
        self.minimumInterval = minimumInterval
    }

    public mutating func noteAnswered() { pending = true }

    public func shouldSync(now: Date) -> Bool {
        guard pending else { return false }
        guard let lastSync else { return true }
        return now.timeIntervalSince(lastSync) >= minimumInterval
    }

    public mutating func didStart(at now: Date) {
        lastSync = now
        pending = false
    }

    public mutating func didFail() { pending = true }
}

public protocol SyncService: Sendable {
    func startSync() async throws -> String
    func operationState(_ id: String) async throws -> OperationState
}

extension AnkiConnectClient: SyncService {}

@MainActor
public final class SyncCoordinator {
    private let service: SyncService
    private var throttle: SyncThrottle
    private let pollInterval: Duration
    public private(set) var isSyncing = false

    public init(service: SyncService, throttle: SyncThrottle = SyncThrottle(), pollInterval: Duration = .milliseconds(500)) {
        self.service = service
        self.throttle = throttle
        self.pollInterval = pollInterval
    }

    public func noteAnswered() { throttle.noteAnswered() }

    /// Starts a sync if one is due and waits for it (up to two minutes).
    /// Returns `nil` when no sync was due, otherwise whether it succeeded.
    @discardableResult
    public func syncIfDue(now: Date = Date()) async -> Bool? {
        guard !isSyncing, throttle.shouldSync(now: now) else { return nil }
        isSyncing = true
        throttle.didStart(at: now)
        defer { isSyncing = false }
        do {
            let id = try await service.startSync()
            for _ in 0..<240 {
                switch try await service.operationState(id) {
                case .succeeded: return true
                case .failed, .cancelled: throttle.didFail(); return false
                case .pending, .running: try await Task.sleep(for: pollInterval)
                }
            }
        } catch {
            throttle.didFail()
        }
        return false
    }
}
