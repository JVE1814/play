import XCTest
@testable import RunnerEngine

/// What is on the course, and what happens when the runner meets it.
final class CourseTests: XCTestCase {
    /// Runs until the runner is `metres` along (or has crashed), collecting what happened.
    @discardableResult
    private func advance(_ run: inout Run, to metres: Double) -> [Run.Event] {
        var events: [Run.Event] = []
        while run.status == .running, run.distance < metres {
            events += run.advance(by: Run.step)
        }
        return events
    }

    /// Jumps so that the top of the jump comes over `position`.
    private func jump(_ run: inout Run, over position: Double) {
        advance(&run, to: position - run.speed * Body.jumpTime / 2)
        run.perform(.jump)
    }

    func testABarrierIsJumpedOrRunInto() {
        let course = [Obstacle(.barrier, lane: 1, position: 20)]
        var careless = Run(obstacles: course)
        let events = advance(&careless, to: 30)
        XCTAssertEqual(careless.status, .crashed)
        XCTAssertEqual(careless.crashedInto?.kind, .barrier)
        XCTAssertEqual(events.last, .crashed)
        XCTAssertEqual(careless.distance, 20, accuracy: 0.5)
        XCTAssertTrue(careless.advance(by: 1).isEmpty, "a crashed run stands still")
        XCTAssertEqual(careless.distance, 20, accuracy: 0.5)

        var jumper = Run(obstacles: course)
        jump(&jumper, over: 20)
        advance(&jumper, to: 30)
        XCTAssertEqual(jumper.status, .running)

        var slider = Run(obstacles: course)
        advance(&slider, to: 18)
        slider.perform(.slide)
        advance(&slider, to: 30)
        XCTAssertEqual(slider.status, .crashed, "too low to slide under")

        var dodger = Run(obstacles: course)
        dodger.perform(.left)
        advance(&dodger, to: 30)
        XCTAssertEqual(dodger.status, .running)
    }

    func testABeamIsSlidUnder() {
        let course = [Obstacle(.beam, lane: 1, position: 20)]
        var upright = Run(obstacles: course)
        advance(&upright, to: 30)
        XCTAssertEqual(upright.status, .crashed)

        var slider = Run(obstacles: course)
        advance(&slider, to: 18)
        slider.perform(.slide)
        advance(&slider, to: 30)
        XCTAssertEqual(slider.status, .running)

        var jumper = Run(obstacles: course)
        jump(&jumper, over: 20)
        advance(&jumper, to: 30)
        XCTAssertEqual(jumper.status, .crashed, "a jump goes straight into it")
    }

    func testAStackHasToBeGoneRound() {
        let course = [Obstacle(.stack, lane: 1, position: 20)]
        var jumper = Run(obstacles: course)
        jump(&jumper, over: 20.7)
        advance(&jumper, to: 30)
        XCTAssertEqual(jumper.status, .crashed)

        var slider = Run(obstacles: course)
        advance(&slider, to: 18)
        slider.perform(.slide)
        advance(&slider, to: 30)
        XCTAssertEqual(slider.status, .crashed)

        var dodger = Run(obstacles: course)
        dodger.perform(.right)
        advance(&dodger, to: 30)
        XCTAssertEqual(dodger.status, .running)
    }

    func testSwervingIntoTheSideOfALongStackCrashes() {
        var run = Run(obstacles: [Obstacle(.stack, lane: 0, position: 20, length: 15)])
        advance(&run, to: 26)
        XCTAssertEqual(run.status, .running, "alongside it")
        run.perform(.left)
        advance(&run, to: 30)
        XCTAssertEqual(run.status, .crashed)
    }

    func testAChangeOfLaneLeftTooLateStillHits() {
        var run = Run(obstacles: [Obstacle(.stack, lane: 1, position: 20)])
        advance(&run, to: 19.9)
        run.perform(.left)
        advance(&run, to: 30)
        XCTAssertEqual(run.status, .crashed)
    }

    func testABarrelRollsInAndMeetsTheRunnerWhereItShould() {
        let meetTime = Pace.time(toReach: 40, from: 0, at: 0)
        let barrel = Obstacle(.barrel, lane: 1, position: 40, rollSpeed: 5, meetTime: meetTime)
        XCTAssertEqual(barrel.nearSide(at: meetTime - 2), 50, accuracy: 1e-9)
        XCTAssertFalse(barrel.isOnCourse(at: meetTime - Obstacle.barrelNotice - 0.1))
        XCTAssertTrue(barrel.isOnCourse(at: meetTime - Obstacle.barrelNotice + 0.1))

        var careless = Run(obstacles: [barrel])
        advance(&careless, to: 60)
        XCTAssertEqual(careless.status, .crashed)
        XCTAssertEqual(careless.distance, 40, accuracy: 0.5)

        var jumper = Run(obstacles: [barrel])
        // It closes faster than something standing still, so the jump starts nearer to it.
        while jumper.time < meetTime - Body.jumpTime / 2 { jumper.advance(by: Run.step) }
        jumper.perform(.jump)
        advance(&jumper, to: 60)
        XCTAssertEqual(jumper.status, .running)
    }

    func testTheObstacleAheadIsTheNearestInTheRunnersLane() {
        var run = Run(obstacles: [Obstacle(.beam, lane: 0, position: 15), Obstacle(.barrier, lane: 1, position: 25),
                                  Obstacle(.stack, lane: 1, position: 40)])
        XCTAssertEqual(run.obstacleAhead?.kind, .barrier)
        XCTAssertEqual(run.seconds(to: run.obstacleAhead!), 25 / run.speed, accuracy: 0.01)
        run.perform(.left)
        XCTAssertEqual(run.obstacleAhead?.kind, .beam)
    }

    // MARK: Coins and power-ups

    func testCoinsInTheRunnersLaneAreCollectedAndCountInTheScore() {
        var run = Run(coins: [Coin(lane: 1, position: 10, height: Coin.usualHeight), Coin(lane: 1, position: 12, height: Coin.usualHeight),
                              Coin(lane: 0, position: 14, height: Coin.usualHeight)])
        let events = advance(&run, to: 20)
        XCTAssertEqual(events.filter { $0 == .coin }.count, 2)
        XCTAssertEqual(run.coinCount, 2)
        XCTAssertEqual(run.score, Int(run.distance) + 2 * Run.coinValue)
    }

    func testHighCoinsNeedAJump() {
        let course = [Coin(lane: 1, position: 20, height: 2.1)]
        var runner = Run(coins: course)
        advance(&runner, to: 25)
        XCTAssertEqual(runner.coinCount, 0)

        var jumper = Run(coins: course)
        jump(&jumper, over: 20)
        advance(&jumper, to: 25)
        XCTAssertEqual(jumper.coinCount, 1)
    }

    func testTheMagnetPullsInEveryLaneForAWhile() {
        let near = (0..<5).map { Coin(lane: 2 * ($0 % 2), position: 20 + Double($0) * 3, height: 2.4) }
        let far = Coin(lane: 0, position: 400, height: Coin.usualHeight)
        var run = Run(coins: near + [far], pickups: [Pickup(kind: .magnet, lane: 1, position: 10)])
        let events = advance(&run, to: 15)
        XCTAssertTrue(events.contains(.pickup(.magnet)))
        XCTAssertTrue(run.hasMagnet)
        advance(&run, to: 40)
        XCTAssertEqual(run.coinCount, 5, "coins in the outer lanes, out of reach of a jump")
        advance(&run, to: 410)
        XCTAssertFalse(run.hasMagnet, "\(Run.magnetTime) seconds are long over")
        XCTAssertEqual(run.coinCount, 5)
    }

    func testTheShieldTakesOneHit() {
        var run = Run(obstacles: [Obstacle(.barrier, lane: 1, position: 20), Obstacle(.stack, lane: 1, position: 24),
                                  Obstacle(.barrier, lane: 1, position: 80)],
                      pickups: [Pickup(kind: .shield, lane: 1, position: 10)])
        advance(&run, to: 15)
        XCTAssertTrue(run.hasShield)
        let events = advance(&run, to: 30)
        XCTAssertEqual(events.filter { $0 == .shieldBroke }.count, 1)
        XCTAssertFalse(run.hasShield)
        XCTAssertEqual(run.status, .running, "the stack just behind the barrier is passed while still shaken")
        XCTAssertFalse(run.obstacles.contains { $0.position == 20 }, "what the shield hit is gone")
        advance(&run, to: 90)
        XCTAssertEqual(run.status, .crashed, "the next hit counts")
    }

    // MARK: The laid course

    /// The rows of the first `metres` of a course.
    private func rows(seed: UInt64, coached: Bool = false, to metres: Double) -> [(position: Double, row: Row)] {
        var builder = CourseBuilder(seed: seed, coached: coached)
        var rows: [(Double, Row)] = []
        while builder.nextRow < metres {
            let position = builder.nextRow
            rows.append((position, builder.layRow(runnerAt: max(0, position - Run.sight), time: 0)))
        }
        return rows
    }

    func testTheSameSeedLaysTheSameCourse() {
        XCTAssertEqual(Run(seed: 5), Run(seed: 5))
        XCTAssertNotEqual(Run(seed: 5).obstacles, Run(seed: 6).obstacles)
    }

    func testNoRowWallsThePierIn() {
        for seed in 1...40 as ClosedRange<UInt64> {
            var stacks: [Obstacle] = []
            for (position, row) in rows(seed: seed, to: 5_000) {
                stacks += row.obstacles.filter { $0.kind == .stack }
                let walled = Set(stacks.filter { $0.position <= position && $0.position + $0.length >= position }.map(\.lane))
                XCTAssertLessThan(walled.count, Body.lanes, "seed \(seed) at \(Int(position)) m")
            }
        }
    }

    func testALongStackDownTheMiddleLeavesBothSidesRunnable() {
        var splits = 0
        for seed in 1...40 as ClosedRange<UInt64> {
            let laid = rows(seed: seed, to: 5_000)
            let all = laid.flatMap(\.row.obstacles)
            for stack in all where stack.kind == .stack && stack.lane == 1 && stack.length > 5 {
                splits += 1
                // A stack in the row where it begins can still be gone round on the way in.
                let alongside = stack.position...(stack.position + stack.length + CourseBuilder.crossingRoom)
                let walls = all.filter { $0.kind == .stack && $0.lane != 1 && $0.position > stack.position && alongside.contains($0.position) }
                XCTAssertTrue(walls.isEmpty, "seed \(seed): a dead end beside the stack at \(Int(stack.position)) m")
            }
        }
        XCTAssertGreaterThan(splits, 20, "such stacks do occur")
    }

    func testNobodyHasToSwerveInRightBehindALongStack() {
        for seed in 1...40 as ClosedRange<UInt64> {
            let laid = rows(seed: seed, to: 5_000)
            let stacks = laid.flatMap(\.row.obstacles).filter { $0.kind == .stack }
            for long in stacks where long.length > 5 {
                let end = long.position + long.length
                // Until there has been room to move over, some other lane must be runnable.
                for (position, _) in laid where position > long.position && position <= end + CourseBuilder.crossingRoom {
                    let walled = Set(stacks.filter { $0.position <= position && $0.position + $0.length >= position }.map(\.lane))
                    XCTAssertFalse(walled.union([long.lane]).count == Body.lanes, "seed \(seed) at \(Int(position)) m")
                }
            }
        }
    }

    func testNothingToPickUpLiesInsideALongStack() {
        for seed in 1...40 as ClosedRange<UInt64> {
            let laid = rows(seed: seed, to: 5_000)
            let long = laid.flatMap(\.row.obstacles).filter { $0.kind == .stack && $0.length > 5 }
            func buried(_ lane: Int, _ position: Double) -> Bool {
                long.contains { $0.lane == lane && position > $0.position - 0.5 && position < $0.position + $0.length + 0.5 }
            }
            XCTAssertFalse(laid.flatMap(\.row.coins).contains { buried($0.lane, $0.position) }, "seed \(seed): a coin")
            XCTAssertFalse(laid.flatMap(\.row.pickups).contains { buried($0.lane, $0.position) }, "seed \(seed): a power-up")
        }
    }

    func testTheCourseGetsHarderWithDistance() {
        var early = 0, late = 0
        for seed in 1...20 as ClosedRange<UInt64> {
            for (position, row) in rows(seed: seed, to: 4_000) {
                XCTAssertGreaterThanOrEqual(position, CourseBuilder.firstRow)
                for obstacle in row.obstacles {
                    if obstacle.kind == .barrel { XCTAssertGreaterThan(position, 500, "barrels come later") }
                    if obstacle.length > 5 { XCTAssertGreaterThan(position, 250, "long stacks come later") }
                }
                if position < 400 { early += row.obstacles.count } else if position > 3_000 { late += row.obstacles.count }
            }
        }
        // Rows are about as far apart everywhere, so obstacles per metre compare directly.
        XCTAssertGreaterThan(Double(late) / 1_000, 1.15 * Double(early) / 370)
    }

    func testNothingStandsWhereABarrelRollsIn() {
        for seed in 1...20 as ClosedRange<UInt64> {
            let all = rows(seed: seed, to: 4_000).flatMap(\.row.obstacles)
            for barrel in all where barrel.kind == .barrel {
                let runIn = barrel.position...(barrel.position + barrel.rollSpeed * Obstacle.barrelNotice)
                let inTheWay = all.filter { $0.lane == barrel.lane && $0.position > barrel.position && runIn.contains($0.position) }
                XCTAssertTrue(inTheWay.isEmpty, "seed \(seed), barrel at \(Int(barrel.position)) m")
            }
        }
    }

    func testCoinsAndPowerUpsAreLaidAlongTheWay() {
        let laid = rows(seed: 3, to: 2_000)
        let coins = laid.flatMap(\.row.coins)
        let pickups = laid.flatMap(\.row.pickups)
        XCTAssertGreaterThan(coins.count, 300)
        XCTAssertTrue(coins.contains { $0.height > 1.5 }, "arcs over what has to be jumped")
        XCTAssertTrue(coins.contains { $0.height < 0.6 }, "low coins under beams")
        XCTAssertTrue((3...8).contains(pickups.count), "\(pickups.count) power-ups in two kilometres")
        XCTAssertTrue(zip(pickups, pickups.dropFirst()).allSatisfy { $0.kind != $1.kind }, "the magnet and the shield take turns")
    }

    func testTheCoachedOpeningTeachesEachMoveInTurn() {
        let opening = rows(seed: 1, coached: true, to: 80).prefix(3).map { $0.row.obstacles.map(\.kind) }
        XCTAssertEqual(opening, [[.stack, .stack], [.barrier, .barrier, .barrier], [.beam, .beam, .beam]])

        // Doing as told gets through the opening, whether at once or after a moment's thought.
        for reaction in [0, 0.15, 0.3] {
            var run = Run(seed: 1, coached: true)
            var prompts: [Move] = []
            var due: (move: Move, at: Double)?
            while run.status == .running, run.distance < 80 {
                if let prompt = run.prompt, prompts.last != prompt {
                    prompts.append(prompt)
                    due = (prompt, run.time + reaction)
                }
                if let move = due, run.time >= move.at {
                    run.perform(move.move)
                    due = nil
                }
                run.advance(by: Run.step)
            }
            XCTAssertEqual(prompts, [.left, .jump, .slide], "reacting after \(reaction) s")
            XCTAssertEqual(run.status, .running, "reacting after \(reaction) s")
        }
        XCTAssertNil(Run(seed: 1).prompt)
    }

    func testARunSavedAndLoadedCarriesOnExactly() throws {
        var run = RunnerBot.expert.play(Run(seed: 12), to: 700)
        XCTAssertEqual(run.status, .running)
        var loaded = try JSONDecoder().decode(Run.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(loaded, run)
        run = RunnerBot.expert.play(run, to: 1_200)
        loaded = RunnerBot.expert.play(loaded, to: 1_200)
        XCTAssertEqual(loaded, run, "the course still to come is part of the save")
    }
}
