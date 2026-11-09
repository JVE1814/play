import CoreGraphics
import KlondikeEngine

/// Where one card is drawn.
public struct CardPlacement: Identifiable {
    public let card: Card
    public let center: CGPoint
    public let faceUp: Bool
    public let pile: Pile
    /// Position within its pile, 0 = bottom (tableau counts face-down cards too).
    public let index: Int
    public let zIndex: Double

    public var id: Card { card }
}

/// Geometry of the table, computed from the available size.
///
/// The layout is built for one thumb: the seven columns fill the top of the screen, and the
/// stock, waste and foundations sit in one row at the bottom, right above the toolbar. The stock
/// (the most-tapped pile) is at the right edge, or the left edge in left-handed mode.
public struct BoardLayout {
    public let size: CGSize
    public let leftHanded: Bool
    public let margin: CGFloat
    public let gap: CGFloat
    public let card: CGSize
    public let tableauTop: CGFloat
    public let tableauBottom: CGFloat
    public let bottomRowY: CGFloat

    /// A card's height over its width.
    static let cardAspect: CGFloat = 1.4
    private static let columns = CGFloat(Board.columnCount)

    /// Drawing order. Each pile stacks upwards from its base; a card on the move is drawn above
    /// every pile, and a dragged one above that.
    enum Layer {
        static let waste = 100.0
        static let foundation = 200.0
        static let tableau = 300.0
        static let moving = 1000.0
        static let dragged = 2000.0
    }

    public init(size: CGSize, leftHanded: Bool) {
        self.size = size
        self.leftHanded = leftHanded
        margin = 8
        gap = max(4, (size.width * 0.012).rounded())
        let fitWidth = (size.width - 2 * margin - (Self.columns - 1) * gap) / Self.columns
        // Never let the bottom row plus a full column overflow short screens.
        let fitHeight = max(30, (size.height - 2 * margin) / 6.2) / Self.cardAspect
        let width = max(30, min(fitWidth, fitHeight, 96)).rounded(.down)
        card = CGSize(width: width, height: (width * Self.cardAspect).rounded())
        bottomRowY = size.height - margin - card.height / 2
        tableauTop = margin
        tableauBottom = bottomRowY - card.height / 2 - gap * 2
    }

    // MARK: Columns and slots

    public func columnX(_ column: Int) -> CGFloat {
        let total = Self.columns * card.width + (Self.columns - 1) * gap
        let origin = (size.width - total) / 2
        return origin + card.width / 2 + CGFloat(column) * (card.width + gap)
    }

    /// The bottom row and the margin under it. Anything floating over the table sits above
    /// this, so it never hides a card you need.
    var bottomRowHeight: CGFloat { card.height + margin }

    // The bottom row has a slot under each column. The stock takes the one at the thumb's edge
    // and the waste the one beside it; the foundations fill the far end, always left to right.
    private var lastSlot: Int { Board.columnCount - 1 }

    public var stockCenter: CGPoint { CGPoint(x: columnX(leftHanded ? 0 : lastSlot), y: bottomRowY) }

    public func foundationCenter(_ foundation: Int) -> CGPoint {
        let first = leftHanded ? Board.columnCount - Board.foundationCount : 0
        return CGPoint(x: columnX(first + foundation), y: bottomRowY)
    }

    /// Horizontal step between fanned waste cards (Draw 3): as wide as possible, so the rank of
    /// every fanned card stays readable, without touching the foundations.
    public var wasteStep: CGFloat { min(card.width * 0.5, (card.width + 2 * gap - 4) / 2).rounded(.down) }

    /// Centre of the waste card in fan slot `slot` (0 = deepest shown) when `shown` cards are fanned.
    /// The top card always sits next to the stock; older cards fan out towards the foundations.
    public func wasteCenter(slot: Int, shown: Int) -> CGPoint {
        let fromTop = CGFloat(max(0, shown - 1 - slot))
        let topX = columnX(leftHanded ? 1 : lastSlot - 1)
        let x = leftHanded ? topX + fromTop * wasteStep : topX - fromTop * wasteStep
        return CGPoint(x: x, y: bottomRowY)
    }

    func columnTopCenter(_ column: Int) -> CGPoint {
        CGPoint(x: columnX(column), y: tableauTop + card.height / 2)
    }

    /// Vertical offsets between face-down and face-up cards of a column, squeezed when the
    /// column would otherwise run into the bottom row.
    public func offsets(hidden: Int, visible: Int) -> (down: CGFloat, up: CGFloat) {
        let available = max(0, tableauBottom - tableauTop - card.height)
        var down = (card.height * 0.14).rounded()
        var up = (card.height * 0.40).rounded()
        let gaps = CGFloat(max(visible - 1, 0))
        let hiddenCount = CGFloat(hidden)
        if hiddenCount * down + gaps * up <= available { return (down, up) }
        let minUp = (card.height * 0.31).rounded()
        if gaps > 0, hiddenCount * down + gaps * minUp <= available {
            up = ((available - hiddenCount * down) / gaps).rounded(.down)
            return (down, up)
        }
        up = minUp
        if hiddenCount > 0 { down = max(3, ((available - gaps * up) / hiddenCount).rounded(.down)) }
        if hiddenCount * down + gaps * up > available, gaps > 0 {
            up = max(8, ((available - hiddenCount * down) / gaps).rounded(.down))
        }
        return (down, up)
    }

    // MARK: Placements

    public func placements(for game: KlondikeGame) -> [CardPlacement] {
        var result: [CardPlacement] = []
        result.reserveCapacity(52)
        for (i, card) in game.stock.enumerated() {
            result.append(CardPlacement(card: card, center: stockCenter, faceUp: false, pile: .stock, index: i,
                                        zIndex: Double(i)))
        }
        let shown = min(game.drawMode.rawValue, game.waste.count)
        for (i, card) in game.waste.enumerated() {
            let fromTop = game.waste.count - 1 - i
            let slot = max(0, shown - 1 - fromTop)
            result.append(CardPlacement(card: card, center: wasteCenter(slot: slot, shown: shown), faceUp: true,
                                        pile: .waste, index: i, zIndex: Layer.waste + Double(i)))
        }
        for (f, foundation) in game.foundations.enumerated() {
            for (i, card) in foundation.enumerated() {
                result.append(CardPlacement(card: card, center: foundationCenter(f), faceUp: true,
                                            pile: .foundation(f), index: i, zIndex: Layer.foundation + Double(i)))
            }
        }
        for (t, column) in game.tableau.enumerated() {
            let (down, up) = offsets(hidden: column.hidden.count, visible: column.visible.count)
            let top = columnTopCenter(t)
            var y = top.y
            for (i, card) in column.hidden.enumerated() {
                result.append(CardPlacement(card: card, center: CGPoint(x: top.x, y: y), faceUp: false,
                                            pile: .tableau(t), index: i, zIndex: Layer.tableau + Double(i)))
                y += down
            }
            for (i, card) in column.visible.enumerated() {
                if i > 0 { y += up }
                result.append(CardPlacement(card: card, center: CGPoint(x: top.x, y: y), faceUp: true,
                                            pile: .tableau(t), index: column.hidden.count + i,
                                            zIndex: Layer.tableau + Double(column.hidden.count + i)))
            }
        }
        return result
    }

    // MARK: Drag and drop

    /// The area that accepts a drop (or, for a column, a tap) on `pile`. Columns take them
    /// anywhere along their height, down to just above the bottom row.
    func dropZone(for pile: Pile) -> CGRect {
        switch pile {
        case .tableau(let t):
            return CGRect(x: columnX(t) - card.width / 2 - gap / 2, y: 0,
                          width: card.width + gap, height: tableauBottom + gap)
        case .foundation(let f):
            let c = foundationCenter(f)
            return CGRect(x: c.x - card.width / 2, y: c.y - card.height / 2, width: card.width, height: card.height)
                .insetBy(dx: -gap / 2, dy: -gap * 2)
        case .stock, .waste:
            return .null
        }
    }

    /// Which of the `legal` destinations a drop lands on: the one under the finger at `location`,
    /// or else the one the moving card at `cardRect` overlaps most.
    func dropTarget(among legal: [Pile], location: CGPoint, cardRect: CGRect) -> Pile? {
        if let hit = legal.first(where: { dropZone(for: $0).contains(location) }) { return hit }
        var best: (pile: Pile, area: CGFloat)?
        for pile in legal {
            let overlap = dropZone(for: pile).intersection(cardRect)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let area = overlap.width * overlap.height
            if best == nil || area > best!.area { best = (pile, area) }
        }
        return best?.pile
    }
}
