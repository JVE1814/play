import XCTest
@testable import KlondikeEngine

final class InvariantTests: XCTestCase {
    /// 1,000 seeded random games: after every single move the board holds exactly the 52
    /// unique cards of a full deck, and undoing everything returns to the original deal.
    func testOneThousandSeededRandomGamesAlwaysKeepExactly52UniqueCards() {
        let fullDeck = Set(Card.fullDeck)
        var movesPlayed = 0
        var gamesChecked = 0
        for seed in 1...1000 as ClosedRange<UInt64> {
            var game = KlondikeGame(seed: seed, drawMode: seed.isMultiple(of: 2) ? .three : .one)
            let deal = game
            var player = RandomPlayer(seed: seed)
            for _ in 0..<150 {
                guard player.play(&game) != nil else { break }
                movesPlayed += 1
                let cards = game.board.allCards
                if cards.count != 52 || Set(cards).count != 52 || Set(cards) != fullDeck {
                    XCTFail("seed \(seed) move \(game.moveCount): \(cards.count) cards, \(Set(cards).count) unique")
                    break
                }
                for column in game.tableau where !Board.isValidRun(column.visible) {
                    XCTFail("seed \(seed): invalid run \(column.visible)")
                }
            }
            XCTAssertEqual(game.board.integrityProblems, [], "seed \(seed)")
            game.undoAll()
            XCTAssertEqual(game, deal, "seed \(seed): undo all should restore the deal")
            gamesChecked += 1
        }
        XCTAssertEqual(gamesChecked, 1000)
        XCTAssertGreaterThan(movesPlayed, 100_000)
    }

    func testSavedGamesRoundTripExactly() throws {
        var game = KlondikeGame(seed: 77, drawMode: .three)
        var player = RandomPlayer(seed: 77)
        for _ in 0..<120 { _ = player.play(&game) }
        let data = try JSONEncoder().encode(game)
        let decoded = try JSONDecoder().decode(KlondikeGame.self, from: data)
        XCTAssertEqual(decoded, game)
        XCTAssertEqual(decoded.board.signature, game.board.signature)
        XCTAssertEqual(decoded.integrityProblems, [])
        var a = game, b = decoded
        a.undoAll(); b.undoAll()
        XCTAssertEqual(a, b)
    }

    func testCardsEncodeAsSmallIntegers() throws {
        let data = try JSONEncoder().encode([Card(1, .spades), Card(13, .clubs)])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[0,51]")
        XCTAssertThrowsError(try JSONDecoder().decode([Card].self, from: Data("[52]".utf8)))
    }

    func testIntegrityCheckCatchesCorruption() {
        let good = KlondikeGame(seed: 4).board
        XCTAssertEqual(good.integrityProblems, [])

        var duplicated = good
        duplicated.stock.append(duplicated.stock[0])
        XCTAssertTrue(duplicated.integrityProblems.contains { $0.contains("duplicate") })

        var badRun = good
        let top = badRun.tableau[1].visible[0]
        let sameColour = badRun.stock.firstIndex { $0.isRed == top.isRed }!
        badRun.tableau[1].visible.append(badRun.stock.remove(at: sameColour))
        XCTAssertTrue(badRun.integrityProblems.contains { $0.contains("not a valid run") })

        var noFaceUp = good
        noFaceUp.stock.append(noFaceUp.tableau[3].visible.removeLast())
        XCTAssertTrue(noFaceUp.integrityProblems.contains { $0.contains("no face-up card") })

        var badFoundation = good
        badFoundation.foundations[0] = [badFoundation.stock.removeLast()]
        if badFoundation.foundations[0][0].rank != 1 {
            XCTAssertTrue(badFoundation.integrityProblems.contains { $0.contains("foundation") })
        }
    }
}
