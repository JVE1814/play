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

    /// The context `module`'s game would get if the app had been launched with `arguments`.
    /// Animations are off unless asked for, so sessions act at once instead of after a pause.
    func context(for module: any GameModule, arguments: [String] = [], animated: Bool = false) -> GameContext {
        GameContext(gameID: module.id, accent: module.accent, storage: storage, stats: stats, defaults: defaults,
                    feedback: feedback,
                    options: Self.options(arguments + (animated ? [] : ["-disableAnimations"])))
    }

    /// Options as if the app had been launched with these arguments (debug builds only).
    static func options(_ arguments: [String]) -> LaunchOptions {
        LaunchOptions(arguments: ["app"] + arguments)
    }
}
