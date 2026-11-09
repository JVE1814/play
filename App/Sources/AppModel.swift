import PlayKit
import SwiftUI

/// A game from the registry, with its id captured for use as a stable identity.
struct RegisteredGame: Identifiable {
    let id: String
    let module: any GameModule

    init(_ module: any GameModule) {
        self.id = module.id
        self.module = module
    }
}

/// App-wide state and services: the game list, which game is open, settings, statistics.
@MainActor
final class AppModel: ObservableObject {
    let options: LaunchOptions
    let storage: Storage
    let settings: AppSettings
    let stats: StatsStore
    let feedback: Feedback
    let games: [RegisteredGame]
    private let defaults: UserDefaults
    private let appState: AppStateStore
    private var contexts: [String: GameContext] = [:]

    /// The game on screen, persisted immediately so a relaunch (even after a force quit)
    /// reopens it.
    @Published var openGameID: String? {
        didSet { appState.openGameID = openGameID }
    }

    /// Settings opens over the game too; the game is told so it can pause its clock.
    @Published var showingSettings = false {
        didSet { contexts.values.forEach { $0.setCovered(showingSettings) } }
    }
    @Published var showingStats = false

    init(options: LaunchOptions = .current, storage: Storage? = nil, defaults: UserDefaults = .standard) {
        let storage = storage ?? Storage(root: Storage.defaultRoot())
        if options.resetState {
            storage.wipe()
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("settings.") || key.hasPrefix("game.") {
                defaults.removeObject(forKey: key)
            }
        }
        self.options = options
        self.storage = storage
        self.defaults = defaults
        let settings = AppSettings(defaults: defaults)
        self.settings = settings
        self.stats = StatsStore(storage: storage)
        self.feedback = Feedback(settings: settings)
        let games = GameRegistry.games(options: options).map(RegisteredGame.init)
        self.games = games
        let appState = AppStateStore(storage: storage)
        self.appState = appState
        let saved = appState.openGameID
        self.openGameID = games.contains { $0.id == saved } ? saved : nil
    }

    var openGame: RegisteredGame? {
        games.first { $0.id == openGameID }
    }

    func open(_ game: RegisteredGame) {
        openGameID = game.id
    }

    func closeGame() {
        openGameID = nil
    }

    /// The single context for a game (created on first use).
    func context(for game: RegisteredGame) -> GameContext {
        if let existing = contexts[game.id] { return existing }
        let context = GameContext(
            gameID: game.id,
            accent: game.module.accent,
            storage: storage,
            stats: stats,
            defaults: defaults,
            feedback: feedback,
            options: options,
            exit: { [weak self] in self?.closeGame() },
            openSettings: { [weak self] in self?.showingSettings = true }
        )
        contexts[game.id] = context
        return context
    }

    var colorScheme: ColorScheme? {
        options.forcedAppearance?.colorScheme ?? settings.appearance.colorScheme
    }
}
