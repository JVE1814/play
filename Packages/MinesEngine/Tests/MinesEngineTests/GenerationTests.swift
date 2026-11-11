import XCTest
@testable import MinesEngine

final class GenerationTests: XCTestCase {
    /// Every first tap on every difficulty: the tap opens an area, the board holds its mines,
    /// and the difficulty's solver clears it without guessing.
    func testEveryFirstTapOpensAnAreaOnAFairBoard() {
        var mostAttempts = 0
        for difficulty in Difficulty.allCases {
            let solver = MinesSolver(reasoning: difficulty.reasoning)
            for tap in 0..<MinesGrid.cellCount {
                for seed in 1...4 as ClosedRange<UInt64> {
                    let (field, report) = MinesGenerator.generate(seed: seed, difficulty: difficulty, firstTap: tap)
                    XCTAssertEqual(field.mines.count, difficulty.mineCount)
                    XCTAssertTrue(field.mines.isDisjoint(with: MinesGrid.zone(around: tap)))
                    XCTAssertEqual(field.count(around: tap), 0)
                    XCTAssertTrue(solver.solves(field, firstTap: tap), "\(difficulty) tap \(tap) seed \(seed)")
                    XCTAssertFalse(report.usedFallback)
                    mostAttempts = max(mostAttempts, report.attempts)
                }
            }
        }
        XCTAssertLessThan(mostAttempts, 120, "far from the limit of \(MinesGenerator.attemptLimit)")
    }

    func testTheFallbackIsWonByTheFirstTapWherePlayerTaps() {
        for difficulty in Difficulty.allCases {
            for tap in 0..<MinesGrid.cellCount {
                let field = MinesGenerator.fallback(difficulty: difficulty, firstTap: tap)
                XCTAssertEqual(field.mines.count, difficulty.mineCount)
                XCTAssertTrue(field.mines.isDisjoint(with: MinesGrid.zone(around: tap)), "\(difficulty) tap \(tap)")
                XCTAssertEqual(field.flood(from: tap), field.safeCells, "\(difficulty) tap \(tap)")
            }
        }
    }

    func testTheSameSeedAndTapLayTheSameBoard() {
        let board = MinesGenerator.generate(seed: 11, difficulty: .hard, firstTap: 40).field
        XCTAssertEqual(MinesGenerator.generate(seed: 11, difficulty: .hard, firstTap: 40).field, board)
        XCTAssertNotEqual(MinesGenerator.generate(seed: 12, difficulty: .hard, firstTap: 40).field, board)
        XCTAssertNotEqual(MinesGenerator.generate(seed: 11, difficulty: .hard, firstTap: 41).field, board)
        XCTAssertNotEqual(MinesGenerator.generate(seed: 11, difficulty: .medium, firstTap: 40).field.mines.count,
                          board.mines.count)
    }

    /// Boards must not change from one launch or Swift release to the next: a saved fresh
    /// board, or a seeded test, would otherwise get different mines.
    func testBoardsAreTheSameOnEveryLaunch() {
        XCTAssertEqual(Array(MinesGenerator.generate(seed: 1, difficulty: .easy, firstTap: cell(6, 3)).field.mines),
                       [0, 27, 31, 38, 41, 46, 63, 66, 67, 74, 88, 91])
        XCTAssertEqual(Array(MinesGenerator.generate(seed: 42, difficulty: .medium, firstTap: cell(0, 0)).field.mines),
                       [2, 10, 15, 20, 28, 30, 35, 45, 48, 53, 56, 57, 58, 80, 83, 90])
        XCTAssertEqual(Array(MinesGenerator.generate(seed: 2026, difficulty: .hard, firstTap: cell(11, 7)).field.mines),
                       [0, 1, 8, 9, 10, 15, 23, 30, 33, 40, 47, 53, 57, 59, 67, 73, 77, 81, 85, 93])
    }

    func testBoardsAreQuickToMake() {
        let start = Date()
        for seed in 1...300 as ClosedRange<UInt64> {
            _ = MinesGenerator.generate(seed: seed, difficulty: .hard, firstTap: cell(0, 0))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3, "the first tap lays the board on the main thread")
    }
}
