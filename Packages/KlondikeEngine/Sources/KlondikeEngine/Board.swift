import Foundation

/// Identifies one pile on the table.
public enum Pile: Hashable, Codable, Sendable, CustomStringConvertible {
    case stock
    case waste
    /// One of the four foundations, `0..<4`. Any Ace may start any empty foundation.
    case foundation(Int)
    /// One of the seven tableau columns, `0..<7`.
    case tableau(Int)

    public var description: String {
        switch self {
        case .stock: return "stock"
        case .waste: return "waste"
        case .foundation(let i): return "foundation \(i + 1)"
        case .tableau(let i): return "column \(i + 1)"
        }
    }
}

/// A tableau column: face-down cards underneath, a run of face-up cards on top.
public struct TableauColumn: Hashable, Codable, Sendable {
    /// Face-down cards, bottom first.
    public internal(set) var hidden: [Card]
    /// Face-up cards, bottom first. Always a descending run of alternating colours.
    public internal(set) var visible: [Card]

    public init(hidden: [Card] = [], visible: [Card] = []) {
        self.hidden = hidden
        self.visible = visible
    }

    public var isEmpty: Bool { hidden.isEmpty && visible.isEmpty }
    public var count: Int { hidden.count + visible.count }
    public var top: Card? { visible.last }
}

/// Where a card currently lies.
public struct CardLocation: Hashable, Sendable {
    public let pile: Pile
    /// Position within the pile, 0 = bottom. For tableau columns this counts hidden cards too.
    public let index: Int
    public let isFaceUp: Bool
}

/// The complete arrangement of the 52 cards. Pure state, no history.
public struct Board: Hashable, Codable, Sendable {
    /// Face-down stock, bottom first (`last` is the next card to draw).
    public internal(set) var stock: [Card]
    /// Face-up waste, bottom first (`last` is the playable card).
    public internal(set) var waste: [Card]
    /// Four foundations, bottom first.
    public internal(set) var foundations: [[Card]]
    /// Seven tableau columns.
    public internal(set) var tableau: [TableauColumn]

    public static let foundationCount = 4
    public static let columnCount = 7

    public init(stock: [Card], waste: [Card], foundations: [[Card]], tableau: [TableauColumn]) {
        precondition(foundations.count == Board.foundationCount, "need 4 foundations")
        precondition(tableau.count == Board.columnCount, "need 7 columns")
        self.stock = stock
        self.waste = waste
        self.foundations = foundations
        self.tableau = tableau
    }

    /// Standard Klondike deal from a seed: column n receives n+1 cards with only the top
    /// card face up; the remaining 24 cards form the stock.
    public init(seed: UInt64) {
        var deck = Card.fullDeck
        var generator = SeededGenerator(seed: seed)
        deck.seededShuffle(using: &generator)
        var columns = Array(repeating: TableauColumn(), count: Board.columnCount)
        var next = 0
        for row in 0..<Board.columnCount {
            for column in row..<Board.columnCount {
                if row == column {
                    columns[column].visible.append(deck[next])
                } else {
                    columns[column].hidden.append(deck[next])
                }
                next += 1
            }
        }
        // The rest of the deck is the stock; deck order is preserved (last = top).
        self.init(stock: Array(deck[next...]), waste: [], foundations: Array(repeating: [], count: Board.foundationCount), tableau: columns)
    }

    /// Every card on the board, in a fixed pile order.
    public var allCards: [Card] {
        var cards = stock + waste
        for foundation in foundations { cards += foundation }
        for column in tableau { cards += column.hidden + column.visible }
        return cards
    }

    public var isWon: Bool { foundations.allSatisfy { $0.count == 13 } }

    /// True when no card is face down: the stock is empty and every tableau card is turned up.
    public var allCardsRevealed: Bool { stock.isEmpty && tableau.allSatisfy { $0.hidden.isEmpty } }

    public var foundationCardCount: Int { foundations.reduce(0) { $0 + $1.count } }

    public func location(of card: Card) -> CardLocation? {
        if let i = stock.firstIndex(of: card) { return CardLocation(pile: .stock, index: i, isFaceUp: false) }
        if let i = waste.firstIndex(of: card) { return CardLocation(pile: .waste, index: i, isFaceUp: true) }
        for (f, foundation) in foundations.enumerated() {
            if let i = foundation.firstIndex(of: card) { return CardLocation(pile: .foundation(f), index: i, isFaceUp: true) }
        }
        for (t, column) in tableau.enumerated() {
            if let i = column.hidden.firstIndex(of: card) { return CardLocation(pile: .tableau(t), index: i, isFaceUp: false) }
            if let i = column.visible.firstIndex(of: card) {
                return CardLocation(pile: .tableau(t), index: column.hidden.count + i, isFaceUp: true)
            }
        }
        return nil
    }

    /// The face-up cards that would travel if `count` cards were lifted from `pile`, or nil
    /// if that many cards cannot be lifted from it.
    public func movableCards(from pile: Pile, count: Int) -> [Card]? {
        guard count >= 1 else { return nil }
        switch pile {
        case .stock:
            return nil
        case .waste:
            guard count == 1, let top = waste.last else { return nil }
            return [top]
        case .foundation(let f):
            guard Board.foundationIndices.contains(f), count == 1, let top = foundations[f].last else { return nil }
            return [top]
        case .tableau(let t):
            guard Board.columnIndices.contains(t), count <= tableau[t].visible.count else { return nil }
            return Array(tableau[t].visible.suffix(count))
        }
    }

    /// Can `card` be placed on foundation `f`? Aces start empty foundations; otherwise same suit, one rank higher.
    public func canPlace(_ card: Card, onFoundation f: Int) -> Bool {
        guard Board.foundationIndices.contains(f) else { return false }
        guard let top = foundations[f].last else { return card.rank == 1 }
        return top.suit == card.suit && card.rank == top.rank + 1
    }

    /// Can a run whose bottom card is `card` be placed on column `t`? Kings start empty
    /// columns; otherwise the column's top card must be face up, of the opposite colour and one rank higher.
    public func canPlace(_ card: Card, onTableau t: Int) -> Bool {
        guard Board.columnIndices.contains(t) else { return false }
        let column = tableau[t]
        guard let top = column.visible.last else { return column.hidden.isEmpty && card.rank == 13 }
        return top.isRed != card.isRed && card.rank == top.rank - 1
    }

    public static let foundationIndices = 0..<foundationCount
    public static let columnIndices = 0..<columnCount

    /// The card on top of `pile`: the next to draw from the stock, the playable one elsewhere.
    public func topCard(of pile: Pile) -> Card? {
        switch pile {
        case .stock: return stock.last
        case .waste: return waste.last
        case .foundation(let f): return foundations[f].last
        case .tableau(let t): return tableau[t].top
        }
    }

    /// A compact, human-readable, deterministic description of the whole board.
    /// Face-down cards are shown in lowercase. Used by tests to compare boards exactly.
    public var signature: String {
        func list(_ cards: [Card]) -> String { cards.map(\.code).joined(separator: ",") }
        var parts: [String] = []
        parts.append("S:" + stock.map { $0.code.lowercased() }.joined(separator: ","))
        parts.append("W:" + list(waste))
        for (i, f) in foundations.enumerated() { parts.append("F\(i):" + list(f)) }
        for (i, c) in tableau.enumerated() {
            parts.append("T\(i):" + (c.hidden.map { $0.code.lowercased() } + c.visible.map(\.code)).joined(separator: ","))
        }
        return parts.joined(separator: "|")
    }
}
