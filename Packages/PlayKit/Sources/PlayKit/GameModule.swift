import SwiftUI

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
    /// The game's own accent colour, from the shared palette.
    var accent: Accent { get }

    /// A flat illustration for the home screen tile.
    @MainActor func makeIcon() -> AnyView
    /// The full-screen game. Call `context.exit()` to return home.
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

/// Everything a game may use from the app: its save slot, statistics, preferences,
/// shared settings, feedback and navigation. One context exists per game per launch.
@MainActor
public final class GameContext: ObservableObject {
    public let gameID: String
    public let accent: Accent
    public let saveSlot: SaveSlot
    public let stats: StatsStore
    public let settings: AppSettings
    public let preferences: GamePreferences
    public let feedback: Feedback
    public let options: LaunchOptions
    private let exitAction: () -> Void
    private let settingsAction: () -> Void
    private var sharedObjects: [ObjectIdentifier: AnyObject] = [:]

    /// True while something the app shows (such as the Settings sheet) covers the game. Games
    /// with a clock pause it, as they do when the app goes to the background.
    @Published public private(set) var isCovered = false

    public init(
        gameID: String,
        accent: Accent,
        storage: Storage,
        stats: StatsStore,
        settings: AppSettings,
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
        self.settings = settings
        self.preferences = GamePreferences(gameID: gameID, defaults: defaults)
        self.feedback = feedback
        self.options = options
        self.exitAction = exit
        self.settingsAction = openSettings
    }

    /// Return to the home screen.
    public func exit() { exitAction() }

    /// Show the shared Settings screen.
    public func openSettings() { settingsAction() }

    /// Called by the app when it covers or uncovers the game.
    public func setCovered(_ covered: Bool) {
        if isCovered != covered { isCovered = covered }
    }

    /// This game's statistics.
    public var gameStats: GameStats { stats.stats(for: gameID) }

    /// One shared instance of `T` per game, so the game screen and its settings rows observe
    /// the same object.
    public func shared<T: AnyObject>(_ type: T.Type = T.self, make: () -> T) -> T {
        let key = ObjectIdentifier(type)
        if let existing = sharedObjects[key] as? T { return existing }
        let created = make()
        sharedObjects[key] = created
        return created
    }
}
