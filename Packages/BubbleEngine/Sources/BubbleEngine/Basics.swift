import Foundation

/// The six bubble colours. Each has its own symbol, so colours never have to be told apart by hue.
public enum BubbleColor: Int, CaseIterable, Codable, Sendable, Comparable {
    case red = 0, yellow, green, blue, purple, cyan

    public var name: String {
        switch self {
        case .red: return "Red"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .cyan: return "Cyan"
        }
    }

    public static func < (lhs: BubbleColor, rhs: BubbleColor) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What can occupy a cell of the grid.
public enum Bubble: Hashable, Codable, Sendable {
    /// A coloured bubble: pops in groups of three or more of the same colour.
    case color(BubbleColor)
    /// A grey stone: never matches; it only falls when cut loose, or breaks in a blast.
    case stone
    /// A bomb: a shot that lands next to it sets it off, clearing it and every bubble around it.
    case bomb

    public var color: BubbleColor? {
        if case .color(let color) = self { return color }
        return nil
    }

    /// One-character codes used in signatures and hand-built grids: r y g b p c for the
    /// colours, S for stone, B for bomb.
    private static let codes: [(code: Character, bubble: Bubble)] =
        zip("rygbpc", BubbleColor.allCases).map { ($0, .color($1)) } + [("S", .stone), ("B", .bomb)]

    public var code: Character { Self.codes.first { $0.bubble == self }!.code }

    public init?(code: Character) {
        guard let match = Self.codes.first(where: { $0.code == code }) else { return nil }
        self = match.bubble
    }
}

/// A cell of the hexagonal grid. Odd rows are shifted half a bubble to the right.
public struct Cell: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let row: Int
    public let column: Int

    public init(_ row: Int, _ column: Int) {
        self.row = row
        self.column = column
    }

    public static func < (lhs: Cell, rhs: Cell) -> Bool {
        (lhs.row, lhs.column) < (rhs.row, rhs.column)
    }

    public var description: String { "(\(row),\(column))" }
}

/// A point in grid units: one unit is one bubble diameter. x grows to the right, y downwards.
public struct Point: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static func + (a: Point, b: Point) -> Point { Point(a.x + b.x, a.y + b.y) }
    public static func - (a: Point, b: Point) -> Point { Point(a.x - b.x, a.y - b.y) }
    public static func * (a: Point, k: Double) -> Point { Point(a.x * k, a.y * k) }
    public func dot(_ other: Point) -> Double { x * other.x + y * other.y }
    public var length: Double { dot(self).squareRoot() }

    public var normalized: Point {
        let l = length
        return l > 0 ? Point(x / l, y / l) : self
    }

    public func distance(to other: Point) -> Double { (self - other).length }
}

/// A path as a list of corners, such as a shot with its bounces.
extension Array where Element == Point {
    public var pathLength: Double {
        zip(self, dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// The point `distance` along the path (its end, once the path runs out).
    public func point(atDistance distance: Double) -> Point? {
        var remaining = distance
        for (a, b) in zip(self, dropFirst()) {
            let length = a.distance(to: b)
            if remaining <= length, length > 0 { return a + (b - a) * (remaining / length) }
            remaining -= length
        }
        return last
    }

    /// The start of the path, cut off after `length`.
    public func truncated(to length: Double) -> [Point] {
        guard let first else { return [] }
        var result = [first]
        var remaining = length
        for (a, b) in zip(self, dropFirst()) {
            let step = a.distance(to: b)
            if step >= remaining {
                result.append(a + (b - a) * (remaining / step))
                break
            }
            result.append(b)
            remaining -= step
        }
        return result
    }
}

/// A small deterministic random number generator (SplitMix64) that can be saved with a game.
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

    /// Uniform integer in `0..<bound` (rejection sampling, no modulo bias).
    public mutating func nextInt(below bound: Int) -> Int {
        precondition(bound > 0, "bound must be positive")
        let upper = UInt64(bound)
        let limit = UInt64.max - (UInt64.max % upper)
        while true {
            let value = next()
            if value < limit { return Int(value % upper) }
        }
    }

    /// Uniform double in `0..<1`.
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    public mutating func chance(_ probability: Double) -> Bool {
        nextUnit() < probability
    }

    public mutating func pick<T>(_ items: [T]) -> T {
        items[nextInt(below: items.count)]
    }

    public mutating func shuffle<T>(_ items: inout [T]) {
        guard items.count > 1 else { return }
        for i in stride(from: items.count - 1, to: 0, by: -1) {
            let j = nextInt(below: i + 1)
            if i != j { items.swapAt(i, j) }
        }
    }
}
