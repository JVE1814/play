import Foundation

/// How an arrow flies. The bow sight is set for each distance, so in still air an arrow lands
/// exactly where the sight was pointing. Gravity only shapes the arc you watch; the crosswind
/// pushes the arrow sideways while it is in the air, so longer shots drift further.
public enum Ballistics {
    /// Arrow speed in metres per second (a recurve target arrow).
    public static let arrowSpeed = 58.0
    /// Gravity for the drawn arc, scaled down so the arc stays on screen at long distances.
    public static let arcGravity = 3.0
    /// Where the arrow leaves the bow, relative to the archer's eye: a little below and to the side.
    public static let launchOffset = Vec3(0.06, -0.09, 0.6)
    /// Height of the archer's eye and of the boss centre above the ground, in metres.
    public static let eyeHeight = 1.55
    public static let bossHeight = 1.3

    /// Drift per metre per second of crosswind is `windScale · distance^windExponent` metres:
    /// about 7 cm at 18 m and 26 cm at 90 m. Real arrows drift less at short range, but then
    /// the wind would only matter at the far end of the game.
    public static let windScale = 0.0052
    public static let windExponent = 0.87

    public static func flightTime(distance: Double) -> Double {
        distance / arrowSpeed
    }

    /// Metres of drift per metre per second of steady crosswind at `distance`.
    public static func driftPerWind(distance: Double) -> Double {
        windScale * pow(distance, windExponent)
    }

    /// Sideways drift in metres for an arrow released at `release` (level time) towards a target
    /// `distance` away. The wind is followed as it changes during the flight; as with a real
    /// arrow, wind early in the flight counts for more than wind near the target.
    public static func drift(distance: Double, wind: Wind, release: Double) -> Double {
        guard !wind.isCalm else { return 0 }
        let duration = flightTime(distance: distance)
        let steps = 32
        var weighted = 0.0
        var total = 0.0
        for step in 0..<steps {
            let s = (Double(step) + 0.5) / Double(steps)
            let weight = 1 - s
            weighted += weight * wind.speed(at: release + s * duration)
            total += weight
        }
        return driftPerWind(distance: distance) * weighted / total
    }

    /// The drift if the wind stayed exactly as it is at `release`: what an archer reading the
    /// flag would expect.
    public static func expectedDrift(distance: Double, windSpeed: Double) -> Double {
        driftPerWind(distance: distance) * windSpeed
    }
}

/// The arrow's path through the world, for drawing it in flight.
public struct FlightPath: Hashable, Sendable {
    /// Where the arrow leaves the bow (world coordinates).
    public let start: Vec3
    /// Where it lands (world coordinates), or where it passes the target when it misses.
    public let end: Vec3
    /// Sideways drift reached at the target.
    public let drift: Double
    public let duration: Double

    /// `impact` is where the arrow landed relative to the boss centre, and `targetOffset` is how
    /// far the boss had moved from its rest position when the arrow arrived. `mirrored` launches
    /// from the left of the eye, for a left-handed archer.
    public init(distance: Double, impact: Vec2, targetOffset: Vec2, drift: Double, mirrored: Bool = false) {
        let launch = Ballistics.launchOffset
        start = Vec3(mirrored ? -launch.x : launch.x, Ballistics.eyeHeight + launch.y, launch.z)
        let world = impact + targetOffset
        end = Vec3(world.x, Ballistics.bossHeight + world.y, distance)
        self.drift = drift
        duration = Ballistics.flightTime(distance: distance)
    }

    /// Position after `fraction` (0...1) of the flight.
    public func position(at fraction: Double) -> Vec3 {
        let s = min(1, max(0, fraction))
        let t = s * duration
        // The aim line leads to the landing point less the drift; the wind adds the drift
        // growing with the square of time, and the arc rises above the line and falls back.
        let x = start.x + (end.x - drift - start.x) * s + drift * s * s
        let arc = 0.5 * Ballistics.arcGravity * t * (duration - t)
        let y = start.y + (end.y - start.y) * s + arc
        let z = start.z + (end.z - start.z) * s
        return Vec3(x, y, z)
    }

    /// Direction of travel at `fraction` of the flight (not normalised).
    public func heading(at fraction: Double) -> Vec3 {
        let a = position(at: max(0, fraction - 0.01))
        let b = position(at: min(1, fraction + 0.01))
        return b - a
    }
}

/// How big the target looks. The view is magnified like a sight's scope, so that a 122 cm face
/// fills half the width of the screen up to about 20 m and a quarter of it at 90 m: far targets
/// look smaller, but never too small to aim at, and near ones leave room for the wind flag.
public enum Optics {
    /// Apparent width of a 122 cm face, as a share of the view's width.
    public static func faceShare(distance: Double) -> Double {
        min(0.5, max(0.2, 0.56 * (18 / distance).squareRoot()))
    }

    /// Screen points per metre at the target, for a view `viewWidth` points wide.
    public static func pointsPerMetre(distance: Double, viewWidth: Double) -> Double {
        faceShare(distance: distance) * viewWidth / 1.22
    }

    /// The phone width the bots aim on.
    public static let referenceWidth = 400.0
}
