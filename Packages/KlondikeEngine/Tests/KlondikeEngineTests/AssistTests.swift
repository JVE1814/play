import XCTest
@testable import KlondikeEngine

final class AssistTests: XCTestCase {
    func testTappingAnAceSendsItToTheFirstEmptyFoundation() {
        let game = makeGame(makeBoard(foundations: ["AS", "", "", ""], tableau: [("", "AH")]))
        XCTAssertEqual(game.bestMove(tapping: card("AH")), .transfer(from: .tableau(0), to: .foundation(1), count: 1))
    }

    func testTapPrefersTheFoundation() {
        let game = makeGame(makeBoard(foundations: ["AH", "", "", ""], tableau: [("", "2H"), ("", "3S")]))
        XCTAssertEqual(game.bestMove(tapping: card("2H")), .transfer(from: .tableau(0), to: .foundation(0), count: 1))
    }

    func testTappingARunMovesTheWholeRun() {
        let game = makeGame(makeBoard(tableau: [("2C", "9D 8S 7H"), ("", "10C")]))
        XCTAssertEqual(game.bestMove(tapping: card("9D")), .transfer(from: .tableau(0), to: .tableau(1), count: 3))
    }

    func testTapPrefersAMoveThatRevealsACard() {
        // 6H can go onto 7S (column 1) or 7C (column 2); moving it reveals nothing either way,
        // but 5S on top of column 0 makes the whole run the tap target.
        let game = makeGame(makeBoard(tableau: [("3D", "6H 5S"), ("", "7S"), ("4C", "7C")]))
        let move = game.bestMove(tapping: card("6H"))
        XCTAssertEqual(move, .transfer(from: .tableau(0), to: .tableau(1), count: 2))
    }

    func testTapFallsBackToANeighbouringCardInTheSameColumn() {
        // The tapped 8S has nowhere to go, but the 7H above it can go onto 8C.
        let game = makeGame(makeBoard(tableau: [("", "9D 8S 7H"), ("", "8C")]))
        XCTAssertEqual(game.bestMove(tapping: card("8S")), .transfer(from: .tableau(0), to: .tableau(1), count: 1))
    }

    func testTappingTheStockDrawsThenRedeals() {
        var game = makeGame(makeBoard(stock: "2C"))
        XCTAssertEqual(game.bestMove(tappingPile: .stock), .draw)
        game.perform(.draw)
        XCTAssertEqual(game.bestMove(tappingPile: .stock), .recycle)
        XCTAssertNil(makeGame(makeBoard()).bestMove(tappingPile: .stock))
        XCTAssertEqual(makeGame(makeBoard(stock: "2C 3C")).bestMove(tapping: card("2C")), .draw)
    }

    func testTappingAFaceDownCardDoesNothing() {
        let game = makeGame(makeBoard(foundations: ["AS", "", "", ""], tableau: [("2S", "KD")]))
        XCTAssertNil(game.bestMove(tapping: card("2S")))
    }

    func testTapWithNoLegalMoveReturnsNil() {
        let game = makeGame(makeBoard(tableau: [("", "5D"), ("", "9C")]))
        XCTAssertNil(game.bestMove(tapping: card("5D")))
    }

    func testTapDoesNotShuffleAKingBetweenEmptyColumns() {
        let game = makeGame(makeBoard(tableau: [("", "KD"), ("", "")]))
        XCTAssertNil(game.bestMove(tapping: card("KD")))
    }

    func testTappingABuriedWasteCardPlaysTheTopOne() {
        let game = makeGame(makeBoard(waste: "9C AD", foundations: ["", "", "", ""]), drawMode: .three)
        XCTAssertEqual(game.bestMove(tapping: card("9C")), .transfer(from: .waste, to: .foundation(0), count: 1))
    }

    func testTappingBelowAColumnActsOnItsTopCard() {
        let game = makeGame(makeBoard(foundations: ["AC", "", "", ""], tableau: [("", "3H 2C")]))
        XCTAssertEqual(game.bestMove(tappingPile: .tableau(0)), .transfer(from: .tableau(0), to: .foundation(0), count: 1))
        XCTAssertNil(game.bestMove(tappingPile: .tableau(3)))
    }

    func testHintPrefersFoundationThenRevealingACard() {
        let game = makeGame(makeBoard(foundations: ["AH", "", "", ""], tableau: [("", "2H"), ("4D", "6H"), ("", "7S")]))
        XCTAssertEqual(game.hint(), .transfer(from: .tableau(0), to: .foundation(0), count: 1))
        let second = makeGame(makeBoard(tableau: [("4D", "6H"), ("", "7S"), ("", "7C")]))
        XCTAssertEqual(second.hint(), .transfer(from: .tableau(0), to: .tableau(1), count: 1))
    }

    func testHintSuggestsTheStockWhenAPlayableCardIsThere() {
        let game = makeGame(makeBoard(stock: "AH 5C", tableau: [("", "9D")]))
        XCTAssertEqual(game.hint(), .draw)
        var redeal = makeGame(makeBoard(stock: "AH 5C", tableau: [("", "9D")]))
        redeal.perform(.draw)
        redeal.perform(.draw)
        XCTAssertEqual(redeal.hint(), .transfer(from: .waste, to: .foundation(0), count: 1))
        var cycle = makeGame(makeBoard(stock: "5C AH", tableau: [("", "9D")]))
        cycle.perform(.draw)
        cycle.perform(.draw)
        XCTAssertEqual(cycle.waste.last, card("5C"))
        XCTAssertEqual(cycle.hint(), .recycle, "AH is under the waste top, so redeal")
    }

    func testHintIsNilWhenNothingUsefulRemains() {
        let game = makeGame(makeBoard(stock: "5C", tableau: [("", "9D"), ("", "3S")]))
        XCTAssertNil(game.hint())
    }

    func testHintIgnoresPointlessMoves() {
        // Moving the lone 6H between two black sevens would just go back and forth.
        let game = makeGame(makeBoard(tableau: [("", "6H"), ("", "7S"), ("", "7C")]))
        XCTAssertNil(game.hint())
        XCTAssertNotNil(game.bestMove(tapping: card("6H")), "but a tap still moves it")
    }

    func testAidsOnlyEverSuggestLegalMoves() {
        for seed in 0..<150 as Range<UInt64> {
            var game = KlondikeGame(seed: seed, drawMode: seed.isMultiple(of: 3) ? .three : .one)
            var player = RandomPlayer(seed: seed)
            for _ in 0..<80 {
                if let hint = game.hint() { XCTAssertTrue(game.isLegal(hint), "hint \(hint) seed \(seed)") }
                for card in Card.fullDeck {
                    if let move = game.bestMove(tapping: card) { XCTAssertTrue(game.isLegal(move), "\(card) → \(move)") }
                }
                if let finish = game.autoFinishMoves() {
                    var copy = game
                    for move in finish { XCTAssertTrue(copy.perform(move)) }
                    XCTAssertTrue(copy.isWon)
                }
                guard player.play(&game) != nil else { break }
            }
        }
    }

    /// Sanity check of hint quality: following hints alone wins a share of Draw 1 deals.
    func testFollowingHintsWinsSomeGames() {
        var wins = 0
        for seed in 0..<200 as Range<UInt64> {
            var game = KlondikeGame(seed: seed, drawMode: .one)
            var steps = 0
            while !game.isWon && steps < 1500 {
                if let finish = game.autoFinishMoves() {
                    for move in finish { game.perform(move) }
                    break
                }
                guard let move = game.hint() else { break }
                game.perform(move)
                steps += 1
            }
            if game.isWon { wins += 1 }
        }
        XCTAssertGreaterThan(wins, 5, "hint player won \(wins) of 200")
    }
}
