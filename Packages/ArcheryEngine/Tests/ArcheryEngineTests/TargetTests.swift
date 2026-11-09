import XCTest
@testable import ArcheryEngine

final class TargetTests: XCTestCase {
    let face = Face.full122

    func testRingsAreTenthsOfTheRadius() {
        XCTAssertEqual(face.ringWidth, 0.061, accuracy: 1e-9)
        XCTAssertEqual(face.radius, 0.61, accuracy: 1e-9)
        XCTAssertEqual(face.outerRadius(ofRing: 10), 0.061, accuracy: 1e-9)
        XCTAssertEqual(face.xRadius, 0.0305, accuracy: 1e-9)
        XCTAssertEqual(Face.spot(0.4).radius, 0.10, accuracy: 1e-9, "a spot shows rings 6 to 10")
    }

    func testScoresFromTheMiddleOut() {
        XCTAssertEqual(face.score(distance: 0).ring, 10)
        XCTAssertTrue(face.score(distance: 0).isX)
        XCTAssertEqual(face.score(distance: 0.05).ring, 10)
        XCTAssertFalse(face.score(distance: 0.05).isX)
        XCTAssertEqual(face.score(distance: 0.10).ring, 9)
        XCTAssertEqual(face.score(distance: 0.30).ring, 6)
        XCTAssertEqual(face.score(distance: 0.60).ring, 1)
        XCTAssertEqual(face.score(distance: 0.70).ring, 0)
    }

    func testAnArrowTouchingALineScoresTheHigherRing() {
        // The 9/8 line is 0.122 m out. An arrow centred 2 mm outside it still cuts the line.
        XCTAssertEqual(face.score(distance: 0.124).ring, 9)
        XCTAssertEqual(face.score(distance: 0.122 + Arrow.radius + 0.0005).ring, 8)
    }

    func testRingColoursMatchARealFace() {
        XCTAssertEqual((1...10).map { Face.zone(ofRing: $0) },
                       [.white, .white, .black, .black, .blue, .blue, .red, .red, .gold, .gold])
    }

    func testSpotFacesScoreNothingOutsideTheBlue() {
        let spot = Face.spot(0.4)
        XCTAssertEqual(spot.score(distance: 0.09).ring, 6)
        XCTAssertEqual(spot.score(distance: 0.12).ring, 0)
    }

    func testMissingTheBossFliesPast() {
        let layout = TargetLayout.single(.full80)
        let onBoss = layout.hit(at: Vec2(0.5, 0.5))
        XCTAssertTrue(onBoss.inBoss)
        XCTAssertEqual(onBoss.score, 0)
        XCTAssertEqual(onBoss.label, "M")
        let past = layout.hit(at: Vec2(0.7, 0))
        XCTAssertFalse(past.inBoss)
        XCTAssertNil(past.spot)
    }

    func testThreeSpotsTakeOneArrowEach() {
        let layout = TargetLayout.threeSpots(size: 0.6)
        XCTAssertEqual(layout.spots.count, 3)
        XCTAssertTrue(layout.onePerSpot)
        let top = layout.spots[0].center
        XCTAssertGreaterThan(top.y, 0)
        let first = layout.hit(at: top)
        XCTAssertEqual(first.spot, 0)
        XCTAssertEqual(first.label, "X")
        let again = layout.hit(at: top, used: [0])
        XCTAssertTrue(again.repeatSpot)
        XCTAssertEqual(again.score, 0, "a second arrow in the same spot scores nothing")
        XCTAssertEqual(layout.hit(at: layout.spots[2].center, used: [0]).score, 10)
        // The spots never overlap.
        XCTAssertGreaterThan(layout.spots[0].center.y - layout.spots[1].center.y, layout.spots[0].face.radius * 2)
    }
}
