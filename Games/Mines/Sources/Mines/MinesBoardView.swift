import MinesEngine
import PlayKit
import SwiftUI

/// The colours of the board, in light and dark mode. Flat, like the rest of the collection.
/// The digits always carry the number, so their colours only help and are never needed.
enum MinesPalette {
    /// A covered square: dark gold on the yellow table, bright gold on the dark one.
    static let covered = Color(light: 0x8A6400, dark: 0x9A7820)
    /// The small diamond on a covered square, so covered squares read without colour.
    static let coveredMark = Color(light: 0xFFFFFF, lightOpacity: 0.24, dark: 0x000000, darkOpacity: 0.22)
    /// An open square.
    static let open = Color(light: 0xFFF6DD, dark: 0x3A3216)
    /// Flags drawn on covered squares.
    static let flag = Color(light: 0xFFF6DD, dark: 0x2B2000)
    /// Mines shown on open squares after a loss.
    static let mine = Color(light: 0x17171C, dark: 0xF4F4F6)
    /// The opened mine.
    static let exploded = Theme.danger
    static let onExploded = Color(light: 0xFFFFFF, dark: 0x1E1A0C)

    private static let digits: [Color] = [
        Color(light: 0x1D5FBF, dark: 0x7DB4FF),
        Color(light: 0x1A7A3A, dark: 0x7FD99A),
        Color(light: 0xC0262D, dark: 0xFF8A8A),
        Color(light: 0x5B2A9E, dark: 0xC6A8FF),
        Color(light: 0x8A2412, dark: 0xFFB07A),
        Color(light: 0x0B6B73, dark: 0x6FE0E0),
        Color(light: 0x17171C, dark: 0xF4F4F6),
        Color(light: 0x4A4A55, dark: 0xBDBDC6),
    ]

    static func digit(_ number: Int) -> Color { digits[max(1, min(8, number)) - 1] }
}

/// The board: 96 squares, each answering taps (open, or flag in flag mode) and long presses
/// (flag) over its whole share of the board.
struct MinesBoardView: View {
    @ObservedObject var session: MinesSession
    let layout: MinesLayout
    let animate: Bool

    static let longPress = 0.4

    var body: some View {
        let game = session.game
        let opening = session.lastOpening
        ZStack(alignment: .topLeading) {
            ForEach(0..<MinesGrid.cellCount, id: \.self) { square in
                let state = game.cellState(square)
                let shakes = CGFloat(session.rejections[square] ?? 0)
                MinesCellView(state: state, side: layout.cell)
                    .animation(animate ? .easeOut(duration: 0.15).delay(rippleDelay(square, opening)) : nil, value: state)
                    .modifier(ShakeEffect(animatableData: animate ? shakes : 0))
                    .animation(animate ? .linear(duration: 0.3) : nil, value: shakes)
                    .frame(width: layout.pitch, height: layout.pitch)
                    .contentShape(Rectangle())
                    .onTapGesture { session.tap(square) }
                    .onLongPressGesture(minimumDuration: Self.longPress) { session.longPress(square) }
                    .modifier(SquareAccessibility(square: square, state: state, session: session))
                    .position(layout.center(of: square))
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("minesBoard")
    }

    /// Squares opened together appear outward from the one tapped.
    private func rippleDelay(_ square: Int, _ opening: MinesSession.Opening?) -> Double {
        guard let opening, opening.cells.count > 1, opening.cells.contains(square) else { return 0 }
        let rows = abs(MinesGrid.row(of: square) - MinesGrid.row(of: opening.origin))
        let columns = abs(MinesGrid.column(of: square) - MinesGrid.column(of: opening.origin))
        return min(0.25, 0.018 * Double(max(rows, columns)))
    }
}

/// One square, drawn for what it shows.
struct MinesCellView: View, Equatable {
    let state: MinesGame.CellState
    let side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.16, style: .continuous)
                .fill(background)
            content
        }
        .frame(width: side, height: side)
    }

    private var background: Color {
        switch state {
        case .covered, .flagged, .wrongFlag: return MinesPalette.covered
        case .number, .mine: return MinesPalette.open
        case .exploded: return MinesPalette.exploded
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .covered:
            Rectangle()
                .fill(MinesPalette.coveredMark)
                .frame(width: side * 0.14, height: side * 0.14)
                .rotationEffect(.degrees(45))
        case .flagged:
            FlagShape().fill(MinesPalette.flag).frame(width: side * 0.6, height: side * 0.6)
        case .wrongFlag:
            ZStack {
                FlagShape().fill(MinesPalette.flag).frame(width: side * 0.6, height: side * 0.6)
                Capsule()
                    .fill(MinesPalette.flag)
                    .frame(width: side * 0.78, height: max(2, side * 0.07))
                    .rotationEffect(.degrees(-45))
            }
        case .number(let n) where n > 0:
            Text("\(n)")
                .font(.system(size: side * 0.58, weight: .heavy, design: .rounded))
                .foregroundStyle(MinesPalette.digit(n))
        case .number:
            EmptyView()
        case .mine:
            MineShape().fill(MinesPalette.mine).frame(width: side * 0.62, height: side * 0.62)
        case .exploded:
            MineShape().fill(MinesPalette.onExploded).frame(width: side * 0.62, height: side * 0.62)
        }
    }
}

/// VoiceOver for one square: where it is, what it shows, a double-tap that does what a tap
/// does, and actions for the rest.
struct SquareAccessibility: ViewModifier {
    let square: Int
    let state: MinesGame.CellState
    @ObservedObject var session: MinesSession

    func body(content: Content) -> some View {
        let game = session.game
        let row = MinesGrid.row(of: square), column = MinesGrid.column(of: square)
        let playing = game.status == .fresh || game.status == .playing
        let covered = state == .covered || state == .flagged
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Row \(row + 1), column \(column + 1)")
            .accessibilityValue(Self.describe(state))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(playing && covered ? (session.flagMode ? "Double-tap to flag." : "Double-tap to open.") : "")
            .accessibilityAction { session.tap(square) }
            .accessibilityActions {
                if playing && covered && game.isStarted {
                    Button(state == .flagged ? "Remove flag" : "Flag") { session.longPress(square) }
                }
                if playing && state == .covered && session.flagMode {
                    Button("Open") { session.open(square) }
                }
                if game.canChord(square) {
                    Button("Open around") { session.openAround(square) }
                }
            }
            .accessibilityIdentifier("cell-\(row)-\(column)")
    }

    static func describe(_ state: MinesGame.CellState) -> String {
        switch state {
        case .covered: return "covered"
        case .flagged: return "flagged"
        case .number(0): return "no mines around"
        case .number(let n): return n == 1 ? "1 mine around" : "\(n) mines around"
        case .mine: return "mine"
        case .exploded: return "opened mine"
        case .wrongFlag: return "flagged, no mine"
        }
    }
}

/// A pennant on a pole with a foot.
struct FlagShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var path = Path()
        path.addRoundedRect(in: CGRect(x: x + w * 0.30, y: y + h * 0.10, width: w * 0.09, height: h * 0.74),
                            cornerSize: CGSize(width: w * 0.045, height: w * 0.045))
        path.move(to: CGPoint(x: x + w * 0.39, y: y + h * 0.10))
        path.addLine(to: CGPoint(x: x + w * 0.84, y: y + h * 0.29))
        path.addLine(to: CGPoint(x: x + w * 0.39, y: y + h * 0.50))
        path.closeSubpath()
        path.addRoundedRect(in: CGRect(x: x + w * 0.16, y: y + h * 0.80, width: w * 0.40, height: h * 0.10),
                            cornerSize: CGSize(width: h * 0.05, height: h * 0.05))
        return path
    }
}

/// A round body with four studs.
struct MineShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addEllipse(in: CGRect(x: center.x - side * 0.30, y: center.y - side * 0.30, width: side * 0.6, height: side * 0.6))
        let reach = side * 0.40, stud = side * 0.10
        for (dx, dy) in [(0.0, -1.0), (1.0, 0.0), (0.0, 1.0), (-1.0, 0.0)] {
            let point = CGPoint(x: center.x + reach * dx, y: center.y + reach * dy)
            path.addEllipse(in: CGRect(x: point.x - stud, y: point.y - stud, width: stud * 2, height: stud * 2))
        }
        return path
    }
}

/// A small sideways shake for a tap that did nothing.
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 4 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// The home screen illustration: four squares of a board, one of them flagged.
struct MinesIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let square = side * 0.42, gap = side * 0.08
            let ink = Accent.sun.onFill
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    RoundedRectangle(cornerRadius: square * 0.18, style: .continuous)
                        .fill(ink)
                        .overlay(FlagShape().fill(Accent.sun.fill).padding(square * 0.18))
                    RoundedRectangle(cornerRadius: square * 0.18, style: .continuous)
                        .strokeBorder(ink, lineWidth: max(2, square * 0.08))
                        .overlay(Text("1").font(.system(size: square * 0.62, weight: .heavy, design: .rounded))
                            .foregroundStyle(ink))
                }
                HStack(spacing: gap) {
                    RoundedRectangle(cornerRadius: square * 0.18, style: .continuous)
                        .strokeBorder(ink, lineWidth: max(2, square * 0.08))
                        .overlay(Text("2").font(.system(size: square * 0.62, weight: .heavy, design: .rounded))
                            .foregroundStyle(ink))
                    RoundedRectangle(cornerRadius: square * 0.18, style: .continuous)
                        .fill(ink)
                }
            }
            .frame(width: square * 2 + gap, height: square * 2 + gap)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
