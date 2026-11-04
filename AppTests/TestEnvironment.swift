import Foundation
import PlayKit

/// An isolated storage folder and defaults suite per test, so tests never touch real data.
@MainActor
struct TestEnvironment {
    let storage: Storage
    let defaults: UserDefaults
    let settings: AppSettings
    let stats: StatsStore
    let feedback: Feedback

    init() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BetweenStopsTests-\(UUID().uuidString)")
        storage = Storage(root: root)
        let suite = "tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settings = AppSettings(defaults: defaults)
        stats = StatsStore(storage: storage)
        feedback = Feedback(settings: settings)
    }

    func context(gameID: String = "klondike", accent: Accent = .jade, options: LaunchOptions = LaunchOptions()) -> GameContext {
        GameContext(gameID: gameID, accent: accent, storage: storage, stats: stats, settings: settings,
                    defaults: defaults, feedback: feedback, options: options)
    }

    /// Options as if the app had been launched with these arguments (debug builds only).
    static func options(_ arguments: [String]) -> LaunchOptions {
        LaunchOptions(arguments: ["app"] + arguments)
    }
}
