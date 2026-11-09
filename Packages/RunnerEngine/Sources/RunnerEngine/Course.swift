import Foundation

/// What the runner can do. Each is one swipe.
public enum Move: String, Codable, CaseIterable, Sendable {
    case left, right, jump, slide
}

/// How the runner moves, in metres and seconds. Lanes are counted from the left, from 0.
public enum Body {
    public static let lanes = 3
    public static let startLane = 1
    /// Seconds to cross from one lane to the next.
    public static let laneChangeTime = 0.13
    public static let jumpSpeed = 8.75
    public static let gravity = 25.0
    /// A slide asked for in the air brings the runner down at least this fast.
    public static let dropSpeed = 14.0
    public static let slideTime = 0.62
    public static let height = 1.7
    public static let tuckedHeight = 0.6
    /// Half the room the runner takes along the course.
    static let halfDepth = 0.25
    /// How far to the side of an obstacle's lane (in lanes) the runner still hits it.
    static let reach = 0.42
    /// A jump asked for this long before landing happens on landing.
    static let jumpBuffer = 0.14

    /// Seconds in the air.
    public static var jumpTime: Double { 2 * jumpSpeed / gravity }

    /// Height of the feet `time` seconds into a jump.
    public static func jumpHeight(after time: Double) -> Double {
        max(0, jumpSpeed * time - gravity * time * time / 2)
    }
}

/// Something in a lane that ends the run if the runner touches it.
public struct Obstacle: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// A low rail: jump it.
        case barrier
        /// A bar at head height: slide under it.
        case beam
        /// Crates stacked too high to jump and too solid to slide under: go round.
        case stack
        /// A barrel rolling towards the runner: jump it.
        case barrel

        /// The heights it fills, in metres above the planks. A little less than it looks, for
        /// the low ones: a foot that seems to clip the top gets over.
        public var blocked: ClosedRange<Double> {
            switch self {
            case .barrier: return 0...0.55
            case .beam: return 1.05...2.6
            case .stack: return 0...2.6
            case .barrel: return 0...0.6
            }
        }

        /// The move that gets past it without leaving the lane.
        public var answer: Move? {
            switch self {
            case .barrier, .barrel: return .jump
            case .beam: return .slide
            case .stack: return nil
            }
        }
    }

    /// A barrel is on the course from this long before the runner meets it.
    public static let barrelNotice = 3.0

    public let kind: Kind
    public let lane: Int
    /// Where the runner reaches its near side, in metres from the start.
    public let position: Double
    public let length: Double
    /// How fast it rolls towards the runner (0 for everything but a barrel).
    public let rollSpeed: Double
    /// When a rolling obstacle is at `position`.
    public let meetTime: Double

    public init(_ kind: Kind, lane: Int, position: Double, length: Double? = nil, rollSpeed: Double = 0, meetTime: Double = 0) {
        self.kind = kind
        self.lane = lane
        self.position = position
        self.length = length ?? Self.usualLength(of: kind)
        self.rollSpeed = rollSpeed
        self.meetTime = meetTime
    }

    static func usualLength(of kind: Kind) -> Double {
        switch kind {
        case .barrier, .beam: return 0.3
        case .stack: return 1.4
        case .barrel: return 0.7
        }
    }

    /// Where its near side is at `time`.
    public func nearSide(at time: Double) -> Double {
        position + rollSpeed * (meetTime - time)
    }

    public func isOnCourse(at time: Double) -> Bool {
        rollSpeed == 0 || time >= meetTime - Self.barrelNotice
    }
}

public struct Coin: Codable, Equatable, Sendable {
    public let lane: Int
    public let position: Double
    /// Height of its middle above the planks.
    public let height: Double

    /// Where a coin sits for a runner on the ground.
    public static let usualHeight = 0.9

    public init(lane: Int, position: Double, height: Double = Coin.usualHeight) {
        self.lane = lane
        self.position = position
        self.height = height
    }
}

/// A power-up lying on the course.
public struct Pickup: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// Pulls in the coins of every lane for a while.
        case magnet
        /// Takes one hit.
        case shield
    }

    public let kind: Kind
    public let lane: Int
    public let position: Double

    public static let height = 1.0

    public init(kind: Kind, lane: Int, position: Double) {
        self.kind = kind
        self.lane = lane
        self.position = position
    }
}

/// How the run speeds up and the course tightens with distance.
public enum Pace {
    /// 0 at the start, rising towards 1 the further the runner gets.
    public static func difficulty(at distance: Double) -> Double {
        1 - exp(-max(0, distance) / 1_500)
    }

    /// The runner's speed, in metres a second.
    public static func speed(at distance: Double) -> Double {
        9.5 + 12.5 * difficulty(at: distance)
    }

    /// Seconds between one row of obstacles and the next.
    static func rowGap(at distance: Double) -> Double {
        0.62 + 0.78 * exp(-max(0, distance) / 900)
    }

    /// Metres from a row at `position` to the row after it.
    static func rowSpacing(at position: Double) -> Double {
        speed(at: position) * rowGap(at: position)
    }

    /// When a runner who is at `distance` at `time` gets to `position`.
    static func time(toReach position: Double, from distance: Double, at time: Double) -> Double {
        var distance = distance
        var time = time
        while distance < position {
            distance += speed(at: distance) * Run.step
            time += Run.step
        }
        return time
    }
}

/// The scores to aim for, one after the other.
public enum Goals {
    static let ladder = [250, 500, 750, 1_000, 1_500, 2_000, 2_500, 3_000, 4_000, 5_000, 6_000, 8_000, 10_000]

    /// The score to beat next, for a runner whose best so far is `best`.
    public static func next(after best: Int) -> Int {
        ladder.first { $0 > best } ?? (best / 2_500 + 1) * 2_500
    }
}
