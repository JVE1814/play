import BubbleEngine
import CoreGraphics

/// Maps the engine's grid units (one bubble diameter) to points on screen.
public struct FieldLayout {
    public let size: CGSize
    /// Points per bubble diameter.
    public let diameter: CGFloat
    /// Where grid point (0, 0) sits.
    public let origin: CGPoint

    /// Grid units from the ceiling to just below the launcher.
    static let unitsTall = BubbleGrid.launcher.y + 0.85

    public init(size: CGSize) {
        self.size = size
        let padding: CGFloat = 6
        let byWidth = (size.width - 2 * padding) / CGFloat(BubbleGrid.width)
        let byHeight = (size.height - 2 * padding) / CGFloat(Self.unitsTall)
        diameter = max(8, min(byWidth, byHeight))
        let fieldWidth = diameter * CGFloat(BubbleGrid.width)
        let fieldHeight = diameter * CGFloat(Self.unitsTall)
        origin = CGPoint(x: (size.width - fieldWidth) / 2, y: max(padding, (size.height - fieldHeight) / 2))
    }

    public func point(_ p: Point) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(p.x) * diameter, y: origin.y + CGFloat(p.y) * diameter)
    }

    public func center(of cell: Cell) -> CGPoint { point(BubbleGrid.center(of: cell)) }

    public var launcher: CGPoint { point(BubbleGrid.launcher) }

    /// The next-bubble button, beside the launcher on the thumb side.
    public var nextBubble: CGPoint { CGPoint(x: launcher.x + diameter * 1.9, y: launcher.y + diameter * 0.1) }

    /// The field panel behind the grid.
    public var fieldRect: CGRect {
        CGRect(x: origin.x - 4, y: origin.y - 4,
               width: diameter * CGFloat(BubbleGrid.width) + 8, height: diameter * CGFloat(Self.unitsTall) + 8)
    }

    /// Top edge of the death row: a bubble left below this line loses the level.
    public var deathLineY: CGFloat {
        point(Point(0, 0.5 + Double(BubbleGrid.deathRow) * BubbleGrid.rowHeight - 0.5)).y
    }

    /// The aim for a touch at `location`. Above (or beside) the launcher you point where to shoot;
    /// clearly below it you pull back like a slingshot. Too close to the launcher means no aim
    /// (release there to cancel).
    public func aim(for location: CGPoint) -> Point? {
        var dx = Double(location.x - launcher.x)
        var dy = Double(location.y - launcher.y)
        if dy > Double(diameter) * 0.25 {
            dx = -dx
            dy = -dy
        }
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > Double(diameter) * 0.6 else { return nil }
        var x = dx / length
        var y = dy / length
        // Never flatter than 7° above horizontal.
        let minimumRise = 0.122
        if -y < minimumRise {
            y = -minimumRise
            x = (x < 0 ? -1 : 1) * (1 - minimumRise * minimumRise).squareRoot()
        }
        return Point(x, y)
    }
}
