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

    /// The shape drawn inside the bubble.
    public var symbol: String {
        switch self {
        case .red: return "triangle"
        case .yellow: return "circle"
        case .green: return "square"
        case .blue: return "diamond"
        case .purple: return "plus"
        case .cyan: return "star"
        }
    }

    /// Spoken description, e.g. "Red triangle".
    public var spokenName: String { "\(name) \(symbol)" }

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

    public var spokenName: String {
        switch self {
        case .color(let color): return color.spokenName
        case .stone: return "Stone"
        case .bomb: return "Bomb"
        }
    }

    /// One-character code used in signatures: r y g b p c, S for stone, B for bomb.
    public var code: Character {
        switch self {
        case .color(let color): return Array("rygbpc")[color.rawValue]
        case .stone: return "S"
        case .bomb: return "B"
        }
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
