import XCTest
@testable import RunnerEngine

/// The runner's own movement: lanes, jumps and slides.
final class RunnerTests: XCTestCase {
    func testASwipeMovesOneLaneOverAMoment() {
        var run = Run()
        XCTAssertEqual(run.perform(.left), .changedLane)
        XCTAssertEqual(run.lane, 0)
        run.advance(by: Body.laneChangeTime / 2)
        XCTAssertEqual(run.across, 0.5, accuracy: 0.1, "half way across")
        run.advance(by: Body.laneChangeTime)
        XCTAssertEqual(run.across, 0, accuracy: 1e-9)
    }

    func testTheEdgesOfThePierStopTheRunner() {
        var run = Run()
        run.perform(.right)
        XCTAssertEqual(run.perform(.right), .hitEdge)
        XCTAssertEqual(run.lane, Body.lanes - 1)
        run.perform(.left)
        run.perform(.left)
        XCTAssertEqual(run.perform(.left), .hitEdge)
        XCTAssertEqual(run.lane, 0)
    }

    func testAJumpPeaksAndLandsOnTime() {
        var run = Run()
        XCTAssertEqual(run.perform(.jump), .jumped)
        run.advance(by: Body.jumpTime / 2)
        XCTAssertEqual(run.height, Body.jumpSpeed * Body.jumpSpeed / (2 * Body.gravity), accuracy: 0.05)
        XCTAssertTrue(run.isAirborne)
        let events = run.advance(by: Body.jumpTime / 2 + 0.02)
        XCTAssertEqual(events, [.landed])
        XCTAssertEqual(run.height, 0)
        XCTAssertFalse(run.isAirborne)
    }

    func testASlideEndsByItself() {
        var run = Run()
        XCTAssertEqual(run.perform(.slide), .slid)
        run.advance(by: Body.slideTime - 0.05)
        XCTAssertTrue(run.isSliding)
        run.advance(by: 0.1)
        XCTAssertFalse(run.isSliding)
    }

    func testASlideInTheAirDropsTheRunnerIntoASlide() {
        var run = Run()
        run.perform(.jump)
        run.advance(by: 0.15)
        run.perform(.slide)
        XCTAssertTrue(run.isTucked)
        run.advance(by: 0.15)
        XCTAssertFalse(run.isAirborne, "down long before the jump would have ended")
        XCTAssertTrue(run.isSliding)
    }

    func testAJumpAskedForJustBeforeLandingHappensOnLanding() {
        var early = Run()
        early.perform(.jump)
        early.advance(by: Body.jumpTime - 0.3)
        XCTAssertNil(early.perform(.jump))
        early.advance(by: 0.35)
        XCTAssertFalse(early.isAirborne, "too early: forgotten by the time the runner lands")

        var late = Run()
        late.perform(.jump)
        late.advance(by: Body.jumpTime - 0.1)
        XCTAssertNil(late.perform(.jump))
        let events = late.advance(by: 0.15)
        XCTAssertEqual(events, [.landed, .jumped])
        XCTAssertTrue(late.isAirborne)
    }

    func testAJumpCutsASlideShort() {
        var run = Run()
        run.perform(.slide)
        run.advance(by: 0.1)
        run.perform(.jump)
        XCTAssertTrue(run.isAirborne)
        XCTAssertFalse(run.isTucked)
    }

    func testTheFrameRateDoesNotChangeTheRun() {
        var smooth = Run(seed: 9)
        var choppy = Run(seed: 9)
        for frame in 0..<1_200 {
            if frame == 240 {
                smooth.perform(.left)
                choppy.perform(.left)
            }
            smooth.advance(by: 1.0 / 120)
            if frame % 4 == 3 { choppy.advance(by: 1.0 / 30) }
        }
        XCTAssertEqual(smooth.distance, choppy.distance, accuracy: 2 * Pace.speed(at: smooth.distance) * Run.step)
        XCTAssertEqual(smooth.status, choppy.status)
        XCTAssertEqual(smooth.coinCount, choppy.coinCount)
    }

    func testTheRunSpeedsUpButNeverBeyondItsTopSpeed() {
        XCTAssertLessThan(Pace.speed(at: 0), Pace.speed(at: 500))
        XCTAssertLessThan(Pace.speed(at: 500), Pace.speed(at: 3_000))
        XCTAssertLessThan(Pace.speed(at: 1_000_000), 22.5)
        XCTAssertGreaterThan(Pace.rowGap(at: 0), Pace.rowGap(at: 3_000))
        // A jump over one row, begun at the last moment that clears it, is down before the next.
        XCTAssertGreaterThan(Pace.rowGap(at: 1_000_000), Body.jumpTime - 0.1)
    }

    func testGoalsClimbAndAlwaysLieAhead() {
        XCTAssertEqual(Goals.next(after: 0), 250)
        XCTAssertEqual(Goals.next(after: 249), 250)
        XCTAssertEqual(Goals.next(after: 250), 500)
        XCTAssertEqual(Goals.next(after: 10_000), 12_500)
        XCTAssertEqual(Goals.next(after: 12_499), 12_500)
        XCTAssertEqual(Goals.next(after: 12_500), 15_000)
        XCTAssertEqual(Goals.ladder, Goals.ladder.sorted())
    }
}
