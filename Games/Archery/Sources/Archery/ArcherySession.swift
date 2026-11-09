import ArcheryEngine
import Foundation
import PlayKit

/// The level in progress: wraps the engine with drawing, aiming, the arrow's flight, progress,
/// statistics and saving. The view layer only calls these methods.
///
/// Every arrow is committed to the round (and saved) the moment it is released; `landedArrows`
/// trails behind while the arrow is still in the air, so a force quit mid-flight loses nothing.
@MainActor
public final class ArcherySession: ObservableObject, LevelSession {
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
        /// Seconds until the arrow reaches the target.
        public let arrival: TimeInterval
        /// Seconds it stays in the air: an arrow that misses the boss carries on past it.
        public let duration: TimeInterval
    }

    /// The arrow that landed last, for the score that pops up beside it.
    public struct Landing: Equatable {
        public let arrow: Int
        public let shot: Shot
        public let date: Date
    }

    @Published public private(set) var round: ArcheryRound
    @Published public private(set) var progress: LevelProgress
    /// Where the thumb has put the sight, before sway (target coordinates, boss at rest).
    @Published public private(set) var aim: Vec2
    @Published public private(set) var draw: Draw? = nil
    @Published public private(set) var flight: Flight? = nil
    @Published public private(set) var landing: Landing? = nil
    /// Arrows that have reached the target (one fewer than shot while an arrow is in the air).
    @Published public private(set) var landedArrows: Int
    @Published public private(set) var showsResult: Bool
    @Published public var showingTip: Bool
    @Published public var showingLevels = false
    @Published public var confirmingRestart = false
    /// A short message, such as why an arrow was not shot.
    @Published public private(set) var notice: String? = nil

    public let context: GameContext
    public let preferences: ArcheryPreferences

    private var resultRecorded: Bool
    /// Time spent on this attempt, for statistics: from the first draw to the end.
    private var playClock: PlayClock
    private var inView = false
    /// The display clock when it was paused after the last arrow, so a moving target carries
    /// on from where it was rather than jumping back to the moment the end finished.
    private var heldClock: Double?
    /// The level clock at a moment of real time, while the level is on screen. Between syncs the
    /// clock runs on from here. It keeps running after the last arrow so a moving target keeps
    /// moving behind the result.
    private var clockAnchor: (clock: Double, date: Date)?
    /// Recent sight positions, so lifting the thumb (which tends to nudge it) does not move the shot.
    private var aimHistory: [(date: Date, aim: Vec2)] = []
    private let flightEnd = Pending()
    private let resultReveal = Pending()
    private let noticeEnd = Pending()
    private let fullDraw = Pending()
    private var tickTask: Task<Void, Never>?
    private var lastSaved = Date.distantPast

    /// The moments before lifting the thumb that are ignored.
    static let releaseFilter: TimeInterval = 0.07
    /// A hold inside the steady window: for an arrow shot with VoiceOver, and the screenshot pose.
    static let steadyHold = 1.2

    public init(context: GameContext) {
        self.context = context
        self.preferences = context.preferences(ArcheryPreferences.self)
        let options = context.options
        let initial: ArcheryRound
        var startAim: Vec2
        if let save = context.saveSlot.load(ArcherySave.self) {
            initial = save.round
            progress = save.progress
            startAim = save.aim
            playClock = PlayClock(elapsed: save.elapsed)
            resultRecorded = save.resultRecorded
        } else {
            let start = options.startLevel(of: LevelCatalog.count)
            initial = Scenarios.round(options.scenario) ?? ArcheryRound(level: LevelCatalog.level(start))
            progress = LevelProgress(unlocked: initial.level.number)
            startAim = initial.shots.last?.aim ?? initial.level.layout.spots[0].center
            playClock = PlayClock()
            resultRecorded = false
        }
        // `-demoAim X`: for screenshots, the bow held at full draw with the sight X metres aside.
        var demoDraw: Draw?
        if let demo = options.value(after: "-demoAim").flatMap({ Double($0) }), initial.status == .playing {
            startAim = startAim + Vec2(demo, 0)
            demoDraw = Draw(start: Date(), frozenHeld: Self.steadyHold)
        }
        round = initial
        aim = startAim
        landedArrows = initial.shots.count
        showsResult = initial.isOver
        showingTip = initial.shots.isEmpty && !initial.isOver && demoDraw == nil
        draw = demoDraw
        if round.isOver && !resultRecorded {
            // The app closed while the last arrow was in the air: record the end now.
            checkFinished(at: Date(), quietly: true)
        }
        save()
    }

    // MARK: State for the view

    public var level: Level { round.level }
    public var levelNumber: Int { round.level.number }
    public var levelCount: Int { LevelCatalog.count }
    public var isPlaying: Bool { round.status == .playing }
    /// A new arrow can be drawn: the level is on, and the last arrow has landed.
    public var canDraw: Bool { isPlaying && flight == nil && draw == nil }
    public var isDrawing: Bool { draw != nil }
    public var hasAttemptInProgress: Bool { isPlaying && !round.shots.isEmpty }
    /// A restart waits for the arrow in the air to land.
    public var canRestart: Bool { flight == nil }

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
        round.timeLeft(at: isPlaying ? clock(at: date) : round.clock)
    }

    /// Seconds since full draw at `date` (negative while still drawing).
    public func held(at date: Date = Date()) -> Double? {
        draw.map { held($0, at: date) }
    }

    private func held(_ draw: Draw, at date: Date) -> Double {
        draw.frozenHeld ?? date.timeIntervalSince(draw.start) - Sway.drawTime
    }

    /// Where the sight points after `held` seconds at full draw: the aim plus the sway.
    private func sight(held: Double) -> Vec2 {
        aim + round.sway(held: held, strength: preferences.swayStrength)
    }

    /// 0 when the bow is down, 1 at full draw.
    public func drawProgress(at date: Date = Date()) -> Double {
        guard let draw else { return 0 }
        if draw.frozenHeld != nil { return 1 }
        return min(1, max(0, date.timeIntervalSince(draw.start) / Sway.drawTime))
    }

    /// Where the sight points at `date`, sway included.
    public func sight(at date: Date = Date()) -> Vec2 {
        held(at: date).map { sight(held: $0) } ?? aim
    }

    /// Whole state, for UI tests.
    public var signature: String { round.signature + "|landed:\(landedArrows)|unlocked:\(progress.unlocked)" }

    // MARK: Lifecycle

    /// Out of view (the home screen, the background, Settings or the level list over the game),
    /// the bow comes down, an arrow in the air lands at once and the clocks stop.
    public func setInView(_ inView: Bool) {
        self.inView = inView
        if !inView {
            cancelDraw()
            settleFlight(at: Date())
        }
        updateClock()
        save()
    }

    /// Lands an arrow still in the air at once, so leaving, restarting or closing the app never
    /// loses it (or the end it finishes).
    private func settleFlight(at now: Date) {
        guard let flight else { return }
        flightEnd.cancel()
        land(flight.shot, arrow: flight.arrow, at: now, quietly: true)
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
        fullDraw.schedule(after: Sway.drawTime) { [weak self] in self?.context.feedback.play(.draw) }
    }

    /// Thumb moved: move the sight by `delta` metres, keeping it within `limit` of the centre.
    public func moveAim(by delta: Vec2, limit: Vec2, at now: Date = Date()) {
        guard draw?.frozenHeld == nil, draw != nil else { return }
        aim = Vec2(min(limit.x, max(-limit.x, aim.x + delta.x)), min(limit.y, max(-limit.y, aim.y + delta.y)))
        aimHistory.append((now, aim))
        // Keep the newest sample older than half a second too: after a still hold it is the
        // aim the release filter falls back to.
        if let stale = aimHistory.lastIndex(where: { now.timeIntervalSince($0.date) > 0.5 }), stale > 0 {
            aimHistory.removeFirst(stale)
        }
    }

    /// Thumb up: loose the arrow, or let the bow down if it wasn't fully drawn.
    public func release(at now: Date = Date()) {
        guard let current = draw, current.frozenHeld == nil else { return }
        draw = nil
        fullDraw.cancel()
        let held = self.held(current, at: now)
        guard held >= 0 else {
            show(notice: "Hold until the bow is fully drawn, then let go.")
            return
        }
        // Ignore the last few hundredths of a second: lifting the thumb tends to nudge it.
        if let settled = aimHistory.last(where: { now.timeIntervalSince($0.date) >= Self.releaseFilter }) {
            aim = settled.aim
        }
        shoot(sight: sight(held: held), at: now)
    }

    /// Stops drawing without shooting (the view disappeared, or the clock ran out).
    public func cancelDraw() {
        guard draw?.frozenHeld == nil else { return }
        draw = nil
        fullDraw.cancel()
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
        guard context.animationsEnabled else {
            land(shot, arrow: index, at: now)
            return
        }
        // A moving target is shown exactly where the engine says it is when the arrow arrives.
        let arrival = round.level.motion.isMoving ? path.duration : max(0.24, path.duration)
        let duration = shot.hit.inBoss ? arrival : arrival * 1.25
        flight = Flight(shot: shot, arrow: index, path: path, start: now, arrival: arrival, duration: duration)
        flightEnd.schedule(after: duration) { [weak self] in self?.land(shot, arrow: index, at: Date()) }
    }

    private func land(_ shot: Shot, arrow: Int, at now: Date, quietly: Bool = false) {
        flight = nil
        landedArrows = min(round.shots.count, arrow + 1)
        landing = Landing(arrow: arrow, shot: shot, date: now)
        if !quietly {
            // A thunk whenever the arrow goes into the boss; a miss that flies past just goes quiet.
            context.feedback.play(shot.hit.inBoss ? .hit : .invalid)
            let advice = coaching(for: shot)
            context.announce(describe(shot) + (advice.map { " " + $0 } ?? ""))
            if let advice { show(notice: advice) }
        }
        checkFinished(at: now, quietly: quietly)
    }

    /// In the first three venues, a word on what the wind or a moving target did to the arrow,
    /// and which way to adjust if it landed off centre.
    func coaching(for shot: Shot) -> String? {
        let level = round.level
        guard level.chapter.rawValue <= Chapter.lakeside.rawValue, shot.hit.inBoss, !round.isOver else { return nil }
        let ring = level.layout.largestFace.ringWidth
        let aimedAt = level.layout.spots[shot.hit.spot ?? 0].center
        let miss = shot.hit.point.x - aimedAt.x
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
        shoot(sight: sight(held: Self.steadyHold), at: now)
    }

    /// Names for the faces of a three-spot target, top to bottom.
    static func spotName(_ index: Int, of count: Int) -> String {
        count == 3 ? ["top", "middle", "bottom"][index] : "spot \(index + 1)"
    }

    private var nearestSpot: Int {
        let spots = round.level.layout.spots
        return spots.indices.min { spots[$0].center.distance(to: aim) < spots[$1].center.distance(to: aim) } ?? 0
    }

    /// Moves the sight to the middle of the next face that has no arrow yet (three-spot targets).
    public func aimAtNextFreeSpot() {
        guard isPlaying, round.level.layout.spots.count > 1 else { return }
        let spots = round.level.layout.spots
        let free = spots.indices.filter { !round.usedSpots.contains($0) }
        guard !free.isEmpty else { return }
        let next = free.first { $0 > nearestSpot } ?? free[0]
        aim = spots[next].center
        showingTip = false
    }

    /// The sight, wind and arrows, in words.
    public func spokenStatus(at date: Date = Date()) -> String {
        var parts: [String] = []
        let spots = round.level.layout.spots
        let spot = nearestSpot
        if spots.count > 1 {
            let free = spots.indices.filter { !round.usedSpots.contains($0) }.map { Self.spotName($0, of: spots.count) }
            parts.append("On the \(Self.spotName(spot, of: spots.count)) spot.")
            parts.append(describeSight(aim - spots[spot].center))
            parts.append(free.isEmpty ? "Every spot has an arrow." : "Free: " + free.joined(separator: ", ") + ".")
        } else {
            parts.append(describeSight(aim - spots[0].center))
        }
        parts.append("Wind " + Self.spokenWind(round.windSpeed(at: clock(at: date))) + ".")
        if round.level.motion.isMoving { parts.append("The target is moving.") }
        parts.append("\(Format.count(displayedArrowsLeft, "arrow")) left.")
        return parts.joined(separator: " ")
    }

    private func describeSight(_ offset: Vec2) -> String {
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

    /// Leaving a level unfinished is not a loss.
    public func start(level number: Int) {
        guard progress.isUnlocked(number) else { return }
        // An end that is already decided (its last arrow still in the air) is recorded first.
        settleFlight(at: Date())
        resultReveal.cancel()
        noticeEnd.cancel()
        cancelDraw()
        stopClock()
        let level = LevelCatalog.level(number)
        round = ArcheryRound(level: level, attempt: round.attempt + 1)
        aim = level.layout.spots[0].center
        draw = nil
        landing = nil
        landedArrows = 0
        playClock = PlayClock()
        resultRecorded = false
        showsResult = false
        confirmingRestart = false
        showingLevels = false
        showingTip = true
        notice = nil
        heldClock = nil
        updateClock()
        save()
        context.feedback.play(.draw)
        context.announce("Level \(number), \(level.name). \(level.summary).")
    }

    // MARK: Internals

    /// Records the end once every arrow has landed (or the time ran out): progress, statistics
    /// and the result. `quietly` skips sounds and announcements (the app is closing or restarting).
    private func checkFinished(at now: Date, quietly: Bool = false) {
        guard round.isOver, landedArrows >= round.shots.count, flight == nil, !resultRecorded else { return }
        cancelDraw()
        resultRecorded = true
        updateRunClock(now)
        let score = round.score
        progress.record(level: round.level.number, stars: round.stars, score: score, of: LevelCatalog.count)
        if round.passed {
            context.recordWin(time: playClock.elapsed(at: now))
            if !quietly {
                context.feedback.play(.win)
                context.announce("Level complete with \(score) points and \(Format.count(round.stars, "star")).")
            }
        } else {
            context.recordLoss()
            if !quietly {
                context.feedback.play(.invalid)
                context.announce(round.timedOut ? "Out of time with \(score) points."
                                 : "\(score) points. Not quite enough for a star.")
            }
        }
        save()
        // The last arrow's score is seen before the panel covers it.
        resultReveal.schedule(after: context.animationsEnabled && !quietly ? 0.9 : 0) { [weak self] in
            self?.showsResult = true
        }
    }

    private func updateClock(_ now: Date = Date()) {
        if inView {
            if clockAnchor == nil { clockAnchor = (heldClock ?? round.clock, now) }
            startTicking()
        } else {
            stopClock(now)
        }
        updateRunClock(now)
    }

    /// On a timed level this is where time runs out.
    private func syncClock(_ now: Date = Date()) {
        guard clockAnchor != nil else { return }
        let time = clock(at: now)
        if round.status == .playing {
            round.advance(to: time)
            if round.isOver { checkFinished(at: now) }
        }
        clockAnchor = (round.status == .playing ? round.clock : time, now)
    }

    private func stopClock(_ now: Date = Date()) {
        syncClock(now)
        if round.status != .playing, let anchor = clockAnchor { heldClock = anchor.clock }
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

    private func updateRunClock(_ now: Date = Date()) {
        let started = !round.shots.isEmpty || draw != nil || playClock.hasStarted
        playClock.setRunning(inView && started && !resultRecorded, at: now)
    }

    private func save() {
        lastSaved = Date()
        context.saveSlot.save(ArcherySave(progress: progress, round: round, aim: aim, elapsed: playClock.elapsed(),
                                          resultRecorded: resultRecorded))
    }

    private func show(notice text: String) {
        notice = text
        noticeEnd.schedule(after: 3.4) { [weak self] in self?.notice = nil }
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
}

private func centimetres(_ metres: Double) -> Int { Int((abs(metres) * 100).rounded()) }
