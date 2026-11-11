import Foundation

/// One board of Mines, from before the first tap to won or lost.
///
/// Illegal actions return nil or false and change nothing. Opening a mine never changes the
/// board, only the status, so taking a slip back needs no history.
public struct MinesGame: Hashable, Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// No square opened yet; the mines are laid by the first tap.
        case fresh
        case playing
        /// A mine was opened and the player may take it back.
        case slipped
        case won
        case lost
    }

    /// What a square shows.
    public enum CellState: Hashable, Sendable {
        case covered
        case flagged
        /// Open, with the number of mines around it (0 shows nothing).
        case number(Int)
        /// A mine shown after the board is lost.
        case mine
        /// The mine that was opened.
        case exploded
        /// A flag on a safe square, shown after the board is lost.
        case wrongFlag
    }

    public enum Outcome: Hashable, Sendable {
        case opened(CellSet)
        case won(CellSet)
        case slipped(mine: Int)
        case lost(mine: Int)
    }

    public let seed: UInt64
    public let difficulty: Difficulty
    /// Nil until the first tap lays the mines.
    public private(set) var field: Minefield?
    public private(set) var firstTap: Int?
    public private(set) var opened: CellSet
    public private(set) var flagged: CellSet
    public private(set) var status: Status
    /// The mine that was opened, while slipped or once lost.
    public private(set) var exploded: Int?
    /// True once the one take-back of this board has been used.
    public private(set) var slipUsed: Bool
}

extension MinesGame {
    /// A board waiting for its first tap.
    public init(seed: UInt64, difficulty: Difficulty) {
        self.init(seed: seed, difficulty: difficulty, field: nil, firstTap: nil, opened: CellSet(),
                  flagged: CellSet(), status: .fresh, exploded: nil, slipUsed: false)
    }

    /// A board with chosen mines, already opened at `firstTap`. For scenarios and tests.
    public init(difficulty: Difficulty, mines: CellSet, firstTap: Int) {
        precondition(mines.isDisjoint(with: MinesGrid.zone(around: firstTap)), "the first tap must open an area")
        let field = Minefield(mines: mines)
        self.init(seed: 0, difficulty: difficulty, field: field, firstTap: firstTap,
                  opened: field.flood(from: firstTap), flagged: CellSet(), status: .playing,
                  exploded: nil, slipUsed: false)
        if opened == field.safeCells { finishWon(field) }
    }

    public var isStarted: Bool { status != .fresh }
    public var isFinished: Bool { status == .won || status == .lost }

    /// Mines not yet flagged. Below zero when there are more flags than mines.
    public var minesLeft: Int { difficulty.mineCount - flagged.count }

    public var safeCount: Int { MinesGrid.cellCount - difficulty.mineCount }

    public func cellState(_ cell: Int) -> CellState {
        if cell == exploded { return .exploded }
        if opened.contains(cell), let field { return .number(field.count(around: cell)) }
        if status == .lost, let field {
            if field.isMine(cell) { return flagged.contains(cell) ? .flagged : .mine }
            if flagged.contains(cell) { return .wrongFlag }
        }
        return flagged.contains(cell) ? .flagged : .covered
    }

    /// True when tapping the open number at `cell` would open its other neighbours: its
    /// flags match its number and some neighbour is still covered and unflagged.
    public func canChord(_ cell: Int) -> Bool {
        guard status == .playing, let field, opened.contains(cell) else { return false }
        let number = field.count(around: cell)
        guard number > 0 else { return false }
        let around = MinesGrid.neighbours(of: cell)
        return around.intersection(flagged).count == number && !around.subtracting(opened).subtracting(flagged).isEmpty
    }

    /// Opens a covered, unflagged square. On a fresh board this lays the mines first.
    /// `forgiving` lets the first mine of the board be taken back.
    @discardableResult
    public mutating func open(_ cell: Int, forgiving: Bool) -> Outcome? {
        guard MinesGrid.isValid(cell), status == .fresh || status == .playing,
              !opened.contains(cell), !flagged.contains(cell) else { return nil }
        if status == .fresh {
            field = MinesGenerator.generate(seed: seed, difficulty: difficulty, firstTap: cell).field
            firstTap = cell
            status = .playing
        }
        guard let field else { return nil }
        if field.isMine(cell) { return hitMine(cell, forgiving: forgiving) }
        return reveal(field.flood(from: cell), in: field)
    }

    /// Opens the covered, unflagged neighbours of an open number whose flags match it.
    @discardableResult
    public mutating func chord(_ cell: Int, forgiving: Bool) -> Outcome? {
        guard canChord(cell), let field else { return nil }
        let targets = MinesGrid.neighbours(of: cell).subtracting(opened).subtracting(flagged)
        if let mine = targets.first(where: field.isMine) { return hitMine(mine, forgiving: forgiving) }
        var revealed = CellSet()
        for target in targets { revealed = revealed.union(field.flood(from: target)) }
        return reveal(revealed, in: field)
    }

    /// Flags or unflags a covered square. Not before the first tap: there is nothing to reason from.
    @discardableResult
    public mutating func toggleFlag(_ cell: Int) -> Bool {
        guard MinesGrid.isValid(cell), status == .playing, !opened.contains(cell) else { return false }
        if flagged.contains(cell) { flagged.remove(cell) } else { flagged.insert(cell) }
        return true
    }

    /// Takes back the mine just opened: the board is as it was before that tap.
    @discardableResult
    public mutating func takeBack() -> Bool {
        guard status == .slipped else { return false }
        status = .playing
        exploded = nil
        slipUsed = true
        return true
    }

    /// Declines the take-back: the board is lost.
    @discardableResult
    public mutating func endBoard() -> Bool {
        guard status == .slipped else { return false }
        status = .lost
        return true
    }

    private mutating func hitMine(_ cell: Int, forgiving: Bool) -> Outcome {
        exploded = cell
        if forgiving && !slipUsed {
            status = .slipped
            return .slipped(mine: cell)
        }
        status = .lost
        return .lost(mine: cell)
    }

    private mutating func reveal(_ cells: CellSet, in field: Minefield) -> Outcome {
        let revealed = cells.subtracting(opened)
        opened = opened.union(revealed)
        // A flag on a square that turns out safe goes when the square opens.
        flagged = flagged.subtracting(revealed)
        if opened == field.safeCells {
            finishWon(field)
            return .won(revealed)
        }
        return .opened(revealed)
    }

    private mutating func finishWon(_ field: Minefield) {
        status = .won
        flagged = field.mines
    }

    /// The board as text, for tests: the difficulty and status, then 12 rows of 8 squares:
    /// `.` covered, `f` flag, `0`–`8` open, `X` the opened mine, `*` a mine shown after a
    /// loss, `x` a wrong flag.
    public var signature: String {
        guard isStarted else { return "\(difficulty.key)|fresh" }
        let rows = (0..<MinesGrid.rows).map { row in
            String((0..<MinesGrid.columns).map { column -> Character in
                switch cellState(MinesGrid.index(row: row, column: column)) {
                case .covered: return "."
                case .flagged: return "f"
                case .number(let n): return Character(String(n))
                case .mine: return "*"
                case .exploded: return "X"
                case .wrongFlag: return "x"
                }
            })
        }
        return "\(difficulty.key)|\(status.rawValue)|slip:\(slipUsed ? 1 : 0)|left:\(minesLeft)|" + rows.joined(separator: "/")
    }
}
