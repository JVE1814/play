import Foundation

/// How well a bot archer shoots. Two skill levels stand in for players when the levels are
/// tuned: the expert sets what three stars take, the novice what passing takes. Both aim on a
/// phone-sized view, misjudge the wind at first and learn from where their arrows land.
public struct ArcherSkill: Sendable {
    /// Random aiming error on screen (one standard deviation), in points.
    public let aimError: Double
    /// Share of the expected wind drift allowed for on the first arrow (1 = all of it).
    public let windAllowance: Double
    /// How much of the gap to the true drift each arrow closes (0...1).
    public let windLearning: Double
    /// Random error in the allowance, as a share of the drift (one standard deviation).
    public let windError: Double
    /// Share of a moving target's travel led on the first arrow (1 = exactly).
    public let leading: Double
    /// Random error in the lead, as a share of the target's travel.
    public let leadError: Double
    /// Share of the sight's sway the archer's finger cancels out.
    public let swayControl: Double
    /// Waits for a calm sight before letting go, rather than letting go whenever.
    public let patient: Bool
    /// Seconds spent between arrows (watching the flag, nocking the next arrow).
    public let pace: ClosedRange<Double>

    public init(aimError: Double, windAllowance: Double, windLearning: Double, windError: Double,
                leading: Double, leadError: Double, swayControl: Double, patient: Bool,
                pace: ClosedRange<Double>) {
        self.aimError = aimError
        self.windAllowance = windAllowance
        self.windLearning = windLearning
        self.windError = windError
        self.leading = leading
        self.leadError = leadError
        self.swayControl = swayControl
        self.patient = patient
        self.pace = pace
    }

    /// A practised player: reads the flag, leads moving targets and waits for a calm sight.
    public static let expert = ArcherSkill(aimError: 1.8, windAllowance: 0.85, windLearning: 0.7,
                                           windError: 0.15, leading: 0.85, leadError: 0.15, swayControl: 0.35,
                                           patient: true, pace: 1.0...2.5)
    /// A newcomer: allows for little wind at first, barely leads and lets go whenever.
    public static let novice = ArcherSkill(aimError: 4.0, windAllowance: 0.25, windLearning: 0.5,
                                           windError: 0.35, leading: 0.35, leadError: 0.35, swayControl: 0.1,
                                           patient: false, pace: 1.5...4.0)
}

/// A bot archer that plays a whole attempt through the same API as the app.
public struct Archer {
    public let skill: ArcherSkill
    public var generator: SeededGenerator
    /// Current belief about the wind: the share of the expected drift to allow for.
    private var windShare: Double
    /// Current belief about leading a moving target.
    private var leadShare: Double

    public init(skill: ArcherSkill, seed: UInt64) {
        self.skill = skill
        generator = SeededGenerator(seed: seed)
        windShare = skill.windAllowance
        leadShare = skill.leading
    }

    /// Plays `level` `attempts` times, each a fresh attempt by a fresh archer of `skill`, and
    /// returns the finished rounds. The level tests and `archery-calibrate` both judge the star
    /// scores on these.
    public static func play(_ level: Level, skill: ArcherSkill, attempts: Int) -> [ArcheryRound] {
        (0..<attempts).map { attempt in
            var round = ArcheryRound(level: level, attempt: attempt)
            var archer = Archer(skill: skill, seed: UInt64(attempt * 104_729 + level.number))
            archer.play(&round)
            return round
        }
    }

    /// Shoots every arrow of `round` (or until its time runs out).
    public mutating func play(_ round: inout ArcheryRound) {
        while round.status == .playing {
            round.advance(by: generator.uniform(skill.pace))
            guard round.status == .playing else { break }
            round.startTimer()
            round.advance(by: Sway.drawTime)
            let held = chooseHold(round)
            round.advance(by: held)
            guard round.status == .playing else { break }
            guard let shot = round.shoot(aim: chooseAim(round, held: held)) else { break }
            learn(from: shot, distance: round.level.distance, moving: round.level.motion.isMoving)
        }
    }

    /// Seconds to hold at full draw before letting go. A patient archer waits for the calmest
    /// moment of the steady window but reacts a little late.
    mutating func chooseHold(_ round: ArcheryRound) -> Double {
        guard skill.patient else { return generator.uniform(0.3...4.5) }
        var best = (held: 1.0, sway: Double.infinity)
        for step in 0...42 {
            let held = 0.5 + Double(step) * 0.05
            let sway = round.sway(held: held).length
            if sway < best.sway { best = (held, sway) }
        }
        return max(0.3, best.held + 0.12 + 0.06 * generator.gaussian())
    }

    /// Where the sight is when the arrow is released.
    mutating func chooseAim(_ round: ArcheryRound, held: Double) -> Vec2 {
        let layout = round.level.layout
        let spot = layout.onePerSpot
            ? (layout.spots.indices.first { !round.usedSpots.contains($0) } ?? 0)
            : 0
        let distance = round.level.distance
        let now = round.targetOffset(at: round.clock)
        let then = round.targetOffset(at: round.clock + Ballistics.flightTime(distance: distance))
        let lead = (then - now) * (leadShare + skill.leadError * generator.gaussian())
        let target = layout.spots[spot].center + now + lead
        let expected = Ballistics.expectedDrift(distance: distance, windSpeed: round.windNow)
        let allowance = expected * (windShare + skill.windError * generator.gaussian())
        let sway = round.sway(held: held) * (1 - skill.swayControl)
        let metresPerPoint = 1 / Optics.pointsPerMetre(distance: distance, viewWidth: Optics.referenceWidth)
        let noise = Vec2(generator.gaussian(), generator.gaussian()) * (skill.aimError * metresPerPoint)
        return target - Vec2(allowance, 0) + sway + noise
    }

    /// Seeing where the arrow went, the archer adjusts how much wind and lead to allow for.
    mutating func learn(from shot: Shot, distance: Double, moving: Bool) {
        let expected = Ballistics.expectedDrift(distance: distance, windSpeed: shot.windAtRelease)
        if abs(expected) > 0.01 {
            let observed = min(2, max(0, shot.drift / expected))
            windShare += skill.windLearning * (observed - windShare)
        }
        if moving { leadShare += skill.windLearning * 0.6 * (1 - leadShare) }
    }
}
