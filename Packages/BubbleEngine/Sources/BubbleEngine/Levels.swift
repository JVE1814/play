import Foundation

/// A playable level: the layout that passed calibration, and its shot limit.
public struct Level: Hashable, Sendable {
    public let layout: LevelLayout
    /// Shots the bot needed to clear it.
    public let par: Int
    public let shotLimit: Int
}

/// The generated layout of a level: its starting grid and colours.
public struct LevelLayout: Hashable, Sendable {
    public let number: Int
    /// Which generated variant this is (0 unless the first one failed calibration).
    public let variant: Int
    public let grid: BubbleGrid
    public let palette: [BubbleColor]
    public let seed: UInt64
    /// Names of the shape and colouring used (for variety checks and debugging).
    public let pattern: String
    public let coloring: String

    /// A game on this layout with an unlimited supply of shots (used to calibrate par).
    public var calibrationGame: BubbleGame {
        BubbleGame(grid: grid, palette: palette, shotLimit: 10_000, par: 0,
                   seed: BubbleGame.queueSeed(for: self), levelNumber: number)
    }
}

/// Two thousand levels, generated deterministically from their number.
///
/// Difficulty rises over the first few hundred levels (more colours, more rows, stones from level
/// 30, bombs from level 60), with an easier "breather" every tenth level and a bigger board on
/// round numbers. Every level was cleared by `Bot` when its par was computed, so every level is
/// winnable within its shot limit.
public enum LevelCatalog {
    public static let count = 2_000

    public static func level(_ number: Int) -> Level {
        precondition((1...count).contains(number), "no such level")
        let calibration = tabledPar(for: number) ?? calibrate(number)
        return Level(layout: layout(number, variant: calibration.variant),
                     par: calibration.par, shotLimit: shotLimit(par: calibration.par))
    }

    /// Par plus about 30% (at least three) spare shots.
    public static func shotLimit(par: Int) -> Int {
        par + max(3, Int((Double(par) * 0.3).rounded(.up)))
    }

    static func tabledPar(for number: Int) -> (par: Int, variant: Int)? {
        let index = number - 1
        guard index < LevelPar.par.count, index < LevelPar.variant.count, LevelPar.par[index] > 0 else { return nil }
        return (Int(LevelPar.par[index]), Int(LevelPar.variant[index]))
    }

    /// The fewest shots a level may need: no one-shot giveaways, and later levels take longer.
    public static func minimumPar(for number: Int) -> Int {
        min(12, 3 + number / 30)
    }

    /// The most shots a level may need, so no level turns into a slog.
    public static let maximumPar = 36

    /// Plays the level with the bot to find its par. A layout the bot cannot clear, or clears too
    /// quickly or too slowly, is replaced by the next variant; the closest one is kept otherwise.
    public static func calibrate(_ number: Int, variants: Int = 24) -> (par: Int, variant: Int) {
        let range = minimumPar(for: number)...maximumPar
        var fallback: (par: Int, variant: Int, miss: Int)?
        for variant in 0..<variants {
            guard let shots = Bot.play(layout(number, variant: variant).calibrationGame) else { continue }
            if range.contains(shots) { return (shots, variant) }
            let miss = shots < range.lowerBound ? range.lowerBound - shots : shots - range.upperBound
            if fallback == nil || miss < fallback!.miss { fallback = (shots, variant, miss) }
        }
        if let fallback { return (fallback.par, fallback.variant) }
        // Every shipped level is calibrated (see LevelTests); this keeps the API total.
        return (max(10, layout(number, variant: 0).grid.count), 0)
    }

    // MARK: Generation

    enum Pattern: String, CaseIterable {
        case wall, funnel, pillars, diamond, steps, curtains, zigzag, swiss, frame, hourglass
        case chandelier, mirror, triangle, fringe

        /// First level where the pattern can appear.
        var firstLevel: Int {
            switch self {
            case .wall: return 1
            case .funnel: return 2
            case .pillars: return 4
            case .diamond: return 6
            case .steps: return 9
            case .curtains: return 12
            case .zigzag: return 15
            case .swiss: return 19
            case .frame: return 23
            case .hourglass: return 28
            case .chandelier: return 34
            case .mirror: return 40
            case .triangle: return 46
            case .fringe: return 52
            }
        }
    }

    enum Coloring: String, CaseIterable {
        case clustered, rows, columns, regions, diagonal, blocks

        var firstLevel: Int {
            switch self {
            case .clustered, .rows: return 1
            case .columns: return 5
            case .regions: return 10
            case .diagonal: return 18
            case .blocks: return 26
            }
        }
    }

    struct Difficulty {
        var colors: Int
        var rows: Int
        var stones: Int
        var bombs: Int
        var clustering: Double
        var noise: Double
    }

    static func difficulty(for n: Int, rng: inout SeededGenerator) -> Difficulty {
        let ramp = min(1.0, Double(n - 1) / 400.0)
        let breather = n > 10 && n % 10 == 5
        let big = n % 10 == 0
        var colors = n <= 10 ? 3 : n <= 40 ? 4 : n <= 120 ? 5 : 6
        if n > 120 && rng.chance(0.25) { colors = 5 }
        if breather { colors = max(3, colors - 1) }
        var rows = 5 + Int((ramp * 3).rounded()) + rng.nextInt(below: 2)
        if big { rows += 1 }
        if breather { rows -= 1 }
        rows = min(9, max(3, rows))
        var stones = n < 30 ? 0 : rng.nextInt(below: 2 + Int(ramp * 5))
        var bombs = n < 60 ? 0 : rng.nextInt(below: 2 + Int(ramp * 2))
        if n >= 60 && n % 12 == 0 { bombs = max(bombs, 1) }
        if breather { stones = 0 }
        return Difficulty(colors: colors, rows: rows, stones: stones, bombs: bombs,
                          clustering: 0.45 - 0.25 * ramp, noise: 0.08 + 0.12 * ramp)
    }

    static func seed(for n: Int, variant: Int) -> UInt64 {
        var mixer = SeededGenerator(seed: UInt64(n) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(variant) &* 0xD1B5_4A32_D192_ED03)
        return mixer.next()
    }

    /// The layout of level `n`. Deterministic: the same number and variant always give the same grid.
    public static func layout(_ n: Int, variant: Int = 0) -> LevelLayout {
        let seed = seed(for: n, variant: variant)
        var rng = SeededGenerator(seed: seed)
        let difficulty = difficulty(for: n, rng: &rng)
        var colors = BubbleColor.allCases
        rng.shuffle(&colors)
        let palette = Array(colors.prefix(difficulty.colors)).sorted()

        let patterns = Pattern.allCases.filter { $0.firstLevel <= n }
        let colorings = Coloring.allCases.filter { $0.firstLevel <= n }
        // New shapes get a spotlight on the level that introduces them.
        let pattern = patterns.first { $0.firstLevel == n } ?? rng.pick(patterns)
        let coloring = rng.pick(colorings)

        var grid = paint(mask(pattern, rows: difficulty.rows, rng: &rng), coloring: coloring, palette: palette,
                         difficulty: difficulty, rng: &rng)
        var usedPattern = pattern
        // Too sparse to hold three of every colour comfortably: use a full wall instead.
        if grid.count < max(12, palette.count * 4) {
            usedPattern = .wall
            grid = paint(mask(.wall, rows: max(4, difficulty.rows), rng: &rng), coloring: coloring, palette: palette,
                         difficulty: difficulty, rng: &rng)
        }
        mixTopRow(&grid, palette: palette, rng: &rng)
        ensureEveryColor(&grid, palette: palette, rng: &rng)
        place(.stone, count: difficulty.stones, in: &grid, minimumRow: 1, rng: &rng)
        place(.bomb, count: difficulty.bombs, in: &grid, minimumRow: 1, rng: &rng)
        return LevelLayout(number: n, variant: variant, grid: grid, palette: palette, seed: seed,
                           pattern: usedPattern.rawValue, coloring: coloring.rawValue)
    }

    /// Which cells of the first `rows` rows are filled, by shape.
    static func mask(_ pattern: Pattern, rows: Int, rng: inout SeededGenerator) -> [[Bool]] {
        let cx = BubbleGrid.width / 2
        let last = Double(max(rows - 1, 1))
        let mid = Double(rows - 1) / 2
        let flip = rng.chance(0.5)
        var holes = Set<Cell>()
        if pattern == .swiss {
            for r in 0..<rows { for c in 0..<BubbleGrid.columns where rng.chance(0.22) { holes.insert(Cell(r, c)) } }
        }
        var mirrorHalf: [[Bool]] = []
        if pattern == .mirror {
            mirrorHalf = (0..<rows).map { r in (0..<4).map { _ in r == 0 || rng.chance(0.72) } }
        }
        let zig: [Double] = [0, 0.5, 1, 0.5, 0, -0.5, -1, -0.5]
        let zigPhase = rng.nextInt(below: zig.count)
        return (0..<rows).map { r in
            (0..<BubbleGrid.columns).map { c in
                let x = BubbleGrid.center(of: Cell(r, c)).x
                let dx = abs(x - cx)
                let rd = Double(r)
                switch pattern {
                case .wall:
                    return true
                case .funnel:
                    return dx <= 4.3 - rd * (3.2 / last)
                case .pillars:
                    return r == 0 || c % 3 != 2
                case .diamond:
                    return dx <= 1.0 + 3.3 * (1 - abs(rd - mid) / max(mid, 1))
                case .steps:
                    let column = flip ? BubbleGrid.columns - 1 - c : c
                    return column <= BubbleGrid.columns - 1 - r || r == 0
                case .curtains:
                    return r == 0 || dx >= 0.7 + rd * 0.35
                case .zigzag:
                    let center = cx + 2.4 * zig[(r + zigPhase) % zig.count]
                    return abs(x - center) <= 1.9
                case .swiss:
                    return !holes.contains(Cell(r, c))
                case .frame:
                    return r == 0 || r == rows - 1 || c == 0 || c == BubbleGrid.columns - 1
                        || (dx < 1.0 && rd <= mid)
                case .hourglass:
                    return dx <= 0.9 + 3.4 * abs(rd - mid) / max(mid, 1)
                case .chandelier:
                    let stem = x < cx ? cx - 2.0 : cx + 2.0
                    if r < 3 { return abs(x - stem) <= 0.6 }
                    return abs(x - stem) <= min(2.0, 1.0 + (rd - 3) * 0.6)
                case .mirror:
                    let column = c < 4 ? c : BubbleGrid.columns - 1 - c
                    return mirrorHalf[r][column]
                case .triangle:
                    return dx <= 0.9 + rd * 0.6
                case .fringe:
                    return r < rows - 2 || (c + r) % 4 < 2
                }
            }
        }
    }

    /// Fills the masked cells with colours.
    static func paint(_ mask: [[Bool]], coloring: Coloring, palette: [BubbleColor], difficulty: Difficulty,
                      rng: inout SeededGenerator) -> BubbleGrid {
        var grid = BubbleGrid()
        var order = palette
        rng.shuffle(&order)
        let k = order.count
        let band = rng.chance(0.5) ? 1 : 2
        let offset = rng.nextInt(below: k)
        var seeds: [(Point, BubbleColor)] = []
        if coloring == .regions {
            let count = k + rng.nextInt(below: 3)
            for i in 0..<count {
                let r = rng.nextInt(below: mask.count)
                let c = rng.nextInt(below: BubbleGrid.columns)
                seeds.append((BubbleGrid.center(of: Cell(r, c)), order[i % k]))
            }
        }
        for r in mask.indices {
            for c in 0..<BubbleGrid.columns where mask[r][c] {
                let cell = Cell(r, c)
                var color: BubbleColor
                switch coloring {
                case .clustered:
                    let painted = BubbleGrid.neighbors(of: cell).compactMap { grid[$0]?.color }
                    color = !painted.isEmpty && rng.chance(difficulty.clustering) ? rng.pick(painted) : rng.pick(order)
                case .rows:
                    color = order[(r / band + offset) % k]
                case .columns:
                    color = order[(c / 2 + offset) % k]
                case .regions:
                    let point = BubbleGrid.center(of: cell)
                    color = seeds.min { $0.0.distance(to: point) < $1.0.distance(to: point) }!.1
                case .diagonal:
                    color = order[((c + r) / 2 + offset) % k]
                case .blocks:
                    color = order[((r / 2) * 3 + c / 2 + offset) % k]
                }
                if rng.chance(difficulty.noise) { color = rng.pick(order) }
                grid[cell] = .color(color)
            }
        }
        removeFloating(&grid)
        return grid
    }

    static func removeFloating(_ grid: inout BubbleGrid) {
        let anchored = grid.anchored()
        for cell in grid.occupied where !anchored.contains(cell) { grid[cell] = nil }
    }

    /// Gives the top row at least three colours (or all of them), so a single pop can't drop the
    /// whole board.
    static func mixTopRow(_ grid: inout BubbleGrid, palette: [BubbleColor], rng: inout SeededGenerator) {
        let top = (0..<BubbleGrid.columns).map { Cell(0, $0) }.filter { grid[$0] != nil }
        let wanted = min(3, palette.count, top.count)
        var attempts = 0
        while Set(top.compactMap { grid[$0]?.color }).count < wanted && attempts < 50 {
            attempts += 1
            let used = Set(top.compactMap { grid[$0]?.color })
            guard let missing = palette.first(where: { !used.contains($0) }) else { break }
            // The most crowded colour gives one up. On a tie it is the colour that comes first in
            // the row: a dictionary's own order changes from one launch to the next.
            let groups = Dictionary(grouping: top, by: { grid[$0]?.color }).values
            guard let crowded = groups.max(by: { ($0.count, $1[0]) < ($1.count, $0[0]) }), crowded.count > 1 else { break }
            grid[rng.pick(crowded)] = .color(missing)
        }
    }

    /// Makes sure each palette colour appears at least three times.
    static func ensureEveryColor(_ grid: inout BubbleGrid, palette: [BubbleColor], rng: inout SeededGenerator) {
        for color in palette {
            var have = grid.occupied.filter { grid[$0]?.color == color }.count
            var attempts = 0
            while have < 3 && attempts < 200 {
                attempts += 1
                let cells = grid.occupied
                let cell = rng.pick(cells)
                guard let existing = grid[cell]?.color, existing != color else { continue }
                let existingCount = cells.filter { grid[$0]?.color == existing }.count
                guard existingCount > 3 else { continue }
                grid[cell] = .color(color)
                have += 1
            }
        }
    }

    /// Turns `count` coloured bubbles at or below `minimumRow` into stones or bombs.
    static func place(_ bubble: Bubble, count: Int, in grid: inout BubbleGrid, minimumRow: Int,
                      rng: inout SeededGenerator) {
        guard count > 0 else { return }
        var candidates = grid.occupied.filter { $0.row >= minimumRow && grid[$0]?.color != nil }
        rng.shuffle(&candidates)
        var placed = 0
        for cell in candidates where placed < count {
            // Keep at least three of every colour.
            guard let color = grid[cell]?.color,
                  grid.occupied.filter({ grid[$0]?.color == color }).count > 3 else { continue }
            grid[cell] = bubble
            placed += 1
        }
    }
}
