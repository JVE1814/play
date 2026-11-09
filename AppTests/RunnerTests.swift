import PlayKit
import Runner
import RunnerEngine
import XCTest

@MainActor
final class RunnerTests: XCTestCase {
    /// A session as the app would make it. With `animated`, time passes as it does for a
    /// player (the tests then say what time it is); without, as in UI tests, it stands still
    /// until a touch moves it on.
    private func session(_ env: TestEnvironment, _ arguments: [String] = [], animated: Bool = false) -> RunnerSession {
        let session = RunnerSession(context: env.context(for: RunnerModule(), arguments: arguments, animated: animated))
        // As the game's screen does: out of view until it has appeared.
        session.setInView(false)
        session.setInView(true)
        return session
    }

    private func stats(_ s: RunnerSession) -> GameStats { s.context.gameStats }

    func testANewPlayerWaitsOnTheStartLineWithTheFirstGoal() {
        let env = TestEnvironment()
        let s = session(env, ["-seed", "5"])
        XCTAssertEqual(s.phase, .ready)
        XCTAssertEqual(s.goal, 250)
        XCTAssertEqual(s.best, 0)
        XCTAssertFalse(s.showsResult)
        XCTAssertFalse(s.hasRunInProgress)
        XCTAssertEqual(s.run, Run(seed: 5, coached: true), "the first course opens with the lessons")
        XCTAssertEqual(s.signature, "ready|running|m:0|lane:1|run|coins:0|best:0|goal:250")
        XCTAssertNil(RunnerModule().statusLine(context: s.context))
    }

    func testATouchStartsTheRunAndTimeCarriesIt() {
        let env = TestEnvironment()
        let s = session(env, ["-seed", "5"], animated: true)
        let start = Date()
        s.advance(to: start.addingTimeInterval(5))
        XCTAssertEqual(s.run.distance, 0, "nothing moves before the first touch")
        s.tap(at: start)
        XCTAssertEqual(s.phase, .running)
        XCTAssertTrue(s.hasRunInProgress)
        for frame in 1...60 { s.advance(to: start.addingTimeInterval(Double(frame) / 60)) }
        XCTAssertEqual(s.run.distance, Pace.speed(at: 0), accuracy: 0.5, "a second's running")
        XCTAssertEqual(s.hud.score, s.run.score)
        XCTAssertGreaterThan(s.hud.score, 0)
    }

    func testTheFirstSwipeStartsTheRunAndCounts() {
        let env = TestEnvironment()
        let s = session(env, ["-seed", "5"], animated: true)
        s.perform(.left)
        XCTAssertEqual(s.phase, .running)
        XCTAssertEqual(s.run.lane, 0)
    }

    func testAHitchCountsForAQuarterOfASecondAtMost() {
        let env = TestEnvironment()
        let s = session(env, ["-seed", "5"], animated: true)
        let start = Date()
        s.tap(at: start)
        s.advance(to: start.addingTimeInterval(30))
        XCTAssertLessThan(s.run.distance, Pace.speed(at: 0) * 0.3)
        XCTAssertEqual(s.phase, .running)
    }

    func testThePierIsDrawnAheadOfThePlayedRunWithoutChangingIt() {
        let env = TestEnvironment()
        let s = session(env, ["-seed", "5"], animated: true)
        let start = Date()
        s.tap(at: start)
        s.advance(to: start.addingTimeInterval(0.2))
        let played = s.run
        let drawn = s.run(at: start.addingTimeInterval(0.3))
        XCTAssertEqual(drawn.distance - played.distance, Pace.speed(at: 0) * 0.1, accuracy: 0.2)
        XCTAssertEqual(s.run, played)
    }

    func testLeavingPausesAndTheRunWaitsForATouchAndAMomentMore() throws {
        let env = TestEnvironment()
        let s = session(env, ["-seed", "5"], animated: true)
        let start = Date()
        s.tap(at: start)
        s.advance(to: start.addingTimeInterval(0.25))
        s.advance(to: start.addingTimeInterval(0.5))
        s.setInView(false)
        XCTAssertEqual(s.phase, .paused)
        let status = try XCTUnwrap(RunnerModule().statusLine(context: s.context))
        XCTAssertTrue(status.hasPrefix("Resume · "), status)
        s.setInView(true)
        XCTAssertEqual(s.phase, .paused, "coming back does not start it")
        let paused = s.run.distance
        s.advance(to: start.addingTimeInterval(60))
        XCTAssertEqual(s.run.distance, paused)

        let back = start.addingTimeInterval(100)
        s.tap(at: back)
        XCTAssertEqual(s.phase, .running)
        XCTAssertEqual(s.resumesAt, back.addingTimeInterval(RunnerSession.resumeDelay))
        s.perform(.jump, at: back.addingTimeInterval(0.5))
        s.advance(to: back.addingTimeInterval(1))
        XCTAssertEqual(s.run.distance, paused, "still counting down")
        XCTAssertFalse(s.run.isAirborne, "a swipe made while nothing moves is not saved up")
        s.advance(to: back.addingTimeInterval(RunnerSession.resumeDelay + 0.2))
        XCTAssertGreaterThan(s.run.distance, paused)
        XCTAssertNil(s.resumesAt)
    }

    func testPauseAndCarryOnFromTheToolbar() {
        let env = TestEnvironment()
        let s = session(env, ["-seed", "5"])
        s.togglePause()
        XCTAssertEqual(s.phase, .ready, "nothing to pause yet")
        s.tap()
        s.togglePause()
        XCTAssertEqual(s.phase, .paused)
        s.perform(.left)
        XCTAssertEqual(s.run.lane, 1, "a paused runner does not move")
        s.togglePause()
        XCTAssertEqual(s.phase, .running)
    }

    func testInUITestsEveryTouchMovesTheClockOn() {
        let env = TestEnvironment()
        let s = session(env, ["-seed", "5"])
        s.tap()
        XCTAssertEqual(s.run.distance, 0)
        s.tap()
        XCTAssertEqual(s.run.time, RunnerSession.testStride, accuracy: 0.01)
        s.perform(.right)
        XCTAssertEqual(s.run.time, 2 * RunnerSession.testStride, accuracy: 0.01)
        XCTAssertEqual(s.run.lane, 2)
        XCTAssertEqual(s.run.across, 2, "the change of lane is over by the end of the stride")
    }

    func testRunningIntoSomethingEndsTheRunBelowTheGoalAsALoss() throws {
        let env = TestEnvironment()
        let s = session(env, ["-scenario", "runnerDeadEnd"])
        s.tap()
        for _ in 0..<4 { s.tap() }
        XCTAssertEqual(s.phase, .over)
        XCTAssertTrue(s.showsResult)
        let result = try XCTUnwrap(s.result)
        XCTAssertEqual(result.coins, 3)
        XCTAssertEqual(result.score, result.metres + 3 * Run.coinValue)
        XCTAssertFalse(result.reachedGoal)
        XCTAssertTrue(result.isBest, "a first run is the best so far")
        XCTAssertEqual(result.headline, "New best!")
        XCTAssertEqual(s.best, result.score)
        XCTAssertEqual(stats(s).played, 1)
        XCTAssertEqual(stats(s).won, 0)
        XCTAssertFalse(s.hasRunInProgress)
        s.tap()
        s.perform(.jump)
        XCTAssertEqual(s.phase, .over, "touches do nothing until a new run is asked for")
        XCTAssertEqual(RunnerModule().statusLine(context: s.context), "Best \(result.score) · goal 250")
    }

    func testARunThatReachesItsGoalIsAWinAndTheNextGoalIsHigher() throws {
        let env = TestEnvironment()
        // The app closed on the crash: the run is recorded when it is next opened.
        let s = session(env, ["-scenario", "runnerOver", "-seed", "40"])
        XCTAssertEqual(s.phase, .over)
        XCTAssertTrue(s.showsResult)
        let result = try XCTUnwrap(s.result)
        XCTAssertGreaterThan(result.score, 250)
        XCTAssertTrue(result.reachedGoal)
        XCTAssertEqual(result.headline, "Goal reached!")
        XCTAssertEqual(stats(s).won, 1)
        XCTAssertEqual(stats(s).bestTime ?? 0, s.run.time, accuracy: 0.001)

        XCTAssertEqual(stats(session(env)).played, 1, "opening it again does not count it twice")

        s.startNewRun()
        XCTAssertEqual(s.phase, .ready)
        XCTAssertFalse(s.showsResult)
        XCTAssertNil(s.result)
        XCTAssertEqual(s.goal, Goals.next(after: result.score))
        XCTAssertGreaterThan(s.goal, result.score)
        XCTAssertEqual(s.hud.score, 0)
        XCTAssertEqual(s.run, Run(seed: 41), "an ordinary course: the lessons are for those who have not passed them")
    }

    func testAskingForANewRunMidRunPausesAndEndsItOnlyWhenConfirmed() {
        let env = TestEnvironment()
        let s = session(env, ["-seed", "5"])
        s.requestNewRun()
        XCTAssertFalse(s.confirmingNewRun, "nothing to lose on the start line")
        XCTAssertEqual(s.run, Run(seed: 6, coached: true))
        s.tap()
        s.tap()
        s.requestNewRun()
        XCTAssertTrue(s.confirmingNewRun)
        XCTAssertEqual(s.phase, .paused)
        XCTAssertEqual(stats(s).played, 0)
        s.startNewRun()
        XCTAssertFalse(s.confirmingNewRun)
        XCTAssertEqual(s.phase, .ready)
        XCTAssertEqual(stats(s).played, 1, "the run given up counts as it stood")
        XCTAssertEqual(stats(s).won, 0)
        XCTAssertGreaterThan(s.best, 0)
    }

    func testAForceQuitMidRunComesBackPausedWhereItWasLastSaved() {
        let env = TestEnvironment()
        let s = session(env, ["-seed", "5"], animated: true)
        let start = Date()
        s.tap(at: start)
        s.perform(.left, at: start.addingTimeInterval(0.1))
        var now = start
        for _ in 0..<150 {
            now = now.addingTimeInterval(1.0 / 60)
            s.advance(to: now)
        }
        // No goodbye: the app is gone. What was saved along the way is what comes back.
        let relaunched = session(env, ["-seed", "5"], animated: true)
        XCTAssertEqual(relaunched.phase, .paused)
        XCTAssertTrue(relaunched.hasRunInProgress)
        XCTAssertEqual(relaunched.run.lane, 0)
        XCTAssertGreaterThan(relaunched.run.distance, 0)
        XCTAssertLessThanOrEqual(relaunched.run.distance, s.run.distance)
        XCTAssertEqual(relaunched.goal, s.goal)
    }

    func testTheFirstRunSaysWhatToDo() {
        let env = TestEnvironment()
        let s = session(env, ["-seed", "5"], animated: true)
        var now = Date()
        s.tap(at: now)
        XCTAssertNil(s.prompt)
        while s.prompt == nil, s.phase == .running {
            now = now.addingTimeInterval(1.0 / 60)
            s.advance(to: now)
        }
        XCTAssertEqual(s.prompt, .left, "crates ahead in the middle and right lanes")
        s.perform(.left, at: now)
        s.advance(to: now.addingTimeInterval(0.2))
        XCTAssertNil(s.prompt, "done")
    }

    func testReachingTheGoalMidRunIsMarkedAndTheRunGoesOn() {
        let env = TestEnvironment()
        let almost = RunnerBot.expert.play(Run(seed: 9), to: 120)
        env.context(for: RunnerModule()).saveSlot.save(
            RunnerSave(run: almost, best: 0, goal: almost.score + 10, runsStarted: 1, isUnderWay: true, resultRecorded: false))
        let s = session(env, animated: true)
        XCTAssertEqual(s.phase, .paused)
        XCTAssertFalse(s.goalReached)
        var now = Date()
        s.tap(at: now)
        now = now.addingTimeInterval(RunnerSession.resumeDelay)
        for _ in 0..<90 where s.phase == .running {
            now = now.addingTimeInterval(1.0 / 60)
            s.advance(to: now)
        }
        XCTAssertTrue(s.goalReached)
        XCTAssertEqual(stats(s).played, 0, "nothing is recorded until the run ends")
    }

    func testThePreparedRunsAreWhatTheScreenshotsNeed() {
        let env = TestEnvironment()
        let still = session(env, ["-scenario", "runnerShowcase"])
        XCTAssertEqual(still.phase, .running, "in UI tests: drawn as running, and standing still")
        XCTAssertTrue(still.run.isAirborne)
        XCTAssertGreaterThan(still.run.coinCount, 0)
        XCTAssertEqual(session(TestEnvironment(), ["-scenario", "runnerShowcase"], animated: true).phase, .paused)
    }

    func testWhatVoiceOverHearsAboutThePier() {
        let env = TestEnvironment()
        let s = session(env, ["-scenario", "runnerDeadEnd"])
        XCTAssertEqual(s.spokenStatus, "Ready. Goal 250 points.")
        s.tap()
        s.tap()
        XCTAssertTrue(s.spokenStatus.hasSuffix("lane 2 of 3. Crates ahead: change lane"), s.spokenStatus)
        for _ in 0..<3 { s.tap() }
        XCTAssertTrue(s.spokenStatus.hasPrefix("Run over, "), s.spokenStatus)
    }
}
