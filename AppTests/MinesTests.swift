import Mines
import MinesEngine
import PlayKit
import XCTest

@MainActor
final class MinesTests: XCTestCase {
    private let nearWin = ["-scenario", "minesNearWin"]
    /// The four safe squares left on the near-win board.
    private var nearWinSafe: [Int] { [cell(0, 0), cell(0, 7), cell(1, 2), cell(1, 5)] }

    private func session(_ env: TestEnvironment, _ arguments: [String] = ["-seed", "42"]) -> MinesSession {
        let session = MinesSession(context: env.context(for: MinesModule(), arguments: arguments))
        session.setInView(true)
        return session
    }

    private func cell(_ row: Int, _ column: Int) -> Int { MinesGrid.index(row: row, column: column) }

    func testTheFirstTapLaysTheSeededBoardAndOpensAnArea() {
        let s = session(TestEnvironment())
        XCTAssertEqual(s.game.status, .fresh)
        XCTAssertEqual(s.game.difficulty, .medium, "Medium by default")
        s.tap(cell(6, 3))
        XCTAssertEqual(s.game.field, MinesGenerator.generate(seed: 42, difficulty: .medium, firstTap: cell(6, 3)).field)
        XCTAssertEqual(s.game.cellState(cell(6, 3)), .number(0))
        XCTAssertGreaterThan(s.game.opened.count, 9)
    }

    func testEveryChangeIsSavedSoARelaunchRestoresTheBoard() {
        let env = TestEnvironment()
        let first = session(env, nearWin)
        first.tap(cell(1, 2))
        first.longPress(cell(1, 0))
        first.toggleFlagMode()
        // A brand-new session on the same storage is what the app sees after a force quit.
        let relaunched = session(env, [])
        XCTAssertEqual(relaunched.game, first.game)
        XCTAssertTrue(relaunched.flagMode)
        XCTAssertEqual(relaunched.signature, first.signature)
    }

    func testFlagsComeFromALongPressOrFlagMode() {
        let s = session(TestEnvironment(), nearWin)
        s.longPress(cell(1, 0))
        XCTAssertEqual(s.game.cellState(cell(1, 0)), .flagged)
        XCTAssertEqual(s.game.minesLeft, 11)
        s.tap(cell(1, 0))
        XCTAssertEqual(s.game.cellState(cell(1, 0)), .flagged, "a tap never opens a flagged square")
        XCTAssertEqual(s.rejections[cell(1, 0)], 1)
        s.toggleFlagMode()
        s.tap(cell(1, 1))
        XCTAssertEqual(s.game.cellState(cell(1, 1)), .flagged)
        s.tap(cell(1, 1))
        XCTAssertEqual(s.game.cellState(cell(1, 1)), .covered)
        s.longPress(cell(1, 0))
        XCTAssertEqual(s.game.minesLeft, 12, "a long press unflags in flag mode too")
    }

    func testNoFlagsBeforeTheFirstTap() {
        let s = session(TestEnvironment())
        s.longPress(cell(3, 3))
        XCTAssertTrue(s.game.flagged.isEmpty)
        XCTAssertEqual(s.toast, "Open a square first")
        s.toggleFlagMode()
        s.tap(cell(3, 3))
        XCTAssertEqual(s.game.status, .fresh)
    }

    func testTappingANumberWhoseFlagsMatchOpensAroundIt() {
        // (2,1) shows 2: its covered neighbours (1,0) and (1,1) are mines and (1,2) is safe.
        let s = session(TestEnvironment(), nearWin)
        s.longPress(cell(1, 0))
        s.longPress(cell(1, 1))
        s.tap(cell(2, 1))
        XCTAssertEqual(s.game.cellState(cell(1, 2)), .number(5))
    }

    func testTheFirstMineCanBeTakenBackAndTheSecondEndsTheBoard() {
        let env = TestEnvironment()
        let s = session(env, nearWin)
        s.tap(cell(1, 2))
        let before = s.game
        s.tap(cell(0, 3))
        XCTAssertEqual(s.game.status, .slipped)
        XCTAssertTrue(s.showsResult)
        XCTAssertEqual(session(env, []).game.status, .slipped, "a relaunch still asks")
        s.takeBack()
        XCTAssertFalse(s.showsResult)
        XCTAssertEqual(s.game.status, .playing)
        XCTAssertEqual(s.game.opened, before.opened)
        s.tap(cell(0, 3))
        XCTAssertEqual(s.game.status, .lost)
        XCTAssertTrue(s.showsResult)
        XCTAssertEqual(s.context.gameStats.played, 1)
        XCTAssertEqual(s.context.gameStats.won, 0)
        s.startNewBoard()
        XCTAssertEqual(s.context.gameStats.played, 1, "a lost board is counted once")
    }

    func testWithoutForgivenessTheFirstMineEndsTheBoard() {
        let env = TestEnvironment()
        let context = env.context(for: MinesModule(), arguments: nearWin)
        context.preferences(MinesPreferences.self).forgiveSlip = false
        let s = MinesSession(context: context)
        s.setInView(true)
        s.tap(cell(0, 3))
        XCTAssertEqual(s.game.status, .lost)
        XCTAssertEqual(s.context.gameStats.played, 1)
    }

    func testEndingTheBoardAfterASlipIsALoss() {
        let s = session(TestEnvironment(), nearWin)
        s.tap(cell(0, 3))
        s.endBoard()
        XCTAssertEqual(s.game.status, .lost)
        XCTAssertTrue(s.showsResult)
        XCTAssertEqual(s.context.gameStats.played, 1)
    }

    func testANewBoardMidGameAsksFirstAndCountsAsALoss() {
        let s = session(TestEnvironment())
        s.requestNewBoard()
        XCTAssertFalse(s.confirmingNewBoard, "nothing opened yet, no question needed")
        XCTAssertEqual(s.context.gameStats.played, 0)
        s.tap(cell(6, 3))
        s.requestNewBoard()
        XCTAssertTrue(s.confirmingNewBoard)
        s.startNewBoard()
        XCTAssertEqual(s.context.gameStats.played, 1)
        XCTAssertEqual(s.context.gameStats.won, 0)
        XCTAssertEqual(s.game.status, .fresh)
        XCTAssertEqual(s.game.seed, 43, "board 1 of seed 42")
    }

    func testClearingTheBoardIsAWinRecordedOnceWithABestTime() {
        let env = TestEnvironment()
        let s = session(env, nearWin)
        for safe in nearWinSafe { s.tap(safe) }
        XCTAssertEqual(s.game.status, .won)
        XCTAssertTrue(s.showsResult)
        XCTAssertTrue(s.isNewBest)
        XCTAssertNotNil(s.bestTimes[.easy])
        XCTAssertNil(s.bestTimes[.medium])
        XCTAssertEqual(s.context.gameStats.won, 1)

        let relaunched = session(env, [])
        XCTAssertTrue(relaunched.showsResult)
        XCTAssertEqual(relaunched.context.gameStats.played, 1, "not recorded twice")
        relaunched.requestNewBoard()
        XCTAssertFalse(relaunched.confirmingNewBoard)
        XCTAssertEqual(relaunched.context.gameStats.played, 1, "a new board after a win is not a loss")
        XCTAssertNotNil(relaunched.bestTimes[.easy])
    }

    func testSeeingTheBoardPutsTheResultAsideUntilTheNextTap() {
        let s = session(TestEnvironment(), nearWin)
        s.tap(cell(0, 3))
        s.endBoard()
        s.seeBoard()
        XCTAssertFalse(s.showsResult)
        s.tap(cell(5, 5))
        XCTAssertTrue(s.showsResult)
    }

    func testADifficultyChangeWaitsForTheNextBoardUnlessNothingIsOpen() {
        let s = session(TestEnvironment())
        let preferences = s.context.preferences(MinesPreferences.self)
        preferences.difficulty = .hard
        s.setInView(false)
        s.setInView(true)
        XCTAssertEqual(s.game.difficulty, .hard, "a board not yet started takes it at once")
        preferences.difficulty = .easy
        s.setInView(false)
        s.setInView(true)
        s.tap(cell(6, 3))
        XCTAssertEqual(s.game.field?.mines.count, 12)
        preferences.difficulty = .hard
        s.setInView(false)
        s.setInView(true)
        XCTAssertEqual(s.game.difficulty, .easy, "a started board keeps its difficulty")
        s.startNewBoard()
        XCTAssertEqual(s.game.difficulty, .hard)
    }

    func testADamagedSaveGivesAFreshBoardButKeepsTheBestTimes() throws {
        let env = TestEnvironment()
        let s = session(env, nearWin)
        for safe in nearWinSafe { s.tap(safe) }
        s.startNewBoard()
        s.tap(cell(6, 3))

        // Claim the board is won while squares are still covered.
        let slot = env.context(for: MinesModule()).saveSlot
        let data = try JSONEncoder().encode(try XCTUnwrap(slot.load(MinesSave.self)))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var game = try XCTUnwrap(json["game"] as? [String: Any])
        game["status"] = "won"
        json["game"] = game
        slot.save(try JSONDecoder().decode(MinesSave.self, from: JSONSerialization.data(withJSONObject: json)))

        let relaunched = session(env, [])
        XCTAssertEqual(relaunched.game.status, .fresh)
        XCTAssertNotNil(relaunched.bestTimes[.easy])
    }

    func testAnUnreadableSaveGivesAFreshBoard() {
        let env = TestEnvironment()
        env.context(for: MinesModule()).saveSlot.save(["not": "a board"])
        XCTAssertEqual(session(env).game.status, .fresh)
    }

    func testTheClockRunsOnlyWhileABoardIsPlayedInView() throws {
        let s = session(TestEnvironment())
        let later = Date().addingTimeInterval(600)
        XCTAssertEqual(s.elapsed(at: later), 0, "not before the first tap")
        s.tap(cell(6, 3))
        XCTAssertGreaterThan(s.elapsed(at: later), 500)

        s.setInView(false)
        let away = s.elapsed(at: later)
        XCTAssertEqual(s.elapsed(at: later.addingTimeInterval(600)), away, accuracy: 0.001)
        s.setInView(true)

        let mine = try XCTUnwrap(s.game.field?.mines.first)
        s.tap(mine)
        XCTAssertEqual(s.game.status, .slipped)
        let asking = s.elapsed(at: later)
        XCTAssertEqual(s.elapsed(at: later.addingTimeInterval(600)), asking, accuracy: 0.001,
                       "the clock waits while the slip question is up")
    }

    func testTheHomeTileShowsABoardInProgress() {
        let env = TestEnvironment()
        let module = MinesModule()
        let context = env.context(for: module)
        XCTAssertNil(module.statusLine(context: context))
        let s = MinesSession(context: context)
        s.setInView(true)
        XCTAssertNil(module.statusLine(context: context), "nothing opened yet")
        s.tap(cell(6, 3))
        XCTAssertEqual(module.statusLine(context: context)?.hasPrefix("Resume · Medium ·"), true)
    }

    /// Squares stay large enough to hit on a moving train, even on the smallest supported iPhone.
    func testTheBoardFitsTheSmallestPhoneAndGrowsOnLargerOnes() {
        let smallest = MinesLayout(size: CGSize(width: 375, height: 500))
        XCTAssertGreaterThanOrEqual(smallest.cell, 38)
        XCTAssertGreaterThanOrEqual(smallest.pitch, 40)
        XCTAssertGreaterThanOrEqual(MinesLayout(size: CGSize(width: 375, height: 600)).cell, 42)
        XCTAssertGreaterThanOrEqual(MinesLayout(size: CGSize(width: 393, height: 626)).cell, 44)
        XCTAssertGreaterThanOrEqual(MinesLayout(size: CGSize(width: 440, height: 727)).cell, 50)

        for size in [CGSize(width: 375, height: 500), CGSize(width: 375, height: 600),
                     CGSize(width: 393, height: 626), CGSize(width: 440, height: 727)] {
            let layout = MinesLayout(size: size)
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(layout.boardFrame), "\(size)")
            XCTAssertEqual(layout.boardFrame.maxY, size.height - 6, accuracy: 0.5, "rests at the bottom")
            XCTAssertEqual(layout.boardFrame.midX, size.width / 2, accuracy: 1)
            for square in 0..<MinesGrid.cellCount {
                XCTAssertTrue(layout.boardFrame.insetBy(dx: -0.01, dy: -0.01).contains(layout.frame(of: square)))
            }
            XCTAssertEqual(layout.frame(of: 1).minX - layout.frame(of: 0).maxX, layout.gap, accuracy: 0.01)
        }
    }

    func testTheScenarioBoardsAreWhatTheUITestsExpect() throws {
        let near = session(TestEnvironment(), nearWin).game
        let nearField = try XCTUnwrap(near.field)
        XCTAssertEqual(near.integrityProblems, [])
        XCTAssertEqual(near.difficulty, .easy)
        XCTAssertEqual(nearField.safeCells.subtracting(near.opened), CellSet(nearWinSafe))
        for mine in [cell(0, 3), cell(1, 0), cell(1, 1)] { XCTAssertTrue(nearField.isMine(mine)) }
        XCTAssertEqual(nearField.count(around: cell(1, 2)), 5)

        let showcase = session(TestEnvironment(), ["-scenario", "minesShowcase"]).game
        let field = try XCTUnwrap(showcase.field)
        XCTAssertEqual(showcase.integrityProblems, [])
        XCTAssertEqual(showcase.status, .playing)
        XCTAssertEqual(showcase.flagged.count, 3)
        XCTAssertTrue(showcase.flagged.isSubset(of: field.mines))
        XCTAssertEqual(showcase.cellState(cell(4, 4)), .covered)
        XCTAssertTrue(field.isMine(cell(4, 4)))
        XCTAssertFalse(MinesGrid.neighbours(of: cell(4, 4)).isDisjoint(with: showcase.opened))
    }
}
