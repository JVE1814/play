import BubbleEngine
import Bubbles
import PlayKit
import XCTest

@MainActor
final class BubblesTests: XCTestCase {
    private func session(_ env: TestEnvironment, _ arguments: [String] = []) -> BubblesSession {
        let context = env.context(for: BubblesModule(), arguments: arguments)
        let session = BubblesSession(context: context)
        session.setInView(true)
        return session
    }

    private func shoot(_ session: BubblesSession, _ direction: Point = Point(0, -1)) {
        session.setAim(direction)
        session.fire()
    }

    func testANewPlayerStartsAtLevelOne() {
        let env = TestEnvironment()
        let s = session(env)
        XCTAssertEqual(s.levelNumber, 1)
        XCTAssertEqual(s.game.grid, LevelCatalog.level(1).layout.grid)
        XCTAssertEqual(s.game.shotsLeft, LevelCatalog.level(1).shotLimit)
        XCTAssertEqual(BubblesModule().statusLine(context: s.context), "Level 1 · 0 ★")
    }

    func testEveryShotIsSavedSoARelaunchRestoresTheBoard() {
        let env = TestEnvironment()
        let first = session(env, ["-level", "210"])
        shoot(first, Point(-0.4, -1))
        shoot(first, Point(0.6, -1))
        XCTAssertEqual(first.game.shotsFired, 2)
        let relaunched = session(env)
        XCTAssertEqual(relaunched.game, first.game)
        XCTAssertEqual(relaunched.signature, first.signature)
    }

    func testClearingALevelRecordsAWinAndUnlocksTheNext() {
        let env = TestEnvironment()
        let s = session(env, ["-scenario", "bubblesNearWin"])
        XCTAssertNil(s.aimTrace, "no aim yet")
        shoot(s)
        XCTAssertEqual(s.game.status, .won)
        XCTAssertTrue(s.showsResult)
        XCTAssertEqual(s.progress.stars(for: 1), 3)
        XCTAssertTrue(s.progress.isUnlocked(2))
        XCTAssertEqual(s.context.gameStats.won, 1)
        s.nextLevel()
        XCTAssertEqual(s.levelNumber, 2)
        XCTAssertFalse(s.showsResult)
    }

    func testRunningOutOfShotsRecordsALoss() {
        let env = TestEnvironment()
        let s = session(env, ["-scenario", "bubblesLastShot"])
        shoot(s)
        XCTAssertEqual(s.game.status, .outOfShots)
        XCTAssertTrue(s.showsResult)
        let stats = s.context.gameStats
        XCTAssertEqual(stats.played, 1)
        XCTAssertEqual(stats.won, 0)
        XCTAssertFalse(s.progress.isUnlocked(2))
        s.retry()
        XCTAssertEqual(s.game.status, .playing)
        XCTAssertEqual(s.game.grid, LevelCatalog.level(1).layout.grid)
    }

    func testRestartAsksOnlyOnceShotsHaveBeenFired() {
        let env = TestEnvironment()
        let s = session(env)
        s.requestRestart()
        XCTAssertFalse(s.confirmingRestart)
        shoot(s, Point(0.9, -1))
        s.requestRestart()
        XCTAssertTrue(s.confirmingRestart)
        s.retry()
        XCTAssertEqual(s.game.shotsFired, 0)
        XCTAssertEqual(s.context.gameStats.played, 0, "restarting is not a loss")
    }

    func testLockedLevelsCannotBeStarted() {
        let env = TestEnvironment()
        let s = session(env)
        s.start(level: 50)
        XCTAssertEqual(s.levelNumber, 1)
        let unlocked = session(TestEnvironment(), ["-level", "50"])
        unlocked.start(level: 49)
        XCTAssertEqual(unlocked.levelNumber, 49)
    }

    func testSwapExchangesTheBubbles() {
        let env = TestEnvironment()
        let s = session(env, ["-scenario", "bubblesLastShot"])
        XCTAssertEqual(s.game.current, .red)
        s.swap()
        XCTAssertEqual(s.game.current, .yellow)
        XCTAssertEqual(s.game.next, .red)
    }

    func testVoiceOverAimingTurnsAndFires() {
        let env = TestEnvironment()
        let s = session(env, ["-scenario", "bubblesNearWin"])
        s.adjustSpokenAim(by: 5)
        XCTAssertTrue(s.spokenAim.contains("5 degrees right"), s.spokenAim)
        s.adjustSpokenAim(by: -5)
        XCTAssertTrue(s.spokenAim.contains("straight up"), s.spokenAim)
        s.fireSpokenAim()
        XCTAssertEqual(s.game.status, .won)
    }

    /// Touch above the launcher points; touch below pulls back like a slingshot.
    func testTouchAimingPointsOrPullsBack() throws {
        let layout = FieldLayout(size: CGSize(width: 390, height: 600))
        let launcher = layout.launcher
        let above = try XCTUnwrap(layout.aim(for: CGPoint(x: launcher.x - 100, y: launcher.y - 100)))
        XCTAssertLessThan(above.x, 0)
        XCTAssertLessThan(above.y, 0)
        let below = try XCTUnwrap(layout.aim(for: CGPoint(x: launcher.x - 60, y: launcher.y + 60)))
        XCTAssertGreaterThan(below.x, 0, "pulling back down-left aims up-right")
        XCTAssertLessThan(below.y, 0)
        XCTAssertNil(layout.aim(for: CGPoint(x: launcher.x + 3, y: launcher.y - 3)), "too close cancels")
        let flat = try XCTUnwrap(layout.aim(for: CGPoint(x: launcher.x + 200, y: launcher.y - 1)))
        XCTAssertGreaterThan(flat.x, 0, "beside the launcher still points")
        XCTAssertGreaterThanOrEqual(-flat.y, 0.12, "never flatter than about 7°")
        XCTAssertGreaterThanOrEqual(layout.diameter, 40, "bubbles stay big enough to see on a train")
    }
}
