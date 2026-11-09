import Foundation

/// A point or offset on the target, in metres. x grows to the right and y upwards, seen from
/// the shooting line. (0, 0) is the centre of the target boss at rest.
public struct Vec2: Hashable, Codable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, k: Double) -> Vec2 { Vec2(a.x * k, a.y * k) }
    public static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }

    public var length: Double { (x * x + y * y).squareRoot() }
    public func distance(to other: Vec2) -> Double { (self - other).length }

    public var description: String {
        String(format: "(%.3f,%.3f)", x, y)
    }
}

/// A point in the world, in metres: x to the right, y up from the ground, z down the range from
/// the shooting line.
public struct Vec3: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Vec3, k: Double) -> Vec3 { Vec3(a.x * k, a.y * k, a.z * k) }
}

/// A small deterministic random number generator (SplitMix64). Bots and tests use it; play
/// itself has no randomness beyond the attempt number.
public struct SeededGenerator: RandomNumberGenerator, Hashable, Codable, Sendable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform double in `0..<1`.
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// Uniform double in `range`.
    public mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * nextUnit()
    }

    /// Normally distributed, mean 0 and standard deviation 1 (Box–Muller).
    public mutating func gaussian() -> Double {
        let u1 = max(nextUnit(), 1e-12)
        let u2 = nextUnit()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

/// A stable 64-bit mix of a few integers, used to give every arrow its own sway pattern.
func mix(_ values: Int...) -> UInt64 {
    var generator = SeededGenerator(seed: 0x5EED_A7C4)
    var result: UInt64 = 0
    for value in values {
        generator = SeededGenerator(seed: generator.next() ^ UInt64(bitPattern: Int64(value)))
        result ^= generator.next()
    }
    return result
}
