import XCTest
@testable import MinesEngine

final class RulesTests: XCTestCase {
    /// The corner pocket, opened from the far corner: everything but the mines and the three
    /// pocket squares is open.
    private func pocketGame() -> MinesGame {
        MinesGame(difficulty: .easy, mines: cornerPocket, firstTap: cell(11, 7))
    }

    func testAFreshBoardWaitsForItsFirstTap() {
        var game = MinesGame(seed: 7, difficulty: .medium)
        XCTAssertEqual(game.status, .fresh)
        XCTAssertNil(game.field)
        XCTAssertFalse(game.toggleFlag(cell(3, 3)), "nothing to reason from before the first tap")
        XCTAssertEqual(game.signature, "medium|fresh")
        XCTAssertEqual(game.minesLeft, 16)

        let outcome = game.open(cell(6, 4), forgiving: true)
        guard case .opened(let revealed) = outcome else { return XCTFail("\(String(describing: outcome))") }
        XCTAssertEqual(game.status, .playing)
        XCTAssertEqual(game.firstTap, cell(6, 4))
        XCTAssertEqual(game.field?.mines.count, 16)
        XCTAssertEqual(game.field?.count(around: cell(6, 4)), 0)
        XCTAssertEqual(revealed, game.opened)
        XCTAssertGreaterThan(revealed.count, 9)
    }

    func testOpeningANumberOpensOnlyThatSquare() {
        var game = pocketGame()
        XCTAssertEqual(game.opened.count, 90)
        XCTAssertEqual(game.cellState(cell(0, 0)), .covered)
        XCTAssertEqual(game.open(cell(0, 0), forgiving: true), .opened(CellSet([cell(0, 0)])))
        XCTAssertEqual(game.cellState(cell(0, 0)), .number(1))
        XCTAssertNil(game.open(cell(0, 0), forgiving: true), "already open")
        XCTAssertNil(game.open(cell(5, 5), forgiving: true), "already open")
        XCTAssertNil(game.open(96, forgiving: true))
    }

    func testAFlaggedSquareCannotBeOpenedAndAnOpenOneCannotBeFlagged() {
        var game = pocketGame()
        XCTAssertTrue(game.toggleFlag(cell(0, 1)))
        XCTAssertEqual(game.cellState(cell(0, 1)), .flagged)
        XCTAssertEqual(game.minesLeft, 11)
        XCTAssertNil(game.open(cell(0, 1), forgiving: true))
        XCTAssertFalse(game.toggleFlag(cell(5, 5)))
        XCTAssertTrue(game.toggleFlag(cell(0, 1)))
        XCTAssertEqual(game.cellState(cell(0, 1)), .covered)
    }

    func testMinesLeftGoesBelowZeroWithTooManyFlags() {
        var game = MinesGame(difficulty: .easy, mines: wall, firstTap: cell(11, 0))
        for square in 0..<13 { XCTAssertTrue(game.toggleFlag(square)) }
        XCTAssertEqual(game.minesLeft, -1)
    }

    func testANumberWhoseFlagsMatchOpensItsNeighbours() {
        var game = pocketGame()
        XCTAssertFalse(game.canChord(cell(1, 2)), "no flags yet")
        XCTAssertNil(game.chord(cell(1, 2), forgiving: true))
        game.toggleFlag(cell(0, 2))
        XCTAssertFalse(game.canChord(cell(1, 2)), "one flag short")
        game.toggleFlag(cell(1, 1))
        XCTAssertTrue(game.canChord(cell(1, 2)))
        XCTAssertEqual(game.chord(cell(1, 2), forgiving: true), .opened(CellSet([cell(0, 1)])))
        XCTAssertFalse(game.canChord(cell(1, 2)), "nothing left to open")
        XCTAssertFalse(game.canChord(cell(0, 0)), "covered squares cannot chord")
    }

    func testAChordOnAWrongFlagOpensAMine() {
        var game = pocketGame()
        game.toggleFlag(cell(0, 2))
        game.toggleFlag(cell(0, 1))
        let before = game
        XCTAssertEqual(game.chord(cell(1, 2), forgiving: true), .slipped(mine: cell(1, 1)))
        XCTAssertEqual(game.status, .slipped)
        XCTAssertEqual(game.opened, before.opened)
        XCTAssertEqual(game.flagged, before.flagged)
    }

    func testOpeningAnAreaClearsWrongFlagsAndTheLastSafeSquareWins() {
        var game = MinesGame(difficulty: .easy, mines: wall, firstTap: cell(11, 0))
        XCTAssertTrue(game.toggleFlag(cell(0, 0)))
        guard case .won(let revealed) = game.open(cell(0, 7), forgiving: true) else { return XCTFail() }
        XCTAssertEqual(revealed.count, 40)
        XCTAssertEqual(game.status, .won)
        XCTAssertEqual(game.flagged, wall, "a win flags every mine")
        XCTAssertEqual(game.minesLeft, 12 - 8)
        XCTAssertEqual(game.cellState(cell(0, 0)), .number(0))
    }

    func testABoardIsWonWithoutAnyFlags() {
        var game = pocketGame()
        game.open(cell(0, 0), forgiving: true)
        game.open(cell(0, 1), forgiving: true)
        XCTAssertEqual(game.open(cell(1, 0), forgiving: true), .won(CellSet([cell(1, 0)])))
        XCTAssertTrue(game.isFinished)
    }

    func testTheFirstMineCanBeTakenBackAndTheSecondLoses() {
        var game = pocketGame()
        game.toggleFlag(cell(0, 0))
        let before = game
        XCTAssertEqual(game.open(cell(1, 1), forgiving: true), .slipped(mine: cell(1, 1)))
        XCTAssertEqual(game.cellState(cell(1, 1)), .exploded)
        XCTAssertNil(game.open(cell(0, 1), forgiving: true), "nothing else until the slip is answered")
        XCTAssertFalse(game.toggleFlag(cell(0, 1)))

        XCTAssertTrue(game.takeBack())
        XCTAssertEqual(game.opened, before.opened)
        XCTAssertEqual(game.flagged, before.flagged)
        XCTAssertNil(game.exploded)
        XCTAssertTrue(game.slipUsed)
        XCTAssertFalse(game.takeBack())

        XCTAssertEqual(game.open(cell(1, 1), forgiving: true), .lost(mine: cell(1, 1)))
        XCTAssertEqual(game.status, .lost)
        XCTAssertFalse(game.takeBack())
    }

    func testWithoutForgivenessTheFirstMineLoses() {
        var game = pocketGame()
        XCTAssertEqual(game.open(cell(2, 0), forgiving: false), .lost(mine: cell(2, 0)))
        XCTAssertFalse(game.slipUsed)
    }

    func testEndingTheBoardAfterASlipLoses() {
        var game = pocketGame()
        XCTAssertFalse(game.endBoard())
        game.open(cell(2, 0), forgiving: true)
        XCTAssertTrue(game.endBoard())
        XCTAssertEqual(game.status, .lost)
        XCTAssertEqual(game.exploded, cell(2, 0))
    }

    func testALostBoardShowsItsMinesAndWrongFlags() {
        var game = pocketGame()
        game.toggleFlag(cell(0, 2))
        game.toggleFlag(cell(0, 0))
        game.open(cell(1, 1), forgiving: false)
        XCTAssertEqual(game.cellState(cell(1, 1)), .exploded)
        XCTAssertEqual(game.cellState(cell(0, 2)), .flagged)
        XCTAssertEqual(game.cellState(cell(2, 0)), .mine)
        XCTAssertEqual(game.cellState(cell(0, 0)), .wrongFlag)
        XCTAssertEqual(game.cellState(cell(0, 1)), .covered)
    }

    func testNothingCanBeDoneOnceTheBoardIsOver() {
        var lost = pocketGame()
        lost.open(cell(2, 0), forgiving: false)
        var won = pocketGame()
        won.open(cell(0, 0), forgiving: true)
        won.open(cell(0, 1), forgiving: true)
        won.open(cell(1, 0), forgiving: true)
        for var game in [lost, won] {
            let before = game
            XCTAssertNil(game.open(cell(0, 0), forgiving: true))
            XCTAssertNil(game.chord(cell(1, 2), forgiving: true))
            XCTAssertFalse(game.toggleFlag(cell(0, 1)))
            XCTAssertFalse(game.takeBack())
            XCTAssertFalse(game.endBoard())
            XCTAssertEqual(game, before)
        }
    }

    func testTheSolverWinsEveryDifficultyThroughTheGame() {
        for difficulty in Difficulty.allCases {
            for seed in 1...20 as ClosedRange<UInt64> {
                var game = MinesGame(seed: seed, difficulty: difficulty)
                game.open(Int(seed * 7 % 96), forgiving: false)
                let solver = MinesSolver(reasoning: difficulty.reasoning)
                while game.status == .playing {
                    guard let field = game.field,
                          let step = solver.step(field, .init(opened: game.opened, mines: game.flagged)) else {
                        return XCTFail("\(difficulty) seed \(seed) needs a guess:\n\(game.signature)")
                    }
                    for mine in step.mines where !game.flagged.contains(mine) { XCTAssertTrue(game.toggleFlag(mine)) }
                    for safe in step.safe where !game.opened.contains(safe) && game.status == .playing {
                        XCTAssertNotNil(game.open(safe, forgiving: false))
                    }
                    XCTAssertEqual(game.integrityProblems, [])
                }
                XCTAssertEqual(game.status, .won, "\(difficulty) seed \(seed)")
            }
        }
    }
}
