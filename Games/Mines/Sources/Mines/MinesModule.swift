import MinesEngine
import PlayKit
import SwiftUI

/// Mines, registered in the app's `GameRegistry`.
public struct MinesModule: GameModule {
    public init() {}

    public var id: String { "mines" }
    public var title: String { "Mines" }
    public var tagline: String { "Logic, not luck: every board can be solved" }
    public var accent: Accent { .sun }

    @MainActor public func makeIcon() -> AnyView {
        AnyView(MinesIcon())
    }

    @MainActor public func makeGameView(context: GameContext) -> AnyView {
        AnyView(MinesScreen(context: context))
    }

    @MainActor public func makeSettingsSection(context: GameContext) -> AnyView? {
        AnyView(MinesSettingsRows(preferences: context.preferences(MinesPreferences.self)))
    }

    @MainActor public func statusLine(context: GameContext) -> String? {
        if let save = MinesSave.load(from: context), save.isPlayable, save.isInProgress {
            return "Resume · \(save.game.difficulty.name) · \(Format.clock(save.elapsed))"
        }
        let stats = context.gameStats
        if stats.played > 0 {
            return "\(stats.won) won · \(Format.percent(stats.winRate)) win rate"
        }
        return nil
    }
}

/// Mines' own preferences, shared by the game screen and its settings rows.
@MainActor
public final class MinesPreferences: ObservableObject, GamePreferenceSet {
    private let store: GamePreferences

    /// Medium by default. Takes effect from the next board (at once on a board not yet started).
    @Published public var difficulty: Difficulty {
        didSet { store.set(difficulty.rawValue, for: "difficulty") }
    }

    /// The first mine opened on a board can be taken back. On by default: on a moving train a
    /// bump should not cost a whole board.
    @Published public var forgiveSlip: Bool {
        didSet { store.set(forgiveSlip, for: "forgiveSlip") }
    }

    /// Mirror the toolbar for left-thumb play.
    @Published public var leftHanded: Bool {
        didSet { store.set(leftHanded, for: "leftHanded") }
    }

    public init(preferences: GamePreferences) {
        store = preferences
        difficulty = Difficulty(rawValue: preferences.int("difficulty", default: Difficulty.medium.rawValue)) ?? .medium
        forgiveSlip = preferences.bool("forgiveSlip", default: true)
        leftHanded = preferences.bool("leftHanded", default: false)
    }
}

/// The fastest win at each difficulty. Statistics are shared by all three, so the best time
/// there is the fastest on any; these say what is fast for the difficulty being played.
public struct BestTimes: Codable, Equatable {
    public var easy: TimeInterval?
    public var medium: TimeInterval?
    public var hard: TimeInterval?

    public init() {}

    public subscript(difficulty: Difficulty) -> TimeInterval? {
        get {
            switch difficulty {
            case .easy: return easy
            case .medium: return medium
            case .hard: return hard
            }
        }
        set {
            switch difficulty {
            case .easy: easy = newValue
            case .medium: medium = newValue
            case .hard: hard = newValue
            }
        }
    }
}

/// What is written to disk after every change.
public struct MinesSave: Codable, Equatable {
    public var game: MinesGame
    /// Seconds of play on this board so far.
    public var elapsed: TimeInterval
    /// Whether this board's win or loss is already in the statistics.
    public var resultRecorded: Bool
    /// How many boards this install has started (used to vary seeded test boards).
    public var boardsStarted: Int
    public var flagMode: Bool
    public var bestTimes: BestTimes

    /// A started board whose result is not yet in the statistics. Abandoning it is a loss.
    public var isInProgress: Bool { game.isStarted && !resultRecorded }

    /// False when the board breaks the rules (a damaged file): a fresh board replaces it, but
    /// the best times are kept.
    public var isPlayable: Bool {
        game.integrityProblems.isEmpty && elapsed.isFinite && elapsed >= 0
    }

    @MainActor
    static func load(from context: GameContext) -> MinesSave? {
        context.saveSlot.load(MinesSave.self)
    }
}

/// Rows shown in the shared Settings screen.
struct MinesSettingsRows: View {
    @ObservedObject var preferences: MinesPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsChoiceRow("Difficulty",
                              detail: "Applies from your next board.",
                              choices: Difficulty.allCases.map { (value: $0, label: $0.name) },
                              selection: $preferences.difficulty,
                              identifier: "minesDifficulty")
            SettingsDivider()
            SettingsToggleRow("Forgive one slip",
                              detail: "The first mine you open on a board can be taken back.",
                              isOn: $preferences.forgiveSlip,
                              identifier: "minesForgive")
            SettingsDivider()
            SettingsToggleRow("Left-handed layout",
                              detail: "Puts the Flag button on the left.",
                              isOn: $preferences.leftHanded,
                              identifier: "minesLeftHanded")
        }
    }
}
