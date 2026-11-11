import XCTest
@testable import ArcheryEngine

final class BallisticsTests: XCTestCase {
    func testStillAirMeansNoDrift() {
        XCTAssertEqual(Ballistics.drift(distance: 70, wind: .calm, release: 3), 0)
    }

    func testWindPushesArrowsDownwind() {
        XCTAssertGreaterThan(Ballistics.drift(distance: 30, wind: Wind(base: 2), release: 0), 0, "from the left: drifts right")
        XCTAssertLessThan(Ballistics.drift(distance: 30, wind: Wind(base: -2), release: 0), 0)
    }

    func testDriftGrowsWithDistanceAndWindSpeed() {
        XCTAssertEqual(Ballistics.driftPerWind(distance: 18), 0.064, accuracy: 0.005, "about 7 cm per m/s at 18 m")
        XCTAssertEqual(Ballistics.driftPerWind(distance: 90), 0.264, accuracy: 0.01, "about 26 cm per m/s at 90 m")
        let steady = Wind(base: 1.5)
        XCTAssertEqual(Ballistics.drift(distance: 50, wind: steady, release: 0),
                       Ballistics.expectedDrift(distance: 50, windSpeed: 1.5), accuracy: 1e-9)
        XCTAssertEqual(Ballistics.drift(distance: 50, wind: Wind(base: 3), release: 0),
                       2 * Ballistics.drift(distance: 50, wind: steady, release: 0), accuracy: 1e-9)
    }

    func testTheWindIsFollowedThroughTheFlight() {
        let gusty = Wind(base: 1, gust: 3, period: 4, phase: 0.3)
        for release in stride(from: 0.0, to: 8, by: 0.5) {
            let drift = Ballistics.drift(distance: 90, wind: gusty, release: release)
            XCTAssertLessThanOrEqual(abs(drift), Ballistics.driftPerWind(distance: 90) * gusty.strongest + 1e-9)
        }
        // On a gusty day the wind at the moment of release is only a guide.
        let changed = stride(from: 0.0, to: 8, by: 0.5).filter { release in
            let drift = Ballistics.drift(distance: 90, wind: gusty, release: release)
            let guess = Ballistics.expectedDrift(distance: 90, windSpeed: gusty.speed(at: release))
            return abs(drift - guess) > 0.05
        }
        XCTAssertFalse(changed.isEmpty)
    }

    /// Wind early in the flight counts for more: an arrow shot into a dying wind drifts further
    /// than the flight's average wind would carry it, and one shot into a rising wind less far.
    func testEarlyWindCountsForMore() {
        let wind = Wind(base: 0, gust: 2, period: 40)
        let flight = Ballistics.flightTime(distance: 90)
        var dying = 0, rising = 0
        for release in stride(from: 0.0, to: 40, by: 0.5) {
            let speeds = (0...16).map { wind.speed(at: release + flight * Double($0) / 16) }
            guard speeds.allSatisfy({ $0 > 0 }) else { continue }
            let average = Ballistics.driftPerWind(distance: 90) * speeds.reduce(0, +) / Double(speeds.count)
            let drift = Ballistics.drift(distance: 90, wind: wind, release: release)
            if zip(speeds, speeds.dropFirst()).allSatisfy({ $0 > $1 }) {
                XCTAssertGreaterThan(drift, average, "dying wind, released at \(release)")
                dying += 1
            } else if zip(speeds, speeds.dropFirst()).allSatisfy({ $0 < $1 }) {
                XCTAssertLessThan(drift, average, "rising wind, released at \(release)")
                rising += 1
            }
        }
        XCTAssertGreaterThan(dying, 0)
        XCTAssertGreaterThan(rising, 0)
    }

    func testTheFlightStartsAtTheBowAndEndsInTheTarget() {
        let path = FlightPath(distance: 50, impact: Vec2(0.1, -0.05), targetOffset: Vec2(0.2, 0), drift: 0.08)
        let start = path.position(at: 0)
        XCTAssertGreaterThan(start.x, 0, "right-handed: the arrow leaves just right of the eye")
        let end = path.position(at: 1)
        XCTAssertEqual(end.x, 0.3, accuracy: 1e-9)
        XCTAssertEqual(end.y, Ballistics.bossHeight - 0.05, accuracy: 1e-9)
        XCTAssertEqual(end.z, 50, accuracy: 1e-9)
        let middle = path.position(at: 0.5)
        XCTAssertGreaterThan(middle.y, (start.y + end.y) / 2, "the arrow arcs above the straight line")
        XCTAssertGreaterThan(path.heading(at: 0.5).z, 0)
        let left = FlightPath(distance: 50, impact: .zero, targetOffset: .zero, drift: 0, mirrored: true)
        XCTAssertLessThan(left.position(at: 0).x, 0)
    }

    func testFarTargetsLookSmallerButNotTiny() {
        XCTAssertEqual(Optics.faceShare(distance: 10), 0.5)
        XCTAssertEqual(Optics.faceShare(distance: 18), 0.5)
        let shares = stride(from: 18.0, through: 90, by: 6).map { Optics.faceShare(distance: $0) }
        XCTAssertTrue(zip(shares, shares.dropFirst()).allSatisfy { $0 > $1 }, "smaller with every step back")
        XCTAssertEqual(Optics.faceShare(distance: 90), 0.25, accuracy: 0.01, "still a quarter of the view at 90 m")
        XCTAssertEqual(Optics.pointsPerMetre(distance: 18, viewWidth: 400) * 1.22, 200, accuracy: 1e-9,
                       "the 122 cm face is half of a 400-point view at 18 m")
    }
}
