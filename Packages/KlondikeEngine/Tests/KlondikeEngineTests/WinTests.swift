import XCTest
@testable import KlondikeEngine

final class WinTests: XCTestCase {
    private func solvedBoard() -> Board {
        Board(stock: [], waste: [], foundations: Suit.allCases.map { s in (1...13).map { Card($0, s) } },
              tableau: Array(repeating: TableauColumn(), count: 7))
    }

    func testWinWhenEveryFoundationIsComplete() {
        let game = KlondikeGame(board: solvedBoard())
        XCTAssertTrue(game.isWon)
        XCTAssertEqual(game.board.integrityProblems, [])
        XCTAssertFalse(game.canAutoFinish, "nothing left to finish")
    }

    func testNotWonWithOneCardOutstanding() {
        var board = solvedBoard()
        let king = board.foundations[3].removeLast()
        board.tableau[0].visible = [king]
        var game = KlondikeGame(board: board)
        XCTAssertFalse(game.isWon)
        XCTAssertTrue(game.perform(.transfer(from: .tableau(0), to: .foundation(3), count: 1)))
        XCTAssertTrue(game.isWon)
        game.undo()
        XCTAssertFalse(game.isWon, "undo takes back the win")
    }

    func testNearlyWonFixtureIsALegalPositionForEverySeed() {
        for seed in 0..<50 as Range<UInt64> {
            let game = KlondikeFixtures.nearlyWon(seed: seed)
            XCTAssertEqual(game.board.integrityProblems, [], "seed \(seed)")
            XCTAssertFalse(game.board.allCardsRevealed)
            XCTAssertFalse(game.canAutoFinish)
        }
        XCTAssertNotEqual(KlondikeFixtures.nearlyWon(seed: 3).board, KlondikeFixtures.nearlyWon(seed: 4).board)
    }

    func testNearlyWonGameCanBePlayedToVictoryByTapping() {
        var game = KlondikeFixtures.nearlyWon(seed: 9)
        var taps = 0
        while !game.isWon && taps < 30 {
            let tops = game.waste.suffix(1) + game.board.tableau.compactMap(\.top)
            let move = tops.lazy.compactMap { game.bestMove(tapping: $0) }.first ?? game.bestMove(tappingPile: .stock)
            guard let move else { break }
            XCTAssertTrue(game.perform(move))
            taps += 1
        }
        XCTAssertTrue(game.isWon)
    }

    func testAutoFinishBecomesAvailableOnceEverythingIsFaceUp() throws {
        var game = KlondikeFixtures.nearlyWon(seed: 21)
        XCTAssertNil(game.autoFinishMoves(), "a card is still face down in the stock")
        game.perform(.draw)
        XCTAssertTrue(game.board.allCardsRevealed)
        XCTAssertTrue(game.canAutoFinish)
        let moves = try XCTUnwrap(game.autoFinishMoves())
        for move in moves { XCTAssertTrue(game.perform(move), "\(move)") }
        XCTAssertTrue(game.isWon)
    }

    func testAutoFinishUnavailableWhileCardsAreFaceDownInColumns() {
        // A face-down King of Spades under the King of Hearts; the Queen of Hearts sits alone.
        var board = solvedBoard()
        let kingSpades = board.foundations[0].removeLast()
        let queenHearts = board.foundations[1].removeLast()
        let kingHearts = board.foundations[1].removeLast()
        board.tableau[0] = TableauColumn(hidden: [kingSpades], visible: [kingHearts])
        board.tableau[1] = TableauColumn(hidden: [], visible: [queenHearts])
        let game = KlondikeGame(board: board)
        XCTAssertEqual(game.board.integrityProblems, [])
        XCTAssertFalse(game.board.allCardsRevealed)
        XCTAssertFalse(game.canAutoFinish)
    }

    func testAutoFinishCyclesTheWasteInDrawOne() throws {
        // All columns face up, stock empty; the waste holds the Queen of Hearts under the King,
        // so the waste must be turned over to reach the Queen first.
        var board = solvedBoard()
        let kingHearts = board.foundations[1].removeLast()
        let queenHearts = board.foundations[1].removeLast()
        board.waste = [queenHearts, kingHearts]
        board.tableau[0].visible = [board.foundations[0].removeLast()]
        var game = KlondikeGame(board: board, drawMode: .one)
        XCTAssertEqual(game.board.integrityProblems, [])
        let moves = try XCTUnwrap(game.autoFinishMoves())
        XCTAssertTrue(moves.contains(.recycle))
        for move in moves { XCTAssertTrue(game.perform(move)) }
        XCTAssertTrue(game.isWon)
    }

    /// In Draw 1, any position with every card face up can be finished automatically.
    func testAutoFinishAlwaysSucceedsInDrawOneWhenEverythingIsFaceUp() {
        var checked = 0
        for seed in 0..<300 as Range<UInt64> {
            var game = KlondikeGame(seed: seed, drawMode: .one)
            var steps = 0
            while !game.board.allCardsRevealed && steps < 2000 {
                guard let move = game.hint() else { break }
                game.perform(move)
                steps += 1
            }
            guard game.board.allCardsRevealed, !game.isWon else { continue }
            checked += 1
            let moves = game.autoFinishMoves()
            XCTAssertNotNil(moves, "seed \(seed)")
            for move in moves ?? [] { game.perform(move) }
            XCTAssertTrue(game.isWon, "seed \(seed)")
        }
        XCTAssertGreaterThan(checked, 0, "some deals should reach an all-face-up position")
    }
}
