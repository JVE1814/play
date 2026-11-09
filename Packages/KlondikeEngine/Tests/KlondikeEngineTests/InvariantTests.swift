import XCTest
@testable import KlondikeEngine

final class InvariantTests: XCTestCase {
    /// 1,000 seeded random games: after every single move the board holds exactly the 52
    /// unique cards of a full deck, and undoing everything returns to the original deal.
    func testOneThousandSeededRandomGamesAlwaysKeepExactly52UniqueCards() {
        let fullDeck = Set(Card.fullDeck)
        var movesPlayed = 0
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
        }
        XCTAssertGreaterThan(movesPlayed, 100_000)
    }

    func testSavedGamesRoundTripExactly() throws {
        var game = KlondikeGame(seed: 77, drawMode: .three)
        var player = RandomPlayer(seed: 77)
        for _ in 0..<120 { _ = player.play(&game) }
        let data = try JSONEncoder().encode(game)
        let decoded = try JSONDecoder().decode(KlondikeGame.self, from: data)
        XCTAssertEqual(decoded, game)
    }

    func testCardsEncodeAsSmallIntegers() throws {
        let data = try JSONEncoder().encode([Card(1, .spades), Card(13, .clubs)])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[0,51]")
        XCTAssertThrowsError(try JSONDecoder().decode([Card].self, from: Data("[52]".utf8)))
    }

    /// A save damaged on disk can still decode. Its history is checked by undoing it, which must
    /// report the damage rather than crash on it.
    func testAHistoryTheBoardCouldNotHaveComeFromIsCaught() throws {
        struct Save: Encodable {
            let board: Board
            let drawMode: DrawMode
            let history: [MoveRecord]
        }
        let impossible = [
            MoveRecord(move: .transfer(from: .tableau(0), to: .tableau(1), count: 40), revealedCard: false, cardCount: 40),
            MoveRecord(move: .transfer(from: .tableau(0), to: .tableau(1), count: 1), revealedCard: true, cardCount: 1),
            MoveRecord(move: .transfer(from: .waste, to: .foundation(9), count: 1), revealedCard: false, cardCount: 1),
            MoveRecord(move: .transfer(from: .tableau(-1), to: .tableau(1), count: 1), revealedCard: false, cardCount: 1),
            MoveRecord(move: .transfer(from: .tableau(1), to: .tableau(1), count: 1), revealedCard: true, cardCount: 1),
            MoveRecord(move: .draw, revealedCard: false, cardCount: 3),
            MoveRecord(move: .draw, revealedCard: false, cardCount: -1),
        ]
        for record in impossible {
            let data = try JSONEncoder().encode(Save(board: Board(seed: 4), drawMode: .one, history: [record]))
            let game = try JSONDecoder().decode(KlondikeGame.self, from: data)
            XCTAssertFalse(game.integrityProblems.isEmpty, "\(record)")
        }
    }

    func testIntegrityCheckCatchesCorruption() {
        let good = KlondikeGame(seed: 4).board
        XCTAssertEqual(good.integrityProblems, [])

        var duplicated = good
        duplicated.stock.append(duplicated.stock[0])
        XCTAssertFalse(duplicated.integrityProblems.isEmpty, "a card twice")

        var badRun = good
        let top = badRun.tableau[1].visible[0]
        let sameColour = badRun.stock.firstIndex { $0.isRed == top.isRed }!
        badRun.tableau[1].visible.append(badRun.stock.remove(at: sameColour))
        XCTAssertFalse(badRun.integrityProblems.isEmpty, "two cards of one colour in a run")

        var noFaceUp = good
        noFaceUp.stock.append(noFaceUp.tableau[3].visible.removeLast())
        XCTAssertFalse(noFaceUp.integrityProblems.isEmpty, "a column with only face-down cards")

        var badFoundation = good
        let notAnAce = badFoundation.stock.firstIndex { $0.rank != 1 }!
        badFoundation.foundations[0] = [badFoundation.stock.remove(at: notAnAce)]
        XCTAssertFalse(badFoundation.integrityProblems.isEmpty, "a foundation that does not start with its ace")
    }
}
