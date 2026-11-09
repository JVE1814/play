import BubbleEngine
import PlayKit
import SwiftUI

/// The bubble shooter, registered in the app's `GameRegistry`.
public struct BubblesModule: GameModule {
    public init() {}

    public var id: String { "bubbles" }
    public var title: String { "Bubbles" }
    public var tagline: String { "Aim, pop and drop through 2,000 levels" }
    public var accent: Accent { .sky }

    @MainActor public func makeIcon() -> AnyView {
        AnyView(BubblesIcon())
    }

    @MainActor public func makeGameView(context: GameContext) -> AnyView {
        AnyView(BubblesScreen(context: context))
    }

    @MainActor public func makeSettingsSection(context: GameContext) -> AnyView? {
        AnyView(BubblesSettingsRows(preferences: BubblesPreferences.shared(in: context)))
    }

    @MainActor public func statusLine(context: GameContext) -> String? {
        guard let save = context.saveSlot.load(BubblesSave.self) else { return nil }
        let level = save.game.levelNumber
        let stars = save.progress.totalStars
        return level > 0 ? "Level \(level) · \(stars) ★" : "\(stars) ★"
    }
}

/// Bubbles' own preferences, shared by the game screen and its settings rows.
@MainActor
public final class BubblesPreferences: ObservableObject {
    private let store: GamePreferences

    /// Show the whole path (bounces included) rather than just its start.
    @Published public var fullAimGuide: Bool {
        didSet { store.set(fullAimGuide, for: "fullAimGuide") }
    }

    public init(preferences: GamePreferences) {
        store = preferences
        fullAimGuide = preferences.bool("fullAimGuide", default: true)
    }

    public static func shared(in context: GameContext) -> BubblesPreferences {
        context.shared(BubblesPreferences.self) { BubblesPreferences(preferences: context.preferences) }
    }
}

/// Levels unlocked and stars earned.
public struct BubblesProgress: Codable, Equatable {
    /// The highest level that may be played.
    public private(set) var unlocked = 1
    /// Best stars per level (index = level − 1).
    public private(set) var stars: [UInt8] = []

    public init(unlocked: Int = 1) {
        self.unlocked = max(1, min(unlocked, LevelCatalog.count))
    }

    public var totalStars: Int { stars.reduce(0) { $0 + Int($1) } }

    public func stars(for level: Int) -> Int {
        level - 1 < stars.count ? Int(stars[level - 1]) : 0
    }

    public func isUnlocked(_ level: Int) -> Bool { (1...unlocked).contains(level) }

    /// Records a cleared level: keeps the best stars and unlocks the next level.
    public mutating func recordClear(level: Int, stars earned: Int) {
        guard (1...LevelCatalog.count).contains(level) else { return }
        if stars.count < level { stars += Array(repeating: 0, count: level - stars.count) }
        stars[level - 1] = UInt8(max(Int(stars[level - 1]), min(3, earned)))
        unlocked = min(LevelCatalog.count, max(unlocked, level + 1))
    }
}

/// What is written to disk after every shot.
public struct BubblesSave: Codable, Equatable {
    public var version = 1
    public var progress: BubblesProgress
    /// The attempt in progress (or just finished).
    public var game: BubbleGame
    /// Increases with every attempt so each one deals a different bubble queue.
    public var attempt: Int
    public var elapsed: TimeInterval
    public var resultRecorded: Bool
}
