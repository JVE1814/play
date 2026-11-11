import Foundation

/// Lays the mines once the first square is tapped.
///
/// The first tap and its eight neighbours never hold a mine, so the first tap always opens
/// an area. The rest is laid at random, and a layout is kept only if `MinesSolver`, at the
/// difficulty's reasoning, clears it from that opening: every board can be won without
/// guessing. The same seed, difficulty and first tap always give the same board.
public enum MinesGenerator {
    /// Random layouts tried before falling back to one that is trivially fair. About one
    /// Hard layout in six is fair when the first tap is in a corner, the hardest case, so
    /// the fallback is never expected to be reached.
    public static let attemptLimit = 400

    public struct Report: Hashable, Sendable {
        /// Layouts tried, the accepted one included.
        public let attempts: Int
        public let usedFallback: Bool
    }

    public static func generate(seed: UInt64, difficulty: Difficulty, firstTap: Int) -> (field: Minefield, report: Report) {
        generate(seed: seed, difficulty: difficulty, firstTap: firstTap, reasoning: difficulty.reasoning)
    }

    /// The same, with the solver at another reasoning. The calibration tool uses it to see
    /// how the difficulties would change.
    public static func generate(seed: UInt64, difficulty: Difficulty, firstTap: Int,
                                reasoning: MinesSolver.Reasoning) -> (field: Minefield, report: Report) {
        precondition(MinesGrid.isValid(firstTap), "square \(firstTap) is off the board")
        var generator = SeededGenerator(seed: mix(seed: seed, difficulty: difficulty, firstTap: firstTap))
        let solver = MinesSolver(reasoning: reasoning)
        var candidates = Array(MinesGrid.all.subtracting(MinesGrid.zone(around: firstTap)))
        let mineCount = difficulty.mineCount

        for attempt in 1...attemptLimit {
            // A partial Fisher–Yates shuffle: the first `mineCount` candidates become the mines.
            for k in 0..<mineCount {
                candidates.swapAt(k, k + generator.nextInt(below: candidates.count - k))
            }
            let field = Minefield(mines: CellSet(candidates[0..<mineCount]))
            if solver.solves(field, firstTap: firstTap) {
                return (field, Report(attempts: attempt, usedFallback: false))
            }
        }
        return (fallback(difficulty: difficulty, firstTap: firstTap), Report(attempts: attemptLimit, usedFallback: true))
    }

    /// A solid block of mines four columns wide in the far corner from the first tap. It
    /// stays at least two rows from the tap, so the tap opens every safe square at once.
    static func fallback(difficulty: Difficulty, firstTap: Int) -> Minefield {
        let height = difficulty.mineCount / 4
        let tapRow = MinesGrid.row(of: firstTap), tapColumn = MinesGrid.column(of: firstTap)
        let rows = tapRow < MinesGrid.rows / 2 ? (MinesGrid.rows - height)..<MinesGrid.rows : 0..<height
        let columns = tapColumn < MinesGrid.columns / 2 ? 4..<8 : 0..<4
        var mines = CellSet()
        for row in rows {
            for column in columns { mines.insert(MinesGrid.index(row: row, column: column)) }
        }
        return Minefield(mines: mines)
    }

    private static func mix(seed: UInt64, difficulty: Difficulty, firstTap: Int) -> UInt64 {
        seed ^ (UInt64(difficulty.rawValue + 1) &* 0xD1B5_4A32_D192_ED03)
            ^ (UInt64(firstTap + 1) &* 0xABC9_8388_FB8F_AC03)
    }
}
