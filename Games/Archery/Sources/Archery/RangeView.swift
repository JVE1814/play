import ArcheryEngine
import PlayKit
import SwiftUI

/// The range, drawn every frame, with the heads-up display on top.
///
/// Touch and hold anywhere to draw; slide to move the sight (relative to where it was, at less
/// than the thumb's speed, so the thumb never covers the target); lift to shoot. Lifting before
/// full draw lets the bow down without shooting.
struct RangeView: View {
    @ObservedObject var session: ArcherySession
    @ObservedObject var preferences: ArcheryPreferences
    let reduceMotion: Bool
    /// False in UI tests (`-disableAnimations`): the range is drawn once per change instead of
    /// every frame, so the app goes idle between steps.
    let live: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var lastTouch: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let camera = RangeCamera(size: size, distance: session.level.distance)
            ZStack {
                TimelineView(.animation(minimumInterval: frameInterval, paused: paused)) { timeline in
                    let frame = makeFrame(size: size, date: timeline.date)
                    Canvas { context, _ in
                        var context = context
                        RangePainter(f: frame).paint(&context)
                    }
                    // Inside the timeline, so the spoken wind follows the gusts.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Range, \(Int(session.level.distance)) metres")
                    .accessibilityValue(session.spokenStatus(at: timeline.date))
                    .accessibilityHint("Swipe up or down to aim left or right, double-tap to shoot. More aiming in the actions.")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: session.nudgeAim(x: 1, y: 0)
                        case .decrement: session.nudgeAim(x: -1, y: 0)
                        @unknown default: break
                        }
                    }
                    .accessibilityAction { session.shootFromAccessibility() }
                    .accessibilityAction(named: "Aim up") { session.nudgeAim(x: 0, y: 1) }
                    .accessibilityAction(named: "Aim down") { session.nudgeAim(x: 0, y: -1) }
                    .accessibilityAction(named: "Aim left") { session.nudgeAim(x: -1, y: 0) }
                    .accessibilityAction(named: "Aim right") { session.nudgeAim(x: 1, y: 0) }
                    .accessibilityActions {
                        if session.level.layout.spots.count > 1 {
                            Button("Next free spot") { session.aimAtNextFreeSpot() }
                        }
                    }
                    .accessibilityIdentifier("range")
                }
                .contentShape(Rectangle())
                .gesture(aimGesture(camera: camera))
                // A thumb held down while the last arrow flew draws as soon as it lands.
                .onChange(of: session.canDraw) { _, canDraw in
                    if canDraw && lastTouch != nil { session.beginDraw() }
                }

                // The wind reading updates four times a second; it needs no more.
                Group {
                    if live {
                        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                            topDisplay(date: timeline.date)
                        }
                    } else {
                        topDisplay(date: Date())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                bottomDisplay(size: size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
    }

    private var paused: Bool { session.showingLevels || !live }

    /// Full frame rate while the bow is drawn or an arrow flies; half otherwise (the flag and
    /// drifting seeds don't need more), which saves battery on a long ride.
    private var frameInterval: Double {
        session.isDrawing || session.flight != nil ? 1.0 / 60 : 1.0 / 30
    }

    private func makeFrame(size: CGSize, date: Date) -> RangeFrame {
        let round = session.round
        let progress = session.drawProgress(at: date)
        let eased = CGFloat(1 - pow(1 - progress, 3))
        let camera = RangeCamera(size: size, distance: round.level.distance, zoom: reduceMotion ? 1 : 1 + 0.045 * eased)
        let time = session.clock(at: date)
        let landed = Array(session.landedShots)
        let venue = Venue.of(round.level.chapter)
        return RangeFrame(camera: camera, venue: venue, level: round.level, time: time,
                          now: date, wind: round.wind, targetOffset: round.targetOffset(at: time), landed: landed,
                          flight: session.flight, landing: session.landing, drawProgress: progress,
                          held: session.held(at: date), sight: session.sight(at: date),
                          showsRestingSight: session.canDraw && !session.showingTip,
                          previousAim: session.isDrawing ? landed.last?.aim : nil,
                          leftHanded: preferences.leftHanded, reduceMotion: reduceMotion,
                          dimmed: colorScheme == .dark && !venue.isNight)
    }

    private func aimGesture(camera: RangeCamera) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Draw at once, or as soon as the last arrow lands if the thumb is still down.
                if !session.isDrawing {
                    if session.canDraw { session.beginDraw() }
                } else if let last = lastTouch {
                    let gain = preferences.aimSpeed.gain / Double(camera.pointsPerMetre)
                    let delta = Vec2(Double(value.location.x - last.x) * gain, -Double(value.location.y - last.y) * gain)
                    session.moveAim(by: delta, limit: camera.aimLimit)
                }
                lastTouch = value.location
            }
            .onEnded { _ in
                lastTouch = nil
                session.release()
            }
    }

    // MARK: Heads-up display

    private func topDisplay(date: Date) -> some View {
        let wind = session.round.windSpeed(at: session.clock(at: date))
        return HStack(alignment: .top) {
            WindGauge(speed: wind)
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                HUDChip(systemImage: "ruler", text: "\(Int(session.level.distance)) m")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Distance")
                    .accessibilityValue("\(Int(session.level.distance)) metres")
                    .accessibilityIdentifier("distance")
                if let left = session.timeLeft(at: date) {
                    TimerChip(seconds: left, running: session.round.timerStart != nil)
                }
            }
        }
        .padding(Theme.Space.s)
        .allowsHitTesting(false)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func bottomDisplay(size: CGSize) -> some View {
        VStack(spacing: Theme.Space.s) {
            Spacer(minLength: 0)
            if let notice = session.notice {
                Toast(notice)
                    .transition(.opacity)
            }
            if session.showingTip && session.isPlaying {
                TipCard(level: session.level)
                    .padding(.horizontal, Theme.Space.m)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(alignment: .bottom) {
                if !preferences.leftHanded { targetCamera(size: size) }
                Spacer(minLength: 0)
                if preferences.leftHanded { targetCamera(size: size) }
            }
            .padding(.horizontal, Theme.Space.s)
            ScoreCard(session: session)
                .padding(.horizontal, Theme.Space.s)
                .padding(.bottom, Theme.Space.s)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: session.showingTip)
        .animation(.easeOut(duration: 0.2), value: session.notice)
        .allowsHitTesting(false)
    }

    @ViewBuilder private func targetCamera(size: CGSize) -> some View {
        if !session.landedShots.isEmpty && !session.showingTip {
            TargetCamera(layout: session.level.layout, shots: Array(session.landedShots), latest: session.landing?.arrow)
                .frame(width: min(104, size.width * 0.26), height: min(104, size.width * 0.26))
        }
    }
}

/// Wind speed and direction, with a bar that fills as the wind rises.
struct WindGauge: View {
    let speed: Double

    var body: some View {
        let strength = min(1, abs(speed) / 5)
        let calm = abs(speed) < 0.05
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "wind")
                Image(systemName: speed >= 0 ? "arrow.right" : "arrow.left")
                    .opacity(calm ? 0 : 1)
                Text(calm ? "Calm" : String(format: "%.1f m/s", abs(speed)))
                    .monospacedDigit()
            }
            .font(Typography.label)
            GeometryReader { proxy in
                ZStack(alignment: speed >= 0 ? .leading : .trailing) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule()
                        .fill(strength > 0.7 ? Color(hex: 0xFF7A5C) : (strength > 0.4 ? Theme.highlight : Color.white))
                        .frame(width: max(4, proxy.size.width * strength))
                }
            }
            .frame(height: 4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .fixedSize(horizontal: true, vertical: false)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(ArcheryStyle.hudFill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wind")
        .accessibilityValue(ArcherySession.spokenWind(speed))
        .accessibilityIdentifier("wind")
    }
}

/// A small dark capsule on the range.
struct HUDChip: View {
    let systemImage: String
    let text: String
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text(text).monospacedDigit()
        }
        .font(Typography.label)
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(Capsule().fill(ArcheryStyle.hudFill))
    }
}

/// The countdown on timed levels. It turns red in the last five seconds.
struct TimerChip: View {
    let seconds: Double
    let running: Bool

    var body: some View {
        let whole = Int(seconds.rounded(.up))
        let urgent = running && seconds <= 5
        HUDChip(systemImage: running ? "stopwatch.fill" : "stopwatch", text: String(format: "%d:%02d", whole / 60, whole % 60),
                tint: urgent ? Color(hex: 0xFF8A7A) : .white)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Time left")
            .accessibilityValue(running ? "\(whole) seconds" : "\(whole) seconds, starts when you draw")
            .accessibilityIdentifier("timer")
    }
}

/// One slot per arrow: what each landed arrow scored, and the arrows still to shoot.
struct ScoreCard: View {
    @ObservedObject var session: ArcherySession

    var body: some View {
        let shots = Array(session.landedShots)
        let total = session.level.arrows
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                if index < shots.count {
                    ScoreChip(hit: shots[index].hit, size: 30)
                } else {
                    ArrowSlot(color: ArcheryStyle.fletching(index))
                }
            }
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(session.displayedScore)")
                    .font(Typography.numeric)
                Text("of \(session.level.maxScore)")
                    .font(Typography.caption)
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(ArcheryStyle.hudFill))
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score card")
        .accessibilityValue(spokenValue(shots))
        .accessibilityIdentifier("scoreCard")
    }

    private func spokenValue(_ shots: [Shot]) -> String {
        let left = session.displayedArrowsLeft
        var parts: [String] = []
        if !shots.isEmpty { parts.append(shots.map(\.hit.spokenLabel).joined(separator: ", ")) }
        parts.append("\(Format.count(left, "arrow")) left")
        parts.append("total \(session.displayedScore) of \(session.level.maxScore)")
        return parts.joined(separator: ". ")
    }
}

/// An arrow still in the quiver: its fletching, seen end on.
struct ArrowSlot: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
            FletchingShape()
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 14, height: 14)
        }
        .frame(width: 30, height: 30)
    }
}

/// Three vanes around a nock.
struct FletchingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for angle in [-90.0, 30.0, 150.0] {
            let radians = angle * .pi / 180
            path.move(to: c)
            path.addLine(to: CGPoint(x: c.x + CGFloat(cos(radians)) * r, y: c.y + CGFloat(sin(radians)) * r))
        }
        return path
    }
}

/// A close-up of the face with this attempt's arrows, like the target camera at a tournament.
struct TargetCamera: View {
    let layout: TargetLayout
    let shots: [Shot]
    let latest: Int?

    var body: some View {
        Canvas { context, size in
            let span = layout.spots.count > 1
                ? (layout.spots.map { abs($0.center.y) }.max() ?? 0) + layout.largestFace.radius
                : layout.largestFace.radius
            let ppm = min(size.width, size.height) / 2 / CGFloat(span * 1.12)
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ v: Vec2) -> CGPoint { CGPoint(x: mid.x + CGFloat(v.x) * ppm, y: mid.y - CGFloat(v.y) * ppm) }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xFBFAF4)))
            for spot in layout.spots {
                let c = point(spot.center)
                for ring in spot.face.lowestRing...10 {
                    let r = CGFloat(spot.face.outerRadius(ofRing: ring)) * ppm
                    let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                    context.fill(circle, with: .color(ArcheryStyle.zoneColor(Face.zone(ofRing: ring))))
                    context.stroke(circle, with: .color(ArcheryStyle.ringLine(Face.zone(ofRing: ring))), lineWidth: 0.5)
                }
            }
            for (index, shot) in shots.enumerated() where shot.hit.inBoss {
                let p = point(shot.hit.point)
                let r: CGFloat = 3.2
                let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                context.fill(dot, with: .color(ArcheryStyle.fletching(index)))
                context.stroke(dot, with: .color(.black.opacity(0.75)), lineWidth: 1)
                if index == latest {
                    let ring = Path(ellipseIn: CGRect(x: p.x - 6.5, y: p.y - 6.5, width: 13, height: 13))
                    context.stroke(ring, with: .color(.white), lineWidth: 1.5)
                    context.stroke(ring, with: .color(.black.opacity(0.4)), lineWidth: 0.5)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).strokeBorder(Color.black.opacity(0.25)))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Target camera")
        .accessibilityValue(shots.map(\.hit.spokenLabel).joined(separator: ", "))
        .accessibilityIdentifier("targetCam")
    }
}

/// What the level is about, shown until the first draw.
struct TipCard: View {
    let level: Level

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                Text("Level \(level.number) · \(level.name)")
                    .font(Typography.headline)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                if let feature = level.feature {
                    Text("NEW · \(feature.uppercased())")
                        .font(Typography.caption.weight(.heavy))
                        .foregroundStyle(Theme.onHighlight)
                        .padding(.horizontal, Theme.Space.s)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.highlight))
                }
            }
            Text(level.tip)
                .font(Typography.body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(level.summary) · \(level.arrows) arrows · \(level.starScores[0]) points for a star")
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Touch and hold to draw, slide to aim, let go to shoot", systemImage: "hand.point.up.left.fill")
                .font(Typography.label)
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 2)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: 440, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous).fill(Theme.surface.opacity(0.96)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tipCard")
    }
}
