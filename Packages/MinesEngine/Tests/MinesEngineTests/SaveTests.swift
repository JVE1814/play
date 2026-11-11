import XCTest
@testable import MinesEngine

final class SaveTests: XCTestCase {
    private func roundTrip(_ game: MinesGame) throws -> MinesGame {
        try JSONDecoder().decode(MinesGame.self, from: JSONEncoder().encode(game))
    }

    /// A real Easy board (12 mines) opened in the middle, with a flag and an open number.
    private func playing() -> MinesGame {
        var game = MinesGame(seed: 5, difficulty: .easy)
        game.open(cell(6, 3), forgiving: true)
        let field = game.field!
        let covered = MinesGrid.all.subtracting(game.opened)
        game.toggleFlag(covered.first(where: field.isMine)!)
        return game
    }

    func testSavedBoardsComeBackExactlyInEveryState() throws {
        var slipped = playing()
        let mine = slipped.field!.mines.first { !slipped.flagged.contains($0) }!
        slipped.open(mine, forgiving: true)
        var lost = slipped
        lost.endBoard()
        let twelve = wall.union(mines(["", "", "", "", "", "", "", "", "", "", "", "....MMMM"]))
        let won = MinesGame(difficulty: .easy, mines: twelve, firstTap: cell(11, 0)).opening(cell(0, 0))

        for game in [MinesGame(seed: 9, difficulty: .hard), playing(), slipped, lost, won] {
            XCTAssertEqual(game.integrityProblems, [], game.signature)
            let restored = try roundTrip(game)
            XCTAssertEqual(restored, game)
            XCTAssertEqual(restored.signature, game.signature)
        }
        XCTAssertEqual(won.status, .won)
        XCTAssertEqual(slipped.status, .slipped)
        XCTAssertEqual(lost.status, .lost)
    }

    func testAFreshBoardStillLaysItsMinesAfterARelaunch() throws {
        var restored = try roundTrip(MinesGame(seed: 3, difficulty: .medium))
        var original = MinesGame(seed: 3, difficulty: .medium)
        restored.open(cell(4, 4), forgiving: true)
        original.open(cell(4, 4), forgiving: true)
        XCTAssertEqual(restored, original)
    }

    func testDamagedSavesAreCaught() {
        let good = playing()
        let field = good.field!
        let anyMine = field.mines.first!
        let coveredSafe = field.safeCells.subtracting(good.opened).first!
        let openZero = good.opened.first { field.count(around: $0) == 0 }!

        func damaged(field: Minefield?? = .none, firstTap: Int?? = .none, opened: CellSet? = nil,
                     flagged: CellSet? = nil, status: MinesGame.Status? = nil, exploded: Int?? = .none,
                     slipUsed: Bool? = nil) -> MinesGame {
            MinesGame(seed: good.seed, difficulty: good.difficulty, field: field ?? good.field,
                      firstTap: firstTap ?? good.firstTap, opened: opened ?? good.opened,
                      flagged: flagged ?? good.flagged, status: status ?? good.status,
                      exploded: exploded ?? good.exploded, slipUsed: slipUsed ?? good.slipUsed)
        }

        let tooFewMines = Minefield(mines: field.mines.subtracting(CellSet([anyMine])))
        let mineByTheTap = Minefield(mines: field.mines.subtracting(CellSet([anyMine])).union(CellSet([cell(6, 4)])))
        let cases: [(String, MinesGame)] = [
            ("wrong mine count", damaged(field: .some(tooFewMines))),
            ("mine next to the first tap", damaged(field: .some(mineByTheTap))),
            ("no first tap", damaged(firstTap: .some(nil))),
            ("first opening covered", damaged(opened: good.opened.subtracting(CellSet([cell(6, 3)])))),
            ("open mine", damaged(opened: good.opened.union(CellSet([anyMine])))),
            ("flag on an open square", damaged(flagged: good.flagged.union(CellSet([openZero])))),
            ("open zero with a covered neighbour",
             damaged(opened: good.opened.subtracting(CellSet([MinesGrid.neighbours(of: openZero).first!])))),
            ("won with squares covered", damaged(status: .won)),
            ("slipped with no opened mine", damaged(status: .slipped)),
            ("lost with no opened mine", damaged(status: .lost)),
            ("opened mine while playing", damaged(exploded: .some(anyMine))),
            ("opened mine that is safe", damaged(status: .lost, exploded: .some(coveredSafe))),
            ("slipped twice", damaged(status: .slipped, exploded: .some(anyMine), slipUsed: true)),
            ("fresh with mines", damaged(status: .fresh)),
            ("moves with no mines", damaged(field: .some(nil))),
            ("playing with no mines", MinesGame(seed: 1, difficulty: .easy, field: nil, firstTap: nil,
                                                opened: CellSet(), flagged: CellSet(), status: .playing,
                                                exploded: nil, slipUsed: false)),
        ]
        XCTAssertEqual(good.integrityProblems, [])
        for (name, game) in cases {
            XCTAssertFalse(game.integrityProblems.isEmpty, name)
        }
    }

    func testTheSignatureDrawsTheBoard() {
        var game = MinesGame(difficulty: .easy, mines: cornerPocket, firstTap: cell(11, 7))
        game.toggleFlag(cell(0, 2))
        game.open(cell(0, 0), forgiving: true)
        game.open(cell(1, 1), forgiving: true)
        let rows = game.signature.split(separator: "|").last!.split(separator: "/")
        XCTAssertTrue(game.signature.hasPrefix("easy|slipped|slip:0|left:11|"), game.signature)
        XCTAssertEqual(rows.count, 12)
        XCTAssertEqual(rows[0], "1.f10000")
        XCTAssertEqual(rows[1], ".X210000")
        XCTAssertEqual(rows[2], ".2100000")
        XCTAssertEqual(rows[11], "00000000")
    }
}

private extension MinesGame {
    func opening(_ cell: Int) -> MinesGame {
        var game = self
        game.open(cell, forgiving: true)
        return game
    }
}
