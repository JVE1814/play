import XCTest
@testable import BubbleEngine

final class ShotTests: XCTestCase {
    let up = Point(0, -1)

    func testStraightUpIntoAnEmptyFieldSticksToTheCeiling() throws {
        let trace = try XCTUnwrap(BubbleGrid().trace(direction: up))
        XCTAssertEqual(trace.cell, Cell(0, 4))
        XCTAssertEqual(trace.path.count, 2)
        XCTAssertEqual(trace.path.last!.y, 0.5, accuracy: 1e-9)
    }

    func testShotStopsAtTheFirstBubbleItTouches() throws {
        let grid = BubbleGrid(rows: ["....r..."])
        let trace = try XCTUnwrap(grid.trace(direction: up))
        XCTAssertEqual(trace.cell, Cell(1, 3))
        let stop = trace.path.last!
        XCTAssertEqual(stop.distance(to: BubbleGrid.center(of: Cell(0, 4))), BubbleGrid.collisionDistance, accuracy: 1e-9)
    }

    func testShotsMustPointUpwards() {
        XCTAssertNil(BubbleGrid().trace(direction: Point(1, 0)))
        XCTAssertNil(BubbleGrid().trace(direction: Point(0, 1)))
        XCTAssertNil(BubbleGrid().trace(direction: Point(0, 0)))
    }

    func testWallBouncesMirrorExactly() throws {
        let grid = BubbleGrid(rows: ["rgbrgbrg", "gbrgbrgb"])
        let left = try XCTUnwrap(grid.trace(direction: Point(-2.5, -1)))
        XCTAssertGreaterThanOrEqual(left.path.count, 3, "bounces off a wall")
        XCTAssertEqual(left.path[1].x, 0.5, accuracy: 1e-9)
        // In an empty field, mirrored shots take mirrored paths.
        let right = try XCTUnwrap(BubbleGrid().trace(direction: Point(2.5, -1)))
        let leftEmpty = try XCTUnwrap(BubbleGrid().trace(direction: Point(-2.5, -1)))
        XCTAssertEqual(right.path.count, leftEmpty.path.count)
        for (a, b) in zip(right.path, leftEmpty.path) {
            XCTAssertEqual(a.x, BubbleGrid.width - b.x, accuracy: 1e-9)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
        }
    }

    func testShotsAlwaysSettleInAnEmptyAttachedCell() {
        var rng = SeededGenerator(seed: 7)
        for _ in 0..<300 {
            var grid = BubbleGrid()
            for r in 0..<(1 + rng.nextInt(below: 8)) {
                for c in 0..<BubbleGrid.columns where rng.chance(0.7) { grid[Cell(r, c)] = .color(rng.pick(BubbleColor.allCases)) }
            }
            let direction = Point(-4 + 8 * rng.nextUnit(), -1)
            guard let trace = grid.trace(direction: direction) else { XCTFail("no trace"); continue }
            XCTAssertNil(grid[trace.cell], "lands in an empty cell")
            XCTAssertTrue(trace.cell.row == 0 || BubbleGrid.neighbors(of: trace.cell).contains { grid[$0] != nil },
                          "lands touching the ceiling or another bubble")
            for point in trace.path {
                XCTAssertGreaterThanOrEqual(point.x, 0.5 - 1e-9)
                XCTAssertLessThanOrEqual(point.x, BubbleGrid.width - 0.5 + 1e-9)
            }
        }
    }

    func testThreeOfAColourPopAndTwoDoNot() {
        var grid = BubbleGrid(rows: ["rr.y....", "........"])
        let pop = grid.resolve(placing: .color(.red), at: Cell(1, 0))
        XCTAssertEqual(pop.popped, [Cell(0, 0), Cell(0, 1), Cell(1, 0)])
        XCTAssertEqual(grid.signature, "...y....")
        var pair = BubbleGrid(rows: ["r..y...."])
        let none = pair.resolve(placing: .color(.red), at: Cell(1, 0))
        XCTAssertEqual(none.clearedCount, 0)
        XCTAssertEqual(pair.count, 3)
    }

    func testBubblesCutLooseFallStonesIncluded() {
        // Popping the reds leaves the stone and the yellow hanging from nothing.
        var grid = BubbleGrid(rows: ["rr......", "S.......", "y......."])
        let result = grid.resolve(placing: .color(.red), at: Cell(0, 2))
        XCTAssertEqual(result.popped, [Cell(0, 0), Cell(0, 1), Cell(0, 2)])
        XCTAssertEqual(Set(result.dropped), [Cell(1, 0), Cell(2, 0)])
        XCTAssertEqual(result.removed[Cell(1, 0)], .stone)
        XCTAssertTrue(grid.isEmpty)
    }

    func testStonesNeverMatch() {
        var grid = BubbleGrid(rows: ["SS......"])
        let result = grid.resolve(placing: .stone, at: Cell(0, 2))
        XCTAssertEqual(result.clearedCount, 0)
    }

    func testBombsClearTheirNeighboursAndSetOffOtherBombs() {
        var grid = BubbleGrid(rows: ["gggB....", "ppB.....", "cc......"])
        // The shot lands next to the bomb at (0,3); its blast reaches the bomb at (1,2), which goes off too.
        let result = grid.resolve(placing: .color(.red), at: Cell(0, 4))
        XCTAssertEqual(Set(result.exploded), [Cell(0, 2), Cell(0, 3), Cell(0, 4), Cell(1, 1), Cell(1, 2)])
        XCTAssertEqual(result.removed[Cell(1, 2)], .bomb)
        XCTAssertEqual(grid.signature, "gg....../p......./cc......")
    }

    func testEveryShotConservesBubbles() {
        for level in stride(from: 1, through: 2000, by: 97) {
            var game = BubbleGame(level: LevelCatalog.level(level))
            var rng = SeededGenerator(seed: UInt64(level))
            while game.status == .playing {
                let before = game.grid.count
                guard let outcome = game.shoot(direction: Point(-4 + 8 * rng.nextUnit(), -1)) else { break }
                XCTAssertEqual(game.grid.count, before + 1 - outcome.result.clearedCount, "level \(level)")
                XCTAssertEqual(outcome.result.removed.count, outcome.result.clearedCount)
            }
            XCTAssertNotEqual(game.status, .playing)
        }
    }
}
