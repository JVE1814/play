import Foundation

/// Plays a board the way a careful player can: it sees only the numbers on open squares and
/// how many mines the board holds, and opens a square only when those prove it safe.
///
/// A board is fair ("no guessing") when this solver, starting from the first tap's opening,
/// opens every safe square. The generator keeps only boards it can clear.
public struct MinesSolver: Sendable {
    public enum Reasoning: Int, Comparable, Sendable {
        /// One number at a time, plus the board's mine count.
        case single
        /// Also two overlapping numbers read together, such as the 1-2-1 along an edge.
        case pairs

        public static func < (lhs: Reasoning, rhs: Reasoning) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// What the solver knows: the squares it has opened and the squares it has proved are mines.
    public struct Knowledge: Hashable, Sendable {
        public var opened: CellSet
        public var mines: CellSet

        public init(opened: CellSet, mines: CellSet = CellSet()) {
            self.opened = opened
            self.mines = mines
        }
    }

    public enum Rule: Sendable {
        /// A number whose mines are all found (the rest are safe), or that has as many covered
        /// neighbours as mines left (all of them are mines).
        case single
        /// The board's mine count: no mines left anywhere, or as many as there are covered squares.
        case count
        /// Two numbers read together.
        case pairs
    }

    /// One round of deductions, all made from the same knowledge.
    public struct Step: Hashable, Sendable {
        public let safe: CellSet
        public let mines: CellSet
        public let rule: Rule
    }

    /// How often each rule was needed to clear a board.
    public struct RuleCounts: Hashable, Sendable {
        public var single = 0
        public var count = 0
        public var pairs = 0
    }

    public struct Result: Hashable, Sendable {
        public let solved: Bool
        public let knowledge: Knowledge
        public let rules: RuleCounts
    }

    public let reasoning: Reasoning

    public init(reasoning: Reasoning) {
        self.reasoning = reasoning
    }

    /// The deductions the simplest rule that finds any makes, or nil when no rule allowed
    /// at this reasoning finds anything (the player would have to guess).
    public func step(_ field: Minefield, _ knowledge: Knowledge) -> Step? {
        let unknown = MinesGrid.all.subtracting(knowledge.opened).subtracting(knowledge.mines)
        guard !unknown.isEmpty else { return nil }

        var constraints: [(cells: CellSet, mines: Int)] = []
        var safe = CellSet(), mines = CellSet()
        for cell in knowledge.opened {
            let number = field.count(around: cell)
            guard number > 0 else { continue }
            let around = MinesGrid.neighbours(of: cell)
            let cells = around.intersection(unknown)
            guard !cells.isEmpty else { continue }
            let left = number - around.intersection(knowledge.mines).count
            if left == 0 {
                safe = safe.union(cells)
            } else if left == cells.count {
                mines = mines.union(cells)
            }
            constraints.append((cells, left))
        }
        if !safe.isEmpty || !mines.isEmpty { return Step(safe: safe, mines: mines, rule: .single) }

        let remaining = field.mines.count - knowledge.mines.count
        if remaining == 0 { return Step(safe: unknown, mines: CellSet(), rule: .count) }
        if remaining == unknown.count { return Step(safe: CellSet(), mines: unknown, rule: .count) }

        guard reasoning >= .pairs else { return nil }
        // The board's count is one more constraint: every covered square, holding the mines left.
        constraints.append((unknown, remaining))
        for a in constraints.indices {
            for b in constraints.indices where a != b {
                let (cellsA, minesA) = constraints[a]
                let (cellsB, minesB) = constraints[b]
                guard !cellsA.isDisjoint(with: cellsB) else { continue }
                // B holds minesB; at most minesA of them can sit in the overlap with A. If the
                // rest exactly fill B's squares outside A, those are all mines, the overlap holds
                // minesA, and A's squares outside B are all safe.
                let onlyB = cellsB.subtracting(cellsA)
                guard minesB - minesA == onlyB.count else { continue }
                mines = mines.union(onlyB)
                safe = safe.union(cellsA.subtracting(cellsB))
            }
        }
        if !safe.isEmpty || !mines.isEmpty { return Step(safe: safe, mines: mines, rule: .pairs) }
        return nil
    }

    /// Plays the board from its first tap until every safe square is open or it is stuck.
    public func solve(_ field: Minefield, firstTap: Int) -> Result {
        var knowledge = Knowledge(opened: field.flood(from: firstTap))
        var rules = RuleCounts()
        let target = field.safeCells
        while knowledge.opened != target {
            guard let step = step(field, knowledge) else {
                return Result(solved: false, knowledge: knowledge, rules: rules)
            }
            switch step.rule {
            case .single: rules.single += 1
            case .count: rules.count += 1
            case .pairs: rules.pairs += 1
            }
            for cell in step.safe where !knowledge.opened.contains(cell) {
                knowledge.opened = knowledge.opened.union(field.flood(from: cell))
            }
            knowledge.mines = knowledge.mines.union(step.mines)
        }
        return Result(solved: true, knowledge: knowledge, rules: rules)
    }

    public func solves(_ field: Minefield, firstTap: Int) -> Bool {
        solve(field, firstTap: firstTap).solved
    }
}
