import BubbleEngine
import PlayKit
import SwiftUI

/// Flat colours and symbols. Every colour has its own symbol, so bubbles can be told apart
/// without colour; light bubbles carry dark symbols and dark bubbles light ones.
enum BubbleStyle {
    static func fill(_ bubble: Bubble) -> Color {
        switch bubble {
        case .color(let color):
            switch color {
            case .red: return Color(hex: 0xF0435A)
            case .yellow: return Color(hex: 0xFFC531)
            case .green: return Color(hex: 0x2BC27F)
            case .blue: return Color(hex: 0x3D7CF5)
            case .purple: return Color(hex: 0x9B5CF6)
            case .cyan: return Color(hex: 0x2CCBE0)
            }
        case .stone: return Color(hex: 0x8D8F9A)
        case .bomb: return Color(hex: 0x2B2B33)
        }
    }

    static func symbolColor(_ bubble: Bubble) -> Color {
        switch bubble {
        case .color(.yellow), .color(.green), .color(.cyan): return Color(hex: 0x10203A, opacity: 0.72)
        default: return Color.white.opacity(0.92)
        }
    }

    static func symbol(_ bubble: Bubble) -> BubbleSymbol.Kind {
        switch bubble {
        case .color(let color):
            switch color {
            case .red: return .triangle
            case .yellow: return .dot
            case .green: return .square
            case .blue: return .diamond
            case .purple: return .plus
            case .cyan: return .star
            }
        case .stone: return .bar
        case .bomb: return .burst
        }
    }

    /// The field panel behind the bubbles.
    static let panel = Color(light: 0xF3F8FF, dark: 0x0E1726)
    static let guide = Color(light: 0x10203A, lightOpacity: 0.45, dark: 0xFFFFFF, darkOpacity: 0.55)
    static let line = Color(light: 0xC81E3A, lightOpacity: 0.35, dark: 0xFF6B72, darkOpacity: 0.45)
}

/// Original flat symbols drawn inside bubbles.
struct BubbleSymbol: Shape {
    enum Kind { case triangle, dot, square, diamond, plus, star, burst, bar }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height, width: w * rect.width, height: h * rect.height)
        }
        switch kind {
        case .triangle:
            path.move(to: p(0.5, 0.06))
            path.addLine(to: p(0.98, 0.9))
            path.addLine(to: p(0.02, 0.9))
            path.closeSubpath()
        case .dot:
            path.addEllipse(in: r(0.14, 0.14, 0.72, 0.72))
        case .square:
            path.addRoundedRect(in: r(0.1, 0.1, 0.8, 0.8), cornerSize: CGSize(width: rect.width * 0.12, height: rect.height * 0.12))
        case .diamond:
            path.move(to: p(0.5, 0))
            path.addLine(to: p(1, 0.5))
            path.addLine(to: p(0.5, 1))
            path.addLine(to: p(0, 0.5))
            path.closeSubpath()
        case .plus:
            path.addRect(r(0.35, 0.02, 0.3, 0.96))
            path.addRect(r(0.02, 0.35, 0.96, 0.3))
        case .star, .burst:
            let points = kind == .star ? 5 : 8
            let inner: CGFloat = kind == .star ? 0.42 : 0.55
            for i in 0..<(points * 2) {
                let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(points)
                let radius: CGFloat = i % 2 == 0 ? 0.5 : 0.5 * inner
                let point = p(0.5 + radius * cos(angle), 0.53 + radius * sin(angle))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        case .bar:
            path.addRoundedRect(in: r(0.06, 0.37, 0.88, 0.26), cornerSize: CGSize(width: rect.width * 0.1, height: rect.height * 0.1))
        }
        return path
    }
}

/// One bubble: a flat disc with its symbol.
struct BubbleView: View {
    let bubble: Bubble
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(BubbleStyle.fill(bubble))
            Circle()
                .strokeBorder(Color.black.opacity(0.16), lineWidth: max(1, diameter * 0.03))
            BubbleSymbol(kind: BubbleStyle.symbol(bubble))
                .fill(BubbleStyle.symbolColor(bubble))
                .frame(width: diameter * 0.44, height: diameter * 0.44)
        }
        .frame(width: diameter * 0.95, height: diameter * 0.95)
    }
}

/// The home screen illustration: a small cluster of bubbles.
struct BubblesIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let d = proxy.size.width * 0.42
            ZStack {
                BubbleView(bubble: .color(.red), diameter: d).offset(x: -d * 0.52, y: -d * 0.42)
                BubbleView(bubble: .color(.yellow), diameter: d).offset(x: d * 0.52, y: -d * 0.42)
                BubbleView(bubble: .color(.blue), diameter: d).offset(x: 0, y: d * 0.48)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// Rows for the shared Settings screen.
struct BubblesSettingsRows: View {
    @ObservedObject var preferences: BubblesPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsToggleRow("Full aim guide",
                              detail: "Shows the whole path, bounces included. Off shows just its start.",
                              isOn: $preferences.fullAimGuide,
                              identifier: "fullAimGuide")
        }
    }
}
