import Foundation

/// Sends one JSON-RPC request body and returns the response body.
public protocol RPCTransport: Sendable {
    func send(_ body: Data) async throws -> Data
}

public enum AnkiConnectError: Error, Equatable, Sendable {
    /// Anki isn't running, or AnkiConnect isn't installed or listening.
    case unreachable
    /// AnkiConnect answered with a JSON-RPC error; `type` is its `data.type`, such as `notFound`.
    case rpc(code: Int, type: String?, message: String)
    case badResponse(String)
}

public struct URLSessionTransport: RPCTransport {
    public let port: Int
    public let apiKey: String?

    public init(port: Int = 8765, apiKey: String? = nil) {
        self.port = port
        self.apiKey = apiKey
    }

    public func send(_ body: Data) async throws -> Data {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/v1")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw AnkiConnectError.badResponse("HTTP \(http.statusCode)")
            }
            return data
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw AnkiConnectError.badResponse("timed out")
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost: throw AnkiConnectError.unreachable
            default: throw AnkiConnectError.badResponse("network error \(error.code.rawValue): \(error.localizedDescription)")
            }
        }
    }
}

/// Everything the queue and review session need from Anki. `AnkiConnectClient` is the real one; tests use fakes.
public protocol AnkiService: Sendable {
    func decks() async throws -> [Deck]
    func counts(deck: String) async throws -> DeckCounts
    func searchCards(_ query: String, limit: Int, sortByDue: Bool) async throws -> [CardID]
    func schedules(_ ids: [CardID]) async throws -> [CardSchedule]
    func nextDayStarts() async throws -> Date
    func render(_ id: CardID) async throws -> RenderedCard
    func predict(_ id: CardID) async throws -> Prediction
    func answer(_ id: CardID, rating: Rating, stateToken: String, elapsedMs: Int) async throws
    func undo() async throws
}

public struct AnkiConnectClient: AnkiService {
    private let transport: RPCTransport

    public init(transport: RPCTransport) {
        self.transport = transport
    }

    // MARK: JSON-RPC

    private struct Request<P: Encodable>: Encodable {
        let jsonrpc = "2.0"
        let id = 1
        let method: String
        let params: P
    }

    private struct Response<R: Decodable>: Decodable {
        struct RPCError: Decodable {
            struct Info: Decodable { let type: String? }
            let code: Int
            let message: String
            let data: Info?
        }
        let result: R?
        let error: RPCError?
    }

    private struct NoParams: Encodable {}

    func call<R: Decodable>(_ method: String, _ params: some Encodable = NoParams()) async throws -> R {
        let body = try JSONEncoder().encode(Request(method: method, params: params))
        let data = try await transport.send(body)
        let response: Response<R>
        do {
            response = try JSONDecoder().decode(Response<R>.self, from: data)
        } catch {
            throw AnkiConnectError.badResponse("\(method): \(error)")
        }
        if let error = response.error {
            throw AnkiConnectError.rpc(code: error.code, type: error.data?.type, message: error.message)
        }
        guard let result = response.result else {
            throw AnkiConnectError.badResponse("\(method): no result")
        }
        return result
    }

    private struct Ignored: Decodable {}

    // MARK: Reading

    /// Confirms AnkiConnect `/api/v1` is reachable; returns the active profile name.
    public func profile() async throws -> String {
        struct Collection: Decodable { let profile: String }
        let collection: Collection = try await call("collection.get")
        return collection.profile
    }

    public func decks() async throws -> [Deck] {
        try await call("decks.list")
    }

    public func counts(deck: String) async throws -> DeckCounts {
        struct Params: Encodable { let deck: [String: String] }
        return try await call("decks.getCounts", Params(deck: ["name": deck]))
    }

    public func searchCards(_ query: String, limit: Int, sortByDue: Bool) async throws -> [CardID] {
        struct Sort: Encodable { let column = "cardDue"; let direction = "ascending" }
        struct Params: Encodable { let query: String; let limit: Int; let sort: Sort? }
        struct Page: Decodable { let ids: [CardID] }
        let page: Page = try await call("cards.search", Params(query: query, limit: max(limit, 1), sort: sortByDue ? Sort() : nil))
        return page.ids
    }

    public func schedules(_ ids: [CardID]) async throws -> [CardSchedule] {
        struct Params: Encodable { let ids: [CardID] }
        struct Due: Decodable { let kind: String; let at: String?; let day: Int?; let position: Int? }
        struct Scheduling: Decodable { let queue: String; let due: Due }
        struct Card: Decodable { let id: CardID; let scheduling: Scheduling }
        struct Item: Decodable { let result: Card? }
        struct Many: Decodable { let items: [Item] }
        guard !ids.isEmpty else { return [] }
        let many: Many = try await call("cards.getMany", Params(ids: ids))
        return many.items.compactMap(\.result).map { card in
            let due = card.scheduling.due
            let value: CardDue = switch due.kind {
            case "timestamp": .timestamp(Self.date(due.at) ?? .distantFuture)
            case "day": .day(due.day ?? 0)
            default: .position(due.position ?? 0)
            }
            return CardSchedule(id: card.id, queue: card.scheduling.queue, due: value)
        }
    }

    public func nextDayStarts() async throws -> Date {
        struct Today: Decodable { let nextDayAt: String }
        let today: Today = try await call("statistics.getToday")
        guard let date = Self.date(today.nextDayAt) else { throw AnkiConnectError.badResponse("nextDayAt") }
        return date
    }

    public func render(_ id: CardID) async throws -> RenderedCard {
        struct Params: Encodable { let id: CardID }
        return try await call("cards.render", Params(id: id))
    }

    public func predict(_ id: CardID) async throws -> Prediction {
        struct Params: Encodable { let cardId: CardID }
        return try await call("scheduling.predict", Params(cardId: id))
    }

    public func media(_ filename: String) async throws -> Data {
        struct Params: Encodable { let filename: String }
        struct File: Decodable { let data: String }
        let file: File = try await call("media.get", Params(filename: filename))
        guard let data = Data(base64Encoded: file.data) else { throw AnkiConnectError.badResponse("media.get base64") }
        return data
    }

    // MARK: Writing

    public func answer(_ id: CardID, rating: Rating, stateToken: String, elapsedMs: Int) async throws {
        struct Params: Encodable { let cardId: CardID; let rating: Rating; let stateToken: String; let elapsedMs: Int }
        let _: Ignored = try await call("scheduling.answer", Params(cardId: id, rating: rating, stateToken: stateToken, elapsedMs: elapsedMs))
    }

    public func undo() async throws {
        let _: Ignored = try await call("collection.undo")
    }

    /// Starts an AnkiWeb sync and returns its operation ID; poll it with `operationState`.
    public func startSync() async throws -> String {
        struct Operation: Decodable { let operationId: String }
        let operation: Operation = try await call("collection.sync")
        return operation.operationId
    }

    public func operationState(_ id: String) async throws -> OperationState {
        struct Params: Encodable { let operationId: String }
        struct Operation: Decodable { let state: OperationState }
        let operation: Operation = try await call("operations.get", Params(operationId: id))
        return operation.state
    }

    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
