import Foundation
import MinesEngine
import PlayKit

/// The board in progress: wraps the rules engine with the clock, statistics, saving, flag
/// mode and feedback. The view layer only calls these methods.
@MainActor
public final class MinesSession: ObservableObject, GameSession {
    /// The squares the latest move opened and the square it started from, for the ripple.
    public struct Opening: Equatable {
        public let origin: Int
        public let cells: CellSet
    }

    @Published public private(set) var game: MinesGame
    /// The slip question or the result panel is up.
    @Published public private(set) var showsResult: Bool
    @Published public private(set) var toast: String? = nil
    /// Increments each time a tap on a square did nothing (drives a small shake).
    @Published public private(set) var rejections: [Int: Int] = [:]
    @Published public private(set) var lastOpening: Opening? = nil
    /// Taps flag instead of open while this is on.
    @Published public private(set) var flagMode: Bool
    /// The last win was the fastest at its difficulty.
    @Published public private(set) var isNewBest = false
    @Published public var confirmingNewBoard = false

    public let context: GameContext
    public let preferences: MinesPreferences
    public private(set) var bestTimes: BestTimes

    private var resultRecorded: Bool
    private var clock: PlayClock
    private var inView = false
    private var boardsStarted: Int
    private let toastTimer = Pending()
    private let resultReveal = Pending()

    public init(context: GameContext) {
        self.context = context
        let preferences = context.preferences(MinesPreferences.self)
        self.preferences = preferences
        let saved = MinesSave.load(from: context)
        let playable = saved.flatMap { $0.isPlayable ? $0 : nil }
        let initial = playable?.game ?? Scenarios.game(context.options.scenario)
            ?? Self.board(number: 0, options: context.options, difficulty: preferences.difficulty)
        game = initial
        clock = PlayClock(elapsed: playable?.elapsed ?? 0)
        resultRecorded = playable?.resultRecorded ?? false
        flagMode = playable?.flagMode ?? false
        boardsStarted = saved?.boardsStarted ?? 1
        bestTimes = saved?.bestTimes ?? BestTimes()
        showsResult = initial.status == .slipped || initial.isFinished
        if initial.isFinished && !(playable?.resultRecorded ?? false) { record(quietly: true) }
        adoptDifficultyIfUntouched()
        commit()
    }

    // MARK: State for the view

    public var isInProgress: Bool { game.isStarted && !resultRecorded }
    private var forgiving: Bool { preferences.forgiveSlip }

    public func elapsed(at date: Date = Date()) -> TimeInterval {
        clock.elapsed(at: date)
    }

    /// Board description for UI tests.
    public var signature: String { game.signature + (flagMode ? "|flagMode" : "") }

    // MARK: Lifecycle

    public func setInView(_ inView: Bool) {
        self.inView = inView
        // Coming back from Settings: a board not yet started takes the difficulty chosen there.
        if inView { adoptDifficultyIfUntouched() }
        commit()
    }

    // MARK: Player actions

    /// A tap on a square: opens it, flags it in flag mode, or on an open number whose flags
    /// match it, opens the squares around it. On a finished board it brings the result back.
    public func tap(_ cell: Int) {
        switch game.status {
        case .won, .lost:
            if !showsResult { showsResult = true }
            return
        case .slipped:
            return
        case .fresh, .playing:
            break
        }
        if game.opened.contains(cell) {
            if game.canChord(cell) {
                apply(from: cell) { $0.chord(cell, forgiving: self.forgiving) }
            } else if case .number(let n) = game.cellState(cell), n > 0 {
                reject(cell)
            }
        } else if flagMode {
            toggleFlag(cell)
        } else if game.flagged.contains(cell) {
            reject(cell)
        } else {
            apply(from: cell) { $0.open(cell, forgiving: self.forgiving) }
        }
    }

    /// A long press flags or unflags a covered square, whatever the mode.
    public func longPress(_ cell: Int) {
        guard game.status == .fresh || game.status == .playing else { return }
        toggleFlag(cell)
    }

    /// Open around a number (VoiceOver offers it as an action).
    public func openAround(_ cell: Int) {
        guard game.canChord(cell) else { return reject(cell) }
        apply(from: cell) { $0.chord(cell, forgiving: self.forgiving) }
    }

    /// Open a square even in flag mode (VoiceOver offers it as an action).
    public func open(_ cell: Int) {
        guard game.status == .fresh || game.status == .playing, !game.flagged.contains(cell) else { return reject(cell) }
        apply(from: cell) { $0.open(cell, forgiving: self.forgiving) }
    }

    public func toggleFlagMode() {
        flagMode.toggle()
        context.feedback.play(.tap)
        context.announce(flagMode ? "Flag mode on" : "Flag mode off")
        commit()
    }

    public func takeBack() {
        guard game.status == .slipped else { return }
        var next = game
        guard next.takeBack() else { return }
        game = next
        resultReveal.cancel()
        showsResult = false
        context.feedback.play(.tap)
        context.announce("Taken back. That was your one take-back on this board.")
        commit()
    }

    public func endBoard() {
        var next = game
        guard next.endBoard() else { return }
        game = next
        record(quietly: true)
        commit()
    }

    /// Put the result aside to look at the board. A tap on the board brings it back.
    public func seeBoard() {
        guard game.isFinished else { return }
        showsResult = false
    }

    /// Ask for a new board; confirms first if the current one would count as a loss.
    public func requestNewBoard() {
        if isInProgress {
            confirmingNewBoard = true
        } else {
            startNewBoard()
        }
    }

    public func startNewBoard() {
        resultReveal.cancel()
        if isInProgress { context.recordLoss() }
        game = Self.board(number: boardsStarted, options: context.options, difficulty: preferences.difficulty)
        boardsStarted += 1
        clock = PlayClock()
        resultRecorded = false
        showsResult = false
        isNewBest = false
        confirmingNewBoard = false
        lastOpening = nil
        rejections = [:]
        commit()
        context.feedback.play(.draw)
        context.announce("New \(game.difficulty.name) board")
    }

    // MARK: Internals

    /// Boards are random unless `-seed N` is given, when board number `number` is laid from `N + number`.
    static func board(number: Int, options: LaunchOptions, difficulty: Difficulty) -> MinesGame {
        let seed = options.value(after: "-seed").flatMap { UInt64($0) }
        return MinesGame(seed: seed.map { $0 &+ UInt64(number) } ?? UInt64.random(in: 1...UInt64.max),
                         difficulty: difficulty)
    }

    private func adoptDifficultyIfUntouched() {
        guard game.status == .fresh, game.difficulty != preferences.difficulty else { return }
        game = MinesGame(seed: game.seed, difficulty: preferences.difficulty)
    }

    private func apply(from cell: Int, _ action: (inout MinesGame) -> MinesGame.Outcome?) {
        var next = game
        guard let outcome = action(&next) else { return reject(cell) }
        game = next
        switch outcome {
        case .opened(let cells):
            lastOpening = Opening(origin: cell, cells: cells)
            context.feedback.play(.tap)
            context.announce(describeOpening(cells))
        case .won(let cells):
            lastOpening = Opening(origin: cell, cells: cells)
            record()
        case .slipped:
            context.feedback.play(.crash)
            context.announce("That was a mine. Take it back, or end the board.")
            reveal()
        case .lost:
            record()
        }
        commit()
    }

    private func toggleFlag(_ cell: Int) {
        guard game.status == .playing else {
            if game.status == .fresh { showToast("Open a square first") }
            return
        }
        var next = game
        guard next.toggleFlag(cell) else { return reject(cell) }
        game = next
        context.feedback.play(.place)
        let flagged = game.flagged.contains(cell)
        context.announce(flagged ? "Flagged, \(Format.count(game.minesLeft, "mine")) left" : "Flag removed")
        commit()
    }

    /// Puts a finished board's result in the statistics, once. `quietly` plays no sound: after
    /// a slip the mine has already sounded, and at launch nothing just happened.
    private func record(quietly: Bool = false) {
        guard !resultRecorded, game.isFinished else { return }
        resultRecorded = true
        let time = clock.elapsed()
        if game.status == .won {
            context.recordWin(time: time)
            let best = bestTimes[game.difficulty]
            isNewBest = best.map { time < $0 } ?? true
            if isNewBest { bestTimes[game.difficulty] = time }
            if !quietly { context.feedback.play(.win) }
            context.announce("Board cleared! Time \(Format.spokenDuration(time)).")
        } else {
            context.recordLoss()
            if !quietly { context.feedback.play(.crash) }
            context.announce("Board lost.")
        }
        reveal()
    }

    /// The panel comes up once the square that decided it has been seen.
    private func reveal() {
        resultReveal.schedule(after: context.animationsEnabled ? 0.45 : 0) { [weak self] in
            self?.showsResult = true
        }
    }

    private func reject(_ cell: Int) {
        rejections[cell, default: 0] += 1
        context.feedback.play(.invalid)
    }

    private var save: MinesSave {
        MinesSave(game: game, elapsed: clock.elapsed(), resultRecorded: resultRecorded,
                  boardsStarted: boardsStarted, flagMode: flagMode, bestTimes: bestTimes)
    }

    /// After every change: the clock runs while a started board is in view and not waiting on
    /// the slip question, and the board is saved.
    private func commit() {
        clock.setRunning(inView && game.status == .playing)
        context.saveSlot.save(save)
    }

    private func showToast(_ text: String) {
        toast = text
        context.announce(text)
        toastTimer.schedule(after: 3) { [weak self] in self?.toast = nil }
    }

    private func describeOpening(_ cells: CellSet) -> String {
        if cells.count == 1, let cell = cells.first, case .number(let n) = game.cellState(cell) {
            return n == 0 ? "No mines around" : "\(Format.count(n, "mine")) around"
        }
        return "Opened \(Format.count(cells.count, "square"))"
    }
}
