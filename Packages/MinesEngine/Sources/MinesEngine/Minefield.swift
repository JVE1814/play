import Foundation

/// Where the mines are, with the count of mines around every square.
public struct Minefield: Sendable {
    public let mines: CellSet
    private let counts: [UInt8]

    public init(mines: CellSet) {
        self.mines = mines
        counts = (0..<MinesGrid.cellCount).map { UInt8(MinesGrid.neighbours(of: $0).intersection(mines).count) }
    }

    public func isMine(_ cell: Int) -> Bool { mines.contains(cell) }

    /// The number shown on `cell` once it is open: the mines among its neighbours.
    public func count(around cell: Int) -> Int { Int(counts[cell]) }

    public var safeCells: CellSet { MinesGrid.all.subtracting(mines) }

    /// The squares opening safe `cell` reveals: the square itself, and if it shows no
    /// number, everything reachable through squares that show none, with the numbers that
    /// border them.
    public func flood(from cell: Int) -> CellSet {
        var revealed = CellSet([cell])
        guard counts[cell] == 0 else { return revealed }
        var stack = [cell]
        while let next = stack.popLast() {
            for neighbour in MinesGrid.neighbours(of: next) where !revealed.contains(neighbour) {
                revealed.insert(neighbour)
                if counts[neighbour] == 0 { stack.append(neighbour) }
            }
        }
        return revealed
    }
}

// Equal, hashed and saved by its mines alone: the counts follow from them.
extension Minefield: Hashable {
    public static func == (lhs: Minefield, rhs: Minefield) -> Bool { lhs.mines == rhs.mines }
    public func hash(into hasher: inout Hasher) { hasher.combine(mines) }
}

extension Minefield: Codable {
    private enum CodingKeys: String, CodingKey { case mines }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(mines: try container.decode(CellSet.self, forKey: .mines))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mines, forKey: .mines)
    }
}
