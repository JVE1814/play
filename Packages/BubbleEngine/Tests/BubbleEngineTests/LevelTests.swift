import XCTest
@testable import BubbleEngine

final class LevelTests: XCTestCase {
    /// Every one of the 2,000 levels is a fair, well-formed board.
    func testEveryLevelIsWellFormed() {
        var signatures = Set<String>()
        for n in 1...LevelCatalog.count {
            let level = LevelCatalog.level(n)
            let grid = level.layout.grid
            XCTAssertGreaterThanOrEqual(grid.count, 12, "level \(n)")
            XCTAssertLessThanOrEqual(grid.lowestRow, 8, "level \(n) leaves room above the line")
            XCTAssertEqual(grid.anchored().count, grid.count, "level \(n) has nothing floating")
            XCTAssertEqual(grid.colorsPresent, level.layout.palette, "level \(n) uses all its colours")
            XCTAssertTrue((3...6).contains(level.layout.palette.count))
            XCTAssertFalse((0..<BubbleGrid.columns).contains { grid[Cell(0, $0)] == .stone }, "level \(n): stone on top")
            XCTAssertLessThanOrEqual(grid.occupied.filter { grid[$0] == .bomb }.count, 3)
            XCTAssertLessThanOrEqual(grid.occupied.filter { grid[$0] == .stone }.count, 6)
            XCTAssertTrue((LevelCatalog.minimumPar(for: n)...LevelCatalog.maximumPar).contains(level.par), "level \(n) par")
            XCTAssertGreaterThanOrEqual(level.shotLimit, level.par + 3)
            signatures.insert(grid.signature)
        }
        XCTAssertEqual(signatures.count, LevelCatalog.count, "every level is different")
    }

    /// A level number builds the same board on every launch. Levels 35 and 1006 are among those
    /// whose generation has to break a tie between colours, which once depended on the launch.
    func testLevelsAreTheSameOnEveryLaunch() {
        XCTAssertEqual(LevelCatalog.layout(1).grid.signature, LevelTests.goldenLevelOne)
        XCTAssertEqual(LevelCatalog.level(35).layout.grid.signature, "..brcc../...bccr./.....crr/...bccc.")
        XCTAssertEqual(LevelCatalog.level(1006).layout.grid.signature,
                       ".rccb.../..rbSg../....cyp./....Sygb/....ySy./..prpg../.ppSg.../Sgy.....")
    }

    static let goldenLevelOne = "pccbccpp/ppcccppp/ppcppppp/ppbbpcpp/bppbbcpp"

    func testDifficultyRises() {
        func average(_ range: ClosedRange<Int>, _ value: (Level) -> Int) -> Double {
            Double(range.map { value(LevelCatalog.level($0)) }.reduce(0, +)) / Double(range.count)
        }
        XCTAssertLessThan(average(1...50) { $0.layout.palette.count }, average(301...350) { $0.layout.palette.count })
        XCTAssertLessThan(average(1...50) { $0.layout.grid.count }, average(301...350) { $0.layout.grid.count })
        XCTAssertLessThan(average(1...50) { $0.par }, average(301...350) { $0.par })
        for n in 1...29 {
            let grid = LevelCatalog.level(n).layout.grid
            XCTAssertFalse(grid.occupied.contains { grid[$0] == .stone }, "no stones before level 30 (level \(n))")
        }
        let patterns = Set((1...200).map { LevelCatalog.level($0).layout.pattern })
        XCTAssertEqual(patterns.count, LevelCatalog.Pattern.allCases.count, "every shape appears early on")
    }

    /// The par table was produced on one machine; check that the bot still clears a spread of
    /// levels within their shot limits here.
    func testTheBotClearsLevelsWithinTheirShotLimits() {
        for n in stride(from: 1, through: LevelCatalog.count, by: 53) {
            let level = LevelCatalog.level(n)
            let shots = Bot.play(level.layout.calibrationGame)
            XCTAssertNotNil(shots, "level \(n)")
            XCTAssertLessThanOrEqual(shots ?? .max, level.shotLimit, "level \(n)")
        }
    }
}
