import XCTest
@testable import BubbleEngine

final class LevelTests: XCTestCase {
    func testThereAreTwoThousandCalibratedLevels() {
        XCTAssertEqual(LevelCatalog.count, 2000)
        XCTAssertEqual(LevelPar.par.count, LevelCatalog.count)
        XCTAssertEqual(LevelPar.variant.count, LevelCatalog.count)
    }

    /// Every one of the 2,000 levels is a fair, well-formed board.
    func testEveryLevelIsWellFormed() {
        var signatures = Set<String>()
        for n in 1...LevelCatalog.count {
            let level = LevelCatalog.level(n)
            let grid = level.grid
            XCTAssertGreaterThanOrEqual(grid.count, 12, "level \(n)")
            XCTAssertLessThanOrEqual(grid.lowestRow, 8, "level \(n) leaves room above the line")
            XCTAssertEqual(grid.anchored().count, grid.count, "level \(n) has nothing floating")
            XCTAssertEqual(grid.colorsPresent, level.palette, "level \(n) uses all its colours")
            XCTAssertTrue((3...6).contains(level.palette.count))
            XCTAssertFalse((0..<BubbleGrid.columns).contains { grid[Cell(0, $0)] == .stone }, "level \(n): stone on top")
            XCTAssertLessThanOrEqual(grid.occupied.filter { grid[$0] == .bomb }.count, 3)
            XCTAssertLessThanOrEqual(grid.occupied.filter { grid[$0] == .stone }.count, 6)
            XCTAssertTrue((LevelCatalog.minimumPar(for: n)...LevelCatalog.maximumPar).contains(level.par), "level \(n) par")
            XCTAssertGreaterThanOrEqual(level.shotLimit, level.par + 3)
            signatures.insert(grid.signature)
        }
        XCTAssertEqual(signatures.count, LevelCatalog.count, "every level is different")
    }

    func testLevelsAreDeterministic() {
        for n in [1, 2, 50, 999, 2000] {
            XCTAssertEqual(LevelCatalog.level(n), LevelCatalog.level(n))
        }
        XCTAssertEqual(LevelCatalog.layout(1).grid.signature, LevelTests.goldenLevelOne)
    }

    static let goldenLevelOne = "pccbccpp/ppcccppp/ppcppppp/ppbbpcpp/bppbbcpp"

    func testDifficultyRises() {
        func average(_ range: ClosedRange<Int>, _ value: (Level) -> Int) -> Double {
            Double(range.map { value(LevelCatalog.level($0)) }.reduce(0, +)) / Double(range.count)
        }
        XCTAssertLessThan(average(1...50) { $0.palette.count }, average(301...350) { $0.palette.count })
        XCTAssertLessThan(average(1...50) { $0.grid.count }, average(301...350) { $0.grid.count })
        XCTAssertLessThan(average(1...50) { $0.par }, average(301...350) { $0.par })
        for n in 1...29 {
            let grid = LevelCatalog.level(n).grid
            XCTAssertFalse(grid.occupied.contains { grid[$0] == .stone }, "no stones before level 30 (level \(n))")
        }
        let patterns = Set((1...200).map { LevelCatalog.level($0).pattern })
        XCTAssertEqual(patterns.count, LevelCatalog.Pattern.allCases.count, "every shape appears early on")
    }

    /// The par table was produced on one machine; check that the bot still clears a spread of
    /// levels within their shot limits here.
    func testTheBotClearsLevelsWithinTheirShotLimits() {
        for n in stride(from: 1, through: LevelCatalog.count, by: 53) {
            let level = LevelCatalog.level(n)
            let layout = LevelCatalog.layout(n, variant: level.variant)
            let shots = Bot.play(layout.calibrationGame)
            XCTAssertNotNil(shots, "level \(n)")
            XCTAssertLessThanOrEqual(shots ?? .max, level.shotLimit, "level \(n)")
        }
    }
}
