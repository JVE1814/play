import Foundation
import KlondikeEngine
import PlayKit
import UIKit

/// The game in progress: wraps the rules engine with the timer, statistics, saving,
/// hints, auto-finish and feedback. The view layer only calls these methods.
@MainActor
public final class SolitaireSession: ObservableObject {
    @Published public private(set) var game: KlondikeGame
    /// The move currently suggested by Hint, if any.
    @Published public private(set) var hint: Move? = nil
    @Published public private(set) var toast: String? = nil
    @Published public private(set) var showsWin: Bool
    @Published public private(set) var isAutoFinishing = false
    /// Cards moved by the latest move (drawn above the others while they travel).
    @Published public private(set) var recentlyMoved: Set<Card> = []
    /// Increments each time a tap on a card had no legal move (drives a small shake).
    @Published public private(set) var rejections: [Card: Int] = [:]
    @Published public var confirmingNewGame = false

    public let context: GameContext
    public let preferences: SolitairePreferences
    /// Set by the view: false when Reduce Motion is on or tests disable animation.
    public var animationsEnabled = true

    private var resultRecorded: Bool
    private var elapsedBeforeRun: TimeInterval
    private var runStartedAt: Date?
    private var isOnScreen = false
    private var dealsStarted: Int
    private var toastTask: Task<Void, Never>?
    private var autoFinishTask: Task<Void, Never>?
    private var winTask: Task<Void, Never>?

    public init(context: GameContext) {
        self.context = context
        let preferences = SolitairePreferences.shared(in: context)
        self.preferences = preferences
        let saved = context.saveSlot.load(SolitaireSave.self).flatMap { $0.game.integrityProblems.isEmpty ? $0 : nil }
        let initial = saved?.game
            ?? SolitaireSession.makeGame(options: context.options, drawMode: preferences.drawMode, dealNumber: 0)
        game = initial
        elapsedBeforeRun = saved?.elapsed ?? 0
        resultRecorded = saved?.resultRecorded ?? false
        dealsStarted = saved?.dealsStarted ?? 1
        showsWin = initial.isWon
        save()
    }

    /// The first deal can be a prepared scenario (for UI tests and screenshots); later deals are
    /// random, or follow from `-seed` when one is given.
    static func makeGame(options: LaunchOptions, drawMode: DrawMode, dealNumber: Int) -> KlondikeGame {
        if dealNumber == 0, let scenario = options.scenario {
            let seed = options.seed ?? 1
            switch scenario {
            case "nearWin":
                return KlondikeFixtures.nearlyWon(seed: seed, drawMode: drawMode)
            case "midGame":
                var game = KlondikeGame(seed: seed, drawMode: drawMode)
                for _ in 0..<12 {
                    guard let move = game.hint() else { break }
                    game.perform(move)
                }
                return game
            default:
                break
            }
        }
        let seed = options.seed.map { $0 &+ UInt64(dealNumber) } ?? UInt64.random(in: 1...UInt64.max)
        return KlondikeGame(seed: seed, drawMode: drawMode)
    }

    // MARK: State for the view

    public var canUndo: Bool { game.canUndo && !game.isWon && !isAutoFinishing }
    public var canAutoFinish: Bool { !isAutoFinishing && game.canAutoFinish }
    public var canHint: Bool { !game.isWon && !isAutoFinishing }
    /// A started game whose result is not yet in the statistics.
    public var isInProgress: Bool { game.moveCount > 0 && !resultRecorded }

    public func elapsed(at date: Date = Date()) -> TimeInterval {
        elapsedBeforeRun + (runStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    /// Board description for UI tests, including the move count.
    public var signature: String { game.board.signature + "|M:\(game.moveCount)|D:\(game.drawMode.rawValue)" }

    /// Cards and pile involved in the current hint, for highlighting.
    public var hintedCards: Set<Card> {
        guard case let .transfer(from, to, count)? = hint else { return [] }
        var cards = Set(game.board.movableCards(from: from, count: count) ?? [])
        if let target = topCard(of: to) { cards.insert(target) }
        return cards
    }

    public var hintedPile: Pile? {
        switch hint {
        case .draw?, .recycle?: return .stock
        case let .transfer(_, to, _)?: return topCard(of: to) == nil ? to : nil
        case nil: return nil
        }
    }

    // MARK: Lifecycle

    /// Called when the screen appears/disappears or the app moves between foreground and background.
    public func setOnScreen(_ visible: Bool) {
        isOnScreen = visible
        updateClock()
        save()
    }

    // MARK: Player actions

    public func tap(_ card: Card) {
        guard !isAutoFinishing, !game.isWon else { return }
        if let move = game.bestMove(tapping: card) {
            apply(move)
        } else {
            reject(card)
        }
    }

    public func tapPile(_ pile: Pile) {
        guard !isAutoFinishing, !game.isWon else { return }
        if let move = game.bestMove(tappingPile: pile) {
            apply(move)
        } else if let top = topCard(of: pile) {
            reject(top)
        } else {
            context.feedback.play(.invalid)
        }
    }

    /// A drag ended over `pile`. Returns false if the drop is not legal.
    @discardableResult
    public func drop(from source: Pile, count: Int, onto pile: Pile) -> Bool {
        guard !isAutoFinishing, !game.isWon else { return false }
        let move = Move.transfer(from: source, to: pile, count: count)
        guard game.isLegal(move) else {
            context.feedback.play(.invalid)
            return false
        }
        apply(move)
        return true
    }

    public func undo() {
        guard canUndo else { return }
        game.undo()
        hint = nil
        recentlyMoved = []
        context.feedback.play(.tap)
        updateClock()
        save()
        announce("Undone")
    }

    /// Ask for a new deal; confirms first if the current game would count as a loss.
    public func requestNewGame() {
        if isInProgress {
            confirmingNewGame = true
        } else {
            startNewGame()
        }
    }

    public func startNewGame() {
        autoFinishTask?.cancel()
        winTask?.cancel()
        isAutoFinishing = false
        if isInProgress {
            context.stats.recordLoss(gameID: context.gameID)
        }
        game = SolitaireSession.makeGame(options: context.options, drawMode: preferences.drawMode, dealNumber: dealsStarted)
        dealsStarted += 1
        elapsedBeforeRun = 0
        runStartedAt = nil
        resultRecorded = false
        showsWin = false
        hint = nil
        recentlyMoved = []
        confirmingNewGame = false
        updateClock()
        save()
        context.feedback.play(.draw)
        announce("New deal")
    }

    public func showHint() {
        guard canHint else { return }
        context.feedback.play(.tap)
        guard let move = game.hint() else {
            hint = nil
            showToast("No helpful moves left. Try Undo or a new deal.")
            return
        }
        // The highlight stays until the next move, so a glance away doesn't lose it.
        hint = move
        let text = describe(move)
        showToast(text)
        announce(text)
    }

    /// Play the remaining moves to the foundations one by one.
    public func autoFinish() {
        guard !isAutoFinishing, let moves = game.autoFinishMoves() else { return }
        isAutoFinishing = true
        hint = nil
        let delay: UInt64 = animationsEnabled ? 110_000_000 : 15_000_000
        autoFinishTask = Task { [weak self] in
            for move in moves {
                guard !Task.isCancelled, let self else { return }
                self.apply(move, quiet: true)
                try? await Task.sleep(nanoseconds: delay)
            }
            self?.isAutoFinishing = false
        }
    }

    /// Leaving for the home screen.
    public func leave() {
        setOnScreen(false)
        context.exit()
    }

    // MARK: Internals

    private func apply(_ move: Move, quiet: Bool = false) {
        let moving = cards(movedBy: move)
        guard game.perform(move) else { return }
        recentlyMoved = Set(moving)
        hint = nil
        updateClock()
        if game.isWon && !resultRecorded {
            resultRecorded = true
            context.stats.recordWin(gameID: context.gameID, time: elapsedBeforeRun, moves: game.moveCount)
            context.feedback.play(.win)
            presentWin()
        } else if !quiet {
            context.feedback.play(move == .draw || move == .recycle ? .draw : .place)
        }
        save()
        if !quiet { announceMove(move, cards: moving) }
    }

    private func presentWin() {
        announce("You won! Time \(Format.spokenDuration(elapsedBeforeRun)), \(game.moveCount) moves.")
        guard animationsEnabled else {
            showsWin = true
            return
        }
        winTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self, self.game.isWon else { return }
            self.showsWin = true
        }
    }

    private func reject(_ card: Card) {
        rejections[card, default: 0] += 1
        context.feedback.play(.invalid)
    }

    private func updateClock(now: Date = Date()) {
        let started = game.moveCount > 0 || elapsedBeforeRun > 0
        let shouldRun = isOnScreen && started && !game.isWon
        if shouldRun, runStartedAt == nil {
            runStartedAt = now
        } else if !shouldRun, let start = runStartedAt {
            elapsedBeforeRun += max(0, now.timeIntervalSince(start))
            runStartedAt = nil
        }
    }

    private func save() {
        context.saveSlot.save(SolitaireSave(game: game, elapsed: elapsed(), resultRecorded: resultRecorded,
                                            dealsStarted: dealsStarted))
    }

    private func topCard(of pile: Pile) -> Card? {
        switch pile {
        case .stock: return game.stock.last
        case .waste: return game.waste.last
        case .foundation(let f): return game.foundations[f].last
        case .tableau(let t): return game.tableau[t].top
        }
    }

    private func cards(movedBy move: Move) -> [Card] {
        switch move {
        case .draw: return Array(game.stock.suffix(game.drawMode.rawValue))
        case .recycle: return game.waste
        case let .transfer(from, _, count): return game.board.movableCards(from: from, count: count) ?? []
        }
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled, let self, self.toast == text else { return }
            self.toast = nil
        }
    }

    /// Plain-language description of a move, for hints and VoiceOver.
    func describe(_ move: Move) -> String {
        switch move {
        case .draw:
            return "Draw from the stock"
        case .recycle:
            return "Turn the waste over to redeal"
        case let .transfer(from, to, count):
            guard let base = game.board.movableCards(from: from, count: count)?.first else { return "Move" }
            let what = count > 1 ? "the \(base.name) and the cards on it" : "the \(base.name)"
            switch to {
            case .foundation:
                return "Move \(what) to a foundation"
            case .tableau(let t):
                if let top = game.tableau[t].top { return "Move \(what) onto the \(top.name)" }
                return "Move \(what) to the empty column"
            case .stock, .waste:
                return "Move \(what)"
            }
        }
    }

    private func announceMove(_ move: Move, cards: [Card]) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        switch move {
        case .draw:
            announce(game.waste.last.map { "Drew the \($0.name)" } ?? "Drew")
        case .recycle:
            announce("Redealt the waste")
        case let .transfer(_, to, _):
            guard let base = cards.first else { return }
            switch to {
            case .foundation: announce("\(base.name) to foundation")
            case .tableau(let t): announce("\(base.name) to column \(t + 1)")
            case .stock, .waste: break
            }
        }
    }

    private func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
