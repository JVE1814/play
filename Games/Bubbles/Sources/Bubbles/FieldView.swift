import BubbleEngine
import PlayKit
import SwiftUI

/// The playing field: bubbles, aim guide, launcher and shot in flight.
///
/// Aiming works with one thumb: touch above the launcher to point at a spot, or drag below it to
/// pull back like a slingshot. Lift to shoot; slide back onto the launcher to cancel. The guide
/// shows exactly where the bubble will settle.
struct FieldView: View {
    @ObservedObject var session: BubblesSession
    @ObservedObject var preferences: BubblesPreferences
    let layout: FieldLayout
    let animate: Bool

    var body: some View {
        let grid = session.game.grid
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
                .fill(BubbleStyle.panel)
                .frame(width: layout.fieldRect.width, height: layout.fieldRect.height)
                .position(x: layout.fieldRect.midX, y: layout.fieldRect.midY)
                .accessibilityHidden(true)
            deathLine(danger: grid.lowestRow >= BubbleGrid.deathRow - 2)
            ForEach(grid.occupied, id: \.self) { cell in
                if let bubble = grid[cell] {
                    BubbleView(bubble: bubble, diameter: layout.diameter)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(bubble.spokenName)
                        .accessibilityValue("Row \(cell.row + 1), position \(cell.column + 1)")
                        .accessibilityIdentifier("bubble-\(cell.row)-\(cell.column)")
                        .position(layout.center(of: cell))
                }
            }
            aimGuide
            ForEach(session.effects) { effect in
                EffectView(effect: effect, layout: layout)
            }
            flightLayer
            launcher
            nextButton
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .contentShape(Rectangle())
        .gesture(aimGesture)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bubbleField")
    }

    // MARK: Pieces

    private func deathLine(danger: Bool) -> some View {
        Path { path in
            path.move(to: CGPoint(x: layout.fieldRect.minX + 10, y: layout.deathLineY))
            path.addLine(to: CGPoint(x: layout.fieldRect.maxX - 10, y: layout.deathLineY))
        }
        .stroke(danger ? Theme.danger : BubbleStyle.line, style: StrokeStyle(lineWidth: danger ? 3 : 2, lineCap: .round, dash: [6, 7]))
        .accessibilityHidden(true)
    }

    @ViewBuilder private var aimGuide: some View {
        if let trace = session.aimTrace {
            let points = guidePoints(trace)
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
            }
            .stroke(BubbleStyle.guide, style: StrokeStyle(lineWidth: max(3, layout.diameter * 0.11), lineCap: .round,
                                                          dash: [0.1, layout.diameter * 0.3]))
            .accessibilityHidden(true)
            if preferences.fullAimGuide {
                Circle()
                    .strokeBorder(BubbleStyle.fill(.color(session.game.current)), lineWidth: max(2, layout.diameter * 0.08))
                    .frame(width: layout.diameter * 0.92, height: layout.diameter * 0.92)
                    .position(layout.center(of: trace.cell))
                    .accessibilityHidden(true)
            }
        }
    }

    /// The guide's polyline in points: the whole path, or just its first few bubble lengths.
    private func guidePoints(_ trace: ShotTrace) -> [CGPoint] {
        let path = trace.path.map(layout.point)
        guard !preferences.fullAimGuide else { return path }
        var budget = layout.diameter * 4
        var result = [path[0]]
        for (a, b) in zip(path, path.dropFirst()) {
            let length = hypot(b.x - a.x, b.y - a.y)
            if length >= budget {
                result.append(CGPoint(x: a.x + (b.x - a.x) * budget / length, y: a.y + (b.y - a.y) * budget / length))
                break
            }
            result.append(b)
            budget -= length
        }
        return result
    }

    @ViewBuilder private var flightLayer: some View {
        if let flight = session.flight {
            TimelineView(.animation) { timeline in
                let progress = min(1, timeline.date.timeIntervalSince(flight.start) / flight.duration)
                BubbleView(bubble: .color(flight.color), diameter: layout.diameter)
                    .position(layout.point(position(along: flight.path, at: progress)))
            }
            .accessibilityHidden(true)
        }
    }

    private func position(along path: [Point], at progress: Double) -> Point {
        let segments = zip(path, path.dropFirst()).map { ($0, $1, $0.distance(to: $1)) }
        var remaining = segments.reduce(0) { $0 + $1.2 } * progress
        for (a, b, length) in segments {
            if remaining <= length, length > 0 {
                return a + (b - a) * (remaining / length)
            }
            remaining -= length
        }
        return path.last ?? BubbleGrid.launcher
    }

    private var launcher: some View {
        let game = session.game
        return ZStack {
            Circle()
                .strokeBorder(BubbleStyle.guide, lineWidth: 2)
                .frame(width: layout.diameter * 1.3, height: layout.diameter * 1.3)
            if session.flight == nil {
                BubbleView(bubble: .color(game.current), diameter: layout.diameter)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Launcher, \(game.current.spokenName)")
        .accessibilityValue(session.spokenAim)
        .accessibilityHint("Swipe up or down to aim, double-tap to shoot.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: session.adjustSpokenAim(by: 5)
            case .decrement: session.adjustSpokenAim(by: -5)
            @unknown default: break
            }
        }
        .accessibilityAction { session.fireSpokenAim() }
        .accessibilityAction(named: "Swap bubbles") { session.swap() }
        .accessibilityIdentifier("launcher")
        .position(layout.launcher)
    }

    private var nextButton: some View {
        let next = session.game.next
        return Button {
            session.swap()
        } label: {
            ZStack {
                BubbleView(bubble: .color(next), diameter: layout.diameter * 0.78)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: max(9, layout.diameter * 0.2), weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .padding(3)
                    .background(Circle().fill(BubbleStyle.panel))
                    .offset(x: layout.diameter * 0.32, y: layout.diameter * 0.32)
            }
            .frame(width: max(Theme.minTouchTarget, layout.diameter * 1.2), height: max(Theme.minTouchTarget, layout.diameter * 1.2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!session.isPlaying)
        .accessibilityLabel("Next bubble, \(next.spokenName)")
        .accessibilityHint("Swaps it into the launcher.")
        .accessibilityIdentifier("swapBubble")
        .position(layout.nextBubble)
    }

    // MARK: Aiming

    private var aimGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                session.setAim(layout.aim(for: value.location))
            }
            .onEnded { value in
                session.setAim(layout.aim(for: value.location))
                session.fire()
            }
    }
}

/// A bubble leaving the grid: a quick pop in place, or a fall off the bottom.
struct EffectView: View {
    let effect: BubblesSession.Effect
    let layout: FieldLayout
    @State private var finished = false

    var body: some View {
        let start = layout.center(of: effect.cell)
        BubbleView(bubble: effect.bubble, diameter: layout.diameter)
            .scaleEffect(effect.kind == .pop && finished ? 1.35 : 1)
            .opacity(finished ? 0 : 1)
            .position(x: start.x, y: start.y + (effect.kind == .fall && finished ? layout.size.height * 0.6 : 0))
            .accessibilityHidden(true)
            .onAppear {
                let animation: Animation = effect.kind == .pop
                    ? .easeOut(duration: 0.22).delay(effect.delay)
                    : .easeIn(duration: 0.55).delay(effect.delay)
                withAnimation(animation) { finished = true }
            }
    }
}
