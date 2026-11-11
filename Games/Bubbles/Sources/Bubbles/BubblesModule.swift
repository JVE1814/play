import BubbleEngine
import PlayKit
import SwiftUI

/// The bubble shooter, registered in the app's `GameRegistry`.
public struct BubblesModule: GameModule {
    public init() {}

    public var id: String { "bubbles" }
    public var title: String { "Bubbles" }
    public var tagline: String { "Aim, pop and drop through \(LevelCatalog.count.formatted()) levels" }
    public var accent: Accent { .sky }

    @MainActor public func makeIcon() -> AnyView {
        AnyView(BubblesIcon())
    }

    @MainActor public func makeGameView(context: GameContext) -> AnyView {
        AnyView(BubblesScreen(context: context))
    }

    @MainActor public func makeSettingsSection(context: GameContext) -> AnyView? {
        AnyView(BubblesSettingsRows(preferences: context.preferences(BubblesPreferences.self)))
    }

    @MainActor public func statusLine(context: GameContext) -> String? {
        guard let save = context.saveSlot.load(BubblesSave.self) else { return nil }
        return save.progress.statusLine(level: save.game.levelNumber)
    }
}

/// Bubbles' own preferences, shared by the game screen and its settings rows.
@MainActor
public final class BubblesPreferences: ObservableObject, GamePreferenceSet {
    private let store: GamePreferences

    /// Show the whole path (bounces included) rather than just its start.
    @Published public var fullAimGuide: Bool {
        didSet { store.set(fullAimGuide, for: "fullAimGuide") }
    }

    public init(preferences: GamePreferences) {
        store = preferences
        fullAimGuide = preferences.bool("fullAimGuide", default: true)
    }
}

/// What is written to disk after every shot.
public struct BubblesSave: Codable, Equatable {
    public var progress: LevelProgress
    /// The attempt in progress (or just finished).
    public var game: BubbleGame
    /// Increases with every attempt so each one deals a different bubble queue.
    public var attempt: Int
    public var elapsed: TimeInterval
    public var resultRecorded: Bool
}

extension BubbleGame {
    /// How the attempt ended, in words: the result panel's title, its message after a loss, and
    /// what VoiceOver announces.
    var ending: (title: String, message: String?, spoken: String) {
        switch status {
        case .won:
            return ("Level \(levelNumber) cleared!", nil,
                    "Level \(levelNumber) cleared with \(Format.count(stars, "star")).")
        case .reachedLine:
            return ("Too close to the line",
                    "A bubble ended up below the dashed line. Try again with a fresh set of bubbles.",
                    "The bubbles reached the line.")
        case .outOfShots, .playing:
            return ("Out of shots",
                    "\(Format.count(grid.count, "bubble")) left. Try again with a fresh set of bubbles.",
                    "Out of shots.")
        }
    }
}

/// Prepared positions for UI tests and screenshots, by `-scenario` name.
enum Scenarios {
    static func game(_ name: String?) -> BubbleGame? {
        switch name {
        case "bubblesNearWin":
            // Two reds at the top: one shot straight up makes three and clears the board.
            return BubbleGame(grid: BubbleGrid(rows: ["...rr..."]), palette: [.red, .blue], shotLimit: 5, par: 1,
                              seed: 1, levelNumber: 1, current: .red, next: .red)
        case "bubblesLastShot":
            return BubbleGame(grid: BubbleGrid(rows: ["yybbyybb", "bbyybbyy", "yybbyybb"]),
                              palette: [.red, .yellow, .blue], shotLimit: 1, par: 1, seed: 1, levelNumber: 1,
                              current: .red, next: .yellow)
        default:
            return nil
        }
    }
}
