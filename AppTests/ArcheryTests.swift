import Archery
import ArcheryEngine
import PlayKit
import XCTest

@MainActor
final class ArcheryTests: XCTestCase {
    private func session(_ env: TestEnvironment, _ arguments: [String] = [], animated: Bool = false) -> ArcherySession {
        let context = env.context(for: ArcheryModule(), arguments: arguments, animated: animated)
        let session = ArcherySession(context: context)
        session.setInView(true)
        return session
    }

    /// Draws, holds `held` seconds past full draw and lets go, on a simulated clock.
    private func shoot(_ session: ArcherySession, held: Double = 1.0, at start: Date = Date()) {
        session.beginDraw(at: start)
        session.release(at: start.addingTimeInterval(Sway.drawTime + held))
    }

    func testANewArcherStartsAtLevelOneWithTheTip() {
        let env = TestEnvironment()
        let s = session(env)
        XCTAssertEqual(s.level.number, 1)
        XCTAssertEqual(s.displayedArrowsLeft, 3)
        XCTAssertTrue(s.showingTip)
        XCTAssertTrue(s.canDraw)
        XCTAssertEqual(s.aim, .zero, "the sight starts on the gold")
        XCTAssertEqual(ArcheryModule().statusLine(context: s.context), "Level 1 · 0 ★")
    }

    func testDrawingAndLettingGoShootsAnArrow() throws {
        let env = TestEnvironment()
        let s = session(env)
        shoot(s)
        XCTAssertEqual(s.round.shots.count, 1)
        XCTAssertEqual(s.landedArrows, 1)
        let shot = try XCTUnwrap(s.round.shots.first)
        XCTAssertGreaterThanOrEqual(shot.score, 10, "ten metres, no wind, sight on the gold")
        XCTAssertEqual(s.displayedScore, shot.score)
        XCTAssertFalse(s.showingTip, "the tip goes away at the first draw")
        XCTAssertEqual(s.landing?.shot, shot)
        XCTAssertFalse(s.isDrawing)
    }

    func testLettingGoBeforeFullDrawLetsTheBowDown() {
        let env = TestEnvironment()
        let s = session(env)
        let start = Date()
        s.beginDraw(at: start)
        XCTAssertTrue(s.isDrawing)
        XCTAssertLessThan(s.drawProgress(at: start.addingTimeInterval(0.2)), 1)
        s.release(at: start.addingTimeInterval(0.2))
        XCTAssertTrue(s.round.shots.isEmpty)
        XCTAssertNotNil(s.notice)
        XCTAssertTrue(s.canDraw)
    }

    func testTheSightFollowsTheThumbWithinTheView() {
        let env = TestEnvironment()
        let s = session(env)
        s.moveAim(by: Vec2(0.1, 0), limit: Vec2(1, 1))
        XCTAssertEqual(s.aim, .zero, "the sight only moves while drawing")
        s.beginDraw()
        s.moveAim(by: Vec2(0.1, 0.05), limit: Vec2(1, 1))
        XCTAssertEqual(s.aim.x, 0.1, accuracy: 1e-9)
        XCTAssertEqual(s.aim.y, 0.05, accuracy: 1e-9)
        s.moveAim(by: Vec2(5, -5), limit: Vec2(1, 0.8))
        XCTAssertEqual(s.aim, Vec2(1, -0.8))
    }

    func testLiftingTheThumbDoesNotNudgeTheShot() throws {
        let env = TestEnvironment()
        let s = session(env)
        let start = Date()
        s.beginDraw(at: start)
        s.moveAim(by: Vec2(0.2, 0), limit: Vec2(1, 1), at: start.addingTimeInterval(1.0))
        // A flick as the thumb lifts, in the last hundredths of a second.
        s.moveAim(by: Vec2(0.3, 0), limit: Vec2(1, 1), at: start.addingTimeInterval(1.47))
        s.release(at: start.addingTimeInterval(1.5))
        let shot = try XCTUnwrap(s.round.shots.first)
        XCTAssertEqual(shot.aim.x, 0.2, accuracy: 0.03, "the flick is ignored")
        XCTAssertEqual(s.aim.x, 0.2, accuracy: 1e-9)
    }

    func testAFlickAfterAStillHoldIsIgnoredToo() throws {
        let env = TestEnvironment()
        let s = session(env)
        let start = Date()
        s.beginDraw(at: start)
        // No movement for well over half a second, then the thumb nudges as it lifts.
        s.moveAim(by: Vec2(0.3, 0), limit: Vec2(1, 1), at: start.addingTimeInterval(1.47))
        s.release(at: start.addingTimeInterval(1.5))
        let shot = try XCTUnwrap(s.round.shots.first)
        XCTAssertEqual(shot.aim.x, 0, accuracy: 0.03, "shot where the sight rested, not where the lift nudged it")
    }

    func testClosingTheAppWhileTheLastArrowFliesStillRecordsTheEnd() {
        let env = TestEnvironment()
        let s = session(env, ["-scenario", "archeryNearWin"], animated: true)
        shoot(s)
        XCTAssertNotNil(s.flight, "the last arrow is in the air")
        XCTAssertTrue(s.round.isOver)
        // Force quit now: the next launch finds a finished end that was never recorded.
        let relaunched = session(env)
        XCTAssertTrue(relaunched.showsResult)
        XCTAssertEqual(relaunched.progress.stars(for: 1), 3)
        XCTAssertTrue(relaunched.progress.isUnlocked(2), "Next Level works")
        XCTAssertEqual(s.context.gameStats.won, 1)
    }

    func testLeavingWhileTheLastArrowFliesLandsItAndRecordsTheEnd() {
        let env = TestEnvironment()
        let s = session(env, ["-scenario", "archeryNearWin"], animated: true)
        shoot(s)
        s.setInView(false)
        XCTAssertNil(s.flight)
        XCTAssertEqual(s.landedArrows, 3)
        XCTAssertEqual(s.context.gameStats.won, 1)
        XCTAssertEqual(session(env).progress.stars(for: 1), 3, "saved too")
    }

    func testRestartWaitsForAFlyingArrowAndAChosenLevelRecordsTheEndFirst() {
        let env = TestEnvironment()
        let s = session(env, ["-scenario", "archeryNearWin"], animated: true)
        shoot(s)
        s.requestRestart()
        XCTAssertNotNil(s.flight, "restart waits for the arrow to land")
        XCTAssertEqual(s.round.shots.count, 3)
        s.start(level: 1)
        XCTAssertTrue(s.round.shots.isEmpty)
        XCTAssertEqual(s.context.gameStats.won, 1, "the finished end still counts")
        XCTAssertEqual(s.progress.stars(for: 1), 3)
    }

    func testSettingsOverTheGamePausesTheClock() throws {
        let env = TestEnvironment()
        let s = session(env, ["-level", "9"])
        let start = Date()
        shoot(s, at: start)
        s.setInView(false)
        let left = try XCTUnwrap(s.timeLeft(at: start.addingTimeInterval(60)))
        XCTAssertGreaterThan(left, 15, "no time passes behind Settings")
        s.beginDraw(at: start.addingTimeInterval(60))
        XCTAssertFalse(s.round.isOver)
        s.setInView(true)
        XCTAssertFalse(s.round.isOver)
    }

    func testVoiceOverFindsTheSpotsOnAThreeSpotFace() {
        let env = TestEnvironment()
        let s = session(env, ["-level", "6"])
        XCTAssertTrue(s.spokenStatus().hasPrefix("On the top spot. Sight on the centre. Free: top, middle, bottom."),
                      s.spokenStatus())
        s.shootFromAccessibility()
        s.aimAtNextFreeSpot()
        XCTAssertTrue(s.spokenStatus().hasPrefix("On the middle spot. Sight on the centre. Free: middle, bottom."),
                      s.spokenStatus())
        s.nudgeAim(x: 1, y: 0)
        XCTAssertTrue(s.spokenStatus().contains("On the middle spot. Sight 3 centimetres right."), s.spokenStatus())
    }

    func testEveryArrowIsSavedSoARelaunchRestoresTheEnd() {
        let env = TestEnvironment()
        let first = session(env, ["-level", "7"])
        shoot(first)
        shoot(first, held: 0.8)
        XCTAssertEqual(first.round.shots.count, 2)
        let relaunched = session(env)
        XCTAssertEqual(relaunched.round.shots, first.round.shots)
        XCTAssertEqual(relaunched.signature, first.signature)
        XCTAssertEqual(relaunched.aim, first.aim)
        XCTAssertEqual(relaunched.round.clock, first.round.clock, accuracy: 0.5)
    }

    func testFinishingALevelRecordsAWinAndUnlocksTheNext() {
        let env = TestEnvironment()
        let s = session(env, ["-scenario", "archeryNearWin"])
        XCTAssertEqual(s.displayedArrowsLeft, 1)
        shoot(s)
        XCTAssertTrue(s.round.isOver)
        XCTAssertTrue(s.round.passed)
        XCTAssertEqual(s.round.stars, 3)
        XCTAssertTrue(s.showsResult)
        XCTAssertEqual(s.progress.stars(for: 1), 3)
        XCTAssertTrue(s.progress.isUnlocked(2))
        XCTAssertEqual(s.context.gameStats.won, 1)
        XCTAssertEqual(ArcheryModule().statusLine(context: s.context), "Level 1 · 3 ★")
        s.nextLevel()
        XCTAssertEqual(s.level.number, 2)
        XCTAssertFalse(s.showsResult)
        XCTAssertTrue(s.showingTip)
        XCTAssertTrue(s.round.shots.isEmpty)
    }

    func testAPoorEndRecordsALoss() {
        let env = TestEnvironment()
        let s = session(env, ["-scenario", "archeryLastArrow"])
        shoot(s)
        XCTAssertTrue(s.round.isOver)
        XCTAssertFalse(s.round.passed)
        XCTAssertTrue(s.showsResult)
        let stats = s.context.gameStats
        XCTAssertEqual(stats.played, 1)
        XCTAssertEqual(stats.won, 0)
        XCTAssertFalse(s.progress.isUnlocked(2))
        XCTAssertEqual(s.round.score, 0, "the sight was still on the straw beside the face")
        XCTAssertNil(s.progress.bestScore(for: 1), "no points is not a best score")
        let attempt = s.round.attempt
        s.retry()
        XCTAssertEqual(s.round.attempt, attempt + 1, "every attempt meets new conditions")
        XCTAssertTrue(s.round.shots.isEmpty)
        XCTAssertFalse(s.showsResult)
    }

    func testRunningOutOfTimeEndsTheLevel() {
        let env = TestEnvironment()
        let s = session(env, ["-level", "9"])
        XCTAssertEqual(s.timeLeft(), 20, "the clock waits for the first draw")
        let start = Date()
        shoot(s, at: start)
        XCTAssertEqual(s.timeLeft(at: start.addingTimeInterval(5)) ?? 0, 15, accuracy: 0.01)
        s.beginDraw(at: start.addingTimeInterval(30))
        XCTAssertTrue(s.round.isOver)
        XCTAssertTrue(s.round.timedOut)
        XCTAssertFalse(s.isDrawing)
        XCTAssertTrue(s.showsResult)
        XCTAssertEqual(s.round.shots.count, 1)
        XCTAssertEqual(s.context.gameStats.played, 1)
    }

    func testEarlyLevelsSayWhatTheWindDid() throws {
        let env = TestEnvironment()
        let s = session(env, ["-level", "7"])
        shoot(s)
        let shot = try XCTUnwrap(s.round.shots.first)
        XCTAssertGreaterThan(shot.drift, 0.1, "1.8 m/s from the left at 30 m")
        let notice = try XCTUnwrap(s.notice)
        XCTAssertTrue(notice.hasPrefix("The wind carried it 18 cm to the right."), notice)
        XCTAssertTrue(notice.hasSuffix("Aim a little further left."), notice)
        let calm = session(TestEnvironment())
        shoot(calm)
        XCTAssertNil(calm.notice, "nothing to say in still air")
    }

    func testRestartAsksOnlyOnceArrowsAreShot() {
        let env = TestEnvironment()
        let s = session(env)
        s.requestRestart()
        XCTAssertFalse(s.confirmingRestart)
        shoot(s)
        s.requestRestart()
        XCTAssertTrue(s.confirmingRestart)
        s.retry()
        XCTAssertTrue(s.round.shots.isEmpty)
        XCTAssertEqual(s.context.gameStats.played, 0, "restarting is not a loss")
    }

    func testLockedLevelsCannotBeStarted() {
        let env = TestEnvironment()
        let s = session(env)
        s.start(level: 5)
        XCTAssertEqual(s.level.number, 1)
    }

    func testVoiceOverCanAimAndShoot() {
        let env = TestEnvironment()
        let s = session(env, ["-level", "3"])
        XCTAssertTrue(s.spokenStatus().contains("Sight on the centre."), s.spokenStatus())
        XCTAssertTrue(s.spokenStatus().contains("Wind 1.4 metres per second from the left."), s.spokenStatus())
        s.nudgeAim(x: -1, y: 1)
        XCTAssertTrue(s.spokenStatus().contains("Sight 6 centimetres left and 6 centimetres high."), s.spokenStatus())
        s.shootFromAccessibility()
        XCTAssertEqual(s.round.shots.count, 1)
        XCTAssertTrue(s.spokenStatus().contains("2 arrows left."), s.spokenStatus())
    }

    func testSteadyAimReducesTheSway() {
        let shaky = session(TestEnvironment(), ["-level", "27"])
        let steadyEnv = TestEnvironment()
        let steady = session(steadyEnv, ["-level", "27"])
        steady.preferences.steadyAim = true
        let start = Date()
        shaky.beginDraw(at: start)
        steady.beginDraw(at: start)
        let moment = start.addingTimeInterval(Sway.drawTime + 1.3)
        let shakyOffset = (shaky.sight(at: moment) - shaky.aim).length
        let steadyOffset = (steady.sight(at: moment) - steady.aim).length
        XCTAssertGreaterThan(shakyOffset, 0)
        XCTAssertEqual(steadyOffset, shakyOffset * 0.3, accuracy: 1e-9)
    }

    func testPreferencesAreRemembered() {
        let env = TestEnvironment()
        let prefs = ArcheryPreferences(preferences: GamePreferences(gameID: ArcheryModule().id, defaults: env.defaults))
        XCTAssertEqual(prefs.aimSpeed, .normal)
        prefs.aimSpeed = .fast
        prefs.leftHanded = true
        let again = ArcheryPreferences(preferences: GamePreferences(gameID: ArcheryModule().id, defaults: env.defaults))
        XCTAssertEqual(again.aimSpeed, .fast)
        XCTAssertTrue(again.leftHanded)
        XCTAssertEqual(again.aimSpeed.gain, 0.65)
    }
}
