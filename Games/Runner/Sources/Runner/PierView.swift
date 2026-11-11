import PlayKit
import RunnerEngine
import SwiftUI

/// The pier, drawn every frame, with the goal, the power-ups and the cards that say what to
/// do on top.
///
/// Swipe left or right to change lane, up to jump, down to slide. A touch that is not a swipe
/// starts the run, or carries on with a paused one.
struct PierView: View {
    @ObservedObject var session: RunnerSession
    let reduceMotion: Bool
    /// False in UI tests (`-disableAnimations`): the pier is drawn once per change instead of
    /// every frame, so the app goes idle between steps.
    let live: Bool
    @Environment(\.colorScheme) private var colorScheme
    /// Where the touch that has already made its move began. (A touch the system takes away
    /// never ends, so a plain flag would leave the next one ignored.)
    @State private var spentTouch: CGPoint?

    /// How far a thumb has to travel to count as a swipe.
    private static let swipeDistance: CGFloat = 22
    /// What the drifting clouds and the turning coins are timed from.
    private static let opened = Date()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                TimelineView(.animation(minimumInterval: frameInterval, paused: paused)) { timeline in
                    let frame = makeFrame(size: proxy.size, date: live ? timeline.date : Date())
                    Canvas { context, _ in
                        var context = context
                        PierPainter(f: frame).paint(&context)
                    }
                    // Inside the timeline, so what VoiceOver says follows the run.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Pier")
                    .accessibilityValue(session.spokenStatus)
                    .accessibilityHint("Swipe left or right to change lane, up to jump, down to slide. Double-tap to start or carry on.")
                    .accessibilityAddTraits(.allowsDirectInteraction)
                    .accessibilityAction { session.tap() }
                    .accessibilityAction(named: "Move left") { session.perform(.left) }
                    .accessibilityAction(named: "Move right") { session.perform(.right) }
                    .accessibilityAction(named: "Jump") { session.perform(.jump) }
                    .accessibilityAction(named: "Slide") { session.perform(.slide) }
                    .accessibilityIdentifier("pier")
                }
                .contentShape(Rectangle())
                .gesture(swipes)

                PierDisplay(session: session, hud: session.hud)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                cards
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
    }

    /// Nothing is redrawn while the pier is out of view, the run is paused, or the result is up.
    private var paused: Bool { !session.inView || !live || session.phase == .paused || session.showsResult }

    /// Full frame rate while running; half on the start line and after the run, where only
    /// the sea glitters.
    private var frameInterval: Double {
        session.phase == .running ? 1.0 / 60 : 1.0 / 30
    }

    private func makeFrame(size: CGSize, date: Date) -> PierFrame {
        let moments = session.moments
        func since(_ moment: Date?) -> Double? {
            moment.map { date.timeIntervalSince($0) }
        }
        return PierFrame(size: size, run: session.run(at: date), scenery: Scenery.of(colorScheme),
                         clock: live ? date.timeIntervalSince(Self.opened) : 1.37,
                         reduceMotion: reduceMotion, standing: session.phase == .ready,
                         sinceCoin: since(moments.coin), sinceShieldBroke: since(moments.shieldBroke),
                         sinceCrash: since(moments.crash))
    }

    /// One move for each touch, made as soon as the thumb has gone far enough: nobody waits
    /// for the thumb to lift.
    private var swipes: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard spentTouch != value.startLocation else { return }
                let across = value.translation.width
                let down = value.translation.height
                guard max(abs(across), abs(down)) >= Self.swipeDistance else { return }
                spentTouch = value.startLocation
                if abs(across) > abs(down) {
                    session.perform(across < 0 ? .left : .right)
                } else {
                    session.perform(down < 0 ? .jump : .slide)
                }
            }
            .onEnded { value in
                if spentTouch != value.startLocation { session.tap() }
                spentTouch = nil
            }
    }

    /// What to do next, over the lower half of the pier where it hides nothing that matters.
    private var cards: some View {
        VStack(spacing: Theme.Space.m) {
            if let prompt = session.prompt, session.phase == .running {
                PromptCard(move: prompt)
                    .padding(.top, 64)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            switch session.phase {
            case .ready:
                StartCard(goal: session.goal, best: session.best)
                    .transition(.opacity)
            case .paused:
                NoticeCard(title: "Paused", detail: "Tap to carry on", identifier: "pausedCard")
                    .transition(.opacity)
            case .running:
                if session.resumesAt != nil {
                    NoticeCard(title: "Get ready", detail: nil, identifier: "getReadyCard")
                        .transition(.opacity)
                }
            case .over:
                EmptyView()
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.2), value: session.phase)
        .animation(.easeOut(duration: 0.15), value: session.prompt)
        .animation(.easeOut(duration: 0.2), value: session.resumesAt)
        .allowsHitTesting(false)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// Along the top of the pier: the goal on the left, the power-ups in hand on the right.
struct PierDisplay: View {
    @ObservedObject var session: RunnerSession
    @ObservedObject var hud: RunnerHUD

    var body: some View {
        HStack(alignment: .top) {
            GoalChip(score: hud.score, goal: session.goal, reached: session.goalReached)
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                if hud.magnetSeconds > 0 {
                    PowerUpChip(kind: .magnet, text: "\(hud.magnetSeconds) s", spoken: "Magnet, \(hud.magnetSeconds) seconds left")
                }
                if hud.hasShield {
                    PowerUpChip(kind: .shield, text: "Shield", spoken: "Shield")
                }
            }
        }
        .padding(Theme.Space.s)
        .allowsHitTesting(false)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// The score this run is after, with a bar that fills on the way there.
struct GoalChip: View {
    let score: Int
    let goal: Int
    let reached: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: reached ? "checkmark.circle.fill" : "flag.fill")
                Text(reached ? "Goal reached" : "Goal \(goal.formatted())")
                    .monospacedDigit()
            }
            .font(Typography.label)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule()
                        .fill(reached ? Theme.highlight : Color.white)
                        .frame(width: max(4, proxy.size.width * min(1, CGFloat(score) / CGFloat(max(1, goal)))))
                }
            }
            .frame(height: 4)
        }
        .foregroundStyle(reached ? Theme.highlight : .white)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .fixedSize(horizontal: true, vertical: false)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(PierStyle.hudFill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Goal")
        .accessibilityValue(reached ? "\(goal) points, reached" : "\(goal) points")
        .accessibilityIdentifier("goal")
    }
}

/// A power-up in hand.
struct PowerUpChip: View {
    let kind: Pickup.Kind
    let text: String
    let spoken: String

    var body: some View {
        HStack(spacing: 6) {
            PowerUpIcon(kind: kind)
                .frame(width: 18, height: 18)
            Text(text)
                .monospacedDigit()
        }
        .font(Typography.label)
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(Capsule().fill(PierStyle.hudFill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier(kind.rawValue)
    }
}

/// The sign painted on a power-up.
struct PowerUpIcon: View {
    let kind: Pickup.Kind

    var body: some View {
        Canvas { context, size in
            var context = context
            let middle = Double(min(size.width, size.height)) / 2
            switch kind {
            case .magnet: PowerUpShape.magnet(in: &context, x: Double(size.width) / 2, y: Double(size.height) / 2, size: middle * 0.9)
            case .shield: PowerUpShape.shield(in: &context, x: Double(size.width) / 2, y: Double(size.height) / 2, size: middle * 0.92)
            }
        }
    }
}

/// On the start line: how to play, and what to aim for.
struct StartCard: View {
    let goal: Int
    let best: Int

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            Text("Tap to run")
                .font(Typography.title)
                .foregroundStyle(Theme.ink)
            HStack(spacing: Theme.Space.l) {
                swipe("arrow.left.and.right", "Dodge")
                swipe("arrow.up", "Jump")
                swipe("arrow.down", "Slide")
            }
            Text(best > 0 ? "Goal \(goal.formatted()) points · best \(best.formatted())" : "Goal \(goal.formatted()) points")
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: 360)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous).fill(Theme.surface.opacity(0.96)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("startCard")
    }

    private func swipe(_ systemImage: String, _ name: String) -> some View {
        VStack(spacing: Theme.Space.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.hairline))
                .accessibilityHidden(true)
            Text(name)
                .font(Typography.label)
                .accessibilityLabel("Swipe to \(name.lowercased())")
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity)
    }
}

/// A short word over the pier: paused, or about to go on.
struct NoticeCard: View {
    let title: String
    let detail: String?
    let identifier: String

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            Text(title)
                .font(Typography.title)
                .foregroundStyle(Theme.ink)
            if let detail {
                Text(detail)
                    .font(Typography.body)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous).fill(Theme.surface.opacity(0.96)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// During the coached opening: the swipe to make for what is coming.
struct PromptCard: View {
    let move: Move

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: move.arrow)
                .font(.system(size: 22, weight: .heavy))
                .accessibilityHidden(true)
            Text(move.instruction)
                .font(Typography.headline)
        }
        .foregroundStyle(Theme.onHighlight)
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .background(Capsule().fill(Theme.highlight))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("prompt")
    }
}

extension Move {
    var arrow: String {
        switch self {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .jump: return "arrow.up"
        case .slide: return "arrow.down"
        }
    }
}

/// The home screen illustration: the runner in front of a setting sun.
struct RunnerIcon: View {
    var body: some View {
        Canvas { context, size in
            let side = Double(min(size.width, size.height))
            let middle = Spot(x: Double(size.width) / 2, y: Double(size.height) / 2)
            context.fill(Path.disc(x: middle.x, y: middle.y, r: side * 0.46), with: .color(Color(hex: 0xFFE2AE)))
            // Planks under the feet, inside the sun's disc.
            var ground = context
            ground.clip(to: Path.disc(x: middle.x, y: middle.y, r: side * 0.46))
            ground.fill(Path.box(x: 0, y: middle.y + side * 0.3, width: Double(size.width), height: side * 0.3), with: .color(Color(hex: 0xB78657)))
            // The figure is drawn in metres, y up: 1.9 of them fit the icon.
            var figure = context
            let scale = side * 0.4
            figure.translateBy(x: middle.x, y: middle.y + side * 0.36)
            figure.scaleBy(x: scale, y: -scale)
            RunnerFigure.upright(in: &figure, swing: 0.9, tucked: false, armsUp: false, scarfWave: 0.03)
        }
    }
}
