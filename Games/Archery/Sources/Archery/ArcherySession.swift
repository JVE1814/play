import ArcheryEngine
import Foundation
import PlayKit
import UIKit

/// The level in progress: wraps the engine with drawing, aiming, the arrow's flight, progress,
/// statistics and saving. The view layer only calls these methods.
///
/// Every arrow is committed to the round (and saved) the moment it is released; `landedArrows`
/// trails behind while the arrow is still in the air, so a force quit mid-flight loses nothing.
@MainActor
public final class ArcherySession: ObservableObject {
    /// The bow held at full draw (or being drawn).
    public struct Draw: Equatable {
        public let start: Date
        /// For screenshots: a pose frozen this many seconds after full draw.
        public let frozenHeld: Double?
    }

    /// An arrow in the air.
    public struct Flight: Equatable {
        public let shot: Shot
        /// Index of the arrow in this attempt (it sets the fletching colour).
        public let arrow: Int
        public let path: FlightPath
        public let start: Date
        public let duration: TimeInterval
    }

    /// The arrow that landed last, for the score that pops up beside it.
    public struct Landing: Equatable {
        public let arrow: Int
        public let shot: Shot
        public let date: Date
    }

    @Published public private(set) var round: ArcheryRound
    @Published public private(set) var progress: ArcheryProgress
    /// Where the thumb has put the sight, before sway (target coordinates, boss at rest).
    @Published public private(set) var aim: Vec2
    @Published public private(set) var draw: Draw? = nil
    @Published public private(set) var flight: Flight? = nil
    @Published public private(set) var landing: Landing? = nil
    /// Arrows that have reached the target (one fewer than shot while an arrow is in the air).
    @Published public private(set) var landedArrows: Int
    @Published public private(set) var showsResult: Bool
    @Published public var showingTip: Bool
    @Published public var showingLevels = false {
        didSet { updateClock() }
    }
    @Published public var confirmingRestart = false
    /// A short message, such as why an arrow was not shot.
    @Published public private(set) var notice: String? = nil

    public let context: GameContext
    public let preferences: ArcheryPreferences
    /// Set by the view: false when Reduce Motion is on or tests disable animation.
    public var animationsEnabled = true

    private var attempt: Int
    private var resultRecorded: Bool
    private var elapsedBeforeRun: TimeInterval
    private var runStartedAt: Date?
    private var isOnScreen = false
    /// The level clock at a moment of real time, while the level is on screen. Between syncs the
    /// clock runs on from here. It keeps running after the last arrow so a moving target keeps
    /// moving behind the result.
    private var clockAnchor: (clock: Double, date: Date)?
    /// Recent sight positions, so lifting the thumb (which tends to nudge it) does not move the shot.
    private var aimHistory: [(date: Date, aim: Vec2)] = []
    private var flightTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var fullDrawTask: Task<Void, Never>?
    private var lastSaved = Date.distantPast

    /// The moments before lifting the thumb that are ignored.
    static let releaseFilter: TimeInterval = 0.07
    /// Held time used for an arrow shot with VoiceOver: inside the steady window.
    static let spokenHold = 1.2

    public init(context: GameContext) {
        self.context = context
        self.preferences = ArcheryPreferences.shared(in: context)
        let options = context.options
        let initial: ArcheryRound
        var startAim: Vec2
        if let save = context.saveSlot.load(ArcherySave.self) {
            initial = save.round
            progress = save.progress
            startAim = save.aim
            elapsedBeforeRun = save.elapsed
            resultRecorded = save.resultRecorded
        } else if let scenario = Self.scenario(options.scenario) {
            initial = scenario
            progress = ArcheryProgress(unlocked: scenario.level.number)
            startAim = scenario.shots.last?.aim ?? scenario.level.layout.spots[0].center
            elapsedBeforeRun = 0
            resultRecorded = false
        } else {
            let start = min(LevelCatalog.count, max(1, options.level ?? 1))
            let level = LevelCatalog.level(start)
            initial = ArcheryRound(level: level)
            progress = ArcheryProgress(unlocked: start)
            startAim = level.layout.spots[0].center
            elapsedBeforeRun = 0
            resultRecorded = false
        }
        var demoDraw: Draw?
        if let demo = options.demoAim, initial.status == .playing {
            startAim = startAim + Vec2(demo, 0)
            demoDraw = Draw(start: Date(), frozenHeld: 1.2)
        }
        round = initial
        attempt = initial.attempt
        aim = startAim
        landedArrows = initial.shots.count
        showsResult = initial.isOver
        showingTip = initial.shots.isEmpty && !initial.isOver && demoDraw == nil
        draw = demoDraw
        save()
    }

    /// Prepared attempts for UI tests and screenshots.
    static func scenario(_ name: String?) -> ArcheryRound? {
        switch name {
        case "archeryNearWin":
            // Two arrows in the X ring; one more in the gold earns three stars.
            var round = ArcheryRound(level: LevelCatalog.level(1))
            round.shoot(aim: Vec2(0.012, 0.01))
            round.shoot(aim: Vec2(-0.015, -0.008))
            return round
        case "archeryLastArrow":
            // Two arrows in the straw outside the face: even a ten can't reach a star now.
            var round = ArcheryRound(level: LevelCatalog.level(1))
            round.shoot(aim: Vec2(0.63, 0.2))
            round.shoot(aim: Vec2(-0.62, -0.3))
            return round
        case "archeryShowcase":
            return demonstration(level: 22, hits: [(1.8, Vec2(0.02, 0.03)), (6.2, Vec2(-0.08, -0.05)),
                                                   (10.5, Vec2(0.12, 0.07))], clock: 13.4)
        case "archeryNight":
            return demonstration(level: 29, hits: [(2.4, Vec2(-0.05, 0.04)), (7.9, Vec2(0.16, -0.1))], clock: 11.2)
        default:
            return nil
        }
    }

    private static func demonstration(level number: Int, hits: [(Double, Vec2)], clock: Double) -> ArcheryRound {
        var round = ArcheryRound(level: LevelCatalog.level(number))
        for (time, point) in hits {
            round.advance(to: time)
            round.shoot(aim: round.aim(toHit: point))
        }
        round.advance(to: clock)
        return round
    }

    // MARK: State for the view

    public var level: Level { round.level }
    public var isPlaying: Bool { round.status == .playing && !showsResult }
    /// A new arrow can be drawn: the level is on, and the last arrow has landed.
    public var canDraw: Bool { isPlaying && flight == nil && draw == nil }
    public var isDrawing: Bool { draw != nil }
    public var hasNextLevel: Bool { round.level.number < LevelCatalog.count }

    /// Arrows that have landed, and what they scored.
    public var landedShots: ArraySlice<Shot> { round.shots.prefix(landedArrows) }
    public var displayedScore: Int { landedShots.reduce(0) { $0 + $1.score } }
    public var displayedArrowsLeft: Int { round.level.arrows - landedArrows }

    /// The level clock at `date` (drives the wind, the flags and moving targets).
    public func clock(at date: Date = Date()) -> Double {
        guard let anchor = clockAnchor else { return round.clock }
        return anchor.clock + max(0, date.timeIntervalSince(anchor.date))
    }

    /// Seconds left at `date` on a timed level.
    public func timeLeft(at date: Date = Date()) -> Double? {
        guard let limit = round.level.timeLimit else { return nil }
        guard let start = round.timerStart else { return limit }
        guard round.status == .playing else { return round.timeLeft }
        return max(0, limit - (clock(at: date) - start))
    }

    /// Seconds since full draw at `date` (negative while still drawing).
    public func held(at date: Date = Date()) -> Double? {
        guard let draw else { return nil }
        return draw.frozenHeld ?? date.timeIntervalSince(draw.start) - Sway.drawTime
    }

    /// 0 when the bow is down, 1 at full draw.
    public func drawProgress(at date: Date = Date()) -> Double {
        guard let draw else { return 0 }
        if draw.frozenHeld != nil { return 1 }
        return min(1, max(0, date.timeIntervalSince(draw.start) / Sway.drawTime))
    }

    /// Where the sight points at `date`, sway included.
    public func sight(at date: Date = Date()) -> Vec2 {
        guard let held = held(at: date) else { return aim }
        return aim + round.sway(held: held, strength: preferences.swayStrength)
    }

    public func elapsed(at date: Date = Date()) -> TimeInterval {
        elapsedBeforeRun + (runStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    /// Whole state, for UI tests.
    public var signature: String { round.signature + "|landed:\(landedArrows)|unlocked:\(progress.unlocked)" }

    // MARK: Lifecycle

    public func setOnScreen(_ visible: Bool) {
        isOnScreen = visible
        if !visible, draw != nil, draw?.frozenHeld == nil { draw = nil }
        updateClock()
        save()
    }

    public func leave() {
        setOnScreen(false)
        context.exit()
    }

    // MARK: Drawing, aiming and shooting

    /// Thumb down: start drawing the bow.
    public func beginDraw(at now: Date = Date()) {
        guard canDraw else { return }
        syncClock(now)
        guard round.status == .playing else { return }
        round.startTimer()
        startTicking()
        draw = Draw(start: now, frozenHeld: nil)
        showingTip = false
        notice = nil
        aimHistory = [(now, aim)]
        updateRunClock(now)
        context.feedback.play(.tap)
        fullDrawTask?.cancel()
        let started = now
        fullDrawTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Sway.drawTime * 1_000_000_000))
            guard !Task.isCancelled, let self, self.draw?.start == started else { return }
            self.context.feedback.play(.draw)
        }
    }

    /// Thumb moved: move the sight by `delta` metres, keeping it within `limit` of the centre.
    public func moveAim(by delta: Vec2, limit: Vec2, at now: Date = Date()) {
        guard draw?.frozenHeld == nil, draw != nil else { return }
        aim = Vec2(min(limit.x, max(-limit.x, aim.x + delta.x)), min(limit.y, max(-limit.y, aim.y + delta.y)))
        aimHistory.append((now, aim))
        aimHistory.removeAll { now.timeIntervalSince($0.date) > 0.5 }
    }

    /// Thumb up: loose the arrow, or let the bow down if it wasn't fully drawn.
    public func release(at now: Date = Date()) {
        guard let current = draw, current.frozenHeld == nil else { return }
        draw = nil
        fullDrawTask?.cancel()
        let held = now.timeIntervalSince(current.start) - Sway.drawTime
        guard held >= 0 else {
            show(notice: "Hold until the bow is fully drawn, then let go.")
            return
        }
        // Ignore the last few hundredths of a second: lifting the thumb tends to nudge it.
        if let settled = aimHistory.last(where: { now.timeIntervalSince($0.date) >= Self.releaseFilter }) {
            aim = settled.aim
        }
        let sight = aim + round.sway(held: held, strength: preferences.swayStrength)
        shoot(sight: sight, at: now)
    }

    /// Stops drawing without shooting (the view disappeared, or the clock ran out).
    public func cancelDraw() {
        guard draw?.frozenHeld == nil else { return }
        draw = nil
        fullDrawTask?.cancel()
    }

    private func shoot(sight: Vec2, at now: Date) {
        syncClock(now)
        let index = round.shots.count
        guard round.status == .playing, let shot = round.shoot(aim: sight) else { return }
        updateRunClock(now)
        save()
        context.feedback.play(.release)
        let path = FlightPath(distance: round.level.distance, impact: shot.hit.point, targetOffset: shot.targetOffset,
                              drift: shot.drift, mirrored: preferences.leftHanded)
        guard animationsEnabled else {
            land(shot, arrow: index, at: now)
            return
        }
        // A moving target is shown exactly where the engine says it is when the arrow arrives.
        // An arrow that misses the boss carries on past it for a moment.
        let arrival = round.level.motion.isMoving ? path.duration : max(0.24, path.duration)
        let duration = shot.hit.inBoss ? arrival : arrival * 1.25
        flight = Flight(shot: shot, arrow: index, path: path, start: now, duration: duration)
        flightTask?.cancel()
        flightTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.land(shot, arrow: index, at: Date())
        }
    }

    private func land(_ shot: Shot, arrow: Int, at now: Date) {
        flight = nil
        landedArrows = min(round.shots.count, arrow + 1)
        landing = Landing(arrow: arrow, shot: shot, date: now)
        // A thunk whenever the arrow goes into the boss; a miss that flies past just goes quiet.
        context.feedback.play(shot.hit.inBoss ? .hit : .invalid)
        announce(describe(shot))
        if let advice = coaching(for: shot) { show(notice: advice) }
        checkFinished(at: now)
    }

    /// In the first three venues, a word on what the wind or a moving target did to the arrow,
    /// and which way to adjust if it landed off centre.
    func coaching(for shot: Shot) -> String? {
        let level = round.level
        guard level.number <= 18, shot.hit.inBoss, !round.isOver else { return nil }
        let ring = level.layout.largestFace.ringWidth
        let aimedAt = level.layout.spots[shot.hit.spot ?? 0].center
        let miss = shot.hit.point.x - aimedAt.x
        func centimetres(_ metres: Double) -> Int { Int((abs(metres) * 100).rounded()) }
        let travel = shot.targetOffset.x - round.targetOffset(at: shot.release).x
        if level.motion.isMoving, abs(travel) > ring {
            let behind = miss * travel < 0 && abs(miss) > ring
            return "The target moved \(centimetres(travel)) cm while the arrow flew."
                + (behind ? " Aim further ahead of it." : "")
        }
        if abs(shot.drift) > ring {
            let way = shot.drift > 0 ? "right" : "left"
            let downwind = miss * shot.drift > 0 && abs(miss) > ring
            return "The wind carried it \(centimetres(shot.drift)) cm to the \(way)."
                + (downwind ? " Aim a little further \(shot.drift > 0 ? "left" : "right")." : "")
        }
        return nil
    }

    // MARK: VoiceOver

    /// Moves the sight by whole rings of the level's largest face.
    public func nudgeAim(x: Double, y: Double) {
        guard isPlaying else { return }
        let step = round.level.layout.largestFace.ringWidth
        let limit = round.level.layout.bossSize / 2 + 0.4
        aim = Vec2(min(limit, max(-limit, aim.x + x * step)), min(limit, max(-limit, aim.y + y * step)))
        showingTip = false
    }

    /// Shoots without drawing by touch: held for a moment in the steady window.
    public func shootFromAccessibility() {
        guard canDraw else { return }
        let now = Date()
        syncClock(now)
        round.startTimer()
        startTicking()
        showingTip = false
        shoot(sight: aim + round.sway(held: Self.spokenHold, strength: preferences.swayStrength), at: now)
    }

    /// The sight, wind and arrows, in words.
    public func spokenStatus(at date: Date = Date()) -> String {
        var parts: [String] = []
        let offset = aim - round.level.layout.spots[0].center
        parts.append(describeSight(offset))
        parts.append("Wind " + Self.spokenWind(round.windSpeed(at: clock(at: date))) + ".")
        if round.level.motion.isMoving { parts.append("The target is moving.") }
        parts.append("\(displayedArrowsLeft) \(displayedArrowsLeft == 1 ? "arrow" : "arrows") left.")
        return parts.joined(separator: " ")
    }

    private func describeSight(_ offset: Vec2) -> String {
        func centimetres(_ value: Double) -> Int { Int((abs(value) * 100).rounded()) }
        var pieces: [String] = []
        if centimetres(offset.x) > 0 { pieces.append("\(centimetres(offset.x)) centimetres \(offset.x > 0 ? "right" : "left")") }
        if centimetres(offset.y) > 0 { pieces.append("\(centimetres(offset.y)) centimetres \(offset.y > 0 ? "high" : "low")") }
        return pieces.isEmpty ? "Sight on the centre." : "Sight " + pieces.joined(separator: " and ") + "."
    }

    static func spokenWind(_ speed: Double) -> String {
        let text = Wind.describe(speed)
        return text == "Calm" ? "calm" : text.replacingOccurrences(of: "m/s", with: "metres per second")
    }

    // MARK: Levels

    /// Starts a fresh attempt at `level` (if unlocked). Leaving a level unfinished is not a loss.
    public func start(level number: Int) {
        guard progress.isUnlocked(number) else { return }
        flightTask?.cancel()
        resultTask?.cancel()
        fullDrawTask?.cancel()
        stopClock()
        attempt += 1
        let level = LevelCatalog.level(number)
        round = ArcheryRound(level: level, attempt: attempt)
        aim = level.layout.spots[0].center
        draw = nil
        flight = nil
        landing = nil
        landedArrows = 0
        elapsedBeforeRun = 0
        runStartedAt = nil
        resultRecorded = false
        showsResult = false
        confirmingRestart = false
        showingLevels = false
        showingTip = true
        notice = nil
        updateClock()
        save()
        context.feedback.play(.draw)
        announce("Level \(number), \(level.name). \(level.summary).")
    }

    public func retry() { start(level: round.level.number) }

    /// Restart from the toolbar: asks first if arrows have been shot.
    public func requestRestart() {
        if round.status == .playing && !round.shots.isEmpty {
            confirmingRestart = true
        } else {
            retry()
        }
    }

    public func nextLevel() {
        start(level: min(LevelCatalog.count, round.level.number + 1))
    }

    // MARK: Internals

    private func checkFinished(at now: Date) {
        guard round.isOver, landedArrows >= round.shots.count, flight == nil, !resultRecorded else { return }
        cancelDraw()
        resultRecorded = true
        updateRunClock(now)
        let score = round.score
        progress.record(level: round.level.number, score: score, stars: round.stars)
        if round.passed {
            context.stats.recordWin(gameID: context.gameID, time: elapsedBeforeRun, moves: round.arrowsShot)
            context.feedback.play(.win)
            announce("Level complete with \(score) points and \(round.stars) star\(round.stars == 1 ? "" : "s").")
        } else {
            context.stats.recordLoss(gameID: context.gameID)
            context.feedback.play(.invalid)
            announce(round.timedOut ? "Out of time with \(score) points." : "\(score) points. Not quite enough for a star.")
        }
        save()
        guard animationsEnabled else {
            showsResult = true
            return
        }
        resultTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, let self, self.round.isOver else { return }
            self.showsResult = true
        }
    }

    private func updateClock(_ now: Date = Date()) {
        if isOnScreen && !showingLevels {
            if clockAnchor == nil { clockAnchor = (round.clock, now) }
            startTicking()
        } else {
            stopClock(now)
        }
        updateRunClock(now)
    }

    /// Brings the round's clock up to date. On a timed level this is where time runs out.
    private func syncClock(_ now: Date = Date()) {
        guard let anchor = clockAnchor else { return }
        let time = anchor.clock + max(0, now.timeIntervalSince(anchor.date))
        if round.status == .playing {
            round.advance(to: time)
            if round.isOver {
                cancelDraw()
                checkFinished(at: now)
            }
        }
        clockAnchor = (round.status == .playing ? round.clock : time, now)
    }

    private func stopClock(_ now: Date = Date()) {
        syncClock(now)
        clockAnchor = nil
        tickTask?.cancel()
        tickTask = nil
    }

    /// On a timed level with the countdown running, keeps an eye on the clock and saves often.
    private func startTicking() {
        guard tickTask == nil, clockAnchor != nil, round.timerStart != nil, round.status == .playing else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled, let self else { return }
                let now = Date()
                self.syncClock(now)
                if now.timeIntervalSince(self.lastSaved) > 2 { self.save() }
                if self.round.status != .playing {
                    self.tickTask = nil
                    return
                }
            }
        }
    }

    /// The statistics clock: runs while the level is on screen, from the first draw to the end.
    private func updateRunClock(_ now: Date = Date()) {
        let started = !round.shots.isEmpty || draw != nil || elapsedBeforeRun > 0
        let shouldRun = isOnScreen && started && !resultRecorded
        if shouldRun, runStartedAt == nil {
            runStartedAt = now
        } else if !shouldRun, let start = runStartedAt {
            elapsedBeforeRun += max(0, now.timeIntervalSince(start))
            runStartedAt = nil
        }
    }

    private func save() {
        lastSaved = Date()
        context.saveSlot.save(ArcherySave(progress: progress, round: round, aim: aim, elapsed: elapsed(),
                                          resultRecorded: resultRecorded))
    }

    private func show(notice text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_400_000_000)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    private func describe(_ shot: Shot) -> String {
        let hit = shot.hit
        let what: String
        if hit.repeatSpot {
            what = "Spot already used, no score."
        } else if !hit.inBoss {
            what = "Missed the target."
        } else if hit.isX {
            what = "X, inner ten."
        } else if hit.ring == 0 {
            what = "Miss."
        } else {
            what = "\(hit.ring)."
        }
        return what + " Score \(displayedScore)."
    }

    private func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
