import KlondikeEngine
import PlayKit
import SwiftUI

/// Klondike Solitaire, registered in the app's `GameRegistry`.
public struct SolitaireModule: GameModule {
    public init() {}

    public var id: String { "klondike" }
    public var title: String { "Solitaire" }
    public var tagline: String { "Classic Klondike, made for one thumb" }
    public var accent: Accent { .jade }

    @MainActor public func makeIcon() -> AnyView {
        AnyView(SolitaireIcon())
    }

    @MainActor public func makeGameView(context: GameContext) -> AnyView {
        AnyView(SolitaireScreen(context: context))
    }

    @MainActor public func makeSettingsSection(context: GameContext) -> AnyView? {
        AnyView(SolitaireSettingsRows(preferences: SolitairePreferences.shared(in: context)))
    }

    @MainActor public func statusLine(context: GameContext) -> String? {
        if let save = context.saveSlot.load(SolitaireSave.self), save.game.moveCount > 0, !save.game.isWon {
            let moves = save.game.moveCount == 1 ? "1 move" : "\(save.game.moveCount) moves"
            return "Resume · \(moves) · \(Format.clock(save.elapsed))"
        }
        let stats = context.gameStats
        if stats.played > 0 {
            return "\(stats.won) won · \(Format.percent(stats.winRate)) win rate"
        }
        return nil
    }
}

/// Solitaire's own preferences, shared by the game screen and its settings rows.
@MainActor
public final class SolitairePreferences: ObservableObject {
    private let store: GamePreferences

    /// Draw 1 by default. Takes effect from the next deal.
    @Published public var drawMode: DrawMode {
        didSet { store.set(drawMode.rawValue, for: "drawMode") }
    }

    /// Mirror the stock, waste and toolbar for left-thumb play.
    @Published public var leftHanded: Bool {
        didSet { store.set(leftHanded, for: "leftHanded") }
    }

    public init(preferences: GamePreferences) {
        store = preferences
        drawMode = DrawMode(rawValue: preferences.int("drawMode", default: DrawMode.one.rawValue)) ?? .one
        leftHanded = preferences.bool("leftHanded", default: false)
    }

    public static func shared(in context: GameContext) -> SolitairePreferences {
        context.shared(SolitairePreferences.self) { SolitairePreferences(preferences: context.preferences) }
    }
}

/// What is written to disk after every move.
public struct SolitaireSave: Codable, Equatable {
    public var version = 1
    public var game: KlondikeGame
    /// Seconds of play so far.
    public var elapsed: TimeInterval
    /// Whether this game's win or loss is already in the statistics.
    public var resultRecorded: Bool
    /// How many deals this install has started (used to vary seeded test deals).
    public var dealsStarted: Int

    public init(game: KlondikeGame, elapsed: TimeInterval, resultRecorded: Bool, dealsStarted: Int) {
        self.game = game
        self.elapsed = elapsed
        self.resultRecorded = resultRecorded
        self.dealsStarted = dealsStarted
    }
}
