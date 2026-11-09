import ArcheryEngine
import PlayKit
import SwiftUI

/// Everything needed to draw one frame of the range.
struct RangeFrame {
    let camera: RangeCamera
    let venue: Venue
    let level: Level
    /// Level clock in seconds (drives the wind, the flag and moving targets).
    let time: Double
    let now: Date
    let wind: Wind
    let targetOffset: Vec2
    let landed: [Shot]
    let flight: ArcherySession.Flight?
    let landing: ArcherySession.Landing?
    /// 0 with the bow down, 1 at full draw.
    let drawProgress: Double
    /// Seconds since full draw, while drawing.
    let held: Double?
    /// Where the sight points (target coordinates): the swaying sight while drawing, the resting
    /// sight otherwise.
    let sight: Vec2
    /// Show the resting sight (the level is on and the bow is down).
    let showsRestingSight: Bool
    /// Where the last arrow was aimed, shown faintly while drawing the next one.
    let previousAim: Vec2?
    let leftHanded: Bool
    let reduceMotion: Bool
    let dimmed: Bool
}

/// Draws the range: sky and venue, the ground with its mown stripes and distance lines, the
/// target on its stand (or rail, or swinging frame), arrows, the wind flag, drifting seeds, the
/// arrow in flight, and the bow and sight while drawing.
struct RangePainter {
    let f: RangeFrame
    private var cam: RangeCamera { f.camera }
    private var venue: Venue { f.venue }
    private var w: CGFloat { cam.size.width }
    private var h: CGFloat { cam.size.height }
    private var ppm: CGFloat { cam.pointsPerMetre }
    private var distance: Double { f.level.distance }
    /// Wind speed now: positive blows to the right.
    private var windNow: Double { f.wind.speed(at: f.time) }

    func paint(_ context: inout GraphicsContext) {
        sky(&context)
        celestial(&context)
        backdrop(&context)
        ground(&context)
        if venue.isNight { floodlitGround(&context) }
        targetRig(&context)
        flightArrow(&context)
        landingEffects(&context)
        if venue.isNight { floodlightTowers(&context) }
        if !f.reduceMotion { particles(&context) }
        if f.dimmed { context.fill(Path(CGRect(origin: .zero, size: cam.size)), with: .color(.black.opacity(0.12))) }
        if f.drawProgress > 0 {
            if !f.reduceMotion { vignette(&context) }
            previousAimMarker(&context)
            bow(&context)
            reticle(&context)
        } else if f.showsRestingSight {
            restingSight(&context)
        }
    }

    // MARK: Sky and backdrop

    private func sky(_ context: inout GraphicsContext) {
        let horizon = cam.horizonY
        let rect = CGRect(x: 0, y: 0, width: w, height: max(1, horizon + 2))
        let gradient = Gradient(stops: [
            .init(color: venue.skyTop, location: 0),
            .init(color: venue.skyMiddle, location: 0.58),
            .init(color: venue.skyHorizon, location: 1),
        ])
        context.fill(Path(rect), with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
    }

    private func celestial(_ context: inout GraphicsContext) {
        let horizon = cam.horizonY
        if venue.isNight {
            var stars = SeededGenerator(seed: 77)
            for i in 0..<54 {
                let x = CGFloat(stars.nextUnit()) * w
                let y = CGFloat(stars.nextUnit()) * horizon * 0.92
                let size = 0.6 + CGFloat(stars.nextUnit()) * 1.3
                let twinkle = f.reduceMotion ? 1 : 0.65 + 0.35 * sin(f.time * (1.3 + Double(i % 5) * 0.4) + Double(i))
                let rect = CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.35 + 0.5 * twinkle * stars.nextUnit())))
            }
        }
        let sun = venue.sun
        let center = CGPoint(x: w * sun.x, y: horizon - horizon * sun.y)
        let r = sun.radius
        context.fill(Path(ellipseIn: CGRect(x: center.x - r * 5, y: center.y - r * 5, width: r * 10, height: r * 10)),
                     with: .radialGradient(Gradient(colors: [sun.glow, sun.glow.opacity(0)]), center: center,
                                           startRadius: r * 0.8, endRadius: r * 5))
        let disc = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        context.fill(disc, with: .color(sun.color))
        if venue.isNight {
            // A crescent: the dark side of the moon covers most of the disc (and only the disc).
            var moon = context
            moon.clip(to: disc)
            let cover = CGRect(x: center.x - r * 0.62, y: center.y - r * 1.12, width: r * 2, height: r * 2)
            moon.fill(Path(ellipseIn: cover), with: .color(venue.skyMiddle))
        }
    }

    /// A soft ridge along the horizon. `waves` are (cycles across the view, phase, share of height).
    private func ridge(base: CGFloat, height: CGFloat, waves: [(Double, Double, Double)], peaks: Bool = false) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -2, y: base + 2))
        let steps = 48
        for i in 0...steps {
            let u = Double(i) / Double(steps)
            var value = 0.0
            for (cycles, phase, share) in waves {
                let s = sin(u * cycles * 2 * .pi + phase)
                value += share * (peaks ? 1 - abs(s) : 0.5 + 0.5 * s)
            }
            path.addLine(to: CGPoint(x: -2 + (w + 4) * CGFloat(u), y: base - height * CGFloat(value)))
        }
        path.addLine(to: CGPoint(x: w + 2, y: base + 2))
        path.closeSubpath()
        return path
    }

    private func backdrop(_ context: inout GraphicsContext) {
        let horizon = cam.horizonY
        let tall = horizon
        if venue.hasMountains {
            context.fill(ridge(base: horizon, height: tall * 0.3, waves: [(2.2, 0.4, 0.6), (5.3, 1.1, 0.4)], peaks: true),
                         with: .color(venue.farHills))
            context.fill(ridge(base: horizon, height: tall * 0.16, waves: [(3.1, 2.0, 0.7), (7.7, 0.3, 0.3)], peaks: true),
                         with: .color(venue.nearHills))
        } else {
            context.fill(ridge(base: horizon, height: tall * 0.13, waves: [(1.3, 0.8, 0.7), (3.4, 2.2, 0.3)]),
                         with: .color(venue.farHills))
            context.fill(ridge(base: horizon, height: tall * 0.07, waves: [(2.1, 3.0, 0.6), (5.2, 0.6, 0.4)]),
                         with: .color(venue.nearHills))
        }
        // A tree line: round crowns of different sizes, with a few tall poplars.
        var trees = SeededGenerator(seed: UInt64(f.level.chapter.rawValue) * 31)
        var x: CGFloat = -10
        while x < w + 10 {
            let r = CGFloat(trees.uniform(5...13)) * max(0.7, h / 700)
            let tallTree = trees.nextUnit() < 0.18
            let crown = tallTree
                ? CGRect(x: x - r * 0.55, y: horizon - r * 3.4, width: r * 1.1, height: r * 3.6)
                : CGRect(x: x - r, y: horizon - r * 1.7, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: crown), with: .color(venue.trees))
            x += r * CGFloat(trees.uniform(1.1...1.9))
        }
        context.fill(Path(CGRect(x: 0, y: horizon - 3, width: w, height: 4)), with: .color(venue.trees))
    }

    // MARK: Ground

    private func ground(_ context: inout GraphicsContext) {
        let horizon = cam.horizonY
        let groundRect = CGRect(x: 0, y: horizon, width: w, height: h - horizon)
        context.fill(Path(groundRect), with: .linearGradient(Gradient(colors: [venue.groundFar, venue.groundNear]),
                                                            startPoint: CGPoint(x: 0, y: horizon),
                                                            endPoint: CGPoint(x: 0, y: h)))
        let near = max(1, cam.nearestVisibleDepth)
        var far = distance + 40
        if venue.hasLake {
            let shore = distance + 12
            far = shore
            let shoreY = cam.groundY(atDepth: shore)
            let water = CGRect(x: 0, y: horizon, width: w, height: max(0, shoreY - horizon))
            context.fill(Path(water), with: .linearGradient(Gradient(colors: [Color(hex: 0x9CC8EA), Color(hex: 0x4D90C6)]),
                                                           startPoint: CGPoint(x: 0, y: horizon),
                                                           endPoint: CGPoint(x: 0, y: shoreY)))
            var glints = SeededGenerator(seed: 5)
            for _ in 0..<22 {
                let y = horizon + (shoreY - horizon) * CGFloat(glints.nextUnit())
                let drift = f.reduceMotion ? 0 : CGFloat(sin(f.time * 0.5 + glints.nextUnit() * 6)) * 6
                let x = CGFloat(glints.nextUnit()) * w + drift
                let length = 4 + CGFloat(glints.nextUnit()) * 14 * (y - horizon) / max(1, shoreY - horizon)
                var glint = Path()
                glint.move(to: CGPoint(x: x, y: y))
                glint.addLine(to: CGPoint(x: x + length, y: y))
                context.stroke(glint, with: .color(.white.opacity(0.45)), lineWidth: 1)
            }
            context.fill(Path(CGRect(x: 0, y: shoreY - 1.5, width: w, height: 3)), with: .color(Color(hex: 0xE4D3A3)))
        }
        // Mown stripes every five metres.
        var depth = (near / 5).rounded(.down) * 5
        while depth < far {
            let index = Int(depth / 5)
            if index % 2 == 0 {
                let top = cam.groundY(atDepth: min(far, depth + 5))
                let bottom = min(h, cam.groundY(atDepth: max(depth, 0.5)))
                if bottom - top > 0.5 {
                    context.fill(Path(CGRect(x: 0, y: top, width: w, height: bottom - top)), with: .color(venue.stripe))
                }
            }
            depth += 5
        }
        if venue.hasFlowers { flowers(&context, near: near) }
        distanceLines(&context, near: near)
    }

    private func flowers(_ context: inout GraphicsContext, near: Double) {
        var seeds = SeededGenerator(seed: UInt64(f.level.number) &* 97)
        let colors = [Color.white, Color(hex: 0xFFE14D), Color(hex: 0xFF8FC8), Color(hex: 0xB79CFF)]
        for i in 0..<70 {
            let z = near + (distance + 8 - near) * seeds.nextUnit()
            let halfWidth = Double(w / 2) / Double(cam.scale(atDepth: z))
            let x = (seeds.nextUnit() * 2 - 1) * halfWidth
            let p = cam.project(Vec3(x, 0, z))
            let size = min(4, max(0.8, cam.scale(atDepth: z) * 0.04))
            context.fill(Path(ellipseIn: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)),
                         with: .color(colors[i % colors.count].opacity(0.9)))
        }
    }

    private func distanceLines(_ context: inout GraphicsContext, near: Double) {
        var lastLabel: CGFloat = .infinity
        // Clear of the floodlight tower at night.
        let labelX: CGFloat = venue.isNight ? w * 0.04 + 12 : 10
        for metres in stride(from: 10.0, to: distance - 2, by: 10) where metres > near {
            let y = cam.groundY(atDepth: metres)
            let width = min(3, max(0.6, cam.scale(atDepth: metres) * 0.05))
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: w, y: y))
            context.stroke(line, with: .color(venue.line.opacity(0.55)), lineWidth: width)
            if lastLabel - y > 15 {
                let label = Text("\(Int(metres)) m")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(venue.label)
                context.draw(label, at: CGPoint(x: labelX, y: y - 2), anchor: .bottomLeading)
                lastLabel = y
            }
        }
    }

    private func floodlitGround(_ context: inout GraphicsContext) {
        let spot = cam.project(Vec3(0, 0, distance))
        let r = w * 0.75
        context.fill(Path(ellipseIn: CGRect(x: spot.x - r, y: spot.y - r * 0.55, width: r * 2, height: r * 1.1)),
                     with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF3D2, opacity: 0.32), Color(hex: 0xFFF3D2, opacity: 0)]),
                                           center: spot, startRadius: 0, endRadius: r))
        let target = cam.onTarget(.zero)
        for side in [-1.0, 1.0] {
            let lamp = CGPoint(x: w / 2 + CGFloat(side) * w * 0.46, y: h * 0.05)
            var beam = Path()
            beam.move(to: lamp)
            beam.addLine(to: CGPoint(x: target.x - w * 0.22, y: target.y + ppm * 0.9))
            beam.addLine(to: CGPoint(x: target.x + w * 0.22, y: target.y + ppm * 0.9))
            beam.closeSubpath()
            context.fill(beam, with: .linearGradient(Gradient(colors: [Color(hex: 0xFFF6DA, opacity: 0.16), Color(hex: 0xFFF6DA, opacity: 0.02)]),
                                                    startPoint: lamp, endPoint: target))
        }
    }

    private func floodlightTowers(_ context: inout GraphicsContext) {
        for side in [-1.0, 1.0] {
            let x = w / 2 + CGFloat(side) * w * 0.46
            let top = h * 0.05
            var pole = Path()
            pole.move(to: CGPoint(x: x, y: top))
            pole.addLine(to: CGPoint(x: x + CGFloat(side) * 6, y: h))
            context.stroke(pole, with: .color(Color(hex: 0x2A2F3A)), lineWidth: 5)
            let head = CGRect(x: x - 15, y: top - 9, width: 30, height: 14)
            context.fill(Path(roundedRect: head, cornerRadius: 3), with: .color(Color(hex: 0x30343F)))
            context.fill(Path(ellipseIn: head.insetBy(dx: -26, dy: -26)),
                         with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF8E2, opacity: 0.7), Color(hex: 0xFFF8E2, opacity: 0)]),
                                               center: CGPoint(x: head.midX, y: head.midY), startRadius: 2, endRadius: 40))
            for i in 0..<3 {
                let bulb = CGRect(x: head.minX + 3 + CGFloat(i) * 9, y: head.minY + 3, width: 7, height: 7)
                context.fill(Path(ellipseIn: bulb), with: .color(Color(hex: 0xFFFBEE)))
            }
        }
    }

    // MARK: The target

    /// Screen point for boss coordinates, following the moving target (and the landing shake).
    private func onBoss(_ v: Vec2, shake: CGFloat) -> CGPoint {
        let p = cam.onTarget(v + f.targetOffset)
        return CGPoint(x: p.x + shake, y: p.y)
    }

    private var shake: CGFloat {
        guard let landing = f.landing, landing.shot.hit.inBoss, !f.reduceMotion else { return 0 }
        let age = f.now.timeIntervalSince(landing.date)
        guard age >= 0, age < 0.35 else { return 0 }
        return CGFloat(sin(age * 70) * exp(-age * 10)) * min(2.5, ppm * 0.02)
    }

    private func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        return path
    }

    private func targetRig(_ context: inout GraphicsContext) {
        let layout = f.level.layout
        let half = layout.bossSize / 2
        let offset = f.targetOffset
        let jolt = shake
        let woodWidth = max(1.2, ppm * 0.07)

        let shadowCenter = cam.project(Vec3(offset.x + Double(venue.shadowLean) * 0.7, 0, distance))
        let shadowWidth = ppm * 1.7 * (1 + abs(venue.shadowLean) * 0.5)
        let shadowHeight = max(3, cam.groundY(atDepth: distance - 0.5) - cam.groundY(atDepth: distance + 0.5))
        context.fill(Path(ellipseIn: CGRect(x: shadowCenter.x - shadowWidth / 2, y: shadowCenter.y - shadowHeight / 2,
                                            width: shadowWidth, height: shadowHeight)),
                     with: .color(venue.shadow))

        switch f.level.motion {
        case .still:
            standBackLeg(&context, offset: offset, width: woodWidth)
        case .slide(let amplitude, _):
            for z in [distance - 0.25, distance + 0.35] {
                let a = cam.project(Vec3(-(amplitude + 1.0), 0, z))
                let b = cam.project(Vec3(amplitude + 1.0, 0, z))
                context.stroke(line(a, b), with: .color(Color(hex: 0x3F3F44, opacity: 0.85)),
                               lineWidth: max(1, cam.scale(atDepth: z) * 0.04))
            }
            var x = -(amplitude + 1.0)
            while x <= amplitude + 1.0 {
                context.stroke(line(cam.project(Vec3(x, 0, distance - 0.3)), cam.project(Vec3(x, 0, distance + 0.4))),
                               with: .color(Color(hex: 0x5B4634, opacity: 0.7)), lineWidth: max(1, ppm * 0.05))
                x += 0.45
            }
            standBackLeg(&context, offset: offset, width: woodWidth)
        case .swing(let length, let angle, _):
            let span = length * sin(angle) + 0.95
            let beam = 1.95 + length + 0.1
            for side in [-1.0, 1.0] {
                let foot = cam.project(Vec3(side * span, 0, distance + 0.2))
                let top = cam.project(Vec3(side * span, beam, distance + 0.2))
                context.stroke(line(foot, top), with: .color(venue.wood), lineWidth: max(1.5, ppm * 0.1))
            }
            let left = cam.project(Vec3(-span - 0.1, beam, distance + 0.2))
            let right = cam.project(Vec3(span + 0.1, beam, distance + 0.2))
            context.stroke(line(left, right), with: .color(venue.wood), lineWidth: max(1.5, ppm * 0.11))
            for side in [-1.0, 1.0] {
                let pivot = cam.project(Vec3(side * 0.45, 1.95 + length, distance + 0.2))
                let hook = onBoss(Vec2(side * 0.45, half), shake: jolt)
                context.stroke(line(pivot, hook), with: .color(Color(hex: 0xE2D3AE)), lineWidth: max(1, ppm * 0.018))
            }
        }

        // The boss: a square of straw, bound with darker bands.
        let bossRect = self.bossRect(shake: jolt)
        let bossPath = Path(roundedRect: bossRect, cornerRadius: ppm * 0.07)
        context.fill(bossPath, with: .color(venue.boss))
        context.fill(bossPath, with: .linearGradient(Gradient(colors: [.white.opacity(0.18), .black.opacity(0.1)]),
                                                    startPoint: CGPoint(x: 0, y: bossRect.minY),
                                                    endPoint: CGPoint(x: 0, y: bossRect.maxY)))
        for band in [0.42, 0.16, -0.12, -0.4] {
            let y = onBoss(Vec2(0, band), shake: jolt).y
            context.stroke(line(CGPoint(x: bossRect.minX + 1, y: y), CGPoint(x: bossRect.maxX - 1, y: y)),
                           with: .color(venue.bossEdge.opacity(0.45)), lineWidth: max(0.5, ppm * 0.012))
        }
        context.stroke(bossPath, with: .color(venue.bossEdge), lineWidth: max(1, ppm * 0.022))

        faces(&context, shake: jolt)

        if f.level.motion == .still || isSliding {
            standFront(&context, offset: offset, width: woodWidth, shake: jolt)
        }
        flag(&context, shake: jolt)
        stuckArrows(&context, shake: jolt)
    }

    /// The boss on screen, where it is now.
    private func bossRect(shake: CGFloat) -> CGRect {
        let half = f.level.layout.bossSize / 2
        let topLeft = onBoss(Vec2(-half, half), shake: shake)
        let bottomRight = onBoss(Vec2(half, -half), shake: shake)
        return CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
    }

    private var isSliding: Bool {
        if case .slide = f.level.motion { return true }
        return false
    }

    private func standBackLeg(_ context: inout GraphicsContext, offset: Vec2, width: CGFloat) {
        let top = cam.project(Vec3(offset.x, Ballistics.bossHeight + 0.3 + offset.y, distance + 0.1))
        let foot = cam.project(Vec3(offset.x, 0, distance + 0.9))
        context.stroke(line(top, foot), with: .color(venue.wood.opacity(0.85)), lineWidth: width)
    }

    private func standFront(_ context: inout GraphicsContext, offset: Vec2, width: CGFloat, shake: CGFloat) {
        let half = f.level.layout.bossSize / 2
        var feet: [CGPoint] = []
        for side in [-1.0, 1.0] {
            let foot = cam.project(Vec3(offset.x + side * (half - 0.02), 0, distance - 0.2))
            let top = onBoss(Vec2(side * (half - 0.08), half + 0.12), shake: shake)
            context.stroke(line(foot, top), with: .color(venue.wood), lineWidth: width)
            feet.append(foot)
        }
        // A crossbar below the boss, with the target's number plate.
        let barY = onBoss(Vec2(0, -half - 0.1), shake: shake).y
        let left = onBoss(Vec2(-half + 0.02, 0), shake: shake).x
        let right = onBoss(Vec2(half - 0.02, 0), shake: shake).x
        context.stroke(line(CGPoint(x: left, y: barY), CGPoint(x: right, y: barY)), with: .color(venue.wood),
                       lineWidth: width * 0.9)
        let plateCenter = onBoss(Vec2(0, -half - 0.2), shake: shake)
        let plate = CGRect(x: plateCenter.x - ppm * 0.12, y: plateCenter.y - ppm * 0.08, width: ppm * 0.24, height: ppm * 0.16)
        context.fill(Path(roundedRect: plate, cornerRadius: ppm * 0.02), with: .color(Color(hex: 0xFAFAF5)))
        if plate.height > 8 {
            let number = Text("\(f.level.number)")
                .font(.system(size: min(16, plate.height * 0.72), weight: .heavy, design: .rounded))
                .foregroundStyle(Color(hex: 0x1D1D22))
            context.draw(number, at: CGPoint(x: plate.midX, y: plate.midY), anchor: .center)
        }
        if isSliding {
            for foot in feet {
                let r = max(1.5, ppm * 0.05)
                context.fill(Path(ellipseIn: CGRect(x: foot.x - r, y: foot.y - r, width: r * 2, height: r * 2)),
                             with: .color(Color(hex: 0x26262A)))
            }
        }
    }

    private func faces(_ context: inout GraphicsContext, shake: CGFloat) {
        let layout = f.level.layout
        // The paper: one sheet behind all the faces, pinned at the corners.
        let radius = layout.largestFace.radius
        let ys = layout.spots.map(\.center.y)
        let margin = layout.spots.count > 1 ? 0.05 : 0.03
        let sheetTop = onBoss(Vec2(-radius - margin, (ys.max() ?? 0) + radius + margin), shake: shake)
        let sheetBottom = onBoss(Vec2(radius + margin, (ys.min() ?? 0) - radius - margin), shake: shake)
        let sheet = CGRect(x: sheetTop.x, y: sheetTop.y, width: sheetBottom.x - sheetTop.x, height: sheetBottom.y - sheetTop.y)
        context.fill(Path(sheet.offsetBy(dx: 0, dy: max(0.5, ppm * 0.008))), with: .color(.black.opacity(0.15)))
        context.fill(Path(sheet), with: .color(Color(hex: 0xFBFAF4)))
        let pin = max(0.8, ppm * 0.012)
        for corner in [CGPoint(x: sheet.minX, y: sheet.minY), CGPoint(x: sheet.maxX, y: sheet.minY),
                       CGPoint(x: sheet.minX, y: sheet.maxY), CGPoint(x: sheet.maxX, y: sheet.maxY)] {
            let c = CGPoint(x: corner.x + (corner.x < sheet.midX ? 1 : -1) * pin * 2,
                            y: corner.y + (corner.y < sheet.midY ? 1 : -1) * pin * 2)
            context.fill(Path(ellipseIn: CGRect(x: c.x - pin, y: c.y - pin, width: pin * 2, height: pin * 2)),
                         with: .color(Color(hex: 0xD8423A)))
        }
        for spot in layout.spots {
            let center = onBoss(spot.center, shake: shake)
            let face = spot.face
            func circle(_ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }
            for ring in face.lowestRing...10 {
                let r = CGFloat(face.outerRadius(ofRing: ring)) * ppm
                context.fill(circle(r), with: .color(ArcheryStyle.zoneColor(Face.zone(ofRing: ring))))
            }
            let lineWidth = max(0.35, ppm * 0.0018)
            for ring in face.lowestRing...10 {
                let r = CGFloat(face.outerRadius(ofRing: ring)) * ppm
                if r > 1.5 {
                    context.stroke(circle(r), with: .color(ArcheryStyle.ringLine(Face.zone(ofRing: ring))), lineWidth: lineWidth)
                }
            }
            let x = CGFloat(face.xRadius) * ppm
            if x > 2 {
                context.stroke(circle(x), with: .color(.black.opacity(0.4)), lineWidth: lineWidth)
                let arm = max(1, x * 0.25)
                context.stroke(line(CGPoint(x: center.x - arm, y: center.y), CGPoint(x: center.x + arm, y: center.y)),
                               with: .color(.black.opacity(0.55)), lineWidth: lineWidth)
                context.stroke(line(CGPoint(x: center.x, y: center.y - arm), CGPoint(x: center.x, y: center.y + arm)),
                               with: .color(.black.opacity(0.55)), lineWidth: lineWidth)
            }
        }
    }

    /// The wind flag on its pole above the boss. It swivels on the pole top: it hangs limp in
    /// still air, lifts and streams out downwind as the wind rises, and flutters faster in a
    /// strong wind.
    private func flag(_ context: inout GraphicsContext, shake: CGFloat) {
        let half = f.level.layout.bossSize / 2
        let base = Vec2(half - 0.12, half)
        let top = Vec2(half - 0.12, half + 0.6)
        context.stroke(line(onBoss(base, shake: shake), onBoss(top, shake: shake)), with: .color(Color(hex: 0xD9DADF)),
                       lineWidth: max(1, ppm * 0.022))
        let speed = windNow
        let strength = min(1, abs(speed) / 4.5)
        // Which way it streams, eased through calm so the flag swings across the pole (edge on
        // for a moment) rather than flipping when the wind changes sides. On a still day it
        // simply hangs limp beside the pole.
        let side = f.wind.isCalm ? 1 : max(-1, min(1, speed / 0.4))
        let angle = (0.2 + 1.32 * strength) * side  // radians from hanging straight down
        let direction = Vec2(sin(angle), -cos(angle))
        let normal = Vec2(-cos(angle) * side, -abs(sin(angle)))
        let length = 0.32
        let depth = 0.2
        let flutterSpeed = 1.6 + 2.6 * strength
        let flutterSize = f.reduceMotion ? 0 : 0.012 + 0.03 * strength
        var path = Path()
        var bottomEdge: [CGPoint] = []
        for i in 0...8 {
            let u = Double(i) / 8
            let wave = flutterSize * u * sin(2 * .pi * flutterSpeed * f.time - u * 4.2)
            let along = top + direction * (length * u) + normal * wave
            let p = onBoss(along, shake: shake)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            bottomEdge.append(onBoss(along + normal * (depth * (1 - 0.15 * u)), shake: shake))
        }
        for p in bottomEdge.reversed() { path.addLine(to: p) }
        path.closeSubpath()
        context.fill(path, with: .color(Color(hex: 0xFFC93C)))
        context.stroke(path, with: .color(Color(hex: 0xC98A12, opacity: 0.8)), lineWidth: max(0.5, ppm * 0.006))
    }

    /// Arrows in the boss, seen from the shooting line: a short shaft pointing back towards you,
    /// three vanes and the nock.
    private func stuckArrows(_ context: inout GraphicsContext, shake: CGFloat) {
        for (index, shot) in f.landed.enumerated() where shot.hit.inBoss {
            let point = onBoss(shot.hit.point, shake: shake)
            let path = FlightPath(distance: distance, impact: shot.hit.point, targetOffset: shot.targetOffset,
                                  drift: shot.drift, mirrored: f.leftHanded)
            let heading = path.heading(at: 1)
            let length = (heading.x * heading.x + heading.y * heading.y + heading.z * heading.z).squareRoot()
            let back = heading * (-Arrow.length * 0.8 / max(length, 1e-9))
            let tailWorld = Vec3(shot.hit.point.x + f.targetOffset.x, Ballistics.bossHeight + shot.hit.point.y + f.targetOffset.y,
                                 distance) + back
            var tail = cam.project(tailWorld)
            tail.x += shake
            var dx = tail.x - point.x
            var dy = tail.y - point.y
            let stub = hypot(dx, dy)
            let minimum = max(3, ppm * 0.03)
            if stub < minimum {
                let scale = stub > 0.01 ? minimum / stub : 0
                dx = stub > 0.01 ? dx * scale : (f.leftHanded ? 1 : -1) * minimum * 0.35
                dy = stub > 0.01 ? dy * scale : -minimum
            }
            let end = CGPoint(x: point.x + dx, y: point.y + dy)
            drawArrowBack(&context, tip: point, tail: end, vane: min(13, max(2.6, ppm * 0.05)),
                          shaft: min(3, max(1, ppm * 0.008)), color: ArcheryStyle.fletching(index))
        }
    }

    private func drawArrowBack(_ context: inout GraphicsContext, tip: CGPoint, tail: CGPoint, vane: CGFloat, shaft: CGFloat,
                               color: Color, opacity: Double = 1) {
        var layer = context
        layer.opacity = opacity
        layer.stroke(line(tip, tail), with: .color(Color(hex: 0x2A2B31)), style: StrokeStyle(lineWidth: shaft, lineCap: .round))
        for angle in [-90.0, 30.0, 150.0] {
            let radians = angle * .pi / 180
            let end = CGPoint(x: tail.x + CGFloat(cos(radians)) * vane, y: tail.y + CGFloat(sin(radians)) * vane)
            layer.stroke(line(tail, end), with: .color(color), style: StrokeStyle(lineWidth: max(1.2, vane * 0.32), lineCap: .round))
        }
        let nock = max(1, vane * 0.28)
        layer.fill(Path(ellipseIn: CGRect(x: tail.x - nock, y: tail.y - nock, width: nock * 2, height: nock * 2)),
                   with: .color(color))
        layer.stroke(Path(ellipseIn: CGRect(x: tail.x - nock, y: tail.y - nock, width: nock * 2, height: nock * 2)),
                     with: .color(.black.opacity(0.35)), lineWidth: 0.5)
    }

    // MARK: Flight and landing

    private func flightArrow(_ context: inout GraphicsContext) {
        guard let flight = f.flight else { return }
        // Flight fraction: 1 at the target. A miss flies on past it.
        let s = f.now.timeIntervalSince(flight.start) / flight.arrival
        guard s >= 0 else { return }
        let path = flight.path
        func position(_ s: Double) -> Vec3 {
            guard s > 1 else { return path.position(at: s) }
            // `heading(at: 1)` spans the last hundredth of the flight.
            return path.position(at: 1) + path.heading(at: 1) * ((s - 1) / 0.01)
        }
        let tip = position(s)
        let heading = path.heading(at: min(1, s))
        let length = (heading.x * heading.x + heading.y * heading.y + heading.z * heading.z).squareRoot()
        let tailWorld = tip - heading * (Arrow.length / max(length, 1e-9))
        guard tailWorld.z > 0.9 else { return }
        let fade = s > 1 ? max(0, 1 - (s - 1) * 4) : 1
        let tipPoint = cam.project(tip)
        let tailPoint = cam.project(tailWorld)
        let trailStart = cam.project(position(max(0, s - 0.07)))
        // Past the target plane a miss is behind the boss, so the boss hides it.
        var layer = context
        if s > 1 {
            let boss = bossRect(shake: 0)
            layer.clip(to: Path(boss.insetBy(dx: -1, dy: -1)), options: .inverse)
        }
        layer.stroke(line(trailStart, tipPoint), with: .color(.white.opacity(0.28 * fade)),
                     style: StrokeStyle(lineWidth: 1, lineCap: .round))
        drawArrowBack(&layer, tip: tipPoint, tail: tailPoint,
                      vane: min(46, max(2.6, cam.scale(atDepth: tailWorld.z) * 0.05)),
                      shaft: min(7, max(1.1, cam.scale(atDepth: tip.z) * 0.008)),
                      color: ArcheryStyle.fletching(flight.arrow), opacity: fade)
    }

    private func landingEffects(_ context: inout GraphicsContext) {
        guard let landing = f.landing else { return }
        let age = f.now.timeIntervalSince(landing.date)
        guard age >= 0, age < 1.6 else { return }
        let hit = landing.shot.hit
        let point = hit.inBoss ? onBoss(hit.point, shake: 0) : cam.onTarget(hit.point + f.targetOffset)
        if hit.inBoss, age < 0.4, !f.reduceMotion {
            let progress = age / 0.4
            var specks = SeededGenerator(seed: UInt64(landing.arrow + 1) &* 131)
            for i in 0..<8 {
                let angle = Double(i) * .pi / 4 + specks.uniform(-0.3...0.3)
                let reach = CGFloat(1 - pow(1 - progress, 2)) * (6 + ppm * 0.06)
                let p = CGPoint(x: point.x + CGFloat(cos(angle)) * reach, y: point.y + CGFloat(sin(angle)) * reach)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)),
                             with: .color(venue.bossEdge.opacity(1 - progress)))
            }
        }
        let chip = ArcheryStyle.chip(for: hit)
        let rise = f.reduceMotion ? 0 : CGFloat(min(1, age / 1.2)) * 14
        let opacity = age < 1.1 ? 1 : max(0, (1.6 - age) / 0.5)
        let text = context.resolve(Text(hit.label)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(chip.text))
        let size = text.measure(in: CGSize(width: 100, height: 40))
        let center = CGPoint(x: min(w - 24, max(24, point.x + 20)), y: max(16, point.y - 20 - rise))
        let capsule = CGRect(x: center.x - max(size.width / 2 + 8, 13), y: center.y - size.height / 2 - 3,
                             width: max(size.width + 16, 26), height: size.height + 6)
        var layer = context
        layer.opacity = opacity
        layer.fill(Path(roundedRect: capsule, cornerRadius: capsule.height / 2), with: .color(chip.fill))
        layer.stroke(Path(roundedRect: capsule, cornerRadius: capsule.height / 2), with: .color(.black.opacity(0.25)),
                     lineWidth: 1)
        layer.draw(text, at: center, anchor: .center)
    }

    // MARK: Drifting seeds, leaves and moths

    private func particles(_ context: inout GraphicsContext) {
        var seeds = SeededGenerator(seed: UInt64(f.level.chapter.rawValue) &* 7_919)
        let travel = f.wind.travel(at: f.time)
        let count = venue.particle == .moths ? 12 : 16
        for i in 0..<count {
            let x0 = seeds.nextUnit()
            let y0 = seeds.nextUnit()
            let depth = seeds.uniform(0.6...1.4)
            let phase = seeds.uniform(0...(2 * .pi))
            var x = CGFloat(x0) * w + CGFloat(travel * 20 * depth)
            var y = CGFloat(y0) * h * 0.8 + 6
            switch venue.particle {
            case .seeds:
                y -= CGFloat(f.time * 5 * depth)  // rising; wrapped below
            case .moths:
                x = w / 2 + CGFloat(sin(f.time * 1.7 * depth + phase)) * w * 0.3 + CGFloat(sin(f.time * 5.3 + phase)) * 6
                y = cam.onTarget(.zero).y - ppm * 0.6 + CGFloat(cos(f.time * 1.3 * depth + phase)) * h * 0.18
            default:
                break
            }
            y += CGFloat(sin(f.time * 0.9 * depth + phase)) * 7
            let span = w + 40
            x = (x + 20).truncatingRemainder(dividingBy: span)
            if x < 0 { x += span }
            x -= 20
            let wrappedHeight = h * 0.85
            y = y.truncatingRemainder(dividingBy: wrappedHeight)
            if y < 0 { y += wrappedHeight }
            let size = CGFloat(depth) * 1.6
            switch venue.particle {
            case .leaves:
                var leaf = context
                leaf.translateBy(x: x, y: y)
                leaf.rotate(by: .radians(f.time * 1.6 * depth + phase))
                let colors = [Color(hex: 0xE9A23B), Color(hex: 0xB7CF55), Color(hex: 0xD86A2C)]
                leaf.fill(Path(ellipseIn: CGRect(x: -size * 1.8, y: -size * 0.8, width: size * 3.6, height: size * 1.6)),
                          with: .color(colors[i % colors.count].opacity(0.9)))
            default:
                let glow = venue.particle == .seeds ? size * 2.2 : size
                context.fill(Path(ellipseIn: CGRect(x: x - glow, y: y - glow, width: glow * 2, height: glow * 2)),
                             with: .color(venue.particleColor.opacity(venue.particle == .seeds ? 0.25 : 0.5)))
                context.fill(Path(ellipseIn: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)),
                             with: .color(venue.particleColor))
            }
        }
    }

    // MARK: Bow and sight

    private var sightPoint: CGPoint { cam.onTarget(f.sight) }

    /// Where the sight is drawn: it rises into place as the bow is drawn.
    private var raisedSight: CGPoint {
        let eased = 1 - pow(1 - f.drawProgress, 3)
        let raise = f.reduceMotion ? 0 : (1 - eased) * h * 0.6
        return CGPoint(x: sightPoint.x, y: sightPoint.y + raise)
    }
    private var side: CGFloat { f.leftHanded ? -1 : 1 }

    /// The view darkens at the edges while you concentrate at full draw.
    private func vignette(_ context: inout GraphicsContext) {
        let strength = 0.3 * f.drawProgress
        let center = CGPoint(x: w / 2, y: h / 2)
        let radius = max(w, h) * 0.75
        context.fill(Path(CGRect(origin: .zero, size: cam.size)),
                     with: .radialGradient(Gradient(stops: [.init(color: .black.opacity(0), location: 0.55),
                                                            .init(color: .black.opacity(strength), location: 1)]),
                                           center: center, startRadius: 0, endRadius: radius))
    }

    private func previousAimMarker(_ context: inout GraphicsContext) {
        guard let previous = f.previousAim else { return }
        let p = cam.onTarget(previous)
        let arm: CGFloat = 4
        var cross = Path()
        cross.move(to: CGPoint(x: p.x - arm, y: p.y - arm))
        cross.addLine(to: CGPoint(x: p.x + arm, y: p.y + arm))
        cross.move(to: CGPoint(x: p.x + arm, y: p.y - arm))
        cross.addLine(to: CGPoint(x: p.x - arm, y: p.y + arm))
        context.stroke(cross, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        context.stroke(cross, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }

    /// The bow seen from behind the string, as an archer sees it: the riser out of focus beside
    /// the sight, the sight bar reaching across, and the blurred string. It rises into place as
    /// you draw.
    private func bow(_ context: inout GraphicsContext) {
        let progress = f.drawProgress
        let s = raisedSight
        // Far enough out that the riser never hides the wind flag on a near target.
        let riserX = s.x + side * w * 0.4
        let riserWidth = w * 0.1

        var layer = context
        layer.opacity = f.reduceMotion ? progress : 1
        // String: very close to the eye, so only a soft blur.
        var string = layer
        string.addFilter(.blur(radius: 2.2))
        string.stroke(line(CGPoint(x: s.x + side * w * 0.055, y: -20), CGPoint(x: s.x + side * w * 0.035, y: h + 20)),
                      with: .color(.white.opacity(0.32)), lineWidth: 2.2)
        // Riser with the grip below, slightly out of focus.
        var riser = layer
        riser.addFilter(.blur(radius: 3.5))
        var body = Path()
        let top = s.y - h * 0.95
        let bottom = s.y + h * 0.95
        let inner = riserX - side * riserWidth / 2
        let outer = riserX + side * riserWidth / 2
        body.move(to: CGPoint(x: inner, y: top))
        body.addLine(to: CGPoint(x: outer, y: top))
        body.addLine(to: CGPoint(x: outer, y: bottom))
        body.addLine(to: CGPoint(x: inner - side * riserWidth * 0.25, y: bottom))
        // The grip bulges towards the sight below the arrow shelf.
        body.addQuadCurve(to: CGPoint(x: inner, y: s.y + h * 0.16),
                          control: CGPoint(x: inner - side * riserWidth * 0.55, y: s.y + h * 0.45))
        // The sight window is cut away above the shelf.
        body.addQuadCurve(to: CGPoint(x: inner, y: top), control: CGPoint(x: inner + side * riserWidth * 0.35, y: s.y - h * 0.3))
        body.closeSubpath()
        riser.fill(body, with: .linearGradient(Gradient(colors: [Color(hex: 0x40434C), Color(hex: 0x1F2126)]),
                                               startPoint: CGPoint(x: inner, y: 0), endPoint: CGPoint(x: outer, y: 0)))
        // The sight bar, from the riser to the aperture.
        var bar = layer
        bar.addFilter(.blur(radius: 0.8))
        let barY = s.y - 3
        let barStart = CGPoint(x: inner + side * riserWidth * 0.25, y: barY)
        let barEnd = CGPoint(x: s.x + side * 17, y: barY)
        bar.stroke(line(barStart, barEnd), with: .color(Color(hex: 0x2A2C33)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        bar.stroke(line(CGPoint(x: barStart.x, y: barY - 1.5), CGPoint(x: barEnd.x, y: barY - 1.5)),
                   with: .color(.white.opacity(0.18)), lineWidth: 1)
    }

    private func reticle(_ context: inout GraphicsContext) {
        let progress = f.drawProgress
        let s = raisedSight
        let held = f.held ?? -1
        let tiring = held > Sway.steadyTime
        let ring: CGFloat = 15
        let aperture = Path(ellipseIn: CGRect(x: s.x - ring, y: s.y - ring, width: ring * 2, height: ring * 2))
        let ringColor = tiring ? Color(hex: 0xFF5A4E) : Color(hex: 0x15161A)
        context.stroke(aperture, with: .color(ringColor), lineWidth: 3.4)
        context.stroke(aperture, with: .color(.white.opacity(0.6)), lineWidth: 0.8)
        // The pin: a bright fibre-optic dot. Its centre is where the arrow goes in still air.
        let pin: CGFloat = 2.6
        context.fill(Path(ellipseIn: CGRect(x: s.x - pin - 0.8, y: s.y - pin - 0.8, width: (pin + 0.8) * 2, height: (pin + 0.8) * 2)),
                     with: .color(.black.opacity(0.7)))
        context.fill(Path(ellipseIn: CGRect(x: s.x - pin, y: s.y - pin, width: pin * 2, height: pin * 2)),
                     with: .color(Color(hex: 0x9DFF3C)))
        // Outer arc: closes as the bow comes to full draw, then shows the steady window running down.
        let outer: CGFloat = 22
        var arc = Path()
        let fraction: Double
        let arcColor: Color
        if progress < 1 {
            fraction = progress
            arcColor = .white
        } else if !tiring {
            fraction = max(0.02, 1 - held / Sway.steadyTime)
            arcColor = fraction > 0.3 ? .white : Theme.highlight
        } else {
            let pulse = f.reduceMotion ? 1 : 0.6 + 0.4 * sin(f.time * 9)
            fraction = 1
            arcColor = Color(hex: 0xFF5A4E).opacity(pulse)
        }
        arc.addArc(center: s, radius: outer, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
        context.stroke(arc, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
        context.stroke(arc, with: .color(arcColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }

    /// Where the sight will come up for the next arrow.
    private func restingSight(_ context: inout GraphicsContext) {
        let s = sightPoint
        let r: CGFloat = 12
        let ring = Path(ellipseIn: CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2))
        context.stroke(ring, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 3.2, dash: [4, 4]))
        context.stroke(ring, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.6, dash: [4, 4]))
        context.fill(Path(ellipseIn: CGRect(x: s.x - 2, y: s.y - 2, width: 4, height: 4)), with: .color(.white.opacity(0.9)))
    }
}
