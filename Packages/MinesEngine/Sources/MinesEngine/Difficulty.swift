import Foundation

/// How many mines a board holds, and how much reasoning it may ask of the player.
public enum Difficulty: Int, CaseIterable, Codable, Sendable {
    case easy, medium, hard

    public var mineCount: Int {
        switch self {
        case .easy: return 12
        case .medium: return 16
        case .hard: return 20
        }
    }

    /// Easy boards can be cleared one number at a time. Medium and Hard boards may need two
    /// numbers read together.
    public var reasoning: MinesSolver.Reasoning {
        self == .easy ? .single : .pairs
    }

    public var name: String {
        switch self {
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        }
    }

    var key: String {
        switch self {
        case .easy: return "easy"
        case .medium: return "medium"
        case .hard: return "hard"
        }
    }
}
