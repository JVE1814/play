import Foundation

/// A game of Klondike: the board, the draw mode and the full move history (for unlimited undo).
public struct KlondikeGame: Hashable, Codable, Sendable {
    public private(set) var board: Board
    public let drawMode: DrawMode
    public private(set) var history: [MoveRecord]

    /// The same seed always gives the same deal.
    public init(seed: UInt64, drawMode: DrawMode = .one) {
        self.board = Board(seed: seed)
        self.drawMode = drawMode
        self.history = []
    }

    /// Used for fixtures and tests.
    public init(board: Board, drawMode: DrawMode = .one) {
        self.board = board
        self.drawMode = drawMode
        self.history = []
    }

    // MARK: Convenience accessors

    public var stock: [Card] { board.stock }
    public var waste: [Card] { board.waste }
    public var foundations: [[Card]] { board.foundations }
    public var tableau: [TableauColumn] { board.tableau }
    public var isWon: Bool { board.isWon }
    public var moveCount: Int { history.count }
    public var canUndo: Bool { !history.isEmpty }

    // MARK: Rules

    public func isLegal(_ move: Move) -> Bool {
        switch move {
        case .draw:
            return !board.stock.isEmpty
        case .recycle:
            return board.stock.isEmpty && !board.waste.isEmpty
        case let .transfer(from, to, count):
            guard from != to, let cards = board.movableCards(from: from, count: count), let first = cards.first else {
                return false
            }
            switch to {
            case .foundation(let f):
                if case .foundation = from { return false }
                return count == 1 && board.canPlace(first, onFoundation: f)
            case .tableau(let t):
                return board.canPlace(first, onTableau: t)
            case .stock, .waste:
                return false
            }
        }
    }

    /// Every legal move in the current position, in a deterministic order.
    public func legalMoves() -> [Move] {
        var moves: [Move] = []
        if isLegal(.draw) { moves.append(.draw) }
        if isLegal(.recycle) { moves.append(.recycle) }
        var sources: [(Pile, Int)] = []
        if !board.waste.isEmpty { sources.append((.waste, 1)) }
        for t in Board.columnIndices {
            let visible = board.tableau[t].visible.count
            if visible > 0 {
                for count in 1...visible { sources.append((.tableau(t), count)) }
            }
        }
        for f in Board.foundationIndices where !board.foundations[f].isEmpty {
            sources.append((.foundation(f), 1))
        }
        for (from, count) in sources {
            moves += destinations(from: from, count: count).map { .transfer(from: from, to: $0, count: count) }
        }
        return moves
    }

    /// The piles that `count` cards lifted from `source` may go to: foundations first, then columns.
    public func destinations(from source: Pile, count: Int) -> [Pile] {
        let piles = Board.foundationIndices.map { Pile.foundation($0) } + Board.columnIndices.map { Pile.tableau($0) }
        return piles.filter { isLegal(.transfer(from: source, to: $0, count: count)) }
    }

    /// The cards `move` would move, bottom first (empty if it cannot be made).
    public func cards(movedBy move: Move) -> [Card] {
        switch move {
        case .draw: return Array(board.stock.suffix(drawMode.rawValue))
        case .recycle: return board.waste
        case let .transfer(from, _, count): return board.movableCards(from: from, count: count) ?? []
        }
    }

    /// Returns false (and changes nothing) if the move is illegal.
    @discardableResult
    public mutating func perform(_ move: Move) -> Bool {
        guard isLegal(move) else { return false }
        switch move {
        case .draw:
            let n = cards(movedBy: move).count
            for _ in 0..<n { board.waste.append(board.stock.removeLast()) }
            history.append(MoveRecord(move: move, revealedCard: false, cardCount: n))
        case .recycle:
            let n = board.waste.count
            board.stock = board.waste.reversed()
            board.waste = []
            history.append(MoveRecord(move: move, revealedCard: false, cardCount: n))
        case let .transfer(from, to, count):
            let cards = removeCards(count, from: from)
            addCards(cards, to: to)
            var revealed = false
            if case .tableau(let t) = from, board.tableau[t].visible.isEmpty, !board.tableau[t].hidden.isEmpty {
                board.tableau[t].visible.append(board.tableau[t].hidden.removeLast())
                revealed = true
            }
            history.append(MoveRecord(move: move, revealedCard: revealed, cardCount: count))
        }
        return true
    }

    /// Take back the last move, restoring the board exactly. Returns false if there is nothing to
    /// undo, or if the last move is not one this board could have come from (a damaged save).
    @discardableResult
    public mutating func undo() -> Bool {
        guard let record = history.last, canTakeBack(record) else { return false }
        history.removeLast()
        switch record.move {
        case .draw:
            for _ in 0..<record.cardCount { board.stock.append(board.waste.removeLast()) }
        case .recycle:
            board.waste = board.stock.reversed()
            board.stock = []
        case let .transfer(from, to, count):
            if record.revealedCard, case .tableau(let t) = from {
                board.tableau[t].hidden.append(board.tableau[t].visible.removeLast())
            }
            let cards = removeCards(count, from: to)
            addCards(cards, to: from)
        }
        return true
    }

    /// Whether the board holds the cards `record` says it moved. Always true of a game's own
    /// history; a save that was damaged on disk may claim anything.
    private func canTakeBack(_ record: MoveRecord) -> Bool {
        switch record.move {
        case .draw:
            return (0...board.waste.count).contains(record.cardCount)
        case .recycle:
            return board.waste.isEmpty && board.stock.count == record.cardCount
        case let .transfer(from, to, count):
            guard from != to, count >= 1, let moved = faceUpCount(in: to), moved >= count,
                  let source = faceUpCount(in: from) else { return false }
            if record.revealedCard, case .tableau = from { return source > 0 }
            return true
        }
    }

    /// The face-up cards in `pile`, or nil if the board has no such pile.
    private func faceUpCount(in pile: Pile) -> Int? {
        switch pile {
        case .stock: return 0
        case .waste: return board.waste.count
        case .foundation(let f): return board.foundations.indices.contains(f) ? board.foundations[f].count : nil
        case .tableau(let t): return board.tableau.indices.contains(t) ? board.tableau[t].visible.count : nil
        }
    }

    public mutating func undoAll() {
        while undo() {}
    }

    private mutating func removeCards(_ count: Int, from pile: Pile) -> [Card] {
        switch pile {
        case .stock:
            let cards = Array(board.stock.suffix(count))
            board.stock.removeLast(count)
            return cards
        case .waste:
            let cards = Array(board.waste.suffix(count))
            board.waste.removeLast(count)
            return cards
        case .foundation(let f):
            let cards = Array(board.foundations[f].suffix(count))
            board.foundations[f].removeLast(count)
            return cards
        case .tableau(let t):
            let cards = Array(board.tableau[t].visible.suffix(count))
            board.tableau[t].visible.removeLast(count)
            return cards
        }
    }

    private mutating func addCards(_ cards: [Card], to pile: Pile) {
        switch pile {
        case .stock: board.stock += cards
        case .waste: board.waste += cards
        case .foundation(let f): board.foundations[f] += cards
        case .tableau(let t): board.tableau[t].visible += cards
        }
    }
}
