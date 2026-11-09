import Foundation
import KlondikeEngine
import PlayKit

/// The game in progress: wraps the rules engine with the timer, statistics, saving,
/// hints, auto-finish and feedback. The view layer only calls these methods.
@MainActor
public final class SolitaireSession: ObservableObject, GameSession {
    @Published public private(set) var game: KlondikeGame {
        didSet {
            hint = nil
            recentlyMoved = []
        }
    }
    /// The move currently suggested by Hint, if any. It stays until the next move, so a glance
    /// away doesn't lose it.
    @Published public private(set) var hint: Move? = nil
    @Published public private(set) var toast: String? = nil
    @Published public private(set) var showsResult: Bool
    @Published public private(set) var isAutoFinishing = false
    /// Cards moved by the latest move (drawn above the others while they travel).
    @Published public private(set) var recentlyMoved: Set<Card> = []
    /// Increments each time a tap on a card had no legal move (drives a small shake).
    @Published public private(set) var rejections: [Card: Int] = [:]
    @Published public var confirmingNewGame = false

    public let context: GameContext
    public let preferences: SolitairePreferences

    private var resultRecorded: Bool
    private var clock: PlayClock
    private var inView = false
    private var dealsStarted: Int
    private let toastTimer = Pending()
    private let resultReveal = Pending()
    private var autoFinishTask: Task<Void, Never>?

    public init(context: GameContext) {
        self.context = context
        let preferences = context.preferences(SolitairePreferences.self)
        self.preferences = preferences
        let saved = SolitaireSave.load(from: context)
        let initial = saved?.game ?? Deals.game(number: 0, options: context.options, drawMode: preferences.drawMode)
        game = initial
        clock = PlayClock(elapsed: saved?.elapsed ?? 0)
        resultRecorded = saved?.resultRecorded ?? false
        dealsStarted = saved?.dealsStarted ?? 1
        showsResult = initial.isWon
        commit()
    }

    // MARK: State for the view

    /// The player may move cards: the game is neither won nor finishing itself.
    public var canPlay: Bool { !isAutoFinishing && !game.isWon }
    public var canUndo: Bool { game.canUndo && canPlay }
    public var canAutoFinish: Bool { !isAutoFinishing && game.canAutoFinish }
    /// A started game whose result is not yet in the statistics.
    public var isInProgress: Bool { save.isInProgress }

    public func elapsed(at date: Date = Date()) -> TimeInterval {
        clock.elapsed(at: date)
    }

    /// Board description for UI tests, including the move count.
    public var signature: String { game.board.signature + "|M:\(game.moveCount)|D:\(game.drawMode.rawValue)" }

    /// Cards and pile involved in the current hint, for highlighting.
    public var hintedCards: Set<Card> {
        guard case let .transfer(from, to, count)? = hint else { return [] }
        var cards = Set(game.board.movableCards(from: from, count: count) ?? [])
        if let target = game.board.topCard(of: to) { cards.insert(target) }
        return cards
    }

    public var hintedPile: Pile? {
        switch hint {
        case .draw?, .recycle?: return .stock
        case let .transfer(_, to, _)?: return game.board.topCard(of: to) == nil ? to : nil
        case nil: return nil
        }
    }

    // MARK: Lifecycle

    public func setInView(_ inView: Bool) {
        self.inView = inView
        commit()
    }

    // MARK: Player actions

    public func tap(_ card: Card) {
        guard canPlay else { return }
        if let move = game.bestMove(tapping: card) {
            apply(move)
        } else {
            reject(card)
        }
    }

    public func tapPile(_ pile: Pile) {
        guard canPlay else { return }
        if let move = game.bestMove(tappingPile: pile) {
            apply(move)
        } else if let top = game.board.topCard(of: pile) {
            reject(top)
        } else {
            context.feedback.play(.invalid)
        }
    }

    /// A drag ended over `pile`. Returns false if the drop is not legal.
    @discardableResult
    public func drop(from source: Pile, count: Int, onto pile: Pile) -> Bool {
        guard canPlay else { return false }
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
        context.feedback.play(.tap)
        commit()
        context.announce("Undone")
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
        resultReveal.cancel()
        isAutoFinishing = false
        if isInProgress {
            context.recordLoss()
        }
        game = Deals.game(number: dealsStarted, options: context.options, drawMode: preferences.drawMode)
        dealsStarted += 1
        clock = PlayClock()
        resultRecorded = false
        showsResult = false
        confirmingNewGame = false
        commit()
        context.feedback.play(.draw)
        context.announce("New deal")
    }

    public func showHint() {
        guard canPlay else { return }
        context.feedback.play(.tap)
        guard let move = game.hint() else {
            hint = nil
            showToast("No helpful moves left. Try Undo or a new deal.")
            return
        }
        hint = move
        let text = describe(move)
        showToast(text)
        context.announce(text)
    }

    /// Play the remaining moves to the foundations one by one.
    public func autoFinish() {
        guard !isAutoFinishing, let moves = game.autoFinishMoves() else { return }
        isAutoFinishing = true
        hint = nil
        let delay: UInt64 = context.animationsEnabled ? 110_000_000 : 15_000_000
        autoFinishTask = Task { [weak self] in
            for move in moves {
                guard !Task.isCancelled, let self else { return }
                self.apply(move, quiet: true)
                try? await Task.sleep(nanoseconds: delay)
            }
            self?.isAutoFinishing = false
        }
    }

    // MARK: Internals

    private func apply(_ move: Move, quiet: Bool = false) {
        let moving = game.cards(movedBy: move)
        guard game.perform(move) else { return }
        recentlyMoved = Set(moving)
        if game.isWon && !resultRecorded {
            resultRecorded = true
            let time = clock.elapsed()
            context.recordWin(time: time)
            context.feedback.play(.win)
            context.announce("You won! Time \(Format.spokenDuration(time)), \(Format.count(game.moveCount, "move")).")
            // The last card lands before the panel covers it.
            resultReveal.schedule(after: context.animationsEnabled ? 0.45 : 0) { [weak self] in
                self?.showsResult = true
            }
        } else if !quiet {
            context.feedback.play(move == .draw || move == .recycle ? .draw : .place)
        }
        commit()
        if !quiet { announceMove(move, cards: moving) }
    }

    private func reject(_ card: Card) {
        rejections[card, default: 0] += 1
        context.feedback.play(.invalid)
    }

    private var save: SolitaireSave {
        SolitaireSave(game: game, elapsed: clock.elapsed(), resultRecorded: resultRecorded, dealsStarted: dealsStarted)
    }

    /// After every change: the timer runs from the first move while the game is in view, and
    /// the game is saved.
    private func commit() {
        clock.setRunning(inView && (game.moveCount > 0 || clock.hasStarted) && !game.isWon)
        context.saveSlot.save(save)
    }

    private func showToast(_ text: String) {
        toast = text
        toastTimer.schedule(after: 4.5) { [weak self] in self?.toast = nil }
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
        switch move {
        case .draw:
            context.announce(game.waste.last.map { "Drew the \($0.name)" } ?? "Drew")
        case .recycle:
            context.announce("Redealt the waste")
        case let .transfer(_, to, _):
            guard let base = cards.first else { return }
            switch to {
            case .foundation: context.announce("\(base.name) to foundation")
            case .tableau(let t): context.announce("\(base.name) to column \(t + 1)")
            case .stock, .waste: break
            }
        }
    }
}
