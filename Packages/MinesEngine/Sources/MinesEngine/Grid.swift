import Foundation

/// The board: 8 columns by 12 rows on every phone. Squares are numbered row by row from the
/// top left, so square 0 is row 0, column 0 and square 95 is row 11, column 7.
public enum MinesGrid {
    public static let columns = 8
    public static let rows = 12
    public static let cellCount = columns * rows

    public static func index(row: Int, column: Int) -> Int { row * columns + column }
    public static func row(of cell: Int) -> Int { cell / columns }
    public static func column(of cell: Int) -> Int { cell % columns }

    public static func isValid(_ cell: Int) -> Bool { (0..<cellCount).contains(cell) }

    public static let all = CellSet(0..<cellCount)

    /// The up to eight squares touching `cell`.
    public static func neighbours(of cell: Int) -> CellSet { neighbourTable[cell] }

    /// `cell` and its neighbours: the 3×3 block the first tap clears of mines.
    public static func zone(around cell: Int) -> CellSet {
        var zone = neighbourTable[cell]
        zone.insert(cell)
        return zone
    }

    private static let neighbourTable: [CellSet] = (0..<cellCount).map { cell in
        var set = CellSet()
        let row = row(of: cell), column = column(of: cell)
        for dr in -1...1 {
            for dc in -1...1 where dr != 0 || dc != 0 {
                let r = row + dr, c = column + dc
                if (0..<rows).contains(r), (0..<columns).contains(c) { set.insert(index(row: r, column: c)) }
            }
        }
        return set
    }
}

/// A set of squares, held as 96 bits. It iterates in ascending order, so everything built
/// on it is the same on every launch (a `Set` iterates in an order that changes per launch).
public struct CellSet: Hashable, Sendable, Sequence {
    private var low: UInt64 = 0
    private var high: UInt64 = 0

    public init() {}

    public init<S: Sequence>(_ cells: S) where S.Element == Int {
        for cell in cells { insert(cell) }
    }

    public var count: Int { low.nonzeroBitCount + high.nonzeroBitCount }
    public var isEmpty: Bool { low == 0 && high == 0 }

    /// The lowest square in the set.
    public var first: Int? {
        var iterator = makeIterator()
        return iterator.next()
    }

    public func contains(_ cell: Int) -> Bool {
        guard MinesGrid.isValid(cell) else { return false }
        return cell < 64 ? low & (1 << UInt64(cell)) != 0 : high & (1 << UInt64(cell - 64)) != 0
    }

    public mutating func insert(_ cell: Int) {
        precondition(MinesGrid.isValid(cell), "square \(cell) is off the board")
        if cell < 64 { low |= 1 << UInt64(cell) } else { high |= 1 << UInt64(cell - 64) }
    }

    public mutating func remove(_ cell: Int) {
        guard MinesGrid.isValid(cell) else { return }
        if cell < 64 { low &= ~(1 << UInt64(cell)) } else { high &= ~(1 << UInt64(cell - 64)) }
    }

    public func union(_ other: CellSet) -> CellSet {
        var result = self
        result.low |= other.low
        result.high |= other.high
        return result
    }

    public func intersection(_ other: CellSet) -> CellSet {
        var result = self
        result.low &= other.low
        result.high &= other.high
        return result
    }

    public func subtracting(_ other: CellSet) -> CellSet {
        var result = self
        result.low &= ~other.low
        result.high &= ~other.high
        return result
    }

    public func isSubset(of other: CellSet) -> Bool { subtracting(other).isEmpty }
    public func isDisjoint(with other: CellSet) -> Bool { intersection(other).isEmpty }

    public func makeIterator() -> Iterator { Iterator(low: low, high: high) }

    public struct Iterator: IteratorProtocol {
        var low: UInt64
        var high: UInt64

        public mutating func next() -> Int? {
            if low != 0 {
                let bit = low.trailingZeroBitCount
                low &= low - 1
                return bit
            }
            if high != 0 {
                let bit = high.trailingZeroBitCount
                high &= high - 1
                return 64 + bit
            }
            return nil
        }
    }
}

extension CellSet: Codable {
    /// Saved as the ascending list of squares, which is readable in a save file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let cells = try container.decode([Int].self)
        for cell in cells {
            guard MinesGrid.isValid(cell), !contains(cell) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "square \(cell) is off the board or listed twice")
            }
            insert(cell)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Array(self))
    }
}
