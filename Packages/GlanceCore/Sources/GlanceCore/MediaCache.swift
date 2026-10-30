import Foundation

/// Card images fetched through AnkiConnect (`media.get`), kept in memory. Works inside the App Sandbox,
/// which can't read Anki's media folder directly.
public actor MediaCache {
    private let fetch: @Sendable (String) async throws -> Data
    private var cache: [String: Data] = [:]

    public init(fetch: @escaping @Sendable (String) async throws -> Data) {
        self.fetch = fetch
    }

    public func data(for filename: String) async throws -> Data {
        if let data = cache[filename] { return data }
        let data = try await fetch(filename)
        cache[filename] = data
        return data
    }

    public func clear() { cache.removeAll() }
}
