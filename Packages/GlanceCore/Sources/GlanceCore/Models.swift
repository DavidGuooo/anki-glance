import Foundation

public typealias CardID = String

public struct Deck: Decodable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let kind: String

    public init(id: String, name: String, kind: String = "normal") {
        self.id = id
        self.name = name
        self.kind = kind
    }

    /// Anki separates sub-decks with `::`.
    public var depth: Int { name.components(separatedBy: "::").count - 1 }
    public var shortName: String { name.components(separatedBy: "::").last ?? name }
}

/// Today's remaining counts for a deck and its sub-decks, with daily limits applied by Anki.
public struct DeckCounts: Decodable, Sendable, Equatable {
    public let new: Int
    public let learning: Int
    public let review: Int
    public let total: Int

    public init(new: Int, learning: Int, review: Int, total: Int = 0) {
        self.new = new
        self.learning = learning
        self.review = review
        self.total = total
    }

    public var due: Int { new + learning + review }
}

public struct RenderedCard: Decodable, Sendable, Equatable {
    public let cardId: CardID
    public let questionHtml: String
    public let answerHtml: String

    public init(cardId: CardID, questionHtml: String, answerHtml: String) {
        self.cardId = cardId
        self.questionHtml = questionHtml
        self.answerHtml = answerHtml
    }
}

public enum Rating: String, Codable, Sendable, CaseIterable {
    case again, hard, good, easy

    /// Anki's keyboard number for this button.
    public var number: Int { Rating.allCases.firstIndex(of: self)! + 1 }

    public init?(number: Int) {
        guard (1...4).contains(number) else { return nil }
        self = Rating.allCases[number - 1]
    }

    public var title: String { rawValue.capitalized }
}

public struct Prediction: Decodable, Sendable, Equatable {
    public struct Answer: Decodable, Sendable, Equatable {
        public let rating: Rating
        public let label: String

        public init(rating: Rating, label: String) {
            self.rating = rating
            self.label = label
        }
    }

    public let stateToken: String
    public let answers: [Answer]

    public init(stateToken: String, answers: [Answer]) {
        self.stateToken = stateToken
        self.answers = answers
    }

    /// Anki wraps labels in Unicode direction isolates (U+2068/U+2069); strip them for display.
    public func label(for rating: Rating) -> String {
        let raw = answers.first { $0.rating == rating }?.label ?? ""
        return raw.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
    }
}

/// When a card is next due. Learning cards carry an exact time; reviews a day number; new cards a position.
public enum CardDue: Sendable, Equatable {
    case timestamp(Date)
    case day(Int)
    case position(Int)
}

public struct CardSchedule: Sendable, Equatable {
    public let id: CardID
    public let queue: String
    public let due: CardDue

    public init(id: CardID, queue: String, due: CardDue) {
        self.id = id
        self.queue = queue
        self.due = due
    }
}

public enum OperationState: String, Decodable, Sendable {
    case pending, running, succeeded, failed, cancelled
}
