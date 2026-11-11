import CoreGraphics
import MinesEngine

/// Where the squares go: the 8 by 12 board as large as the table allows, centred across it
/// and resting at the bottom, nearest the thumb.
///
/// Each square answers touches over its whole share of the board, gaps included, so a touch
/// between two squares goes to the nearer one.
public struct MinesLayout {
    public let size: CGSize
    /// The side of a square.
    public let cell: CGFloat
    /// The space between squares.
    public let gap: CGFloat
    /// The top-left corner of the first square.
    public let origin: CGPoint

    static let margin: CGFloat = 6
    static let largestCell: CGFloat = 64

    public init(size: CGSize) {
        self.size = size
        gap = size.width < 400 ? 2 : 3
        let columns = CGFloat(MinesGrid.columns), rows = CGFloat(MinesGrid.rows)
        let byWidth = (size.width - 2 * Self.margin - (columns - 1) * gap) / columns
        let byHeight = (size.height - 2 * Self.margin - (rows - 1) * gap) / rows
        cell = max(1, min(byWidth, byHeight, Self.largestCell).rounded(.down))
        let board = CGSize(width: columns * cell + (columns - 1) * gap, height: rows * cell + (rows - 1) * gap)
        origin = CGPoint(x: ((size.width - board.width) / 2).rounded(), y: size.height - Self.margin - board.height)
    }

    /// From one square to the next.
    public var pitch: CGFloat { cell + gap }

    public var boardFrame: CGRect {
        CGRect(x: origin.x, y: origin.y,
               width: CGFloat(MinesGrid.columns) * pitch - gap, height: CGFloat(MinesGrid.rows) * pitch - gap)
    }

    public func frame(of square: Int) -> CGRect {
        CGRect(x: origin.x + CGFloat(MinesGrid.column(of: square)) * pitch,
               y: origin.y + CGFloat(MinesGrid.row(of: square)) * pitch,
               width: cell, height: cell)
    }

    public func center(of square: Int) -> CGPoint {
        let frame = frame(of: square)
        return CGPoint(x: frame.midX, y: frame.midY)
    }
}
