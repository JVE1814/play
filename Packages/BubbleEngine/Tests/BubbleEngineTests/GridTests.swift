import XCTest
@testable import BubbleEngine

final class GridTests: XCTestCase {
    func testCellCentresShiftOddRowsByHalfABubble() {
        XCTAssertEqual(BubbleGrid.center(of: Cell(0, 0)), Point(0.5, 0.5))
        XCTAssertEqual(BubbleGrid.center(of: Cell(1, 0)).x, 1.0)
        XCTAssertEqual(BubbleGrid.center(of: Cell(1, 7)).x, 8.0)
        // Neighbouring centres are exactly one diameter apart.
        for cell in [Cell(0, 3), Cell(1, 3), Cell(4, 0), Cell(5, 7)] {
            for neighbor in BubbleGrid.neighbors(of: cell) {
                XCTAssertEqual(BubbleGrid.center(of: cell).distance(to: BubbleGrid.center(of: neighbor)), 1, accuracy: 1e-9,
                               "\(cell) – \(neighbor)")
            }
        }
    }

    func testNeighboursInEvenAndOddRows() {
        XCTAssertEqual(Set(BubbleGrid.neighbors(of: Cell(2, 3))),
                       [Cell(2, 2), Cell(2, 4), Cell(1, 2), Cell(1, 3), Cell(3, 2), Cell(3, 3)])
        XCTAssertEqual(Set(BubbleGrid.neighbors(of: Cell(3, 3))),
                       [Cell(3, 2), Cell(3, 4), Cell(2, 3), Cell(2, 4), Cell(4, 3), Cell(4, 4)])
        XCTAssertEqual(Set(BubbleGrid.neighbors(of: Cell(0, 0))), [Cell(0, 1), Cell(1, 0)])
        XCTAssertEqual(Set(BubbleGrid.neighbors(of: Cell(1, 7))), [Cell(1, 6), Cell(0, 7), Cell(2, 7)])
    }

    func testRowsInitialiserAndSignatureRoundTrip() {
        let grid = BubbleGrid(rows: ["rygbpcSB", ".r..y...", "..g"])
        XCTAssertEqual(grid.signature, "rygbpcSB/.r..y.../..g.....")
        XCTAssertEqual(grid.count, 11)
        XCTAssertEqual(grid[Cell(0, 6)], .stone)
        XCTAssertEqual(grid[Cell(0, 7)], .bomb)
        XCTAssertEqual(grid.colorsPresent, BubbleColor.allCases)
        XCTAssertEqual(BubbleGrid(rows: grid.signature.split(separator: "/").map(String.init)), grid)
    }

    func testAnchoredCellsHangFromTheCeiling() {
        let grid = BubbleGrid(rows: ["rr......", "r.......", "........", "...gg..."])
        XCTAssertEqual(grid.anchored(), [Cell(0, 0), Cell(0, 1), Cell(1, 0)])
    }

    func testGroupsAreSameColourOnly() {
        // Row 1 is shifted right, so (1, 2) touches (0, 2) and (0, 3) above it.
        let grid = BubbleGrid(rows: ["rrS.r...", ".rr....."])
        XCTAssertEqual(grid.group(at: Cell(0, 0)), [Cell(0, 0), Cell(0, 1), Cell(1, 1), Cell(1, 2)])
        XCTAssertEqual(grid.group(at: Cell(0, 2)), [], "stones never group")
        XCTAssertEqual(grid.group(at: Cell(0, 4)), [Cell(0, 4)])
    }
}
