import XCTest
@testable import KlondikeEngine

final class MoveRuleTests: XCTestCase {

    // MARK: Stock and waste

    func testDrawOneTurnsOneCard() {
        var game = KlondikeGame(board: makeBoard(stock: "2C 3C 4C"))
        XCTAssertTrue(game.perform(.draw))
        XCTAssertEqual(game.waste, cards("4C"))
        XCTAssertEqual(game.stock, cards("2C 3C"))
    }

    func testDrawThreeTurnsThreeCardsWithTheThirdOnTop() {
        var game = KlondikeGame(board: makeBoard(stock: "2C 3C 4C 5C 6C"), drawMode: .three)
        XCTAssertTrue(game.perform(.draw))
        // Turning the top three over as a packet leaves the third card from the top playable.
        XCTAssertEqual(game.waste, cards("6C 5C 4C"))
        XCTAssertEqual(game.stock, cards("2C 3C"))
    }

    func testDrawThreeWithFewerCardsLeftTurnsWhatIsThere() {
        var game = KlondikeGame(board: makeBoard(stock: "2C 3C"), drawMode: .three)
        XCTAssertTrue(game.perform(.draw))
        XCTAssertEqual(game.waste, cards("3C 2C"))
        XCTAssertTrue(game.stock.isEmpty)
    }

    func testCannotDrawFromEmptyStock() {
        var game = KlondikeGame(board: makeBoard(waste: "2C"))
        XCTAssertFalse(game.isLegal(.draw))
        XCTAssertFalse(game.perform(.draw))
    }

    func testRedealRequiresEmptyStockAndSomeWaste() {
        XCTAssertFalse(KlondikeGame(board: makeBoard(stock: "2C", waste: "3C")).isLegal(.recycle))
        XCTAssertFalse(KlondikeGame(board: makeBoard()).isLegal(.recycle))
        XCTAssertTrue(KlondikeGame(board: makeBoard(waste: "3C")).isLegal(.recycle))
    }

    func testRedealTurnsTheWasteBackOverInOriginalOrder() {
        var game = KlondikeGame(board: makeBoard(stock: "2C 3C 4C 5C"))
        let originalStock = game.stock
        for _ in 0..<4 { game.perform(.draw) }
        XCTAssertTrue(game.perform(.recycle))
        XCTAssertEqual(game.stock, originalStock)
        XCTAssertTrue(game.waste.isEmpty)
    }

    func testRedealsAreUnlimitedInBothDrawModes() {
        for mode in DrawMode.allCases {
            var game = KlondikeGame(seed: 3, drawMode: mode)
            let stock = game.stock
            for pass in 1...100 {
                while game.perform(.draw) {}
                XCTAssertTrue(game.perform(.recycle), "redeal \(pass) in \(mode)")
                XCTAssertEqual(game.stock, stock)
            }
        }
    }

    // MARK: Foundations

    func testAceStartsAnEmptyFoundation() {
        let game = KlondikeGame(board: makeBoard(waste: "AH"))
        for f in 0..<4 {
            XCTAssertTrue(game.isLegal(.transfer(from: .waste, to: .foundation(f), count: 1)))
        }
    }

    func testOnlyAnAceStartsAFoundation() {
        let game = KlondikeGame(board: makeBoard(waste: "2H"))
        XCTAssertFalse(game.isLegal(.transfer(from: .waste, to: .foundation(0), count: 1)))
    }

    func testFoundationBuildsUpInSuitOneRankAtATime() {
        let game = KlondikeGame(board: makeBoard(foundations: ["AH 2H", "AS", "", ""], tableau: [("", "3H"), ("", "3S"), ("", "4H")]))
        XCTAssertTrue(game.isLegal(.transfer(from: .tableau(0), to: .foundation(0), count: 1)))
        XCTAssertFalse(game.isLegal(.transfer(from: .tableau(1), to: .foundation(0), count: 1)), "wrong suit")
        XCTAssertFalse(game.isLegal(.transfer(from: .tableau(2), to: .foundation(0), count: 1)), "skips a rank")
        XCTAssertFalse(game.isLegal(.transfer(from: .tableau(0), to: .foundation(1), count: 1)), "wrong suit")
    }

    func testOnlyOneCardAtATimeGoesToAFoundation() {
        let game = KlondikeGame(board: makeBoard(foundations: ["AH", "", "", ""], tableau: [("", "3S 2H")]))
        XCTAssertTrue(game.isLegal(.transfer(from: .tableau(0), to: .foundation(0), count: 1)))
        XCTAssertFalse(game.isLegal(.transfer(from: .tableau(0), to: .foundation(0), count: 2)))
    }

    func testCardsCannotMoveBetweenFoundations() {
        let game = KlondikeGame(board: makeBoard(foundations: ["AH", "", "", ""]))
        XCTAssertFalse(game.isLegal(.transfer(from: .foundation(0), to: .foundation(1), count: 1)))
    }

    func testFoundationCardCanComeBackToAColumn() {
        var game = KlondikeGame(board: makeBoard(foundations: ["AH 2H", "", "", ""], tableau: [("", "3S")]))
        XCTAssertTrue(game.perform(.transfer(from: .foundation(0), to: .tableau(0), count: 1)))
        XCTAssertEqual(game.tableau[0].visible, cards("3S 2H"))
        XCTAssertEqual(game.foundations[0], cards("AH"))
    }

    // MARK: Tableau

    func testKingStartsAnEmptyColumn() {
        let game = KlondikeGame(board: makeBoard(waste: "KD", tableau: [("", ""), ("", "QS")]))
        XCTAssertTrue(game.isLegal(.transfer(from: .waste, to: .tableau(0), count: 1)))
        XCTAssertFalse(game.isLegal(.transfer(from: .tableau(1), to: .tableau(0), count: 1)), "only kings")
    }

    func testColumnBuildsDownInAlternatingColours() {
        let game = KlondikeGame(board: makeBoard(tableau: [("", "8S"), ("", "7H"), ("", "7C"), ("", "6H"), ("", "9H")]))
        XCTAssertTrue(game.isLegal(.transfer(from: .tableau(1), to: .tableau(0), count: 1)), "red 7 on black 8")
        XCTAssertFalse(game.isLegal(.transfer(from: .tableau(2), to: .tableau(0), count: 1)), "black on black")
        XCTAssertFalse(game.isLegal(.transfer(from: .tableau(3), to: .tableau(0), count: 1)), "skips a rank")
        XCTAssertFalse(game.isLegal(.transfer(from: .tableau(4), to: .tableau(0), count: 1)), "builds up")
        XCTAssertTrue(game.isLegal(.transfer(from: .tableau(0), to: .tableau(4), count: 1)), "black 8 on red 9")
    }

    func testRunsOfFaceUpCardsMoveTogether() {
        var game = KlondikeGame(board: makeBoard(tableau: [("2C", "9D 8S 7H"), ("", "10C")]))
        XCTAssertTrue(game.perform(.transfer(from: .tableau(0), to: .tableau(1), count: 3)))
        XCTAssertEqual(game.tableau[1].visible, cards("10C 9D 8S 7H"))
        XCTAssertEqual(game.tableau[0].visible, cards("2C"), "the face-down card is turned up")
        XCTAssertTrue(game.tableau[0].hidden.isEmpty)
    }

    func testPartOfARunCanMove() {
        var game = KlondikeGame(board: makeBoard(tableau: [("", "9D 8S 7H"), ("", "9H")]))
        XCTAssertTrue(game.perform(.transfer(from: .tableau(0), to: .tableau(1), count: 2)))
        XCTAssertEqual(game.tableau[1].visible, cards("9H 8S 7H"))
        XCTAssertEqual(game.tableau[0].visible, cards("9D"))
    }

    func testFaceDownCardsCannotBeLifted() {
        let game = KlondikeGame(board: makeBoard(tableau: [("KC", "QD"), ("", "")]))
        XCTAssertFalse(game.isLegal(.transfer(from: .tableau(0), to: .tableau(1), count: 2)))
    }

    func testCannotPlaceOnAFaceDownCard() {
        // Not reachable in play (the top card is always turned up), but the rule must still hold.
        let game = KlondikeGame(board: makeBoard(waste: "QD", tableau: [("KC", "")]))
        XCTAssertFalse(game.isLegal(.transfer(from: .waste, to: .tableau(0), count: 1)))
    }

    func testMovingTheLastFaceUpCardTurnsUpTheNextOne() {
        var game = KlondikeGame(board: makeBoard(foundations: ["AS", "", "", ""], tableau: [("5D 9C", "2S")]))
        XCTAssertTrue(game.perform(.transfer(from: .tableau(0), to: .foundation(0), count: 1)))
        XCTAssertEqual(game.tableau[0].visible, cards("9C"))
        XCTAssertEqual(game.tableau[0].hidden, cards("5D"))
    }

    func testWasteCardPlaysToColumnAndFoundation() {
        var game = KlondikeGame(board: makeBoard(waste: "AD 6H", tableau: [("", "7S")]))
        XCTAssertTrue(game.perform(.transfer(from: .waste, to: .tableau(0), count: 1)))
        XCTAssertEqual(game.tableau[0].visible, cards("7S 6H"))
        XCTAssertTrue(game.perform(.transfer(from: .waste, to: .foundation(2), count: 1)))
        XCTAssertEqual(game.foundations[2], cards("AD"))
        XCTAssertTrue(game.waste.isEmpty)
    }

    func testOnlyTheTopWasteCardPlays() {
        let game = KlondikeGame(board: makeBoard(waste: "AD 6H"))
        XCTAssertFalse(game.isLegal(.transfer(from: .waste, to: .foundation(0), count: 2)))
        XCTAssertFalse(game.isLegal(.transfer(from: .waste, to: .foundation(0), count: 1)), "AD is not on top")
    }

    // MARK: Malformed moves

    func testMalformedMovesAreIllegal() {
        let game = KlondikeGame(board: makeBoard(stock: "4C", waste: "AH", foundations: ["AS", "", "", ""], tableau: [("", "KH"), ("", "")]))
        let illegal: [Move] = [
            .transfer(from: .tableau(0), to: .tableau(0), count: 1),
            .transfer(from: .waste, to: .waste, count: 1),
            .transfer(from: .waste, to: .stock, count: 1),
            .transfer(from: .tableau(0), to: .waste, count: 1),
            .transfer(from: .stock, to: .tableau(1), count: 1),
            .transfer(from: .tableau(0), to: .tableau(1), count: 0),
            .transfer(from: .tableau(0), to: .tableau(1), count: -1),
            .transfer(from: .tableau(9), to: .tableau(1), count: 1),
            .transfer(from: .tableau(0), to: .tableau(-1), count: 1),
            .transfer(from: .waste, to: .foundation(4), count: 1),
            .transfer(from: .foundation(7), to: .tableau(1), count: 1),
            .transfer(from: .foundation(1), to: .tableau(1), count: 1),
        ]
        for move in illegal { XCTAssertFalse(game.isLegal(move), "\(move) should be illegal") }
    }

    func testIllegalMoveChangesNothing() {
        var game = KlondikeGame(seed: 11)
        let before = game
        let move = Move.transfer(from: .tableau(0), to: .tableau(0), count: 1)
        XCTAssertFalse(game.perform(move))
        XCTAssertEqual(game, before)
    }

    /// legalMoves() must list exactly the moves isLegal accepts, checked by brute force.
    func testLegalMovesMatchesBruteForce() {
        var piles: [Pile] = [.stock, .waste]
        piles += (0..<4).map { Pile.foundation($0) }
        piles += (0..<7).map { Pile.tableau($0) }
        for seed in 0..<40 as Range<UInt64> {
            var game = KlondikeGame(seed: seed, drawMode: seed.isMultiple(of: 2) ? .one : .three)
            var player = RandomPlayer(seed: seed)
            for _ in 0..<60 {
                var expected: Set<Move> = []
                if game.isLegal(.draw) { expected.insert(.draw) }
                if game.isLegal(.recycle) { expected.insert(.recycle) }
                for from in piles { for to in piles { for count in 0...14 {
                    let move = Move.transfer(from: from, to: to, count: count)
                    if game.isLegal(move) { expected.insert(move) }
                } } }
                let listed = game.legalMoves()
                XCTAssertEqual(Set(listed), expected, "seed \(seed)")
                XCTAssertEqual(listed.count, Set(listed).count, "no duplicates")
                guard player.play(&game) != nil else { break }
            }
        }
    }
}
