import Foundation

/// Levels unlocked, stars earned and best scores, for a game played level by level.
public struct LevelProgress: Codable, Equatable {
    public static let maxStars = 3

    /// The highest level that may be played.
    public private(set) var unlocked: Int
    /// Best stars per level (index = level − 1).
    public private(set) var stars: [UInt8] = []
    /// Best score per level (index = level − 1), for games that keep one.
    public private(set) var best: [Int] = []

    public init(unlocked: Int = 1) {
        self.unlocked = max(1, unlocked)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unlocked = try container.decode(Int.self, forKey: .unlocked)
        stars = try container.decode([UInt8].self, forKey: .stars)
        best = try container.decodeIfPresent([Int].self, forKey: .best) ?? []
    }

    public var totalStars: Int { stars.reduce(0) { $0 + Int($1) } }

    public func stars(for level: Int) -> Int {
        stars.indices.contains(level - 1) ? Int(stars[level - 1]) : 0
    }

    public func bestScore(for level: Int) -> Int? {
        best.indices.contains(level - 1) && best[level - 1] > 0 ? best[level - 1] : nil
    }

    public func isUnlocked(_ level: Int) -> Bool { (1...unlocked).contains(level) }

    /// Records a finished attempt at one of `levelCount` levels: keeps the best score and
    /// stars, and unlocks the next level once this one has a star.
    public mutating func record(level: Int, stars earned: Int, score: Int? = nil, of levelCount: Int) {
        guard (1...levelCount).contains(level) else { return }
        if let score {
            if best.count < level { best += Array(repeating: 0, count: level - best.count) }
            best[level - 1] = max(best[level - 1], score)
        }
        guard earned > 0 else { return }
        if stars.count < level { stars += Array(repeating: 0, count: level - stars.count) }
        stars[level - 1] = UInt8(max(Int(stars[level - 1]), min(Self.maxStars, earned)))
        unlocked = min(levelCount, max(unlocked, level + 1))
    }

    /// The home tile's line, such as "Level 12 · 30 ★".
    public func statusLine(level: Int) -> String {
        "Level \(level) · \(totalStars) ★"
    }

    /// What VoiceOver says about a level in the list.
    public func spokenState(of level: Int, isCurrent: Bool) -> String {
        guard isUnlocked(level) else { return "Locked" }
        var text = "\(stars(for: level)) of \(Self.maxStars) stars"
        if let best = bestScore(for: level) { text += ", best \(best)" }
        if isCurrent { text += ", current" }
        return text
    }
}

/// A game played level by level. The shared level views (the list, the result buttons, the
/// Levels and Restart toolbar buttons, the restart question) work from this.
@MainActor
public protocol LevelSession: GameSession {
    var levelNumber: Int { get }
    var levelCount: Int { get }
    var progress: LevelProgress { get }
    /// The attempt has shots that a restart would throw away.
    var hasAttemptInProgress: Bool { get }
    /// False while a restart has to wait.
    var canRestart: Bool { get }
    var showingLevels: Bool { get set }
    var confirmingRestart: Bool { get set }
    /// Sets the game up for a fresh attempt at `level`, which is unlocked. Called by `start(level:)`.
    func beginAttempt(at level: Int)
}

extension LevelSession {
    public var canRestart: Bool { true }
    public var hasNextLevel: Bool { levelNumber < levelCount }
    public var coversTable: Bool { showingLevels }

    /// Starts a fresh attempt at `level`, if it is unlocked, and puts away the level list and
    /// the restart question.
    public func start(level: Int) {
        guard progress.isUnlocked(level) else { return }
        beginAttempt(at: level)
        showingLevels = false
        confirmingRestart = false
    }

    public func retry() { start(level: levelNumber) }
    public func nextLevel() { start(level: levelNumber + 1) }

    /// Restart from the toolbar: asks first if there are shots to lose.
    public func requestRestart() {
        guard canRestart else { return }
        if hasAttemptInProgress {
            confirmingRestart = true
        } else {
            retry()
        }
    }
}

extension LaunchOptions {
    /// `-level N`: the level a game with `levelCount` levels starts at (and unlocks up to).
    public func startLevel(of levelCount: Int) -> Int {
        min(levelCount, max(1, value(after: "-level").flatMap { Int($0) } ?? 1))
    }
}
