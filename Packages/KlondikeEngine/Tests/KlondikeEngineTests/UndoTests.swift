import XCTest
@testable import KlondikeEngine

final class UndoTests: XCTestCase {
    func testNothingToUndoOnAFreshDeal() {
        var game = KlondikeGame(seed: 5)
        XCTAssertFalse(game.canUndo)
        XCTAssertFalse(game.undo())
        XCTAssertEqual(game, KlondikeGame(seed: 5))
    }

    func testUndoDrawInBothModes() {
        for mode in DrawMode.allCases {
            var game = KlondikeGame(board: makeBoard(stock: "2C 3C 4C 5C"), drawMode: mode)
            let before = game.board
            game.perform(.draw)
            XCTAssertTrue(game.undo())
            XCTAssertEqual(game.board, before, "\(mode)")
        }
    }

    func testUndoShortDrawThree() {
        var game = KlondikeGame(board: makeBoard(stock: "2C"), drawMode: .three)
        let before = game.board
        game.perform(.draw)
        game.undo()
        XCTAssertEqual(game.board, before)
    }

    func testUndoRedeal() {
        var game = KlondikeGame(board: makeBoard(stock: "2C 3C 4C"), drawMode: .three)
        game.perform(.draw)
        let beforeRedeal = game.board
        game.perform(.recycle)
        XCTAssertTrue(game.undo())
        XCTAssertEqual(game.board, beforeRedeal)
    }

    func testUndoTurnsTheRevealedCardBackDown() {
        var game = KlondikeGame(board: makeBoard(tableau: [("4D 7C", "9D 8S"), ("", "10C")]))
        let before = game.board
        game.perform(.transfer(from: .tableau(0), to: .tableau(1), count: 2))
        XCTAssertEqual(game.tableau[0].visible, cards("7C"))
        XCTAssertTrue(game.undo())
        XCTAssertEqual(game.board, before)
        XCTAssertEqual(game.tableau[0].hidden, cards("4D 7C"))
    }

    func testUndoFoundationMoves() {
        var game = KlondikeGame(board: makeBoard(waste: "2H", foundations: ["AH", "", "", ""], tableau: [("", "3S")]))
        let start = game.board
        game.perform(.transfer(from: .waste, to: .foundation(0), count: 1))
        let afterUp = game.board
        game.perform(.transfer(from: .foundation(0), to: .tableau(0), count: 1))
        game.undo()
        XCTAssertEqual(game.board, afterUp)
        game.undo()
        XCTAssertEqual(game.board, start)
    }

    func testUndoWasteToColumn() {
        var game = KlondikeGame(board: makeBoard(waste: "6H", tableau: [("", "7S")]))
        let before = game.board
        game.perform(.transfer(from: .waste, to: .tableau(0), count: 1))
        game.undo()
        XCTAssertEqual(game.board, before)
    }

    func testMoveCountFollowsHistory() {
        var game = KlondikeGame(seed: 8)
        game.perform(.draw)
        game.perform(.draw)
        XCTAssertEqual(game.moveCount, 2)
        game.undo()
        XCTAssertEqual(game.moveCount, 1)
    }

    /// Unlimited undo: hundreds of random moves can all be taken back to the exact deal.
    func testUndoIsUnlimited() {
        for mode in DrawMode.allCases {
            var game = KlondikeGame(seed: 2024, drawMode: mode)
            let deal = game
            var player = RandomPlayer(seed: 1)
            var boards: [Board] = [game.board]
            for _ in 0..<600 {
                guard player.play(&game) != nil else { break }
                boards.append(game.board)
            }
            XCTAssertGreaterThan(game.moveCount, 300)
            while game.canUndo {
                boards.removeLast()
                game.undo()
                XCTAssertEqual(game.board, boards.last)
            }
            XCTAssertEqual(game, deal)
        }
    }
}
