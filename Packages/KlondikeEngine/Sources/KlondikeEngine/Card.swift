import Foundation

/// The four French suits. Raw values are stable and used for compact encoding.
public enum Suit: Int, CaseIterable, Codable, Sendable {
    case spades = 0, hearts, diamonds, clubs

    public var isRed: Bool { self == .hearts || self == .diamonds }

    /// Single-letter code used in card codes and board signatures.
    public var letter: String {
        switch self {
        case .spades: return "S"
        case .hearts: return "H"
        case .diamonds: return "D"
        case .clubs: return "C"
        }
    }

    /// English name, used for accessibility labels.
    public var name: String {
        switch self {
        case .spades: return "Spades"
        case .hearts: return "Hearts"
        case .diamonds: return "Diamonds"
        case .clubs: return "Clubs"
        }
    }
}

/// Identity only: whether it is face up is a property of the pile it lies in.
public struct Card: Hashable, Sendable, CustomStringConvertible {
    public let suit: Suit
    /// 1 (Ace) through 13 (King).
    public let rank: Int

    public init(_ rank: Int, _ suit: Suit) {
        precondition((1...13).contains(rank), "rank out of range")
        self.rank = rank
        self.suit = suit
    }

    /// 0..<52, unique per card. Used for compact persistence.
    public var index: Int { suit.rawValue * 13 + (rank - 1) }

    public init?(index: Int) {
        guard (0..<52).contains(index), let suit = Suit(rawValue: index / 13) else { return nil }
        self.init(index % 13 + 1, suit)
    }

    public var isRed: Bool { suit.isRed }

    /// "A", "2" ... "10", "J", "Q", "K".
    public var rankSymbol: String {
        switch rank {
        case 1: return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return String(rank)
        }
    }

    public var rankName: String {
        switch rank {
        case 1: return "Ace"
        case 11: return "Jack"
        case 12: return "Queen"
        case 13: return "King"
        default: return String(rank)
        }
    }

    /// Short code such as "AS", "10H", "QD".
    public var code: String { rankSymbol + suit.letter }

    /// Spoken name such as "Queen of Hearts".
    public var name: String { "\(rankName) of \(suit.name)" }

    public var description: String { code }

    /// All 52 cards in a fixed order (by suit, then rank).
    public static let fullDeck: [Card] = (0..<52).map { Card(index: $0)! }
}

extension Card: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Int.self)
        guard let card = Card(index: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid card index \(value)")
        }
        self = card
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(index)
    }
}
