import Foundation

/// The crosswind across the range, changing smoothly over time.
public struct Wind: Hashable, Codable, Sendable {
    /// Average speed in metres per second. Positive blows from left to right.
    public let base: Double
    /// How far gusts swing the speed either side of the average, in metres per second.
    public let gust: Double
    /// Seconds for one slow gust cycle. A faster ripple rides on top of it.
    public let period: Double
    /// Where in the cycle the level starts (shifted on every attempt).
    public let phase: Double

    public init(base: Double, gust: Double = 0, period: Double = 8, phase: Double = 0) {
        precondition(period > 0, "period must be positive")
        self.base = base
        self.gust = gust
        self.period = period
        self.phase = phase
    }

    public static let calm = Wind(base: 0)

    /// Speed at `time` seconds into the level. Positive blows to the right.
    public func speed(at time: Double) -> Double {
        guard gust != 0 else { return base }
        let slow = sin(2 * .pi * time / period + phase)
        let ripple = sin(2 * .pi * time / (period * 0.37) + 2.3 * phase + 0.8)
        return base + gust * (0.72 * slow + 0.28 * ripple)
    }

    /// How far the air has moved by `time`: the integral of the speed, in metres. Used to drift
    /// seeds and leaves across the view at exactly the speed of the wind.
    public func travel(at time: Double) -> Double {
        guard gust != 0 else { return base * time }
        let slow = period / (2 * .pi)
        let fast = period * 0.37 / (2 * .pi)
        return base * time
            - gust * 0.72 * slow * cos(2 * .pi * time / period + phase)
            - gust * 0.28 * fast * cos(2 * .pi * time / (period * 0.37) + 2.3 * phase + 0.8)
    }

    /// The fastest the wind ever blows, either way.
    public var strongest: Double { abs(base) + abs(gust) }

    public var isCalm: Bool { strongest < 0.05 }

    public func shifted(by extra: Double) -> Wind {
        Wind(base: base, gust: gust, period: period, phase: phase + extra)
    }

    /// "2.4 m/s from the left", "Calm".
    public static func describe(_ speed: Double) -> String {
        let rounded = (abs(speed) * 10).rounded() / 10
        guard rounded >= 0.1 else { return "Calm" }
        return String(format: "%.1f m/s from the %@", rounded, speed > 0 ? "left" : "right")
    }
}

/// How the target moves.
public enum Motion: Hashable, Codable, Sendable {
    /// Stands still on its stand.
    case still
    /// Slides from side to side on a rail, `amplitude` metres each way.
    case slide(amplitude: Double, period: Double)
    /// Hangs from a frame on ropes `length` metres long and swings `angle` radians each way,
    /// rising a little at each end of the swing like any pendulum.
    case swing(length: Double, angle: Double, period: Double)

    /// Offset from the rest position at `time` seconds into the level.
    public func offset(at time: Double, phase: Double = 0) -> Vec2 {
        switch self {
        case .still:
            return .zero
        case .slide(let amplitude, let period):
            return Vec2(amplitude * sin(2 * .pi * time / period + phase), 0)
        case .swing(let length, let angle, let period):
            let theta = angle * sin(2 * .pi * time / period + phase)
            return Vec2(length * sin(theta), length * (1 - cos(theta)))
        }
    }

    public var isMoving: Bool { self != .still }

    /// Top speed across the range, in metres per second.
    public var topSpeed: Double {
        switch self {
        case .still: return 0
        case .slide(let amplitude, let period): return amplitude * 2 * .pi / period
        case .swing(let length, let angle, let period): return length * angle * 2 * .pi / period
        }
    }
}

/// How the sight drifts while the bow is held at full draw. The first moments are shaky while
/// the archer settles, then there is a steady window of a few seconds, after which the arms tire
/// and the sight wanders further the longer you hold.
public enum Sway {
    /// Seconds from touching the screen to full draw.
    public static let drawTime = 0.45
    /// Seconds after full draw before the arms start to tire.
    public static let steadyTime = 3.0
    /// Sway angle at its calmest, in radians, before the level's own multiplier.
    public static let baseAngle = 0.0011

    /// How much the sight is moving `held` seconds after full draw, relative to its calmest.
    public static func amplitude(held: Double) -> Double {
        guard held >= 0 else { return 0 }
        let settling = 1.4 * exp(-held / 0.4)
        let tiring = held > steadyTime ? 0.5 * pow(held - steadyTime, 1.4) : 0
        return 1 + settling + tiring
    }

    /// The sight's offset in metres on a target `distance` away. `seed` gives every arrow its own
    /// pattern, `strength` is the level's sway multiplier.
    public static func offset(held: Double, seed: UInt64, strength: Double, distance: Double) -> Vec2 {
        guard held > 0, strength > 0 else { return .zero }
        var generator = SeededGenerator(seed: seed)
        func wave() -> (Double, Double) {
            (generator.uniform(0.32...0.95) * 2 * .pi, generator.uniform(0...(2 * .pi)))
        }
        let (w1, p1) = wave(), (w2, p2) = wave(), (w3, p3) = wave(), (w4, p4) = wave()
        let x = 0.64 * sin(w1 * held + p1) + 0.36 * sin(w2 * held + p2)
        let y = 0.64 * sin(w3 * held + p3) + 0.36 * sin(w4 * held + p4)
        // Ease in over the first moments so the sight does not jump at full draw.
        let ease = min(1, held / 0.3)
        let scale = baseAngle * strength * distance * amplitude(held: held) * ease * ease * (3 - 2 * ease)
        return Vec2(x * scale, y * 0.85 * scale)
    }
}
