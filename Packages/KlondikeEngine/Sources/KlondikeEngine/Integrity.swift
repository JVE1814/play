import Foundation

extension Board {
    /// True if `cards` (bottom first) form a descending run of alternating colours.
    public static func isValidRun(_ cards: [Card]) -> Bool {
        zip(cards, cards.dropFirst()).allSatisfy { lower, upper in
            upper.rank == lower.rank - 1 && upper.isRed != lower.isRed
        }
    }

    /// Problems with this board, empty when it is a legal Klondike position. Used by tests and
    /// to reject corrupted saved games.
    public var integrityProblems: [String] {
        var problems: [String] = []
        let cards = allCards
        if cards.count != 52 { problems.append("expected 52 cards, found \(cards.count)") }
        if Set(cards).count != cards.count { problems.append("duplicate cards") }
        if Set(cards) != Set(Card.fullDeck) { problems.append("cards missing from the deck") }
        if foundations.count != Board.foundationCount { problems.append("expected 4 foundations") }
        if tableau.count != Board.columnCount { problems.append("expected 7 columns") }
        for (i, foundation) in foundations.enumerated() {
            for (position, card) in foundation.enumerated()
            where card.rank != position + 1 || card.suit != foundation[0].suit {
                problems.append("foundation \(i) out of order at \(card)")
                break
            }
        }
        for (i, column) in tableau.enumerated() {
            if column.visible.isEmpty && !column.hidden.isEmpty { problems.append("column \(i) has no face-up card") }
            if !Board.isValidRun(column.visible) { problems.append("column \(i) face-up cards are not a valid run") }
        }
        return problems
    }
}

extension KlondikeGame {
    /// Problems with the board or history; empty for a consistent game.
    public var integrityProblems: [String] {
        var problems = board.integrityProblems
        // The history must undo to a legal position, and playing it again from there must be
        // legal at every move and arrive at exactly this game.
        var replay = self
        replay.undoAll()
        guard !replay.canUndo else {
            return problems + ["the history holds a move this board could not have come from"]
        }
        problems += replay.board.integrityProblems.map { "after undoing all moves: \($0)" }
        for record in history where !replay.perform(record.move) {
            return problems + ["the history holds an illegal move: \(record.move)"]
        }
        if replay != self { problems.append("the history does not lead to this board") }
        return problems
    }
}
