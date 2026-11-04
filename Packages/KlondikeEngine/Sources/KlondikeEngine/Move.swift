import Foundation

/// How many cards a draw turns from the stock.
public enum DrawMode: Int, Codable, CaseIterable, Sendable {
    case one = 1
    case three = 3

    public var title: String { self == .one ? "Draw 1" : "Draw 3" }
}

/// A player action.
public enum Move: Hashable, Codable, Sendable, CustomStringConvertible {
    /// Turn one or three cards from the stock onto the waste.
    case draw
    /// Turn the whole waste back over to form a new stock (a redeal). Unlimited.
    case recycle
    /// Move the top `count` face-up cards of `from` onto `to`.
    case transfer(from: Pile, to: Pile, count: Int)

    public var description: String {
        switch self {
        case .draw: return "draw"
        case .recycle: return "redeal"
        case let .transfer(from, to, count): return "\(count) from \(from) to \(to)"
        }
    }
}

/// A move that was made, with what is needed to undo it exactly.
public struct MoveRecord: Hashable, Codable, Sendable {
    public let move: Move
    /// For transfers: whether a face-down card in the source column was turned up afterwards.
    public let revealedCard: Bool
    /// For draws: cards drawn. For redeals: cards returned to the stock. Otherwise the cards moved.
    public let cardCount: Int
}
