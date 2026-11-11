import Foundation

extension MinesGame {
    /// What is wrong with a board that came from a save file, or nothing. A board with
    /// problems should be replaced by a fresh one rather than played.
    ///
    /// The check is structural: it does not lay the board again, so a saved board stays
    /// playable even if the generator changes.
    public var integrityProblems: [String] {
        guard let field else {
            var problems: [String] = []
            if status != .fresh { problems.append("a board with no mines is \(status.rawValue)") }
            if firstTap != nil || !opened.isEmpty || !flagged.isEmpty || exploded != nil || slipUsed {
                problems.append("a board with no mines has moves")
            }
            return problems
        }
        var problems: [String] = []
        if status == .fresh { problems.append("a board with mines laid is still fresh") }
        if field.mines.count != difficulty.mineCount {
            problems.append("\(field.mines.count) mines on a \(difficulty.key) board")
        }
        if let firstTap {
            if !field.mines.isDisjoint(with: MinesGrid.zone(around: firstTap)) {
                problems.append("a mine next to the first tap")
            } else if !field.flood(from: firstTap).isSubset(of: opened) {
                problems.append("the first tap's opening is not open")
            }
        } else {
            problems.append("mines laid without a first tap")
        }
        if !opened.isDisjoint(with: field.mines) { problems.append("an open mine") }
        if !flagged.isDisjoint(with: opened) { problems.append("a flag on an open square") }
        for cell in opened where field.count(around: cell) == 0 && !MinesGrid.neighbours(of: cell).isSubset(of: opened) {
            problems.append("an open square with no mines around it has a covered neighbour")
            break
        }

        let cleared = opened == field.safeCells
        switch status {
        case .fresh:
            break
        case .playing:
            if cleared { problems.append("every safe square is open but the board is still playing") }
        case .won:
            if !cleared { problems.append("won with safe squares still covered") }
        case .slipped:
            if cleared { problems.append("every safe square is open but the board is slipped") }
            if slipUsed { problems.append("slipped a second time") }
        case .lost:
            if cleared { problems.append("lost with every safe square open") }
        }
        let needsExploded = status == .slipped || status == .lost
        if let exploded {
            if !needsExploded { problems.append("an opened mine on a board that is \(status.rawValue)") }
            if !field.isMine(exploded) { problems.append("the opened mine is a safe square") }
        } else if needsExploded {
            problems.append("a \(status.rawValue) board with no opened mine")
        }
        return problems
    }
}
