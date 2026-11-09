import Foundation
import PlayKit
import RunnerEngine

/// The numbers above the pier. They change many times a second, so they are published apart
/// from the session: only the readouts follow them, not the whole screen.
@MainActor
public final class RunnerHUD: ObservableObject {
    @Published public private(set) var score = 0
    @Published public private(set) var coins = 0
    @Published public private(set) var hasShield = false
    /// Whole seconds of magnet left (0 without one).
    @Published public private(set) var magnetSeconds = 0

    func show(_ run: Run) {
        if score != run.score { score = run.score }
        if coins != run.coinCount { coins = run.coinCount }
        if hasShield != run.hasShield { hasShield = run.hasShield }
        let seconds = Int(run.magnetLeft.rounded(.up))
        if magnetSeconds != seconds { magnetSeconds = seconds }
    }
}

/// The run in progress: wraps the engine with the clock, pausing, goals, statistics, feedback
/// and saving. The view layer only calls these methods.
///
/// The run itself is not published: it changes every frame, and the pier is redrawn from
/// `run(at:)` by its own timeline.
@MainActor
public final class RunnerSession: ObservableObject, GameSession {
    public enum Phase: String, Equatable {
        /// On the start line, waiting for the first touch.
        case ready
        case running
        case paused
        case over
    }

    /// How a finished run went.
    public struct Result: Equatable {
        public let score: Int
        public let metres: Int
        public let coins: Int
        public let goal: Int
        public let isBest: Bool

        public var reachedGoal: Bool { score >= goal }
    }

    /// When things last happened, for the effects drawn around the runner.
    public struct Moments: Equatable {
        public var coin: Date?
        public var pickup: Date?
        public var shieldBroke: Date?
        public var crash: Date?
    }

    @Published public private(set) var phase: Phase
    @Published public private(set) var best: Int
    /// The score this run is after.
    @Published public private(set) var goal: Int
    @Published public private(set) var goalReached: Bool
    @Published public private(set) var result: Result? = nil
    @Published public private(set) var showsResult = false
    /// During the coached opening, the move to make next.
    @Published public private(set) var prompt: Move? = nil
    /// After a pause the run stands still until this moment, so there is time to find the runner.
    @Published public private(set) var resumesAt: Date? = nil
    @Published public private(set) var inView = false
    @Published public var confirmingNewRun = false

    public let context: GameContext
    public let hud = RunnerHUD()
    public private(set) var run: Run
    public private(set) var moments = Moments()

    private var runsStarted: Int
    private var isUnderWay: Bool
    private var resultRecorded: Bool
    /// The moment the run has been played up to, while the clock is running.
    private var playedTo: Date? = nil
    private var loop: Task<Void, Never>? = nil
    private var lastSaved = Date.distantPast
    private var lastCoinSound = Date.distantPast
    private let resultReveal = Pending()

    /// A run is coached until one has scored this much: the opening has then been passed.
    static let coachedBelow = 100
    /// The longest a single frame may count for: a hitch never throws the runner into
    /// something unseen.
    static let longestFrame = 0.25
    /// Seconds between getting back to a paused run and it moving again.
    public static let resumeDelay = 1.5
    /// In UI tests the clock stands still, and every touch moves it on by this much.
    public static let testStride = 0.5

    public init(context: GameContext) {
        self.context = context
        let run: Run
        let best: Int
        let goal: Int
        let underWay: Bool
        if let save = context.saveSlot.load(RunnerSave.self) {
            run = save.run
            best = save.best
            goal = save.goal
            runsStarted = save.runsStarted
            underWay = save.isUnderWay
            resultRecorded = save.resultRecorded
        } else {
            run = Self.makeRun(number: 0, best: 0, options: context.options)
            best = 0
            goal = Goals.next(after: 0)
            runsStarted = 1
            // A prepared run may start part of the way along.
            underWay = run.distance > 0
            resultRecorded = false
        }
        self.run = run
        self.best = best
        self.goal = goal
        isUnderWay = underWay
        goalReached = run.score >= goal
        if run.status == .crashed {
            phase = .over
        } else if underWay {
            // A run that was under way waits for a touch, except in UI tests, where nothing
            // moves by itself anyway.
            phase = context.options.disableAnimations ? .running : .paused
        } else {
            phase = .ready
        }
        hud.show(run)
        if phase == .over {
            // The app closed on the crash: record the end now.
            record()
            result = makeResult()
            showsResult = true
        }
        save()
    }

    private static func makeRun(number: Int, best: Int, options: LaunchOptions) -> Run {
        if number == 0, let prepared = Scenarios.run(options.scenario) { return prepared }
        // Courses are random unless `-seed N` is given, when run number `number` gets `N + number`.
        let seed = options.value(after: "-seed").flatMap { UInt64($0) }.map { $0 &+ UInt64(number) }
        return Run(seed: seed ?? UInt64.random(in: 1...UInt64.max), coached: best < coachedBelow)
    }

    // MARK: State for the view

    /// In UI tests (`-disableAnimations`) time does not pass by itself.
    private var isStepped: Bool { context.options.disableAnimations }

    /// A run that would be lost by starting another.
    public var hasRunInProgress: Bool { isUnderWay && phase != .over }

    /// The run as it is at `date`: what the pier is drawn from.
    public func run(at date: Date) -> Run {
        guard phase == .running, let playedTo else { return run }
        var ahead = run
        ahead.advance(by: min(Self.longestFrame, max(0, date.timeIntervalSince(playedTo))))
        return ahead
    }

    /// Whole state, for UI tests.
    public var signature: String { "\(phase.rawValue)|\(run.signature)|best:\(best)|goal:\(goal)" }

    /// What VoiceOver says about the pier.
    public var spokenStatus: String {
        switch phase {
        case .ready:
            return "Ready. Goal \(goal) points."
        case .paused:
            return "Paused, \(run.score) points."
        case .over:
            return "Run over, \(run.score) points."
        case .running:
            var text = "\(run.score) points, lane \(run.lane + 1) of \(Body.lanes)"
            if let ahead = run.obstacleAhead, run.seconds(to: ahead) < 2.5 {
                text += ". \(ahead.kind.spokenName) ahead: \(ahead.kind.spokenAdvice)"
            }
            return text
        }
    }

    // MARK: Lifecycle

    /// Out of view (the home screen, the background, Settings over the game), a run pauses.
    public func setInView(_ inView: Bool) {
        if self.inView != inView { self.inView = inView }
        if !inView { pause() }
    }

    // MARK: Player actions

    /// A touch that is not a swipe: starts the run, or carries on with a paused one.
    public func tap(at now: Date = Date()) {
        switch phase {
        case .ready: start(at: now)
        case .paused: resume(at: now)
        case .running: stride(now)
        case .over: break
        }
    }

    /// A swipe. The first one also starts the run.
    public func perform(_ move: Move, at now: Date = Date()) {
        if phase == .ready { start(at: now) }
        guard phase == .running else { return }
        advance(to: now)
        guard phase == .running else { return }
        switch run.perform(move) {
        case .jumped?: context.feedback.play(.jump)
        case .slid?: context.feedback.play(.draw)
        case .changedLane?: context.feedback.play(.tap)
        case .hitEdge?: context.feedback.play(.invalid)
        default: break
        }
        stride(now)
    }

    public func togglePause(at now: Date = Date()) {
        if phase == .running {
            pause(at: now)
        } else if phase == .paused {
            resume(at: now)
        }
    }

    /// Asks for a new run; confirms first if one is under way (and pauses it meanwhile).
    public func requestNewRun() {
        if hasRunInProgress {
            pause()
            confirmingNewRun = true
        } else {
            startNewRun()
        }
    }

    /// Puts a fresh course under the runner's feet. A run still under way ends here, with the
    /// score it has.
    public func startNewRun() {
        if hasRunInProgress { record() }
        resultReveal.cancel()
        stopClock()
        run = Self.makeRun(number: runsStarted, best: best, options: context.options)
        runsStarted += 1
        goal = Goals.next(after: best)
        goalReached = false
        isUnderWay = false
        resultRecorded = false
        resumesAt = nil
        prompt = nil
        result = nil
        moments = Moments()
        showsResult = false
        confirmingNewRun = false
        phase = .ready
        hud.show(run)
        save()
        context.feedback.play(.draw)
        context.announce("New run. Goal \(goal) points.")
    }

    // MARK: The clock

    /// Plays the run up to `now`. Called many times a second while running.
    public func advance(to now: Date) {
        guard phase == .running, let playedTo else { return }
        let elapsed = now.timeIntervalSince(playedTo)
        guard elapsed > 0 else { return }
        self.playedTo = now
        if resumesAt != nil { resumesAt = nil }
        play(for: min(elapsed, Self.longestFrame), at: now)
    }

    private func play(for seconds: TimeInterval, at now: Date) {
        for event in run.advance(by: seconds) {
            switch event {
            case .coin:
                moments.coin = now
                if now.timeIntervalSince(lastCoinSound) > 0.07 {
                    lastCoinSound = now
                    context.feedback.play(.coin)
                }
            case .pickup(let kind):
                moments.pickup = now
                context.feedback.play(.powerUp)
                context.announce(kind == .magnet ? "Magnet" : "Shield")
            case .shieldBroke:
                moments.shieldBroke = now
                context.feedback.play(.hit)
                context.announce("The shield took the hit")
            case .landed:
                context.feedback.play(.place)
            case .jumped:
                context.feedback.play(.jump)
            case .crashed:
                finish(at: now)
            case .changedLane, .hitEdge, .slid:
                break
            }
        }
        hud.show(run)
        if prompt != run.prompt {
            prompt = run.prompt
            if let prompt { context.announce(prompt.instruction) }
        }
        if !goalReached && run.score >= goal {
            goalReached = true
            context.feedback.play(.win)
            context.announce("Goal reached")
        }
        if phase == .running && now.timeIntervalSince(lastSaved) > 2 { save() }
    }

    /// In UI tests, a touch moves the clock on.
    private func stride(_ now: Date) {
        guard isStepped, phase == .running else { return }
        play(for: Self.testStride, at: now)
        // Nothing else tells the pier to redraw when no timeline is running.
        objectWillChange.send()
    }

    private func start(at now: Date) {
        isUnderWay = true
        phase = .running
        startClock(at: now)
        save()
        context.feedback.play(.tap)
        context.announce("Go")
    }

    private func pause(at now: Date = Date()) {
        advance(to: now)
        guard phase == .running else { return }
        phase = .paused
        resumesAt = nil
        stopClock()
        save()
    }

    private func resume(at now: Date) {
        guard phase == .paused else { return }
        phase = .running
        startClock(at: now.addingTimeInterval(Self.resumeDelay))
        resumesAt = playedTo
        context.feedback.play(.tap)
    }

    /// Lets time pass from `moment` on: the run is then played forward sixty times a second.
    /// (The pier's timeline draws from `run(at:)`, so what is seen never waits for this.)
    private func startClock(at moment: Date) {
        guard !isStepped else { return }
        playedTo = moment
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard !Task.isCancelled, let self else { return }
                self.advance(to: Date())
            }
        }
    }

    private func stopClock() {
        playedTo = nil
        loop?.cancel()
        loop = nil
    }

    // MARK: The end of a run

    private func finish(at now: Date) {
        phase = .over
        stopClock()
        moments.crash = now
        record()
        let result = makeResult()
        self.result = result
        save()
        context.feedback.play(.crash)
        context.announce(result.spoken)
        // The tumble is seen before the panel covers it.
        resultReveal.schedule(after: isStepped ? 0 : 0.9) { [weak self] in
            self?.showsResult = true
        }
    }

    /// Puts the run, as it stands, into the statistics: a win if it reached its goal.
    private func record() {
        guard !resultRecorded else { return }
        resultRecorded = true
        if run.score >= goal {
            context.recordWin(time: run.time)
        } else {
            context.recordLoss()
        }
        best = max(best, run.score)
    }

    private func makeResult() -> Result {
        Result(score: run.score, metres: Int(run.distance), coins: run.coinCount, goal: goal,
               isBest: run.score > 0 && run.score >= best)
    }

    private func save() {
        lastSaved = Date()
        context.saveSlot.save(RunnerSave(run: run, best: best, goal: goal, runsStarted: runsStarted,
                                         isUnderWay: isUnderWay, resultRecorded: resultRecorded))
    }
}

extension RunnerSession.Result {
    public var headline: String {
        if reachedGoal { return "Goal reached!" }
        return isBest ? "New best!" : "Run over"
    }

    var spoken: String {
        "\(headline) \(score) points: \(metres) metres and \(Format.count(coins, "coin"))."
    }
}

extension Move {
    /// What the coach says, on the first run.
    var instruction: String {
        switch self {
        case .left: return "Swipe left"
        case .right: return "Swipe right"
        case .jump: return "Swipe up to jump"
        case .slide: return "Swipe down to slide"
        }
    }
}

extension Obstacle.Kind {
    /// What VoiceOver calls it.
    var spokenName: String {
        switch self {
        case .barrier: return "Barrier"
        case .beam: return "Beam"
        case .stack: return "Crates"
        case .barrel: return "Barrel"
        }
    }

    var spokenAdvice: String {
        switch answer {
        case .jump?: return "jump"
        case .slide?: return "slide"
        default: return "change lane"
        }
    }
}
