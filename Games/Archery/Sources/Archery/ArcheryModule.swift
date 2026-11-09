import ArcheryEngine
import PlayKit
import SwiftUI

/// Target archery, registered in the app's `GameRegistry`.
public struct ArcheryModule: GameModule {
    public init() {}

    public var id: String { "archery" }
    public var title: String { "Archery" }
    public var tagline: String { "Read the wind and find the gold, from 10 to 90 metres" }
    public var accent: Accent { .coral }

    @MainActor public func makeIcon() -> AnyView {
        AnyView(ArcheryIcon())
    }

    @MainActor public func makeGameView(context: GameContext) -> AnyView {
        AnyView(ArcheryScreen(context: context))
    }

    @MainActor public func makeSettingsSection(context: GameContext) -> AnyView? {
        AnyView(ArcherySettingsRows(preferences: ArcheryPreferences.shared(in: context)))
    }

    @MainActor public func statusLine(context: GameContext) -> String? {
        guard let save = context.saveSlot.load(ArcherySave.self) else { return nil }
        return "Level \(save.round.level.number) · \(save.progress.totalStars) ★"
    }
}

/// Archery's own preferences, shared by the game screen and its settings rows.
@MainActor
public final class ArcheryPreferences: ObservableObject {
    private let store: GamePreferences

    /// 0 slow, 1 normal, 2 fast: how far the sight moves for a slide of the thumb.
    @Published public var aimSpeed: Int {
        didSet { store.set(aimSpeed, for: "aimSpeed") }
    }

    /// Much less sway, for shaky hands or a bumpy ride.
    @Published public var steadyAim: Bool {
        didSet { store.set(steadyAim, for: "steadyAim") }
    }

    /// Holds the bow in the right hand, so the bow appears on the other side of the sight.
    @Published public var leftHanded: Bool {
        didSet { store.set(leftHanded, for: "leftHanded") }
    }

    public init(preferences: GamePreferences) {
        store = preferences
        aimSpeed = min(2, max(0, preferences.int("aimSpeed", default: 1)))
        steadyAim = preferences.bool("steadyAim", default: false)
        leftHanded = preferences.bool("leftHanded", default: false)
    }

    public static func shared(in context: GameContext) -> ArcheryPreferences {
        context.shared(ArcheryPreferences.self) { ArcheryPreferences(preferences: context.preferences) }
    }

    /// Sight points moved per point the thumb slides. Below 1, so the thumb never has to cover
    /// the target and small corrections are easy.
    public var aimGain: Double { [0.3, 0.45, 0.65][aimSpeed] }

    /// Multiplier for the level's sway.
    public var swayStrength: Double { steadyAim ? 0.3 : 1 }
}

/// Levels unlocked, stars earned and best scores.
public struct ArcheryProgress: Codable, Equatable {
    /// The highest level that may be played.
    public private(set) var unlocked = 1
    /// Best stars per level (index = level − 1).
    public private(set) var stars: [UInt8] = []
    /// Best score per level (index = level − 1).
    public private(set) var best: [Int] = []

    public init(unlocked: Int = 1) {
        self.unlocked = max(1, min(unlocked, LevelCatalog.count))
    }

    public var totalStars: Int { stars.reduce(0) { $0 + Int($1) } }

    public func stars(for level: Int) -> Int {
        level >= 1 && level - 1 < stars.count ? Int(stars[level - 1]) : 0
    }

    public func bestScore(for level: Int) -> Int? {
        level >= 1 && level - 1 < best.count && best[level - 1] > 0 ? best[level - 1] : nil
    }

    public func isUnlocked(_ level: Int) -> Bool { (1...unlocked).contains(level) }

    /// Records a finished attempt: keeps the best score and stars, and unlocks the next level
    /// once this one is passed.
    public mutating func record(level: Int, score: Int, stars earned: Int) {
        guard (1...LevelCatalog.count).contains(level) else { return }
        if best.count < level { best += Array(repeating: 0, count: level - best.count) }
        best[level - 1] = max(best[level - 1], score)
        guard earned > 0 else { return }
        if stars.count < level { stars += Array(repeating: 0, count: level - stars.count) }
        stars[level - 1] = UInt8(max(Int(stars[level - 1]), min(3, earned)))
        unlocked = min(LevelCatalog.count, max(unlocked, level + 1))
    }
}

/// What is written to disk after every arrow.
public struct ArcherySave: Codable, Equatable {
    public var version = 1
    public var progress: ArcheryProgress
    /// The attempt in progress (or just finished).
    public var round: ArcheryRound
    /// Where the sight rests between arrows (target coordinates).
    public var aim: Vec2
    /// Seconds spent on this attempt, for statistics.
    public var elapsed: TimeInterval
    public var resultRecorded: Bool
}
