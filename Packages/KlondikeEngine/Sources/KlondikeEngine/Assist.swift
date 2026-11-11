import Foundation

/// Player aids: the best move for a tapped card, hints, and auto-finish.
extension KlondikeGame {

    // MARK: Tap to move

    /// The best legal move for a tap on `card`, or nil if there is none.
    ///
    /// Tapping a face-up tableau card moves it together with the cards on top of it. Because taps
    /// on a moving train are imprecise, if the tapped card has no move the other face-up cards
    /// of the same column are tried, nearest first. Taps on any waste or foundation card act on
    /// that pile's top card, and a tap on any stock card draws.
    public func bestMove(tapping card: Card) -> Move? {
        guard let location = board.location(of: card) else { return nil }
        switch location.pile {
        case .stock, .waste, .foundation:
            return bestMove(tappingPile: location.pile)
        case .tableau(let t):
            guard location.isFaceUp else { return nil }
            let column = board.tableau[t]
            let tappedCount = column.visible.count - (location.index - column.hidden.count)
            if let move = bestTransfer(from: .tableau(t), count: tappedCount) { return move }
            let others = (1...column.visible.count)
                .filter { $0 != tappedCount }
                .sorted { (abs($0 - tappedCount), $0) < (abs($1 - tappedCount), $1) }
            for count in others {
                if let move = bestTransfer(from: .tableau(t), count: count) { return move }
            }
            return nil
        }
    }

    /// The best move for a tap on a pile itself (for example its empty slot or the space below a column).
    public func bestMove(tappingPile pile: Pile) -> Move? {
        switch pile {
        case .stock:
            return stockMove
        case .waste:
            return bestTransfer(from: .waste, count: 1)
        case .foundation(let f):
            return bestTransfer(from: .foundation(f), count: 1)
        case .tableau(let t):
            guard let top = board.tableau[t].top else { return nil }
            return bestMove(tapping: top)
        }
    }

    /// The highest-scoring legal transfer of `count` cards from `pile`, ignoring pointless moves.
    func bestTransfer(from pile: Pile, count: Int) -> Move? {
        var best: (move: Move, score: Int)?
        for destination in destinations(from: pile, count: count) {
            let move = Move.transfer(from: pile, to: destination, count: count)
            guard let score = score(of: move), score > 0 else { continue }
            if best == nil || score > best!.score { best = (move, score) }
        }
        return best?.move
    }

    // MARK: Hints

    /// Moves scoring at least this much are worth suggesting as a hint.
    static let hintThreshold = 10

    /// A useful move to suggest, or nil when nothing useful is left (the game is stuck or won).
    /// When the only progress is in the stock, suggests drawing (or redealing).
    public func hint() -> Move? {
        var best: (move: Move, score: Int)?
        for move in legalMoves() {
            guard case .transfer = move, let score = score(of: move), score >= Self.hintThreshold else { continue }
            if best == nil || score > best!.score { best = (move, score) }
        }
        if let best { return best.move }
        return stockHoldsPlayableCard ? stockMove : nil
    }

    /// What a tap on the stock does: draw, or turn the waste over once the stock is empty.
    var stockMove: Move? {
        if isLegal(.draw) { return .draw }
        if isLegal(.recycle) { return .recycle }
        return nil
    }

    /// Whether any card in the stock or under the top of the waste could be played right now.
    var stockHoldsPlayableCard: Bool {
        let candidates = board.stock + board.waste.dropLast()
        return candidates.contains { card in
            Board.foundationIndices.contains { board.canPlace(card, onFoundation: $0) }
                || Board.columnIndices.contains { board.canPlace(card, onTableau: $0) }
        }
    }

    /// Heuristic value of a transfer; nil if illegal, 0 if legal but pointless.
    func score(of move: Move) -> Int? {
        guard case let .transfer(from, to, count) = move, isLegal(move) else { return nil }
        var revealsHidden = false
        var emptiesColumn = false
        if case .tableau(let t) = from {
            let column = board.tableau[t]
            revealsHidden = count == column.visible.count && !column.hidden.isEmpty
            emptiesColumn = count == column.visible.count && column.hidden.isEmpty
        }
        switch to {
        case .foundation:
            var score = 100
            if revealsHidden { score += 20 }
            if case .waste = from { score += 5 }
            return score
        case .tableau(let destination):
            let destinationEmpty = board.tableau[destination].isEmpty
            switch from {
            case .waste:
                return destinationEmpty ? 25 : 30
            case .foundation:
                return 1
            case .tableau(let t):
                if revealsHidden { return destinationEmpty ? 55 : 60 }
                if emptiesColumn {
                    if destinationEmpty { return 0 }
                    return kingNeedsSpace(excludingColumn: t) ? 15 : 2
                }
                // Splitting a run only helps if it exposes a card that can go to a foundation.
                let column = board.tableau[t]
                let exposed = column.visible[column.visible.count - count - 1]
                if Board.foundationIndices.contains(where: { board.canPlace(exposed, onFoundation: $0) }) { return 40 }
                return 2
            case .stock:
                return nil
            }
        case .stock, .waste:
            return nil
        }
    }

    /// Is there a King that would benefit from an empty column?
    private func kingNeedsSpace(excludingColumn excluded: Int) -> Bool {
        if board.waste.last?.rank == 13 { return true }
        return Board.columnIndices.contains { t in
            guard t != excluded, let base = board.tableau[t].visible.first else { return false }
            return base.rank == 13 && !board.tableau[t].hidden.isEmpty
        }
    }

    // MARK: Auto-finish

    /// True once every card is face up and the game can be completed by moving cards to the
    /// foundations (turning the waste over as needed).
    public var canAutoFinish: Bool { !isWon && autoFinishMoves() != nil }

    /// The moves that finish the game from here, or nil if auto-finish is not available.
    public func autoFinishMoves() -> [Move]? {
        guard board.allCardsRevealed, !isWon else { return nil }
        var game = self
        var moves: [Move] = []
        var turnsWithoutProgress = 0
        while !game.isWon {
            if let move = game.nextFoundationMove() {
                game.perform(move)
                moves.append(move)
                turnsWithoutProgress = 0
                continue
            }
            let remaining = game.board.stock.count + game.board.waste.count
            guard remaining > 0, turnsWithoutProgress <= 2 * (remaining + 1) else { return nil }
            guard let turn = game.stockMove else { return nil }
            game.perform(turn)
            moves.append(turn)
            turnsWithoutProgress += 1
        }
        return moves
    }

    /// The lowest-ranked card that can go to a foundation right now, from the waste or a column top.
    func nextFoundationMove() -> Move? {
        var best: (move: Move, rank: Int)?
        var sources: [(Pile, Card)] = []
        if let top = board.waste.last { sources.append((.waste, top)) }
        for t in Board.columnIndices { if let top = board.tableau[t].top { sources.append((.tableau(t), top)) } }
        for (pile, card) in sources {
            for f in Board.foundationIndices where board.canPlace(card, onFoundation: f) {
                if best == nil || card.rank < best!.rank {
                    best = (.transfer(from: pile, to: .foundation(f), count: 1), card.rank)
                }
                break
            }
        }
        return best?.move
    }
}
