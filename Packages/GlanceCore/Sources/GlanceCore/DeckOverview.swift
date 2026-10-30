import Foundation

public struct DeckSummary: Sendable, Equatable, Identifiable {
    public let deck: Deck
    public let counts: DeckCounts
    public var id: String { deck.id }

    public init(deck: Deck, counts: DeckCounts) {
        self.deck = deck
        self.counts = counts
    }
}

public enum DeckOverview {
    /// Normal decks in Anki's tree order with today's counts. Like Anki, hides "Default" when it's empty and has no sub-decks.
    public static func load(from anki: AnkiService) async throws -> [DeckSummary] {
        let decks = try await anki.decks().filter { $0.kind == "normal" }
        let summaries = try await withThrowingTaskGroup(of: DeckSummary.self) { group in
            for deck in decks {
                group.addTask { DeckSummary(deck: deck, counts: try await counts(of: deck, from: anki)) }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        return summaries
            .filter { summary in
                guard summary.deck.name == "Default", summary.counts.total == 0 else { return true }
                return decks.contains { $0.name.hasPrefix("Default::") }
            }
            .sorted { treeOrder($0.deck.name, $1.deck.name) }
    }

    /// Anki leaves an empty "Default" deck out of its deck tree, so AnkiConnect has no counts for it.
    private static func counts(of deck: Deck, from anki: AnkiService) async throws -> DeckCounts {
        do {
            return try await anki.counts(deck: deck.name)
        } catch AnkiConnectError.rpc(_, let type, _) where type == "notFound" {
            return DeckCounts(new: 0, learning: 0, review: 0, total: 0)
        }
    }

    /// Total due across the collection: the sum of the top-level decks, whose counts already include their sub-decks.
    public static func totalDue(_ summaries: [DeckSummary]) -> Int {
        summaries.filter { $0.deck.depth == 0 }.reduce(0) { $0 + $1.counts.due }
    }

    static func treeOrder(_ a: String, _ b: String) -> Bool {
        let left = a.components(separatedBy: "::").map { $0.lowercased() }
        let right = b.components(separatedBy: "::").map { $0.lowercased() }
        return left.lexicographicallyPrecedes(right)
    }
}
