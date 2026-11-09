import Foundation

public struct Shot: Hashable, Codable, Sendable {
    /// Where the sight pointed when the arrow was released (target coordinates, boss at rest).
    public let aim: Vec2
    /// Level time of the release, in seconds.
    public let release: Double
    /// Crosswind at the release, in metres per second.
    public let windAtRelease: Double
    /// Sideways drift the wind gave the arrow over its flight.
    public let drift: Double
    /// How far the target had moved from its rest position when the arrow arrived.
    public let targetOffset: Vec2
    public let hit: Hit

    public var score: Int { hit.score }
}

/// One attempt at a level: the arrows shot so far, the level clock (which drives the wind and
/// any moving target) and, on timed levels, the countdown.
public struct ArcheryRound: Hashable, Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        case playing
        /// Every arrow is shot, or the time ran out.
        case finished
    }

    public let level: Level
    /// Every attempt starts the wind and any moving target at a different point of their cycles.
    public let attempt: Int
    public let wind: Wind
    public let motionPhase: Double
    /// Seconds of play since the level began. Only advances while the level is on screen.
    public private(set) var clock: Double = 0
    /// Level time of the first draw, which starts the countdown on timed levels.
    public private(set) var timerStart: Double?
    public private(set) var shots: [Shot] = []
    public private(set) var status: Status = .playing
    /// Set when the countdown ran out with arrows still in the quiver.
    public private(set) var timedOut = false

    public init(level: Level, attempt: Int = 0) {
        self.level = level
        self.attempt = attempt
        let shift = Double(attempt) * 2.399_963 // the golden angle: attempts never line up
        wind = level.wind.shifted(by: shift)
        motionPhase = shift * 0.71
    }

    // MARK: Conditions

    public func windSpeed(at time: Double) -> Double { wind.speed(at: time) }
    public var windNow: Double { windSpeed(at: clock) }

    /// How far the target has moved from its rest position at `time`.
    public func targetOffset(at time: Double) -> Vec2 { level.motion.offset(at: time, phase: motionPhase) }

    // MARK: Progress

    public var arrowsShot: Int { shots.count }
    public var arrowsLeft: Int { status == .playing ? level.arrows - shots.count : 0 }
    public var score: Int { shots.reduce(0) { $0 + $1.score } }
    public var xCount: Int { shots.filter(\.hit.isX).count }
    public var maxScore: Int { level.maxScore }
    public var isOver: Bool { status == .finished }
    public var passed: Bool { score >= level.starScores[0] }
    /// Stars earned so far (0 to 3).
    public var stars: Int { level.stars(for: score) }

    /// Spots that already hold a scoring arrow (for one-arrow-per-spot targets).
    public var usedSpots: Set<Int> {
        Set(shots.compactMap { $0.hit.repeatSpot ? nil : $0.hit.spot })
    }

    /// Seconds left on a timed level (the full limit until the first draw).
    public var timeLeft: Double? { timeLeft(at: clock) }

    /// Seconds left when the level clock reads `time`.
    public func timeLeft(at time: Double) -> Double? {
        guard let limit = level.timeLimit else { return nil }
        guard let start = timerStart else { return limit }
        return max(0, limit - (time - start))
    }

    // MARK: Playing

    /// On a timed level, running out of time ends the attempt and the arrows left in the quiver
    /// score as misses.
    public mutating func advance(by seconds: Double) {
        guard status == .playing, seconds > 0 else { return }
        clock += seconds
        if let left = timeLeft, left <= 0, timerStart != nil {
            timedOut = true
            status = .finished
        }
    }

    /// Sets the clock directly (used when restoring and by tests).
    public mutating func advance(to time: Double) {
        advance(by: time - clock)
    }

    /// The first draw starts the countdown on a timed level.
    public mutating func startTimer() {
        guard status == .playing, timerStart == nil, level.timeLimit != nil else { return }
        timerStart = clock
    }

    /// Where an arrow released now with the sight at `aim` would land, and what it would score.
    public func preview(aim: Vec2) -> (hit: Hit, drift: Double, targetOffset: Vec2) {
        let arrival = clock + Ballistics.flightTime(distance: level.distance)
        let drift = Ballistics.drift(distance: level.distance, wind: wind, release: clock)
        let offset = targetOffset(at: arrival)
        let landing = aim + Vec2(drift, 0) - offset
        return (level.layout.hit(at: landing, used: usedSpots), drift, offset)
    }

    /// Returns nil once the attempt is over.
    @discardableResult
    public mutating func shoot(aim: Vec2) -> Shot? {
        guard status == .playing, arrowsLeft > 0 else { return nil }
        startTimer()
        let result = preview(aim: aim)
        let shot = Shot(aim: aim, release: clock, windAtRelease: windNow, drift: result.drift,
                        targetOffset: result.targetOffset, hit: result.hit)
        shots.append(shot)
        if shots.count == level.arrows { status = .finished }
        return shot
    }

    /// The aim that would put an arrow released now exactly on `point` of the target (relative
    /// to the boss centre). Used by the bots and to set up demonstrations.
    public func aim(toHit point: Vec2) -> Vec2 {
        let arrival = clock + Ballistics.flightTime(distance: level.distance)
        let drift = Ballistics.drift(distance: level.distance, wind: wind, release: clock)
        return point + targetOffset(at: arrival) - Vec2(drift, 0)
    }

    /// The pattern of sight sway for arrow number `index` (0-based) of this attempt.
    public func swaySeed(arrow index: Int) -> UInt64 {
        mix(level.number, attempt, index)
    }

    /// Sight sway in metres `held` seconds after full draw for the next arrow.
    public func sway(held: Double, strength: Double = 1) -> Vec2 {
        Sway.offset(held: held, seed: swaySeed(arrow: shots.count), strength: level.sway * strength,
                    distance: level.distance)
    }

    /// Everything that matters about the attempt, for UI tests (the clock is left out).
    public var signature: String {
        let arrows = shots.map { "\($0.hit.label)@\($0.hit.point)" }.joined(separator: ",")
        return "L\(level.number)|a\(attempt)|\(status.rawValue)|arrows:\(shots.count)/\(level.arrows)"
            + "|score:\(score)|hits:\(arrows)"
    }
}
