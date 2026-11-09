import XCTest
@testable import ArcheryEngine

final class ConditionsTests: XCTestCase {
    func testSteadyWindNeverChanges() {
        let wind = Wind(base: 1.5)
        XCTAssertEqual(wind.speed(at: 0), 1.5)
        XCTAssertEqual(wind.speed(at: 123.4), 1.5)
        XCTAssertTrue(Wind.calm.isCalm)
    }

    func testGustsStayWithinTheirRangeAndRepeat() {
        let wind = Wind(base: 2, gust: 1.5, period: 8, phase: 0.4)
        var lowest = Double.infinity, highest = -Double.infinity
        for i in 0..<2000 {
            let speed = wind.speed(at: Double(i) * 0.05)
            lowest = min(lowest, speed)
            highest = max(highest, speed)
        }
        XCTAssertGreaterThanOrEqual(lowest, 0.5 - 1e-9)
        XCTAssertLessThanOrEqual(highest, 3.5 + 1e-9)
        XCTAssertGreaterThan(highest - lowest, 2, "the gusts really do come and go")
        XCTAssertEqual(wind.strongest, 3.5)
    }

    func testTravelIsTheWindAddedUpOverTime() {
        let wind = Wind(base: 1.2, gust: 1.8, period: 6, phase: 0.7)
        var numeric = 0.0
        let dt = 0.001
        for i in 0..<10_000 { numeric += wind.speed(at: (Double(i) + 0.5) * dt) * dt }
        XCTAssertEqual(wind.travel(at: 10) - wind.travel(at: 0), numeric, accuracy: 1e-6)
        XCTAssertEqual(Wind(base: -2).travel(at: 3), -6)
    }

    func testWindIsDescribedByWhereItComesFrom() {
        XCTAssertEqual(Wind.describe(2.44), "2.4 m/s from the left")
        XCTAssertEqual(Wind.describe(-0.96), "1.0 m/s from the right")
        XCTAssertEqual(Wind.describe(0.02), "Calm")
    }

    func testSlidingTargetsStayOnTheirRail() {
        let motion = Motion.slide(amplitude: 0.5, period: 4)
        for i in 0..<200 {
            let offset = motion.offset(at: Double(i) * 0.1)
            XCTAssertLessThanOrEqual(abs(offset.x), 0.5 + 1e-9)
            XCTAssertEqual(offset.y, 0)
        }
        XCTAssertEqual(motion.offset(at: 1).x, 0.5, accuracy: 1e-9, "a quarter period in, it is at the end")
        XCTAssertEqual(Motion.still.offset(at: 5), .zero)
        XCTAssertFalse(Motion.still.isMoving)
    }

    func testSwingingTargetsRiseAtTheEndsOfTheSwing() {
        let motion = Motion.swing(length: 1.5, angle: 0.3, period: 4)
        let middle = motion.offset(at: 0)
        let end = motion.offset(at: 1)
        XCTAssertEqual(middle, Vec2(0, 0))
        XCTAssertEqual(end.x, 1.5 * sin(0.3), accuracy: 1e-9)
        XCTAssertEqual(end.y, 1.5 * (1 - cos(0.3)), accuracy: 1e-9, "the bottom of the arc is the rest position")
        // Two parallel ropes from fixed pivots keep their length all the way through the swing.
        for i in 0...20 {
            let offset = motion.offset(at: Double(i) * 0.2)
            let rope = Vec2(offset.x, 1.5 - offset.y).length
            XCTAssertEqual(rope, 1.5, accuracy: 1e-9)
        }
    }

    func testSwayIsZeroWhileDrawingAndEasesIn() {
        XCTAssertEqual(Sway.offset(held: -0.1, seed: 1, strength: 1, distance: 50), .zero)
        XCTAssertEqual(Sway.offset(held: 0, seed: 1, strength: 1, distance: 50), .zero)
        let early = Sway.offset(held: 0.02, seed: 1, strength: 1, distance: 50).length
        XCTAssertLessThan(early, 0.002, "no jump at full draw")
        XCTAssertEqual(Sway.offset(held: 1, seed: 1, strength: 0, distance: 50), .zero)
    }

    func testTheSightIsSteadiestBeforeTheArmsTire() {
        XCTAssertGreaterThan(Sway.amplitude(held: 0.1), Sway.amplitude(held: 1.5), "settling")
        XCTAssertLessThan(Sway.amplitude(held: 2.5), 1.05)
        XCTAssertGreaterThan(Sway.amplitude(held: 6), 2, "tiring")
        func average(_ range: ClosedRange<Double>) -> Double {
            var total = 0.0
            var count = 0
            for seed in 0..<40 {
                for i in 0...20 {
                    let held = range.lowerBound + (range.upperBound - range.lowerBound) * Double(i) / 20
                    total += Sway.offset(held: held, seed: UInt64(seed), strength: 1, distance: 50).length
                    count += 1
                }
            }
            return total / Double(count)
        }
        XCTAssertLessThan(average(1...3) * 2, average(6...8))
    }

    func testSwayGrowsWithDistanceAndDiffersPerArrow() {
        let near = Sway.offset(held: 1.3, seed: 9, strength: 1, distance: 18)
        let far = Sway.offset(held: 1.3, seed: 9, strength: 1, distance: 90)
        XCTAssertEqual(far.x, near.x * 5, accuracy: 1e-9)
        XCTAssertNotEqual(Sway.offset(held: 1.3, seed: 10, strength: 1, distance: 18), near)
        XCTAssertEqual(Sway.offset(held: 1.3, seed: 9, strength: 1, distance: 18), near, "deterministic")
    }
}
