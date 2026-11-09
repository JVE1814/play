import KlondikeEngine
import PlayKit

/// Which deal comes next.
enum Deals {
    /// Deals are random unless `-seed N` is given, when deal number `number` is dealt from
    /// `N + number`. With `-scenario`, the first deal is that prepared position (for UI tests
    /// and screenshots).
    static func game(number: Int, options: LaunchOptions, drawMode: DrawMode) -> KlondikeGame {
        let seed = options.value(after: "-seed").flatMap { UInt64($0) }
        if number == 0, let scenario = options.scenario {
            switch scenario {
            case "nearWin":
                return KlondikeFixtures.nearlyWon(seed: seed ?? 1, drawMode: drawMode)
            case "midGame":
                var game = KlondikeGame(seed: seed ?? 1, drawMode: drawMode)
                for _ in 0..<12 {
                    guard let move = game.hint() else { break }
                    game.perform(move)
                }
                return game
            default:
                break
            }
        }
        return KlondikeGame(seed: seed.map { $0 &+ UInt64(number) } ?? UInt64.random(in: 1...UInt64.max),
                            drawMode: drawMode)
    }
}
