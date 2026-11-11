import Foundation

/// One attempt at a level.
public struct BubbleGame: Hashable, Codable, Sendable {
    public enum Status: String, Hashable, Codable, Sendable {
        case playing
        /// Every bubble is gone.
        case won
        /// Shots ran out with bubbles left.
        case outOfShots
        /// A bubble was left in the death row.
        case reachedLine
    }

    /// Level number (0 for hand-built positions).
    public let levelNumber: Int
    public private(set) var grid: BubbleGrid
    /// The bubble in the launcher.
    public private(set) var current: BubbleColor
    /// The bubble after it (tap to swap).
    public private(set) var next: BubbleColor
    /// Colours this level uses, for refills once only stones and bombs are left.
    public let palette: [BubbleColor]
    public let shotLimit: Int
    /// Shots the bot needed: matching it earns three stars.
    public let par: Int
    public private(set) var shotsFired = 0
    public private(set) var status: Status = .playing
    private var generator: SeededGenerator

    /// Each attempt deals its own bubble queue.
    public init(level: Level, attempt: Int = 0) {
        let layout = level.layout
        self.init(grid: layout.grid, palette: layout.palette, shotLimit: level.shotLimit, par: level.par,
                  seed: Self.queueSeed(for: layout, attempt: attempt), levelNumber: layout.number)
    }

    /// The seed of the bubble queue for an attempt at a layout. Par was set on attempt 0's queue.
    static func queueSeed(for layout: LevelLayout, attempt: Int = 0) -> UInt64 {
        layout.seed ^ (UInt64(attempt) &* 0xA076_1D64_78BD_642F) ^ 0x5851_F42D_4C95_7F2D
    }

    /// A hand-built position (tests, tutorials, UI test scenarios).
    public init(grid: BubbleGrid, palette: [BubbleColor], shotLimit: Int, par: Int, seed: UInt64,
                levelNumber: Int = 0, current: BubbleColor? = nil, next: BubbleColor? = nil) {
        precondition(!palette.isEmpty, "palette must not be empty")
        self.levelNumber = levelNumber
        self.grid = grid
        self.palette = palette.sorted()
        self.shotLimit = shotLimit
        self.par = par
        self.generator = SeededGenerator(seed: seed)
        self.current = .red
        self.next = .red
        self.current = current ?? draw()
        self.next = next ?? draw()
    }

    public var shotsLeft: Int { max(0, shotLimit - shotsFired) }
    public var isOver: Bool { status != .playing }

    /// 3 stars for matching par, 2 for using at most half of the spare shots, otherwise 1.
    public var stars: Int {
        status == .won ? Self.stars(shotsUsed: shotsFired, par: par, shotLimit: shotLimit) : 0
    }

    public static func stars(shotsUsed: Int, par: Int, shotLimit: Int) -> Int {
        if shotsUsed <= par { return 3 }
        if shotsUsed <= par + (shotLimit - par) / 2 { return 2 }
        return 1
    }

    /// Swapping is free and unlimited.
    public mutating func swap() {
        guard status == .playing else { return }
        (current, next) = (next, current)
    }

    /// Where a shot in `direction` would go, without firing.
    public func trace(direction: Point) -> ShotTrace? {
        guard status == .playing else { return nil }
        return grid.trace(direction: direction)
    }

    /// Returns nil (and changes nothing) if the game is over or the direction does not point
    /// upwards.
    @discardableResult
    public mutating func shoot(direction: Point) -> ShotOutcome? {
        guard status == .playing, let trace = grid.trace(direction: direction) else { return nil }
        let color = current
        let result = grid.resolve(placing: .color(color), at: trace.cell)
        shotsFired += 1
        if grid.isEmpty {
            status = .won
        } else if grid.lowestRow >= BubbleGrid.deathRow {
            status = .reachedLine
        } else if shotsLeft == 0 {
            status = .outOfShots
        }
        current = next
        next = draw()
        let present = grid.colorsPresent
        if !present.isEmpty {
            if !present.contains(current) { current = draw() }
            if !present.contains(next) { next = draw() }
        }
        return ShotOutcome(trace: trace, color: color, result: result)
    }

    /// A colour still on the grid (or from the palette once none are left).
    private mutating func draw() -> BubbleColor {
        let present = grid.colorsPresent
        return generator.pick(present.isEmpty ? palette : present)
    }

    /// Compact description of the whole state, used by tests to compare positions exactly.
    public var signature: String {
        "L\(levelNumber)|shots:\(shotsFired)/\(shotLimit)|now:\(Bubble.color(current).code)|next:\(Bubble.color(next).code)|\(status.rawValue)|\(grid.signature)"
    }
}

public struct ShotOutcome: Hashable, Sendable {
    public let trace: ShotTrace
    public let color: BubbleColor
    public let result: ShotResult
}

/// A simple deterministic player. It sets each level's par (and so its shot limit and stars),
/// which guarantees every level has been cleared at least once.
public enum Bot {
    /// Fixed aiming directions. Built without trigonometry so results are identical on every platform.
    public static let directions: [Point] = (0...80).map { Point(-4.0 + 0.1 * Double($0), -1).normalized }

    public struct Choice: Hashable, Sendable {
        public let direction: Point
        public let swap: Bool
    }

    /// The best shot available, considering both the launcher bubble and (after a swap) the next one.
    public static func choose(for game: BubbleGame) -> Choice? {
        guard game.status == .playing else { return nil }
        var options: [(color: BubbleColor, swap: Bool)] = [(game.current, false)]
        if game.next != game.current { options.append((game.next, true)) }
        var best: (score: Double, choice: Choice)?
        var seen = Set<Cell>()
        for direction in directions {
            guard let trace = game.grid.trace(direction: direction), seen.insert(trace.cell).inserted else { continue }
            for option in options {
                var grid = game.grid
                let result = grid.resolve(placing: .color(option.color), at: trace.cell)
                var score = Double(result.popped.count + result.exploded.count) + 1.6 * Double(result.dropped.count)
                if result.clearedCount == 0 {
                    let alike = BubbleGrid.neighbors(of: trace.cell).filter { grid[$0]?.color == option.color }.count
                    score += 0.4 * Double(alike)
                }
                if grid.lowestRow >= BubbleGrid.deathRow { score -= 1000 }
                if trace.cell.row >= BubbleGrid.deathRow - 2 { score -= 3 }
                score -= 0.03 * Double(trace.cell.row)
                if option.swap { score -= 0.001 }
                if best == nil || score > best!.score + 1e-9 {
                    best = (score, Choice(direction: direction, swap: option.swap))
                }
            }
        }
        return best?.choice
    }

    /// Plays to the end. Returns the shots used if the bot clears the board, nil otherwise.
    public static func play(_ game: BubbleGame, maxShots: Int = 300) -> Int? {
        var game = game
        while game.status == .playing && game.shotsFired < maxShots {
            guard let choice = choose(for: game) else { return nil }
            if choice.swap { game.swap() }
            game.shoot(direction: choice.direction)
        }
        return game.status == .won ? game.shotsFired : nil
    }
}
