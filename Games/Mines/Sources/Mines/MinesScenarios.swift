import MinesEngine

/// Prepared boards for UI tests and screenshots (`-scenario`). They are used only when there
/// is no save, which in practice means after `-resetState`.
enum Scenarios {
    static func game(_ name: String?) -> MinesGame? {
        switch name {
        case "minesNearWin": return nearWin
        case "minesShowcase": return showcase
        default: return nil
        }
    }

    /// Easy, with the bottom ten rows open and four safe squares left among the mines of the
    /// top two: (0,0) and (0,7) show 3, (1,2) and (1,5) show 5. Every other square up there
    /// is a mine, such as `slipMine`.
    static var nearWin: MinesGame {
        let mines = CellSet([1, 2, 3, 4, 5, 6].map { MinesGrid.index(row: 0, column: $0) }
            + [0, 1, 3, 4, 6, 7].map { MinesGrid.index(row: 1, column: $0) })
        return MinesGame(difficulty: .easy, mines: mines, firstTap: MinesGrid.index(row: 9, column: 3))
    }

    static let nearWinSafe = [(0, 0), (0, 7), (1, 2), (1, 5)].map { MinesGrid.index(row: $0.0, column: $0.1) }
    static let slipMine = MinesGrid.index(row: 0, column: 3)

    /// A Medium board part-way through: the lower half open after two rounds of careful play,
    /// with three mines flagged. `showcaseMine` is a mine next to the opening.
    static var showcase: MinesGame {
        var game = MinesGame(seed: 11, difficulty: .medium)
        game.open(MinesGrid.index(row: 8, column: 3), forgiving: true)
        guard let field = game.field else { return game }
        let solver = MinesSolver(reasoning: .pairs)
        var flags = 0
        for _ in 0..<2 {
            guard let step = solver.step(field, .init(opened: game.opened, mines: game.flagged)) else { break }
            for mine in step.mines where flags < 3 && !game.flagged.contains(mine) {
                game.toggleFlag(mine)
                flags += 1
            }
            for safe in step.safe.prefix(4) where !game.opened.contains(safe) {
                game.open(safe, forgiving: true)
            }
        }
        return game
    }

    static let showcaseMine = MinesGrid.index(row: 4, column: 4)
}
