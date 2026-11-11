import XCTest
@testable import KlondikeEngine

/// Parses a card code such as "AS", "10H" or "qd" (case-insensitive).
func card(_ code: String) -> Card {
    let upper = code.uppercased()
    let suitLetter = String(upper.last!)
    let rankText = String(upper.dropLast())
    let suit = Suit.allCases.first { $0.letter == suitLetter }!
    let rank: Int
    switch rankText {
    case "A": rank = 1
    case "J": rank = 11
    case "Q": rank = 12
    case "K": rank = 13
    default: rank = Int(rankText)!
    }
    return Card(rank, suit)
}

func cards(_ codes: String) -> [Card] {
    codes.split(separator: " ").map { card(String($0)) }
}

/// Builds a (not necessarily 52-card) board for rule tests.
func makeBoard(
    stock: String = "",
    waste: String = "",
    foundations: [String] = ["", "", "", ""],
    tableau: [(hidden: String, visible: String)] = []
) -> Board {
    var columns = tableau.map { TableauColumn(hidden: cards($0.hidden), visible: cards($0.visible)) }
    while columns.count < 7 { columns.append(TableauColumn()) }
    return Board(stock: cards(stock), waste: cards(waste), foundations: foundations.map { cards($0) }, tableau: columns)
}

/// A random-legal-move player, deterministic per seed.
struct RandomPlayer {
    var generator: SeededGenerator

    init(seed: UInt64) { generator = SeededGenerator(seed: seed ^ 0xA5A5_5A5A_DEAD_BEEF) }

    mutating func play(_ game: inout KlondikeGame) -> Move? {
        let moves = game.legalMoves()
        guard !moves.isEmpty else { return nil }
        let move = moves[generator.nextInt(below: moves.count)]
        XCTAssertTrue(game.perform(move), "legal move \(move) was rejected")
        return move
    }
}
