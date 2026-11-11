import Foundation

/// A printed target face with ten scoring rings, like those used in target archery: two gold
/// rings (10 and 9), then red, blue, black and white. The inner ten is the X ring.
public struct Face: Hashable, Codable, Sendable {
    /// Diameter of the full ten-ring face of this size, in metres (1.22, 0.80, 0.60 or 0.40).
    public let size: Double
    /// Lowest ring printed: 1 for a full face, 6 for a spot (gold, red and the inner blue ring).
    public let lowestRing: Int

    public init(size: Double, lowestRing: Int = 1) {
        precondition(size > 0 && (1...10).contains(lowestRing), "invalid face")
        self.size = size
        self.lowestRing = lowestRing
    }

    public static let full122 = Face(size: 1.22)
    public static let full80 = Face(size: 0.80)
    public static func spot(_ size: Double) -> Face { Face(size: size, lowestRing: 6) }

    public var ringWidth: Double { size / 20 }
    /// Outer radius of the printed face.
    public var radius: Double { outerRadius(ofRing: lowestRing) }
    /// Outer radius of ring `ring` (1...10).
    public func outerRadius(ofRing ring: Int) -> Double { Double(11 - ring) * ringWidth }
    /// The X ring, the inner half of the ten.
    public var xRadius: Double { ringWidth / 2 }

    /// The score for an arrow whose centre is `distance` from the middle. An arrow that touches a
    /// line scores the higher ring, as in real archery.
    public func score(distance: Double) -> (ring: Int, isX: Bool) {
        let reach = max(0, distance - Arrow.radius)
        for ring in stride(from: 10, through: lowestRing, by: -1) where reach <= outerRadius(ofRing: ring) {
            return (ring, ring == 10 && reach <= xRadius)
        }
        return (0, false)
    }

    /// Ring colours, from the outside in.
    public enum Zone: String, Sendable {
        case white, black, blue, red, gold
    }

    public static func zone(ofRing ring: Int) -> Zone {
        switch ring {
        case 9...10: return .gold
        case 7...8: return .red
        case 5...6: return .blue
        case 3...4: return .black
        default: return .white
        }
    }
}

/// The arrow itself: only its thickness matters for scoring.
public enum Arrow {
    /// Shaft radius in metres (a 7 mm target arrow).
    public static let radius = 0.0035
    /// Shaft length in metres, for drawing.
    public static let length = 0.72
}

/// One face pinned on the boss, at an offset from the boss centre.
public struct Spot: Hashable, Codable, Sendable {
    public let center: Vec2
    public let face: Face

    public init(center: Vec2 = .zero, face: Face) {
        self.center = center
        self.face = face
    }
}

/// What stands at the end of the range: a boss (a square foam butt) with one or more faces.
public struct TargetLayout: Hashable, Codable, Sendable {
    public let spots: [Spot]
    /// Each spot takes one arrow; a second arrow in the same spot scores as a miss.
    public let onePerSpot: Bool
    /// The boss is a square this wide, centred on (0, 0). Arrows outside it fly past.
    public let bossSize: Double

    public init(spots: [Spot], onePerSpot: Bool = false, bossSize: Double = 1.3) {
        precondition(!spots.isEmpty, "a target needs at least one face")
        self.spots = spots
        self.onePerSpot = onePerSpot
        self.bossSize = bossSize
    }

    /// One face in the middle of the boss.
    public static func single(_ face: Face) -> TargetLayout {
        TargetLayout(spots: [Spot(face: face)])
    }

    /// Three spot faces in a column, one arrow each.
    public static func threeSpots(size: Double) -> TargetLayout {
        let face = Face.spot(size)
        let gap = face.radius * 2 + size * 0.1
        return TargetLayout(spots: [gap, 0, -gap].map { Spot(center: Vec2(0, $0), face: face) }, onePerSpot: true)
    }

    /// The largest face, which sets how big the target looks on screen.
    public var largestFace: Face { spots.map(\.face).max { $0.radius < $1.radius }! }

    /// Scores an arrow at `point` (relative to the boss centre). `used` lists spots that already
    /// hold an arrow, for one-arrow-per-spot targets.
    public func hit(at point: Vec2, used: Set<Int> = []) -> Hit {
        let half = bossSize / 2
        let inBoss = abs(point.x) <= half && abs(point.y) <= half
        guard inBoss else { return Hit(point: point, ring: 0, isX: false, spot: nil, inBoss: false, repeatSpot: false) }
        var best: (index: Int, ring: Int, isX: Bool)?
        for (index, spot) in spots.enumerated() {
            let result = spot.face.score(distance: point.distance(to: spot.center))
            if result.ring > 0, result.ring > (best?.ring ?? 0) {
                best = (index, result.ring, result.isX)
            }
        }
        guard let best else { return Hit(point: point, ring: 0, isX: false, spot: nil, inBoss: true, repeatSpot: false) }
        if onePerSpot && used.contains(best.index) {
            return Hit(point: point, ring: 0, isX: false, spot: best.index, inBoss: true, repeatSpot: true)
        }
        return Hit(point: point, ring: best.ring, isX: best.isX, spot: best.index, inBoss: true, repeatSpot: false)
    }
}

/// Where an arrow ended up and what it scored.
public struct Hit: Hashable, Codable, Sendable {
    /// Relative to the boss centre at the moment the arrow arrived.
    public let point: Vec2
    /// 10 to 1, or 0 for a miss.
    public let ring: Int
    public let isX: Bool
    /// The face the arrow is in, if any.
    public let spot: Int?
    /// False when the arrow missed the boss altogether and flew past.
    public let inBoss: Bool
    /// A second arrow in a one-arrow spot: it scores as a miss.
    public let repeatSpot: Bool

    public var score: Int { ring }

    /// "X", "10" … "1", or "M" for a miss, as on a score sheet.
    public var label: String {
        if isX { return "X" }
        return ring == 0 ? "M" : "\(ring)"
    }
}
