import Bubbles
import PlayKit
import Solitaire
#if DEBUG
import TestGame
#endif

/// The list of games in the app, in home screen order.
///
/// To add a game: create its package under `Games/`, add it to `project.yml`, and add one
/// line here. Nothing else (home, settings, statistics, save/resume) needs to change.
enum GameRegistry {
    static func games(options: LaunchOptions) -> [any GameModule] {
        var games: [any GameModule] = [
            SolitaireModule(),
            BubblesModule(),
        ]
        #if DEBUG
        // Test-only placeholder, never compiled into release builds.
        if options.includeTestGames { games.append(TestGameModule()) }
        #endif
        return games
    }
}
