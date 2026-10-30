import Foundation
import Testing
@testable import GlanceCore

/// Replays a response recorded from the real AnkiConnect and remembers the request it was sent.
final class FixtureTransport: RPCTransport, @unchecked Sendable {
    let response: Data
    private(set) var lastRequest: [String: Any] = [:]

    init(_ name: String) throws {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        response = try Data(contentsOf: url)
    }

    func send(_ body: Data) async throws -> Data {
        lastRequest = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
        return response
    }

    var method: String? { lastRequest["method"] as? String }
    var params: [String: Any] { lastRequest["params"] as? [String: Any] ?? [:] }
}

struct AnkiConnectClientTests {
    @Test func decodesDeckList() async throws {
        let transport = try FixtureTransport("decks.list")
        let decks = try await AnkiConnectClient(transport: transport).decks()
        #expect(transport.method == "decks.list")
        #expect(decks.map(\.name) == ["Default", "General", "Language", "Projects"])
    }

    @Test func decodesCountsAndSendsDeckName() async throws {
        let transport = try FixtureTransport("decks.getCounts")
        let counts = try await AnkiConnectClient(transport: transport).counts(deck: "General")
        #expect(counts == DeckCounts(new: 11, learning: 0, review: 10, total: 129))
        #expect(counts.due == 21)
        #expect(transport.params["deck"] as? [String: String] == ["name": "General"])
    }

    @Test func searchSortsByDueWhenAsked() async throws {
        let transport = try FixtureTransport("cards.search")
        let ids = try await AnkiConnectClient(transport: transport).searchCards("is:due", limit: 3, sortByDue: true)
        #expect(ids == ["1784950250445", "1787361698659", "1787362071795"])
        #expect((transport.params["sort"] as? [String: String])?["column"] == "cardDue")
        #expect(transport.params["limit"] as? Int == 3)
    }

    @Test func decodesRenderedCard() async throws {
        let card = try await AnkiConnectClient(transport: FixtureTransport("cards.render")).render("1784950250445")
        #expect(card.questionHtml.contains("capital of Australia"))
        #expect(card.answerHtml.contains("<hr id=answer>"))
    }

    @Test func decodesPredictionAndStripsDirectionMarks() async throws {
        let prediction = try await AnkiConnectClient(transport: FixtureTransport("scheduling.predict")).predict("1784950250445")
        #expect(prediction.stateToken == "519ffbfd4e57450c817fda054e488249")
        #expect(prediction.label(for: .again) == "<10m")
        #expect(prediction.label(for: .easy) == "3.9mo")
    }

    @Test func decodesSchedules() async throws {
        let schedules = try await AnkiConnectClient(transport: FixtureTransport("cards.getMany")).schedules(["1784950250445"])
        #expect(schedules == [CardSchedule(id: "1784950250445", queue: "review", due: .day(170))])
    }

    @Test func decodesNextDayStart() async throws {
        let date = try await AnkiConnectClient(transport: FixtureTransport("statistics.getToday")).nextDayStarts()
        #expect(date == AnkiConnectClient.date("2026-10-30T20:00:00.000Z"))
    }

    @Test func decodesOperationState() async throws {
        let state = try await AnkiConnectClient(transport: FixtureTransport("operations.get")).operationState("x")
        #expect(state == .succeeded)
    }

    @Test func surfacesRPCErrors() async throws {
        let client = AnkiConnectClient(transport: try FixtureTransport("error.notFound"))
        await #expect(throws: AnkiConnectError.rpc(code: 1001, type: "notFound", message: "Deck not found: {'name': 'Nope'}")) {
            try await client.counts(deck: "Nope")
        }
    }
}
