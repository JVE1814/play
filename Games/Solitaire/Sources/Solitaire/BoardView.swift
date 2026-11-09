import KlondikeEngine
import PlayKit
import SwiftUI

/// Cards being dragged.
struct DragState: Equatable {
    var source: Pile
    var count: Int
    var cards: [Card]
    var translation: CGSize
}

/// The table: every card drawn at an absolute position so moves animate naturally.
///
/// Interaction is forgiving for a moving train: any touch that travels less than `tapSlop`
/// counts as a tap (tap = best legal move), a tap on a card with no move tries its neighbours,
/// columns accept taps and drops along their whole height, and drops snap to the nearest legal
/// pile the card overlaps.
struct BoardView: View {
    @ObservedObject var session: SolitaireSession
    let layout: BoardLayout
    let animate: Bool
    @State private var drag: DragState?
    @GestureState private var touching = false

    static let space = "board"
    static let tapSlop: CGFloat = 12

    var body: some View {
        let placements = layout.placements(for: session.game)
        let hinted = session.hintedCards
        let stockTop = session.game.stock.last
        let stockHinted = session.hintedPile == .stock
        ZStack(alignment: .topLeading) {
            foundationSlots
            stockSlot
            ForEach(Board.columnIndices, id: \.self) { column in
                columnZone(column)
            }
            ForEach(placements) { placement in
                cardLayer(placement, highlighted: hinted.contains(placement.card)
                          || (stockHinted && placement.card == stockTop))
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .coordinateSpace(name: Self.space)
        .animation(animate ? .spring(response: 0.3, dampingFraction: 0.86) : nil, value: session.game)
        .onChange(of: touching) { _, isTouching in
            // A cancelled gesture (for example the app going to the background) never calls
            // onEnded, so make sure no card is left floating.
            if !isTouching, drag != nil { drag = nil }
        }
    }

    // MARK: Slots

    private var foundationSlots: some View {
        ForEach(Board.foundationIndices, id: \.self) { f in
            SlotView(size: layout.card, label: "A", highlighted: session.hintedPile == .foundation(f))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Empty foundation")
                .accessibilityHidden(!session.game.foundations[f].isEmpty)
                .accessibilityIdentifier("foundation-\(f)")
                .position(layout.foundationCenter(f))
        }
    }

    private var stockSlot: some View {
        let game = session.game
        let canRedeal = game.stock.isEmpty && !game.waste.isEmpty
        let value: String
        if game.stock.isEmpty {
            value = canRedeal ? "Empty, redeal available" : "Empty"
        } else {
            value = game.stock.count == 1 ? "1 card" : "\(game.stock.count) cards"
        }
        return SlotView(size: layout.card, systemImage: canRedeal ? "arrow.counterclockwise" : nil,
                        highlighted: session.hintedPile == .stock && game.stock.isEmpty)
            .contentShape(Rectangle())
            .onTapGesture { session.tapPile(.stock) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stock")
            .accessibilityValue(session.hintedPile == .stock ? value + ", suggested by hint" : value)
            .accessibilityHint(game.stock.isEmpty ? "Turns the waste over." : "Draws from the stock.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { session.tapPile(.stock) }
            .accessibilityIdentifier("stock")
            .position(layout.stockCenter)
    }

    private func columnZone(_ column: Int) -> some View {
        let zone = layout.dropZone(for: .tableau(column))
        let isEmpty = session.game.tableau[column].isEmpty
        return ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.clear)
            if isEmpty {
                SlotView(size: layout.card, label: "K", highlighted: session.hintedPile == .tableau(column))
                    .padding(.top, layout.tableauTop - zone.minY)
            }
        }
        .frame(width: zone.width, height: zone.height)
        .contentShape(Rectangle())
        .onTapGesture { session.tapPile(.tableau(column)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Empty column \(column + 1)")
        .accessibilityHidden(!isEmpty)
        .accessibilityIdentifier("column-\(column)")
        .position(x: zone.midX, y: zone.midY)
    }

    // MARK: Cards

    private func cardLayer(_ placement: CardPlacement, highlighted: Bool) -> some View {
        let dragged = drag?.cards.contains(placement.card) ?? false
        let offset = dragged ? (drag?.translation ?? .zero) : .zero
        let shakes = CGFloat(session.rejections[placement.card] ?? 0)
        let raised = session.recentlyMoved.contains(placement.card)
        let z = placement.zIndex + (dragged ? BoardLayout.Layer.dragged : raised ? BoardLayout.Layer.moving : 0)
        return CardView(card: placement.card, faceUp: placement.faceUp, size: layout.card, highlighted: highlighted)
            .scaleEffect(dragged ? 1.05 : 1)
            .modifier(ShakeEffect(animatableData: animate ? shakes : 0))
            .animation(animate ? .linear(duration: 0.3) : nil, value: shakes)
            .contentShape(Rectangle())
            .gesture(cardGesture(placement))
            .modifier(accessibility(for: placement, highlighted: highlighted))
            .position(x: placement.center.x + offset.width, y: placement.center.y + offset.height)
            .zIndex(z)
    }

    private func cardGesture(_ placement: CardPlacement) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: CoordinateSpace.named(Self.space))
            .updating($touching) { _, state, _ in state = true }
            .onChanged { value in
                if drag == nil {
                    guard distance(value.translation) > Self.tapSlop, session.canPlay,
                          let lift = liftable(placement),
                          let cards = session.game.board.movableCards(from: lift.source, count: lift.count) else { return }
                    drag = DragState(source: lift.source, count: lift.count, cards: cards, translation: value.translation)
                } else {
                    drag?.translation = value.translation
                }
            }
            .onEnded { value in
                if distance(value.translation) > Self.tapSlop, session.canPlay, let lift = liftable(placement) {
                    endDrag(source: lift.source, count: lift.count, placement: placement,
                            translation: value.translation, location: value.location)
                } else {
                    drag = nil
                    session.tap(placement.card)
                }
            }
    }

    private func distance(_ translation: CGSize) -> CGFloat {
        (translation.width * translation.width + translation.height * translation.height).squareRoot()
    }

    private func endDrag(source: Pile, count: Int, placement: CardPlacement, translation: CGSize, location: CGPoint) {
        let center = CGPoint(x: placement.center.x + translation.width, y: placement.center.y + translation.height)
        let rect = CGRect(x: center.x - layout.card.width / 2, y: center.y - layout.card.height / 2,
                          width: layout.card.width, height: layout.card.height)
        let target = layout.dropTarget(among: session.game.destinations(from: source, count: count),
                                       location: location, cardRect: rect)
        if let target, session.drop(from: source, count: count, onto: target) {
            drag = nil
        } else {
            withAnimation(animate ? .spring(response: 0.3, dampingFraction: 0.8) : nil) {
                drag = nil
            }
        }
    }

    /// The pile and card count that would be lifted by touching this card, if any: the top card
    /// of the waste or a foundation, or a face-up column card with the cards on it.
    private func liftable(_ placement: CardPlacement) -> (source: Pile, count: Int)? {
        let board = session.game.board
        switch placement.pile {
        case .stock:
            return nil
        case .waste, .foundation:
            return placement.card == board.topCard(of: placement.pile) ? (source: placement.pile, count: 1) : nil
        case .tableau(let t):
            return placement.faceUp ? (source: placement.pile, count: board.tableau[t].count - placement.index) : nil
        }
    }

    // MARK: Accessibility

    private func accessibility(for placement: CardPlacement, highlighted: Bool) -> CardAccessibility {
        let game = session.game
        let lift = liftable(placement)
        var place = ""
        switch placement.pile {
        case .stock:
            break
        case .waste:
            place = "Waste"
        case .foundation:
            place = "Foundation"
        case .tableau(let t):
            let hiddenBelow = game.tableau[t].hidden.count
            place = "Column \(t + 1)"
            if placement.index == hiddenBelow, hiddenBelow > 0 {
                place += ", \(hiddenBelow) face down below"
            }
        }
        var actions: [CardAccessibility.Action] = []
        if let lift {
            var offersFoundation = false
            for pile in game.destinations(from: lift.source, count: lift.count) {
                let name: String
                switch pile {
                case .foundation:
                    // One foundation is as good as another.
                    if offersFoundation { continue }
                    offersFoundation = true
                    name = "Move to foundation"
                case .tableau(let t):
                    name = "Move to column \(t + 1)"
                case .stock, .waste:
                    continue
                }
                actions.append(.init(name: name) {
                    _ = session.drop(from: lift.source, count: lift.count, onto: pile)
                })
            }
        }
        let card = placement.card
        if highlighted { place += ", suggested by hint" }
        return CardAccessibility(
            label: placement.faceUp ? card.name : "Face-down card",
            value: place,
            isAccessible: lift != nil,
            identifier: "card-\(card.code)",
            actions: actions,
            activate: { session.tap(card) }
        )
    }
}

/// VoiceOver support for one card: its name, where it is, a default action (best move) and
/// one custom action per legal destination.
struct CardAccessibility: ViewModifier {
    struct Action {
        let name: String
        let perform: () -> Void
    }

    let label: String
    let value: String
    let isAccessible: Bool
    let identifier: String
    let actions: [Action]
    let activate: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityHint(actions.isEmpty ? "" : "Double-tap to play it, or swipe up or down to choose where.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { activate() }
            .accessibilityActions {
                ForEach(actions.indices, id: \.self) { index in
                    Button(actions[index].name) { actions[index].perform() }
                }
            }
            .accessibilityIdentifier(identifier)
            .accessibilityHidden(!isAccessible)
    }
}
