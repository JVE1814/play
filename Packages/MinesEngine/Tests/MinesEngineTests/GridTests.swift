import XCTest
@testable import MinesEngine

final class GridTests: XCTestCase {
    func testCornersEdgesAndTheMiddleHaveTheirNeighbours() {
        XCTAssertEqual(MinesGrid.neighbours(of: cell(0, 0)), CellSet([cell(0, 1), cell(1, 0), cell(1, 1)]))
        XCTAssertEqual(MinesGrid.neighbours(of: cell(11, 7)).count, 3)
        XCTAssertEqual(MinesGrid.neighbours(of: cell(0, 4)).count, 5)
        XCTAssertEqual(MinesGrid.neighbours(of: cell(6, 0)).count, 5)
        XCTAssertEqual(MinesGrid.neighbours(of: cell(6, 4)).count, 8)
        XCTAssertFalse(MinesGrid.neighbours(of: cell(6, 4)).contains(cell(6, 4)))
        XCTAssertEqual(MinesGrid.zone(around: cell(6, 4)).count, 9)
        for square in 0..<MinesGrid.cellCount {
            XCTAssertEqual(MinesGrid.index(row: MinesGrid.row(of: square), column: MinesGrid.column(of: square)), square)
            for neighbour in MinesGrid.neighbours(of: square) {
                XCTAssertTrue(MinesGrid.neighbours(of: neighbour).contains(square))
            }
        }
    }

    func testCellSetsCombineAndIterateInOrder() {
        let a = CellSet([3, 70, 1, 95])
        let b = CellSet([1, 64, 95])
        XCTAssertEqual(Array(a), [1, 3, 70, 95])
        XCTAssertEqual(a.count, 4)
        XCTAssertEqual(a.union(b), CellSet([1, 3, 64, 70, 95]))
        XCTAssertEqual(a.intersection(b), CellSet([1, 95]))
        XCTAssertEqual(a.subtracting(b), CellSet([3, 70]))
        XCTAssertTrue(CellSet([1, 95]).isSubset(of: a))
        XCTAssertTrue(CellSet([2, 63]).isDisjoint(with: a))
        XCTAssertFalse(a.contains(96))
        XCTAssertFalse(a.contains(-1))
        var c = a
        c.remove(70)
        c.remove(200)
        XCTAssertEqual(c, CellSet([1, 3, 95]))
        XCTAssertEqual(MinesGrid.all.count, 96)
        XCTAssertTrue(CellSet().isEmpty)
    }

    func testCellSetsSaveAsAListAndRejectBadOnes() throws {
        let set = CellSet([90, 2, 64])
        let data = try JSONEncoder().encode(set)
        XCTAssertEqual(String(data: data, encoding: .utf8), "[2,64,90]")
        XCTAssertEqual(try JSONDecoder().decode(CellSet.self, from: data), set)
        for bad in ["[96]", "[-1]", "[3,3]"] {
            XCTAssertThrowsError(try JSONDecoder().decode(CellSet.self, from: Data(bad.utf8)), bad)
        }
    }

    func testSplitMixMatchesReferenceSequence() {
        var generator = SeededGenerator(seed: 0)
        XCTAssertEqual(generator.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(generator.next(), 0x6E78_9E6A_A1B9_65F4)
        XCTAssertEqual(generator.next(), 0x06C4_5D18_8009_454F)
    }

    func testMinefieldCountsAndFloods() {
        let field = Minefield(mines: cornerPocket)
        XCTAssertEqual(field.count(around: cell(0, 0)), 1)
        XCTAssertEqual(field.count(around: cell(0, 1)), 2)
        XCTAssertEqual(field.count(around: cell(1, 0)), 2)
        XCTAssertEqual(field.count(around: cell(1, 2)), 2)
        XCTAssertEqual(field.count(around: cell(11, 7)), 0)
        XCTAssertEqual(field.flood(from: cell(0, 0)), CellSet([cell(0, 0)]))
        XCTAssertEqual(field.flood(from: cell(11, 7)), field.safeCells.subtracting(pocket))
        XCTAssertEqual(field.safeCells.count, 93)
    }
}
