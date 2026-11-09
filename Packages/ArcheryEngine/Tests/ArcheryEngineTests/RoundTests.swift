import XCTest
@testable import ArcheryEngine

final class RoundTests: XCTestCase {
    private func level(distance: Double = 18, layout: TargetLayout = .single(.full122), arrows: Int = 3,
                       wind: Wind = .calm, motion: Motion = .still, time: Double? = nil,
                       stars: [Int] = [10, 20, 27]) -> Level {
        Level(number: 99, name: "Test", chapter: .practiceField, distance: distance, layout: layout, arrows: arrows,
              wind: wind, motion: motion, sway: 1, timeLimit: time, starScores: stars, feature: nil, tip: "")
    }

    func testInStillAirArrowsLandWhereTheSightPoints() throws {
        var round = ArcheryRound(level: level())
        let shot = try XCTUnwrap(round.shoot(aim: .zero))
        XCTAssertEqual(shot.hit.label, "X")
        XCTAssertEqual(shot.hit.point, .zero)
        XCTAssertEqual(round.score, 10)
        XCTAssertEqual(round.xCount, 1)
        XCTAssertEqual(round.arrowsLeft, 2)
        round.shoot(aim: Vec2(0, 0.2))
        XCTAssertEqual(round.shots.last?.hit.ring, 7)
    }

    func testTheAttemptEndsAfterTheLastArrowAndAwardsStars() {
        var round = ArcheryRound(level: level(stars: [10, 20, 27]))
        round.shoot(aim: .zero)
        round.shoot(aim: Vec2(0.1, 0))
        XCTAssertEqual(round.status, .playing)
        XCTAssertEqual(round.stars, 1, "stars follow the score as it builds")
        round.shoot(aim: Vec2(0.25, 0))
        XCTAssertEqual(round.status, .finished)
        XCTAssertEqual(round.score, 10 + 9 + 6)
        XCTAssertEqual(round.stars, 2)
        XCTAssertTrue(round.passed)
        XCTAssertEqual(round.arrowsLeft, 0)
        XCTAssertNil(round.shoot(aim: .zero), "no arrows once it is over")
    }

    func testWindCarriesTheArrowAndCanBeAllowedFor() throws {
        var round = ArcheryRound(level: level(distance: 50, wind: Wind(base: 2)))
        let straight = try XCTUnwrap(round.shoot(aim: .zero))
        XCTAssertGreaterThan(straight.hit.point.x, 0.15, "a 2 m/s wind from the left at 50 m")
        XCTAssertEqual(straight.windAtRelease, 2)
        XCTAssertEqual(straight.drift, straight.hit.point.x, accuracy: 1e-9)
        let allowed = try XCTUnwrap(round.shoot(aim: round.aim(toHit: .zero)))
        XCTAssertEqual(allowed.hit.point.x, 0, accuracy: 1e-9)
        XCTAssertEqual(allowed.hit.label, "X")
    }

    func testMovingTargetsMustBeLed() throws {
        let sliding = level(distance: 40, motion: .slide(amplitude: 0.5, period: 4))
        var round = ArcheryRound(level: sliding)
        round.advance(to: 0.1)
        let now = round.targetOffset(at: round.clock)
        let atTarget = try XCTUnwrap(round.shoot(aim: now))
        XCTAssertGreaterThan(atTarget.hit.point.distance(to: .zero), 0.1, "aiming where it is now trails behind")
        XCTAssertEqual(atTarget.targetOffset, round.targetOffset(at: 0.1 + Ballistics.flightTime(distance: 40)))
        let led = try XCTUnwrap(round.shoot(aim: round.aim(toHit: .zero)))
        XCTAssertEqual(led.hit.label, "X")
    }

    func testTheClockStartsAtTheFirstDrawAndRunningOutEndsTheAttempt() {
        var round = ArcheryRound(level: level(arrows: 3, time: 10))
        XCTAssertEqual(round.timeLeft, 10)
        round.advance(by: 30)
        XCTAssertEqual(round.timeLeft, 10, "nothing counts down before the first draw")
        XCTAssertEqual(round.status, .playing)
        round.startTimer()
        round.advance(by: 4)
        XCTAssertEqual(round.timeLeft ?? 0, 6, accuracy: 1e-9)
        round.shoot(aim: .zero)
        round.advance(by: 6.5)
        XCTAssertEqual(round.status, .finished)
        XCTAssertTrue(round.timedOut)
        XCTAssertEqual(round.timeLeft, 0)
        XCTAssertEqual(round.score, 10, "unshot arrows score nothing")
        XCTAssertNil(round.shoot(aim: .zero))
    }

    func testUntimedLevelsHaveNoClock() {
        var round = ArcheryRound(level: level())
        round.startTimer()
        round.advance(by: 500)
        XCTAssertNil(round.timeLeft)
        XCTAssertEqual(round.status, .playing)
    }

    func testThreeSpotsScoreOneArrowEach() {
        var round = ArcheryRound(level: level(layout: .threeSpots(size: 0.6)))
        let spots = round.level.layout.spots
        round.shoot(aim: spots[0].center)
        round.shoot(aim: spots[0].center + Vec2(0.01, 0))
        round.shoot(aim: spots[1].center)
        XCTAssertEqual(round.shots.map(\.hit.label), ["X", "M", "X"])
        XCTAssertTrue(round.shots[1].hit.repeatSpot)
        XCTAssertEqual(round.usedSpots, [0, 1])
    }

    func testEachAttemptMeetsDifferentConditions() {
        let gusty = level(wind: Wind(base: 1, gust: 2, period: 7), motion: .slide(amplitude: 0.4, period: 5))
        let first = ArcheryRound(level: gusty, attempt: 0)
        let second = ArcheryRound(level: gusty, attempt: 1)
        XCTAssertNotEqual(first.windSpeed(at: 2), second.windSpeed(at: 2))
        XCTAssertNotEqual(first.targetOffset(at: 2), second.targetOffset(at: 2))
        XCTAssertNotEqual(first.swaySeed(arrow: 0), second.swaySeed(arrow: 0))
        XCTAssertNotEqual(first.swaySeed(arrow: 0), first.swaySeed(arrow: 1))
        XCTAssertEqual(ArcheryRound(level: gusty, attempt: 1), second, "but the same attempt is always the same")
    }

    func testARoundSurvivesBeingSavedAndLoaded() throws {
        var round = ArcheryRound(level: LevelCatalog.level(23), attempt: 4)
        round.startTimer()
        round.advance(by: 3.2)
        round.shoot(aim: Vec2(0.05, 0.02))
        round.advance(by: 2)
        let data = try JSONEncoder().encode(round)
        let loaded = try JSONDecoder().decode(ArcheryRound.self, from: data)
        XCTAssertEqual(loaded, round)
        XCTAssertEqual(loaded.timeLeft, round.timeLeft)
        XCTAssertEqual(loaded.signature, round.signature)
        XCTAssertTrue(round.signature.hasPrefix("L23|a4|playing|arrows:1/4|score:"), round.signature)
    }

    func testSwayIsTheLevelsAndThePlayersSetting() {
        let round = ArcheryRound(level: LevelCatalog.level(27))
        let full = round.sway(held: 1.2)
        let steadied = round.sway(held: 1.2, strength: 0.25)
        XCTAssertEqual(steadied.x, full.x * 0.25, accuracy: 1e-12)
        XCTAssertGreaterThan(full.length, 0)
    }
}
