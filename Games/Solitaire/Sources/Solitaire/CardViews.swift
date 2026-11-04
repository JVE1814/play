import KlondikeEngine
import PlayKit
import SwiftUI

/// Card colours. Red and black suits differ in hue and in lightness, and every suit has its own shape.
enum CardPalette {
    static let face = Color(light: 0xFFFFFF, dark: 0x2B2E35)
    static let edge = Color(light: 0x000000, lightOpacity: 0.16, dark: 0xFFFFFF, darkOpacity: 0.16)
    static let red = Color(light: 0xD7263D, dark: 0xFF6B72)
    static let black = Color(light: 0x1B1B22, dark: 0xF2F2F5)
    static let backMark = Color(hex: 0xFFFFFF, opacity: 0.24)

    static func ink(for card: Card) -> Color { card.isRed ? red : black }
}

/// One playing card, face up or face down.
struct CardView: View {
    let card: Card
    let faceUp: Bool
    let size: CGSize
    var highlighted = false

    var body: some View {
        ZStack {
            if faceUp {
                CardFace(card: card, size: size)
            } else {
                CardBack(size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: size.width * 0.14, style: .continuous)
                    .strokeBorder(Theme.highlight, lineWidth: 3.5)
                    .padding(-2)
            }
        }
    }
}

struct CardFace: View {
    let card: Card
    let size: CGSize

    var body: some View {
        let w = size.width
        let ink = CardPalette.ink(for: card)
        let shape = RoundedRectangle(cornerRadius: w * 0.12, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(CardPalette.face)
            shape.strokeBorder(CardPalette.edge, lineWidth: 1)
            HStack(alignment: .center, spacing: w * 0.03) {
                Text(card.rankSymbol)
                    .font(.system(size: w * (card.rank == 10 ? 0.34 : 0.38), weight: .heavy, design: .rounded))
                    .tracking(card.rank == 10 ? -0.8 : 0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                SuitShape(suit: card.suit)
                    .frame(width: w * 0.25, height: w * 0.25)
            }
            .foregroundStyle(ink)
            .padding(.leading, w * 0.08)
            .padding(.top, w * 0.04)
            SuitShape(suit: card.suit)
                .fill(ink)
                .frame(width: w * 0.5, height: w * 0.5)
                .position(x: w / 2, y: size.height * 0.66)
        }
        .frame(width: size.width, height: size.height)
    }
}

struct CardBack: View {
    let size: CGSize
    @Environment(\.accent) private var accent

    var body: some View {
        let w = size.width
        ZStack {
            RoundedRectangle(cornerRadius: w * 0.12, style: .continuous)
                .fill(accent.deep)
            RoundedRectangle(cornerRadius: w * 0.12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.25), lineWidth: 1)
            SuitShape(suit: .diamonds)
                .fill(CardPalette.backMark)
                .frame(width: w * 0.32, height: w * 0.32)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// An empty pile outline with a faint label ("A" for foundations, "K" for columns).
struct SlotView: View {
    let size: CGSize
    var label: String?
    var systemImage: String?
    var highlighted = false
    @Environment(\.accent) private var accent

    var body: some View {
        let w = size.width
        RoundedRectangle(cornerRadius: w * 0.12, style: .continuous)
            .fill(accent.tableControl)
            .overlay {
                if let label {
                    Text(label)
                        .font(.system(size: w * 0.42, weight: .heavy, design: .rounded))
                        .foregroundStyle(accent.onTable.opacity(0.45))
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: w * 0.36, weight: .bold))
                        .foregroundStyle(accent.onTable.opacity(0.6))
                }
            }
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: w * 0.14, style: .continuous)
                        .strokeBorder(Theme.highlight, lineWidth: 3.5)
                        .padding(-2)
                }
            }
            .frame(width: size.width, height: size.height)
    }
}

/// A small horizontal shake used when a tapped card has nowhere to go.
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// The home screen illustration: two fanned cards.
struct SolitaireIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width * 0.56
            let size = CGSize(width: w, height: w * 1.4)
            ZStack {
                CardFace(card: Card(1, .hearts), size: size)
                    .rotationEffect(.degrees(-12))
                    .offset(x: -w * 0.24, y: w * 0.04)
                CardFace(card: Card(1, .spades), size: size)
                    .rotationEffect(.degrees(10))
                    .offset(x: w * 0.24)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .environment(\.colorScheme, .light)
        }
    }
}
