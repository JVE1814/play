import Foundation

/// The playing field: a hexagonal grid eight bubbles wide, hanging from the ceiling.
///
/// Geometry is in bubble diameters. Row `r` sits at `y = 0.5 + r·√3/2`; odd rows are shifted half
/// a bubble to the right, so the field is 8.5 bubbles wide. Any bubble that ends a shot in
/// `deathRow` (or lower) loses the level.
public struct BubbleGrid: Hashable, Codable, Sendable {
    public static let columns = 8
    /// A bubble left in this row after a shot loses the level.
    public static let deathRow = 12
    public static let rows = deathRow + 1
    public static let width = Double(columns) + 0.5
    public static let rowHeight = 0.866_025_403_784_438_6 // √3 / 2
    /// Where shots start: centred, one bubble below the death row.
    public static let launcher = Point(width / 2, y(ofRow: deathRow) + 1.0)

    /// The height of the centres of row `row`.
    public static func y(ofRow row: Int) -> Double { 0.5 + Double(row) * rowHeight }

    private var slots: [Bubble?]

    public init() {
        slots = Array(repeating: nil, count: Self.rows * Self.columns)
    }

    /// Builds a grid from rows of codes (see `Bubble.code`), using "." for empty cells.
    public init(rows: [String]) {
        self.init()
        for (r, line) in rows.enumerated() {
            for (c, character) in line.enumerated() where character != "." && character != " " {
                self[Cell(r, c)] = Bubble(code: character)
            }
        }
    }

    public static func isValid(_ cell: Cell) -> Bool {
        (0..<rows).contains(cell.row) && (0..<columns).contains(cell.column)
    }

    public subscript(cell: Cell) -> Bubble? {
        get { Self.isValid(cell) ? slots[cell.row * Self.columns + cell.column] : nil }
        set {
            guard Self.isValid(cell) else { return }
            slots[cell.row * Self.columns + cell.column] = newValue
        }
    }

    /// Occupied cells in row-major order (deterministic).
    public var occupied: [Cell] {
        var cells: [Cell] = []
        for index in slots.indices where slots[index] != nil {
            cells.append(Cell(index / Self.columns, index % Self.columns))
        }
        return cells
    }

    public var count: Int { slots.reduce(0) { $0 + ($1 == nil ? 0 : 1) } }
    public var isEmpty: Bool { slots.allSatisfy { $0 == nil } }

    /// Colours still on the grid, in a fixed order.
    public var colorsPresent: [BubbleColor] {
        var present = Set<BubbleColor>()
        for slot in slots { if let color = slot?.color { present.insert(color) } }
        return present.sorted()
    }

    /// The lowest occupied row, or -1 when empty.
    public var lowestRow: Int { occupied.last?.row ?? -1 }

    public static func center(of cell: Cell) -> Point {
        Point(0.5 + Double(cell.column) + (cell.row % 2 == 1 ? 0.5 : 0), y(ofRow: cell.row))
    }

    /// The (up to six) valid neighbours of a cell.
    public static func neighbors(of cell: Cell) -> [Cell] {
        let r = cell.row, c = cell.column
        let shift = r % 2 == 1 ? 0 : -1
        let candidates = [
            Cell(r, c - 1), Cell(r, c + 1),
            Cell(r - 1, c + shift), Cell(r - 1, c + shift + 1),
            Cell(r + 1, c + shift), Cell(r + 1, c + shift + 1),
        ]
        return candidates.filter(isValid)
    }

    /// Cells connected to the ceiling through occupied neighbours.
    public func anchored() -> Set<Cell> {
        var seen = Set<Cell>()
        var queue = (0..<Self.columns).map { Cell(0, $0) }.filter { self[$0] != nil }
        seen.formUnion(queue)
        while let cell = queue.popLast() {
            for neighbor in Self.neighbors(of: cell) where self[neighbor] != nil && !seen.contains(neighbor) {
                seen.insert(neighbor)
                queue.append(neighbor)
            }
        }
        return seen
    }

    /// The group of same-coloured bubbles connected to `cell`.
    public func group(at cell: Cell) -> [Cell] {
        guard let color = self[cell]?.color else { return [] }
        var seen: Set<Cell> = [cell]
        var queue = [cell]
        while let current = queue.popLast() {
            for neighbor in Self.neighbors(of: current) where !seen.contains(neighbor) && self[neighbor]?.color == color {
                seen.insert(neighbor)
                queue.append(neighbor)
            }
        }
        return seen.sorted()
    }

    /// One line per row with bubble codes, "." for empty.
    public var signature: String {
        let last = max(lowestRow, 0)
        return (0...last).map { r in
            String((0..<Self.columns).map { self[Cell(r, $0)]?.code ?? "." })
        }.joined(separator: "/")
    }
}

/// The path a shot takes and where it settles.
public struct ShotTrace: Hashable, Sendable {
    /// Start, every wall bounce, and the point where the bubble stops.
    public let path: [Point]
    /// The cell the bubble snaps into.
    public let cell: Cell
}

extension BubbleGrid {
    /// Two bubbles touch when their centres are closer than this. It is slightly less than one
    /// diameter, so shots can slip through gaps that look just wide enough.
    public static let collisionDistance = 0.82

    /// Follows a shot fired from the launcher in `direction` (any length, pointing upwards),
    /// bouncing off the side walls, until it touches a bubble or the ceiling.
    public func trace(direction: Point) -> ShotTrace? {
        var d = direction.normalized
        guard d.y < -0.05 else { return nil }
        var position = Self.launcher
        var path = [position]
        let left = 0.5, right = Self.width - 0.5, ceiling = 0.5
        let cells = occupied
        for _ in 0..<64 {
            var best = Double.infinity
            var hitBubble = false
            // Bubbles.
            for cell in cells {
                let f = position - Self.center(of: cell)
                let b = f.dot(d)
                let c = f.dot(f) - Self.collisionDistance * Self.collisionDistance
                let discriminant = b * b - c
                guard c > 0, b < 0, discriminant >= 0 else { continue }
                let t = -b - discriminant.squareRoot()
                if t > 1e-9, t < best {
                    best = t
                    hitBubble = true
                }
            }
            // Ceiling.
            let tCeiling = (ceiling - position.y) / d.y
            if tCeiling < best {
                best = tCeiling
                hitBubble = false
            }
            // Walls.
            var tWall = Double.infinity
            if d.x < 0 { tWall = (left - position.x) / d.x }
            if d.x > 0 { tWall = (right - position.x) / d.x }
            if tWall < best - 1e-12 {
                position = position + d * tWall
                position.x = d.x < 0 ? left : right
                path.append(position)
                d.x = -d.x
                continue
            }
            let stop = position + d * max(best, 0)
            path.append(stop)
            guard let cell = snapCell(near: stop, touchingCeiling: !hitBubble) else { return nil }
            return ShotTrace(path: path, cell: cell)
        }
        return nil
    }

    /// The empty cell where a bubble stopping at `point` settles: the nearest empty cell that is
    /// in the top row or next to an occupied cell.
    func snapCell(near point: Point, touchingCeiling: Bool) -> Cell? {
        var best: (cell: Cell, distance: Double)?
        let approximateRow = Int(((point.y - 0.5) / Self.rowHeight).rounded())
        for r in max(0, approximateRow - 2)...min(Self.rows - 1, approximateRow + 2) {
            for c in 0..<Self.columns {
                let cell = Cell(r, c)
                guard self[cell] == nil else { continue }
                let attachable = r == 0 || Self.neighbors(of: cell).contains { self[$0] != nil }
                guard attachable else { continue }
                if touchingCeiling && r != 0 { continue }
                let distance = Self.center(of: cell).distance(to: point)
                if best == nil || distance < best!.distance - 1e-9 { best = (cell, distance) }
            }
        }
        return best?.cell
    }
}

/// What a shot did to the grid.
public struct ShotResult: Hashable, Codable, Sendable {
    /// Same-colour group that popped (includes the shot bubble), with what was there.
    public let popped: [Cell]
    /// Cells cleared by bombs (bombs included).
    public let exploded: [Cell]
    /// Bubbles that fell because nothing held them up any more.
    public let dropped: [Cell]
    /// What each cleared cell held before the shot.
    public let removed: [Cell: Bubble]

    public var clearedCount: Int { popped.count + exploded.count + dropped.count }
}

extension BubbleGrid {
    /// Places `bubble` at `cell` and resolves bombs, matches and falling bubbles.
    public mutating func resolve(placing bubble: Bubble, at cell: Cell) -> ShotResult {
        var removed: [Cell: Bubble] = [:]
        self[cell] = bubble
        // Bombs next to the landing cell go off, setting off any bombs caught in their blast.
        var exploded: [Cell] = []
        var blasted = Set<Cell>()
        var detonated = Set<Cell>()
        var fuses = Self.neighbors(of: cell).filter { self[$0] == .bomb }
        while let bomb = fuses.popLast() {
            guard detonated.insert(bomb).inserted else { continue }
            blasted.insert(bomb)
            for target in Self.neighbors(of: bomb) where self[target] != nil {
                blasted.insert(target)
                if self[target] == .bomb, !detonated.contains(target) { fuses.append(target) }
            }
        }
        for target in blasted.sorted() where self[target] != nil {
            removed[target] = self[target]
            self[target] = nil
            exploded.append(target)
        }
        // Three or more of a colour pop.
        var popped: [Cell] = []
        if self[cell] != nil {
            let group = self.group(at: cell)
            if group.count >= 3 {
                for member in group {
                    removed[member] = self[member]
                    self[member] = nil
                }
                popped = group
            }
        }
        // Anything no longer connected to the ceiling falls.
        var dropped: [Cell] = []
        if !popped.isEmpty || !exploded.isEmpty {
            let anchored = self.anchored()
            for other in occupied where !anchored.contains(other) {
                removed[other] = self[other]
                self[other] = nil
                dropped.append(other)
            }
        }
        return ShotResult(popped: popped, exploded: exploded, dropped: dropped, removed: removed)
    }
}
