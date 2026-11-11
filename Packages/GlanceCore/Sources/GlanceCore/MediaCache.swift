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

    /// Fetches a card's images ahead of time, so they're cached by the time the card is shown.
    public func preload(html: String) async {
        await withTaskGroup(of: Void.self) { group in
            for filename in Self.filenames(in: html) where cache[filename] == nil {
                group.addTask { [self] in _ = try? await data(for: filename) }
            }
        }
    }

    public func clear() { cache.removeAll() }

    /// The local files a card's `<img>` tags load, named the way the web view will ask for them.
    static func filenames(in html: String) -> Set<String> {
        let pattern = /<img\b[^>]*?\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)')/.ignoresCase()
        var names: Set<String> = []
        for match in html.matches(of: pattern) {
            guard let raw = match.1 ?? match.2 else { continue }
            let source = String(raw).replacingOccurrences(of: "&amp;", with: "&")
            guard !source.isEmpty, !source.contains(":"), !source.hasPrefix("/") else { continue }
            names.insert(source.removingPercentEncoding ?? source)
        }
        return names
    }
}
