import Foundation

/// Hand-built positions used by tests, UI tests and screenshots.
public enum KlondikeFixtures {

    /// A seeded position a few moves from victory.
    ///
    /// Every suit has Ace through Jack on a foundation. Three columns hold a King with a Queen of
    /// the other colour on it, one column holds the King of Clubs alone, and the Queen of
    /// Diamonds is the only card left in the stock. The seed decides which columns and
    /// foundations are used. Drawing the Queen and playing it reveals every card, after which
    /// auto-finish completes the game.
    public static func nearlyWon(seed: UInt64, drawMode: DrawMode = .one) -> KlondikeGame {
        var generator = SeededGenerator(seed: seed)
        var suits = Suit.allCases
        suits.seededShuffle(using: &generator)
        let foundations = suits.map { suit in (1...11).map { Card($0, suit) } }

        var columns = Array(0..<Board.columnCount)
        columns.seededShuffle(using: &generator)
        let stacks: [[Card]] = [
            [Card(13, .spades), Card(12, .hearts)],
            [Card(13, .hearts), Card(12, .spades)],
            [Card(13, .diamonds), Card(12, .clubs)],
            [Card(13, .clubs)],
        ]
        var tableau = Array(repeating: TableauColumn(), count: Board.columnCount)
        for (stack, column) in zip(stacks, columns) {
            tableau[column] = TableauColumn(hidden: [], visible: stack)
        }
        let board = Board(stock: [Card(12, .diamonds)], waste: [], foundations: foundations, tableau: tableau)
        return KlondikeGame(board: board, drawMode: drawMode, seed: seed)
    }
}
