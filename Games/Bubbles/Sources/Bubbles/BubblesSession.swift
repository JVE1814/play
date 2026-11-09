import BubbleEngine
import Foundation
import PlayKit
import UIKit

/// The level in progress: wraps the engine with aiming, shot animation, progress, statistics
/// and saving. The view layer only calls these methods.
@MainActor
public final class BubblesSession: ObservableObject {
    /// A bubble on its way to the grid.
    public struct Flight: Equatable {
        public let path: [Point]
        public let color: BubbleColor
        public let start: Date
        public let duration: TimeInterval
    }

    /// A bubble leaving the grid: popping in place or falling away.
    public struct Effect: Identifiable, Equatable {
        public enum Kind: Equatable { case pop, fall }
        public let id = UUID()
        public let cell: Cell
        public let bubble: Bubble
        public let kind: Kind
        public let delay: Double
    }

    @Published public private(set) var game: BubbleGame
    @Published public private(set) var progress: BubblesProgress
    /// The direction being aimed, in grid units (nil when not aiming).
    @Published public private(set) var aim: Point? = nil
    @Published public private(set) var flight: Flight? = nil
    @Published public private(set) var effects: [Effect] = []
    @Published public private(set) var showsResult: Bool
    @Published public var showingLevels = false
    @Published public var confirmingRestart = false

    public let context: GameContext
    public let preferences: BubblesPreferences
    /// Set by the view: false when Reduce Motion is on or tests disable animation.
    public var animationsEnabled = true

    private var attempt: Int
    private var resultRecorded: Bool
    private var elapsedBeforeRun: TimeInterval
    private var runStartedAt: Date?
    private var isOnScreen = false
    private var pending: (game: BubbleGame, outcome: ShotOutcome)?
    private var flightTask: Task<Void, Never>?
    private var effectsTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    /// Aim angle used by VoiceOver's adjustable launcher, in degrees (90 = straight up).
    private var spokenAngle = 90.0

    /// Shots travel this many bubble diameters per second.
    static let shotSpeed = 34.0

    public init(context: GameContext) {
        self.context = context
        self.preferences = BubblesPreferences.shared(in: context)
        let initial: BubbleGame
        if let save = context.saveSlot.load(BubblesSave.self) {
            initial = save.game
            progress = save.progress
            attempt = save.attempt
            elapsedBeforeRun = save.elapsed
            resultRecorded = save.resultRecorded
        } else {
            let options = context.options
            let start = min(LevelCatalog.count, max(1, options.level ?? 1))
            progress = BubblesProgress(unlocked: start)
            attempt = 0
            elapsedBeforeRun = 0
            resultRecorded = false
            initial = BubblesSession.scenarioGame(options.scenario) ?? BubbleGame(level: LevelCatalog.level(start))
        }
        game = initial
        showsResult = initial.isOver
        if let demo = context.options.demoAim { aim = Point(demo, -1) }
        save()
    }

    /// Prepared positions for UI tests and screenshots.
    static func scenarioGame(_ scenario: String?) -> BubbleGame? {
        switch scenario {
        case "bubblesNearWin":
            // Two reds at the top: one shot straight up makes three and clears the board.
            return BubbleGame(grid: BubbleGrid(rows: ["...rr..."]), palette: [.red, .blue], shotLimit: 5, par: 1,
                              seed: 1, levelNumber: 1, current: .red, next: .red)
        case "bubblesLastShot":
            return BubbleGame(grid: BubbleGrid(rows: ["yybbyybb", "bbyybbyy", "yybbyybb"]),
                              palette: [.red, .yellow, .blue], shotLimit: 1, par: 1, seed: 1, levelNumber: 1,
                              current: .red, next: .yellow)
        default:
            return nil
        }
    }

    // MARK: State for the view

    public var level: Int { game.levelNumber }
    public var isPlaying: Bool { game.status == .playing && flight == nil }

    /// Where the current aim would land, for the guide.
    public var aimTrace: ShotTrace? {
        guard isPlaying, let aim else { return nil }
        return game.trace(direction: aim)
    }

    public func elapsed(at date: Date = Date()) -> TimeInterval {
        elapsedBeforeRun + (runStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    /// Whole state, for UI tests.
    public var signature: String { game.signature + "|attempt:\(attempt)|unlocked:\(progress.unlocked)" }

    // MARK: Lifecycle

    public func setOnScreen(_ visible: Bool) {
        isOnScreen = visible
        updateClock()
        save()
    }

    public func leave() {
        setOnScreen(false)
        context.exit()
    }

    // MARK: Aiming and shooting

    /// Updates the aim (nil cancels it).
    public func setAim(_ direction: Point?) {
        guard isPlaying else { return }
        aim = direction
    }

    /// Fires along the current aim, if any.
    public func fire() {
        guard isPlaying, let direction = aim else { return }
        aim = nil
        var next = game
        guard let outcome = next.shoot(direction: direction) else {
            context.feedback.play(.invalid)
            return
        }
        pending = (next, outcome)
        updateClock()
        let length = zip(outcome.trace.path, outcome.trace.path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        guard animationsEnabled else {
            commit()
            return
        }
        let duration = max(0.12, length / Self.shotSpeed)
        flight = Flight(path: outcome.trace.path, color: outcome.color, start: Date(), duration: duration)
        context.feedback.play(.tap)
        flightTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.commit()
        }
    }

    /// Lands the shot in flight: updates the grid, starts the pop and fall effects, and ends the
    /// attempt if it is won or lost.
    private func commit() {
        guard let shot = pending else { return }
        let next = shot.game
        let outcome = shot.outcome
        pending = nil
        flight = nil
        let before = game.grid
        game = next
        let result = outcome.result
        if animationsEnabled && result.clearedCount > 0 {
            var added: [Effect] = []
            let popped = (result.popped + result.exploded).sorted()
            for (i, cell) in popped.enumerated() {
                let bubble = result.removed[cell] ?? before[cell] ?? .color(outcome.color)
                added.append(Effect(cell: cell, bubble: bubble, kind: .pop, delay: Double(i) * 0.025))
            }
            for cell in result.dropped.sorted() {
                guard let bubble = result.removed[cell] else { continue }
                added.append(Effect(cell: cell, bubble: bubble, kind: .fall, delay: 0.08))
            }
            effects = added
            effectsTask?.cancel()
            effectsTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled else { return }
                self?.effects = []
            }
        }
        context.feedback.play(result.clearedCount > 0 ? .draw : .place)
        if result.clearedCount > 0 { announce(describe(result)) }
        if game.isOver { finishAttempt() }
        updateClock()
        save()
    }

    private func finishAttempt() {
        updateClock()
        guard !resultRecorded else { return }
        resultRecorded = true
        if game.status == .won {
            progress.recordClear(level: game.levelNumber, stars: game.stars)
            context.stats.recordWin(gameID: context.gameID, time: elapsedBeforeRun, moves: game.shotsFired)
            context.feedback.play(.win)
            announce("Level \(game.levelNumber) cleared with \(game.stars) star\(game.stars == 1 ? "" : "s").")
        } else {
            context.stats.recordLoss(gameID: context.gameID)
            context.feedback.play(.invalid)
            announce(game.status == .reachedLine ? "The bubbles reached the line." : "Out of shots.")
        }
        guard animationsEnabled else {
            showsResult = true
            return
        }
        resultTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled, let self, self.game.isOver else { return }
            self.showsResult = true
        }
    }

    public func swap() {
        guard isPlaying, game.current != game.next else { return }
        game.swap()
        context.feedback.play(.tap)
        save()
        announce("Now \(game.current.spokenName). Next \(game.next.spokenName).")
    }

    // MARK: Levels

    /// Starts a fresh attempt at `level` (if unlocked). Leaving a level unfinished is not a loss.
    public func start(level: Int) {
        guard progress.isUnlocked(level) else { return }
        flightTask?.cancel()
        resultTask?.cancel()
        pending = nil
        flight = nil
        effects = []
        aim = nil
        attempt += 1
        game = BubbleGame(level: LevelCatalog.level(level), attempt: attempt)
        elapsedBeforeRun = 0
        runStartedAt = nil
        resultRecorded = false
        showsResult = false
        confirmingRestart = false
        showingLevels = false
        updateClock()
        save()
        context.feedback.play(.draw)
        announce("Level \(level). \(game.shotsLeft) shots.")
    }

    public func retry() { start(level: max(1, game.levelNumber)) }

    /// Restart from the toolbar: asks first if shots have been fired.
    public func requestRestart() {
        if game.status == .playing && game.shotsFired > 0 {
            confirmingRestart = true
        } else {
            retry()
        }
    }

    public var hasNextLevel: Bool { game.levelNumber < LevelCatalog.count }

    public func nextLevel() {
        start(level: min(LevelCatalog.count, game.levelNumber + 1))
    }

    // MARK: VoiceOver aiming

    /// Rotates the aim in 5° steps (positive = to the right).
    public func adjustSpokenAim(by degrees: Double) {
        guard isPlaying else { return }
        spokenAngle = min(170, max(10, spokenAngle - degrees))
        let radians = spokenAngle * .pi / 180
        aim = Point(cos(radians), -sin(radians))
    }

    /// Fires along the VoiceOver aim (straight up if none is set).
    public func fireSpokenAim() {
        if aim == nil { adjustSpokenAim(by: 0) }
        fire()
    }

    /// Plain description of the aim, for VoiceOver.
    public var spokenAim: String {
        guard let aim, let trace = aimTrace else { return "Not aiming. Swipe up or down to aim." }
        let degrees = Int((atan2(-aim.y, aim.x) * 180 / .pi).rounded())
        let direction: String
        switch degrees {
        case 88...92: direction = "straight up"
        case ..<88: direction = "\(90 - degrees) degrees right"
        default: direction = "\(degrees - 90) degrees left"
        }
        let bounces = trace.path.count - 2
        let touching = BubbleGrid.neighbors(of: trace.cell).compactMap { game.grid[$0] }
        let next = touching.first.map { ", next to \($0.spokenName)" } ?? (trace.cell.row == 0 ? ", at the top" : "")
        let bounce = bounces > 0 ? ", \(bounces) bounce\(bounces == 1 ? "" : "s")" : ""
        return "Aiming \(direction)\(bounce). Lands in row \(trace.cell.row + 1)\(next)."
    }

    // MARK: Internals

    private func updateClock(now: Date = Date()) {
        let started = game.shotsFired > 0 || elapsedBeforeRun > 0 || pending != nil
        let shouldRun = isOnScreen && started && !game.isOver
        if shouldRun, runStartedAt == nil {
            runStartedAt = now
        } else if !shouldRun, let start = runStartedAt {
            elapsedBeforeRun += max(0, now.timeIntervalSince(start))
            runStartedAt = nil
        }
    }

    private func save() {
        context.saveSlot.save(BubblesSave(progress: progress, game: game, attempt: attempt, elapsed: elapsed(),
                                          resultRecorded: resultRecorded))
    }

    private func describe(_ result: ShotResult) -> String {
        var parts: [String] = []
        let popped = result.popped.count + result.exploded.count
        if popped > 0 { parts.append("\(popped) popped") }
        if !result.dropped.isEmpty { parts.append("\(result.dropped.count) dropped") }
        return parts.joined(separator: ", ") + ". \(game.grid.count) left."
    }

    private func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
