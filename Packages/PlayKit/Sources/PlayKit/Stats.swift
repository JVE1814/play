import Foundation

/// Statistics kept for every game. A game counts as played once it is won or abandoned
/// (a new deal started after at least one move), so the win rate is always wins ÷ finished games.
public struct GameStats: Codable, Equatable, Sendable {
    public var played = 0
    public var won = 0
    public var currentStreak = 0
    public var bestStreak = 0
    /// Fastest win, in seconds.
    public var bestTime: TimeInterval?

    public init() {}

    public var lost: Int { played - won }

    /// 0...1, or 0 before any game is finished.
    public var winRate: Double { played == 0 ? 0 : Double(won) / Double(played) }

    public mutating func recordWin(time: TimeInterval) {
        played += 1
        won += 1
        currentStreak += 1
        bestStreak = max(bestStreak, currentStreak)
        bestTime = min(bestTime ?? time, time)
    }

    public mutating func recordLoss() {
        played += 1
        currentStreak = 0
    }
}

/// Per-game statistics, persisted after every change.
@MainActor
public final class StatsStore: ObservableObject {
    @Published public private(set) var all: [String: GameStats]
    private let storage: Storage
    private let name = "stats.json"

    public init(storage: Storage) {
        self.storage = storage
        self.all = storage.load([String: GameStats].self, from: name) ?? [:]
    }

    public func stats(for gameID: String) -> GameStats {
        all[gameID] ?? GameStats()
    }

    public func recordWin(gameID: String, time: TimeInterval) {
        update(gameID) { $0.recordWin(time: time) }
    }

    public func recordLoss(gameID: String) {
        update(gameID) { $0.recordLoss() }
    }

    public func reset(gameID: String) {
        all[gameID] = nil
        storage.store(all, to: name)
    }

    private func update(_ gameID: String, _ change: (inout GameStats) -> Void) {
        var stats = all[gameID] ?? GameStats()
        change(&stats)
        all[gameID] = stats
        storage.store(all, to: name)
    }
}
