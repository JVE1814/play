import BubbleEngine
import Foundation
import PlayKit

/// The level in progress: wraps the engine with aiming, shot animation, progress, statistics
/// and saving. The view layer only calls these methods.
@MainActor
public final class BubblesSession: ObservableObject, LevelSession {
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
    @Published public private(set) var progress: LevelProgress
    /// The direction being aimed, in grid units (nil when not aiming).
    @Published public private(set) var aim: Point? = nil
    @Published public private(set) var flight: Flight? = nil
    @Published public private(set) var effects: [Effect] = []
    @Published public private(set) var showsResult: Bool
    @Published public var showingLevels = false
    @Published public var confirmingRestart = false

    public let context: GameContext

    private var attempt: Int
    private var resultRecorded: Bool
    private var clock: PlayClock
    private var inView = false
    /// The shot in flight: the game as it will be once the bubble lands.
    private var pending: (game: BubbleGame, outcome: ShotOutcome)?
    private let landing = Pending()
    private let effectsEnd = Pending()
    private let resultReveal = Pending()
    /// Aim angle used by VoiceOver's adjustable launcher, in degrees (90 = straight up). It is
    /// kept between shots.
    private var spokenAngle = 90.0

    /// Shots travel this many bubble diameters per second.
    static let shotSpeed = 34.0

    public init(context: GameContext) {
        self.context = context
        let initial: BubbleGame
        if let save = context.saveSlot.load(BubblesSave.self) {
            initial = save.game
            progress = save.progress
            attempt = save.attempt
            clock = PlayClock(elapsed: save.elapsed)
            resultRecorded = save.resultRecorded
        } else {
            let start = context.options.startLevel(of: LevelCatalog.count)
            progress = LevelProgress(unlocked: start)
            attempt = 0
            clock = PlayClock()
            resultRecorded = false
            initial = Scenarios.game(context.options.scenario) ?? BubbleGame(level: LevelCatalog.level(start))
        }
        game = initial
        showsResult = initial.isOver
        // `-demoAim X`: a fixed aim for screenshots (X is the horizontal offset per unit up).
        if let demo = context.options.value(after: "-demoAim").flatMap({ Double($0) }) { aim = Point(demo, -1) }
        commit()
    }

    // MARK: State for the view

    public var levelNumber: Int { game.levelNumber }
    public var levelCount: Int { LevelCatalog.count }
    public var hasAttemptInProgress: Bool { game.status == .playing && game.shotsFired > 0 }
    public var isPlaying: Bool { game.status == .playing && flight == nil }
    public var canSwap: Bool { isPlaying && game.current != game.next }

    /// Where the current aim would land, for the guide.
    public var aimTrace: ShotTrace? {
        guard isPlaying, let aim else { return nil }
        return game.trace(direction: aim)
    }

    /// Whole state, for UI tests.
    public var signature: String { game.signature + "|attempt:\(attempt)|unlocked:\(progress.unlocked)" }

    public func setInView(_ inView: Bool) {
        self.inView = inView
        commit()
    }

    // MARK: Aiming and shooting

    /// Nil cancels the aim.
    public func setAim(_ direction: Point?) {
        guard isPlaying else { return }
        aim = direction
    }

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
        guard context.animationsEnabled else {
            land()
            return
        }
        let path = outcome.trace.path
        let duration = max(0.12, path.pathLength / Self.shotSpeed)
        flight = Flight(path: path, color: outcome.color, start: Date(), duration: duration)
        context.feedback.play(.tap)
        landing.schedule(after: duration) { [weak self] in self?.land() }
    }

    private func land() {
        guard let shot = pending else { return }
        pending = nil
        flight = nil
        game = shot.game
        let result = shot.outcome.result
        if context.animationsEnabled && result.clearedCount > 0 {
            let pops = (result.popped + result.exploded).sorted().enumerated().compactMap { index, cell in
                result.removed[cell].map { Effect(cell: cell, bubble: $0, kind: .pop, delay: Double(index) * 0.025) }
            }
            let falls = result.dropped.sorted().compactMap { cell in
                result.removed[cell].map { Effect(cell: cell, bubble: $0, kind: .fall, delay: 0.08) }
            }
            effects = pops + falls
            effectsEnd.schedule(after: 0.9) { [weak self] in self?.effects = [] }
        }
        context.feedback.play(result.clearedCount > 0 ? .draw : .place)
        if result.clearedCount > 0 { context.announce(describe(result)) }
        if game.isOver { finishAttempt() }
        commit()
    }

    private func finishAttempt() {
        guard !resultRecorded else { return }
        resultRecorded = true
        if game.status == .won {
            progress.record(level: game.levelNumber, stars: game.stars, of: LevelCatalog.count)
            context.recordWin(time: clock.elapsed())
            context.feedback.play(.win)
        } else {
            context.recordLoss()
            context.feedback.play(.invalid)
        }
        context.announce(game.ending.spoken)
        // The pops and falls play out before the panel covers them.
        resultReveal.schedule(after: context.animationsEnabled ? 0.65 : 0) { [weak self] in
            self?.showsResult = true
        }
    }

    public func swap() {
        guard canSwap else { return }
        game.swap()
        context.feedback.play(.tap)
        commit()
        context.announce("Now \(game.current.spokenName). Next \(game.next.spokenName).")
    }

    // MARK: Levels

    /// Leaving a level unfinished is not a loss.
    public func start(level: Int) {
        guard progress.isUnlocked(level) else { return }
        landing.cancel()
        effectsEnd.cancel()
        resultReveal.cancel()
        pending = nil
        flight = nil
        effects = []
        aim = nil
        attempt += 1
        game = BubbleGame(level: LevelCatalog.level(level), attempt: attempt)
        clock = PlayClock()
        resultRecorded = false
        showsResult = false
        confirmingRestart = false
        showingLevels = false
        commit()
        context.feedback.play(.draw)
        context.announce("Level \(level). \(Format.count(game.shotsLeft, "shot")).")
    }

    // MARK: VoiceOver aiming

    /// Positive `degrees` turn the aim to the right.
    public func adjustSpokenAim(by degrees: Double) {
        guard isPlaying else { return }
        spokenAngle = min(170, max(10, spokenAngle - degrees))
        let radians = spokenAngle * .pi / 180
        aim = Point(cos(radians), -sin(radians))
    }

    /// Fires along the VoiceOver aim (where it was left, or straight up).
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
        let bounce = bounces > 0 ? ", \(Format.count(bounces, "bounce"))" : ""
        return "Aiming \(direction)\(bounce). Lands in row \(trace.cell.row + 1)\(next)."
    }

    // MARK: Internals

    /// The statistics clock runs from the first shot while the level is in view.
    private func updateClock() {
        let started = game.shotsFired > 0 || clock.hasStarted || pending != nil
        clock.setRunning(inView && started && !game.isOver)
    }

    /// Called after every change.
    private func commit() {
        updateClock()
        context.saveSlot.save(BubblesSave(progress: progress, game: game, attempt: attempt, elapsed: clock.elapsed(),
                                          resultRecorded: resultRecorded))
    }

    private func describe(_ result: ShotResult) -> String {
        var parts: [String] = []
        let popped = result.popped.count + result.exploded.count
        if popped > 0 { parts.append("\(popped) popped") }
        if !result.dropped.isEmpty { parts.append("\(result.dropped.count) dropped") }
        return parts.joined(separator: ", ") + ". \(game.grid.count) left."
    }
}
