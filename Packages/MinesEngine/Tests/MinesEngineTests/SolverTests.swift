import XCTest
@testable import MinesEngine

final class SolverTests: XCTestCase {
    private let single = MinesSolver(reasoning: .single)
    private let pairs = MinesSolver(reasoning: .pairs)

    func testOneNumberAtATime() throws {
        let field = Minefield(mines: cornerPocket)
        let knowledge = MinesSolver.Knowledge(opened: field.flood(from: cell(11, 7)))
        let step = try XCTUnwrap(single.step(field, knowledge))
        XCTAssertEqual(step.rule, .single)
        // (0,3) shows 1 with one covered neighbour; (3,1) shows 1 with one covered neighbour.
        XCTAssertTrue(step.mines.contains(cell(0, 2)))
        XCTAssertTrue(step.mines.contains(cell(2, 0)))
        XCTAssertTrue(step.mines.isSubset(of: field.mines))
        XCTAssertTrue(single.solves(field, firstTap: cell(11, 7)))
    }

    /// Row 0 holds mines in every other square and everything below is open: no number alone
    /// settles anything, but the 1 and 2 in the corner read together put a mine at (0,2).
    func testTwoNumbersTogether() throws {
        let field = Minefield(mines: mines(["M.M.M.M."]))
        let row0 = CellSet((0..<8).map { cell(0, $0) })
        let knowledge = MinesSolver.Knowledge(opened: everythingOpen(except: row0))
        XCTAssertNil(single.step(field, knowledge), "no single number settles a square")
        let step = try XCTUnwrap(pairs.step(field, knowledge))
        XCTAssertEqual(step.rule, .pairs)
        XCTAssertTrue(step.mines.contains(cell(0, 2)))
        XCTAssertTrue(step.mines.isSubset(of: field.mines))
        XCTAssertTrue(step.safe.isDisjoint(with: field.mines))
    }

    /// (0,0) and (0,1) touch exactly the same numbers and share one mine: a true 50/50.
    func testAFiftyFiftyIsReportedNotGuessed() {
        let field = Minefield(mines: CellSet([cell(0, 0), cell(0, 2), cell(1, 2)]))
        let covered = CellSet([cell(0, 0), cell(0, 1), cell(0, 2), cell(1, 2)])
        let knowledge = MinesSolver.Knowledge(opened: everythingOpen(except: covered),
                                              mines: CellSet([cell(0, 2), cell(1, 2)]))
        XCTAssertNil(pairs.step(field, knowledge))
        XCTAssertNil(single.step(field, knowledge))
    }

    func testTheMineCountSettlesASquareNoNumberTouches() throws {
        let walls = CellSet([cell(0, 1), cell(1, 0), cell(1, 1)])
        let covered = walls.union(CellSet([cell(0, 0)]))

        let safeCorner = Minefield(mines: walls)
        let noneLeft = try XCTUnwrap(single.step(safeCorner, .init(opened: everythingOpen(except: covered), mines: walls)))
        XCTAssertEqual(noneLeft.rule, .count)
        XCTAssertEqual(noneLeft.safe, CellSet([cell(0, 0)]))

        let mineCorner = Minefield(mines: covered)
        let oneLeft = try XCTUnwrap(single.step(mineCorner, .init(opened: everythingOpen(except: covered), mines: walls)))
        XCTAssertEqual(oneLeft.rule, .count)
        XCTAssertEqual(oneLeft.mines, CellSet([cell(0, 0)]))
    }

    func testSomeBoardsNeedTwoNumbersTogether() {
        let needingPairs = (1...40 as ClosedRange<UInt64>).filter { seed in
            let tap = cell(0, 0)
            let field = MinesGenerator.generate(seed: seed, difficulty: .medium, firstTap: tap).field
            return !single.solves(field, firstTap: tap)
        }
        XCTAssertGreaterThan(needingPairs.count, 10)
    }

    /// On random layouts, fair or not, every square the solver opens is safe and every square
    /// it marks is a mine.
    func testTheSolverNeverMakesAMistake() {
        var generator = SeededGenerator(seed: 2026)
        for board in 0..<2000 {
            let difficulty = Difficulty.allCases[board % 3]
            let tap = generator.nextInt(below: MinesGrid.cellCount)
            var candidates = Array(MinesGrid.all.subtracting(MinesGrid.zone(around: tap)))
            for k in 0..<difficulty.mineCount {
                candidates.swapAt(k, k + generator.nextInt(below: candidates.count - k))
            }
            let field = Minefield(mines: CellSet(candidates[0..<difficulty.mineCount]))
            for solver in [single, pairs] {
                let result = solver.solve(field, firstTap: tap)
                XCTAssertTrue(result.knowledge.opened.isDisjoint(with: field.mines), "board \(board)")
                XCTAssertTrue(result.knowledge.mines.isSubset(of: field.mines), "board \(board)")
                if result.solved { XCTAssertEqual(result.knowledge.opened, field.safeCells) }
            }
        }
    }
}
