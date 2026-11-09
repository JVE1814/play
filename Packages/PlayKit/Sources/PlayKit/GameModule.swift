import SwiftUI
import UIKit

/// A game in the collection.
///
/// Each game lives in its own Swift package, depends only on PlayKit (plus its own engine),
/// and is listed once in the app's `GameRegistry`. The home screen, settings and statistics
/// screens are driven entirely by this protocol, so adding a game never touches them.
public protocol GameModule {
    /// Stable identifier used for save files, statistics and preferences. Never change it after release.
    var id: String { get }
    /// Name shown on the home screen, e.g. "Solitaire".
    var title: String { get }
    /// One short line under the title.
    var tagline: String { get }
    var accent: Accent { get }

    /// A flat illustration for the home screen tile.
    @MainActor func makeIcon() -> AnyView
    /// The full-screen game, built on `GameScreen`.
    @MainActor func makeGameView(context: GameContext) -> AnyView
    /// Optional rows for the shared Settings screen.
    @MainActor func makeSettingsSection(context: GameContext) -> AnyView?
    /// Optional status for the home tile, such as "In progress · 42 moves".
    @MainActor func statusLine(context: GameContext) -> String?
}

extension GameModule {
    @MainActor public func makeSettingsSection(context: GameContext) -> AnyView? { nil }
    @MainActor public func statusLine(context: GameContext) -> String? { nil }
}

/// Everything a game may use from the app: its save slot, statistics, preferences, feedback,
/// launch options and navigation. One context exists per game per launch.
@MainActor
public final class GameContext: ObservableObject {
    private let gameID: String
    public let accent: Accent
    public let saveSlot: SaveSlot
    public let feedback: Feedback
    public let options: LaunchOptions
    private let stats: StatsStore
    private let preferenceStore: GamePreferences
    private var preferenceSets: [ObjectIdentifier: AnyObject] = [:]
    private let exitAction: () -> Void
    private let settingsAction: () -> Void

    /// True while something the app shows (such as the Settings sheet) covers the game.
    /// `GameScreen` counts a covered game as out of view.
    @Published public private(set) var isCovered = false

    public init(
        gameID: String,
        accent: Accent,
        storage: Storage,
        stats: StatsStore,
        defaults: UserDefaults,
        feedback: Feedback,
        options: LaunchOptions,
        exit: @escaping () -> Void = {},
        openSettings: @escaping () -> Void = {}
    ) {
        self.gameID = gameID
        self.accent = accent
        self.saveSlot = SaveSlot(storage: storage, gameID: gameID)
        self.stats = stats
        self.preferenceStore = GamePreferences(gameID: gameID, defaults: defaults)
        self.feedback = feedback
        self.options = options
        self.exitAction = exit
        self.settingsAction = openSettings
    }

    /// Games leave through `GameSession.leave()`, which lets the session save first.
    func exit() { exitAction() }

    public func openSettings() { settingsAction() }

    /// Called by the app when it covers or uncovers the game.
    public func setCovered(_ covered: Bool) {
        if isCovered != covered { isCovered = covered }
    }

    /// False when Reduce Motion is on or tests disable animation: sessions then skip the
    /// pauses they leave for animations.
    public var animationsEnabled: Bool {
        animates(reduceMotion: UIAccessibility.isReduceMotionEnabled)
    }

    /// The same rule for views, which read Reduce Motion from their environment.
    public func animates(reduceMotion: Bool) -> Bool {
        !reduceMotion && !options.disableAnimations
    }

    public func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    public var gameStats: GameStats { stats.stats(for: gameID) }

    public func recordWin(time: TimeInterval) { stats.recordWin(gameID: gameID, time: time) }
    public func recordLoss() { stats.recordLoss(gameID: gameID) }

    /// The game's own preferences: one instance per game, so the game screen and its settings
    /// rows observe the same object.
    public func preferences<Preferences: GamePreferenceSet>(_ type: Preferences.Type = Preferences.self) -> Preferences {
        let key = ObjectIdentifier(type)
        if let existing = preferenceSets[key] as? Preferences { return existing }
        let created = Preferences(preferences: preferenceStore)
        preferenceSets[key] = created
        return created
    }
}

/// A game's preferences, built on its namespaced `GamePreferences` store.
@MainActor
public protocol GamePreferenceSet: AnyObject {
    init(preferences: GamePreferences)
}
