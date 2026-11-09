import PlayKit
import RunnerEngine
import SwiftUI

/// Everything needed to draw one frame of the pier.
struct PierFrame {
    let size: CGSize
    let run: Run
    let scenery: Scenery
    /// Seconds, for what moves by itself: stars, glitter on the water, coins turning.
    let clock: Double
    let reduceMotion: Bool
    /// On the start line the runner stands still.
    let standing: Bool
    /// Seconds since the last coin was picked up, the shield broke and the run ended, while
    /// those are recent enough to show.
    let sinceCoin: Double?
    let sinceShieldBroke: Double?
    let sinceCrash: Double?
}

/// Draws the pier: sky and sea, the planks running to the horizon, bollards and lamps going
/// by, what stands on the course, coins and power-ups, and the runner, seen from behind.
struct PierPainter {
    let f: PierFrame
    private let cam: PierCamera
    /// The distance the course is drawn from.
    private let distance: Double

    init(f: PierFrame) {
        self.f = f
        cam = PierCamera(size: f.size, across: f.run.across)
        distance = f.run.drawnDistance
    }

    private var run: Run { f.run }
    private var scenery: Scenery { f.scenery }
    private var w: Double { cam.width }
    private var h: Double { cam.height }
    /// Where the runner is across the pier, in metres.
    private var runnerX: Double { PierCamera.x(ofLane: run.across) }

    /// One thing standing on the pier, at its depth from the camera.
    private enum Item {
        case furniture(index: Int, z: Double)
        case obstacle(Obstacle, z: Double)
        case coin(Coin, z: Double)
        case pickup(Pickup, z: Double)
        case runner

        var depth: Double {
            switch self {
            case .furniture(_, let z), .obstacle(_, let z), .coin(_, let z), .pickup(_, let z): return z
            case .runner: return PierCamera.back
            }
        }
    }

    func paint(_ context: inout GraphicsContext) {
        var context = context
        if let since = f.sinceCrash, !f.reduceMotion, since < 0.4 {
            // The view shakes when the runner hits something.
            let strength = 7 * (1 - since / 0.4)
            context.translateBy(x: strength * sin(since * 70), y: strength * cos(since * 55))
        }
        sky(&context)
        sea(&context)
        deck(&context)
        for item in items() {
            switch item {
            case .furniture(let index, let z): furniture(&context, index: index, z: z)
            case .obstacle(let obstacle, let z): draw(obstacle, z: z, in: &context)
            case .coin(let coin, let z): draw(coin, z: z, in: &context)
            case .pickup(let pickup, let z): draw(pickup, z: z, in: &context)
            case .runner: runner(&context)
            }
        }
        if !f.reduceMotion { speedLines(&context) }
        // The bottom edge falls into shade, so the toolbar below does not cut the planks off hard.
        context.fill(Path.box(x: 0, y: h * 0.78, width: w, height: h * 0.22),
                     with: .linearGradient(Gradient(colors: [.black.opacity(0), .black.opacity(0.22)]),
                                           startPoint: CGPoint(x: 0, y: h * 0.78), endPoint: CGPoint(x: 0, y: h)))
    }

    /// Everything on the pier, the farthest first.
    private func items() -> [Item] {
        var items: [Item] = [.runner]
        let first = Int(((distance - PierCamera.back) / Self.bollardSpacing).rounded(.up))
        for index in first...(first + Int(Self.sight / Self.bollardSpacing)) {
            let z = Double(index) * Self.bollardSpacing - distance + PierCamera.back
            if z > 1.2 { items.append(.furniture(index: index, z: z)) }
        }
        for obstacle in run.obstacles where obstacle.isOnCourse(at: run.time) {
            let z = depth(of: obstacle.nearSide(at: run.time))
            if z + obstacle.length > PierCamera.near, z < Self.sight { items.append(.obstacle(obstacle, z: z)) }
        }
        for coin in run.coins {
            let z = depth(of: coin.position)
            if z > PierCamera.near, z < Self.sight { items.append(.coin(coin, z: z)) }
        }
        for pickup in run.pickups {
            let z = depth(of: pickup.position)
            if z > PierCamera.near, z < Self.sight { items.append(.pickup(pickup, z: z)) }
        }
        return items.sorted { $0.depth > $1.depth }
    }

    /// Metres in front of the camera of something `position` metres down the course.
    private func depth(of position: Double) -> Double {
        position - distance + PierCamera.back
    }

    /// How far down the pier things are drawn.
    private static let sight = 120.0
    private static let bollardSpacing = 6.0

    /// 1 for something near, falling to 0 over the last stretch before `sight`.
    private func haze(_ z: Double) -> Double {
        min(1, max(0, (Self.sight - z) / 35))
    }

    /// What the runner has passed fades out at once, before it can loom over the camera.
    private func passed(_ farSide: Double) -> Double {
        min(1, max(0, farSide - (PierCamera.back - 1)))
    }

    // MARK: Sky and sea

    private func sky(_ context: inout GraphicsContext) {
        let horizon = cam.horizon
        context.fill(Path.box(x: -10, y: -10, width: w + 20, height: horizon + 12),
                     with: .linearGradient(Gradient(stops: scenery.sky), startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
        var stars = SeededGenerator(seed: 77)
        for index in 0..<scenery.starCount {
            let x = stars.nextUnit() * w
            let y = stars.nextUnit() * horizon * 0.7
            let size = 0.6 + stars.nextUnit() * 1.2
            let twinkle = f.reduceMotion ? 1 : 0.6 + 0.4 * sin(f.clock * (1 + Double(index % 5) * 0.4) + Double(index))
            context.fill(Path.disc(x: x, y: y, r: size / 2), with: .color(scenery.star.opacity(twinkle)))
        }

        // The sun on the horizon, or the moon above it, a little to the right. Nothing of
        // either shows below the horizon.
        var above = context
        above.clip(to: Path.box(x: -10, y: -10, width: w + 20, height: horizon + 10))
        let centre = Spot(x: w * 0.64 - cam.x * 3, y: horizon - horizon * scenery.discHeight)
        let radius = w * scenery.discRadius
        above.fill(Path.disc(x: centre.x, y: centre.y, r: radius * 4.5),
                   with: .radialGradient(Gradient(colors: [scenery.discGlow, scenery.discGlow.opacity(0)]),
                                         center: centre.point, startRadius: radius * 0.6, endRadius: radius * 4.5))
        let disc = Path.disc(x: centre.x, y: centre.y, r: radius)
        above.fill(disc, with: .color(scenery.disc))
        if scenery.isNight {
            // A crescent: the dark side covers most of the disc.
            var moon = above
            moon.clip(to: disc)
            moon.fill(Path.disc(x: centre.x - radius * 0.45, y: centre.y - radius * 0.2, r: radius * 0.95),
                      with: .color(scenery.discShade))
        }

        // Long thin clouds, drifting.
        let drift = f.reduceMotion ? 0 : f.clock * 1.2
        let clouds: [(x: Double, y: Double, width: Double)] = [(0.12, 0.42, 0.34), (0.55, 0.3, 0.26), (0.8, 0.62, 0.3), (0.3, 0.72, 0.22)]
        for (index, cloud) in clouds.enumerated() {
            let travelled = cloud.x * w + drift * (1 + Double(index) * 0.3)
            let x = travelled.truncatingRemainder(dividingBy: w * 1.4) - w * 0.2
            let y = horizon * cloud.y
            let width = w * cloud.width
            above.fill(Path.box(x: x, y: y, width: width, height: horizon * 0.035, radius: horizon * 0.02), with: .color(scenery.cloud))
            above.fill(Path.box(x: x + width * 0.2, y: y + horizon * 0.03, width: width * 0.55, height: horizon * 0.028, radius: horizon * 0.014),
                       with: .color(scenery.cloud))
        }

        // A low shore on the right, and a headland with a lighthouse on the left.
        let shift = -cam.x * 6
        var shore = Path()
        shore.move(to: CGPoint(x: w * 0.5 + shift, y: horizon + 1))
        shore.addQuadCurve(to: CGPoint(x: w * 1.1 + shift, y: horizon * 0.955), control: CGPoint(x: w * 0.78 + shift, y: horizon * 0.93))
        shore.addLine(to: CGPoint(x: w * 1.1 + shift, y: horizon + 1))
        shore.closeSubpath()
        context.fill(shore, with: .color(scenery.farShore))
        var headland = Path()
        headland.move(to: CGPoint(x: -w * 0.1 + shift, y: horizon + 1))
        headland.addLine(to: CGPoint(x: -w * 0.1 + shift, y: horizon * 0.9))
        headland.addQuadCurve(to: CGPoint(x: w * 0.22 + shift, y: horizon * 0.94), control: CGPoint(x: w * 0.12 + shift, y: horizon * 0.85))
        headland.addQuadCurve(to: CGPoint(x: w * 0.4 + shift, y: horizon + 1), control: CGPoint(x: w * 0.3 + shift, y: horizon * 0.99))
        headland.closeSubpath()
        context.fill(headland, with: .color(scenery.headland))

        let foot = Spot(x: w * 0.13 + shift, y: horizon * 0.87)
        let tall = horizon * 0.16
        let wide = w * 0.016
        context.fill(Path.polygon([Spot(x: foot.x - wide, y: foot.y), Spot(x: foot.x + wide, y: foot.y),
                                   Spot(x: foot.x + wide * 0.65, y: foot.y - tall), Spot(x: foot.x - wide * 0.65, y: foot.y - tall)]),
                     with: .color(scenery.lighthouse))
        context.fill(Path.box(x: foot.x - wide * 0.8, y: foot.y - tall * 0.62, width: wide * 1.6, height: tall * 0.16), with: .color(scenery.headland))
        context.fill(Path.box(x: foot.x - wide * 0.9, y: foot.y - tall * 1.16, width: wide * 1.8, height: tall * 0.16), with: .color(scenery.headland))
        let blink = f.reduceMotion ? 1 : 0.5 + 0.5 * sin(f.clock * 1.6)
        let light = Spot(x: foot.x, y: foot.y - tall * 1.08)
        let lightColor = Color(hex: 0xFFF0BE)
        context.fill(Path.disc(x: light.x, y: light.y, r: tall * 0.9),
                     with: .radialGradient(Gradient(colors: [lightColor.opacity(0.9 * blink), lightColor.opacity(0)]),
                                           center: light.point, startRadius: 0, endRadius: tall * 0.9))
    }

    private func sea(_ context: inout GraphicsContext) {
        let horizon = cam.horizon
        context.fill(Path.box(x: -10, y: horizon, width: w + 20, height: h - horizon + 10),
                     with: .linearGradient(Gradient(stops: scenery.sea), startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))
        // Glitter under the sun or moon: short dashes, wider towards the viewer.
        let below = w * 0.64 - cam.x * 3
        var random = SeededGenerator(seed: 5)
        for index in 0..<26 {
            let u = random.nextUnit()
            let y = horizon + 2 + u * u * (h - horizon) * 0.55
            let spread = 6 + u * w * 0.16
            let width = 4 + u * 22
            let x = below + (random.nextUnit() - 0.5) * 2 * spread
            let rate = 1.2 + random.nextUnit() * 2
            let shimmer = f.reduceMotion ? 0.6 : 0.35 + 0.65 * abs(sin(f.clock * rate + Double(index) * 1.7))
            context.fill(Path.box(x: x - width / 2, y: y, width: width, height: 1.2 + u * 1.6, radius: 1),
                         with: .color(scenery.glitter.opacity(shimmer * (1 - u * 0.6))))
        }
    }

    // MARK: The pier

    /// A strip of planks between two distances from the middle, from `z0` out to `z1`.
    private func strip(_ x0: Double, _ x1: Double, from z0: Double, to z1: Double) -> Path {
        Path.polygon([cam.point(x0, 0, z0), cam.point(x1, 0, z0), cam.point(x1, 0, z1), cam.point(x0, 0, z1)])
    }

    private func deck(_ context: inout GraphicsContext) {
        let half = PierCamera.halfWidth
        let near = 1.6
        let far = 400.0
        let kerb = 0.22
        context.fill(strip(-half, half, from: near, to: far),
                     with: .linearGradient(Gradient(stops: [.init(color: scenery.deckFar, location: 0), .init(color: scenery.deck, location: 0.22),
                                                            .init(color: scenery.deck, location: 1)]),
                                           startPoint: CGPoint(x: 0, y: cam.horizon), endPoint: CGPoint(x: 0, y: h)))
        context.fill(strip(-half, -half + kerb, from: near, to: far), with: .color(scenery.kerb))
        context.fill(strip(half - kerb, half, from: near, to: far), with: .color(scenery.kerb))

        // The gaps between the planks, coming towards the runner.
        let plank = 1.25
        var z = plank - distance.truncatingRemainder(dividingBy: plank) + near - plank
        while z < 70 {
            if z >= near {
                context.stroke(Path.line(cam.point(-half + kerb, 0, z), cam.point(half - kerb, 0, z)),
                               with: .color(scenery.plankLine.opacity(min(1, (70 - z) / 30))),
                               lineWidth: max(0.5, cam.scale(z) * 0.035))
            }
            z += plank
        }

        // The lanes: two pale lines painted in dashes.
        let dash = 5.0
        for line in 1..<Body.lanes {
            let x = PierCamera.x(ofLane: Double(line) - 0.5)
            var start = dash - distance.truncatingRemainder(dividingBy: dash) + near - dash
            while start < 90 {
                let end = start + dash * 0.55
                if end > near {
                    context.fill(strip(x - 0.035, x + 0.035, from: max(near, start), to: end), with: .color(scenery.laneLine))
                }
                start += dash
            }
        }
    }

    /// A box standing on the planks: its top and the side the camera can see, then its front.
    private func box(_ context: inout GraphicsContext, x x0: Double, _ x1: Double, y y0: Double, _ y1: Double,
                     z near: Double, _ far: Double, front: Color, side: Color, top: Color) {
        let z0 = max(near, PierCamera.near)
        let z1 = max(far, z0 + 0.01)
        if cam.x < x0 {
            context.fill(Path.polygon([cam.point(x0, y0, z0), cam.point(x0, y1, z0), cam.point(x0, y1, z1), cam.point(x0, y0, z1)]), with: .color(side))
        }
        if cam.x > x1 {
            context.fill(Path.polygon([cam.point(x1, y0, z0), cam.point(x1, y1, z0), cam.point(x1, y1, z1), cam.point(x1, y0, z1)]), with: .color(side))
        }
        if y1 < PierCamera.height {
            context.fill(Path.polygon([cam.point(x0, y1, z0), cam.point(x1, y1, z0), cam.point(x1, y1, z1), cam.point(x0, y1, z1)]), with: .color(top))
        }
        context.fill(Path.polygon([cam.point(x0, y0, z0), cam.point(x1, y0, z0), cam.point(x1, y1, z0), cam.point(x0, y1, z0)]), with: .color(front))
    }

    /// A bollard on each edge with a rope sagging to the next, and a lamp at every fourth.
    private func furniture(_ context: inout GraphicsContext, index: Int, z: Double) {
        var layer = context
        layer.opacity = haze(z)
        let scale = cam.scale(z)
        for side in [-1.0, 1.0] {
            let x = side * (PierCamera.halfWidth + 0.12)
            let top = cam.point(x, 0.8, z)
            let next = cam.point(x, 0.8, z + Self.bollardSpacing)
            let sag = cam.point(x, 0.1, z + Self.bollardSpacing / 2)
            var rope = Path()
            rope.move(to: top.point)
            rope.addQuadCurve(to: next.point, control: sag.point)
            layer.stroke(rope, with: .color(scenery.rope), style: StrokeStyle(lineWidth: max(0.6, scale * 0.035), lineCap: .round))
            box(&layer, x: x - 0.1, x + 0.1, y: 0, 0.9, z: z, z + 0.2, front: scenery.post, side: scenery.postSide, top: scenery.postTop)
            let cap = cam.point(x, 0.9, z)
            layer.fill(Path.box(x: cap.x - scale * 0.13, y: cap.y - scale * 0.07, width: scale * 0.26, height: scale * 0.09, radius: scale * 0.03),
                       with: .color(scenery.postCap))
            guard index % 4 == 0 else { continue }
            let foot = cam.point(x + side * 0.05, 0, z)
            let head = cam.point(x + side * 0.05, 3.4, z)
            let arm = cam.point(x - side * 0.5, 3.4, z)
            var post = Path()
            post.move(to: foot.point)
            post.addLine(to: head.point)
            post.addLine(to: arm.point)
            layer.stroke(post, with: .color(scenery.lampPost), style: StrokeStyle(lineWidth: max(1, scale * 0.09), lineCap: .round, lineJoin: .round))
            layer.fill(Path.disc(x: arm.x, y: arm.y, r: scale * 1.1),
                       with: .radialGradient(Gradient(colors: [scenery.lampGlow, scenery.lampGlow.opacity(0)]),
                                             center: arm.point, startRadius: 0, endRadius: scale * 1.1))
            layer.fill(Path.disc(x: arm.x, y: arm.y + scale * 0.05, r: scale * 0.13), with: .color(scenery.lamp))
        }
    }

    // MARK: On the course

    /// The dark patch under something standing on the planks.
    private func groundShadow(_ context: inout GraphicsContext, x: Double, z: Double, halfWidth: Double, depth: Double) {
        let middle = z + depth / 2
        let centre = cam.point(x, 0, middle)
        let scale = cam.scale(middle)
        context.fill(Path.oval(x: centre.x, y: centre.y, rx: halfWidth * scale, ry: max(1, halfWidth * scale * 0.22 + depth * scale * 0.12)),
                     with: .color(scenery.shadow))
    }

    /// A board across a lane, painted in blocks of two colours.
    private func stripedBoard(_ context: inout GraphicsContext, x x0: Double, _ x1: Double, y y0: Double, _ y1: Double, z: Double,
                              colors: (Color, Color), blocks: Int) {
        let topLeft = cam.point(x0, y1, z)
        let bottomRight = cam.point(x1, y0, z)
        let width = bottomRight.x - topLeft.x
        let height = bottomRight.y - topLeft.y
        var board = context
        board.clip(to: Path.box(x: topLeft.x, y: topLeft.y, width: width, height: height, radius: height * 0.2))
        let block = width / Double(blocks)
        for index in 0..<blocks {
            board.fill(Path.box(x: topLeft.x + Double(index) * block - 0.5, y: topLeft.y, width: block + 1, height: height),
                       with: .color(index % 2 == 0 ? colors.0 : colors.1))
        }
        board.fill(Path.box(x: topLeft.x, y: topLeft.y + height * 0.72, width: width, height: height * 0.28), with: .color(.black.opacity(0.12)))
    }

    private func crate(_ context: inout GraphicsContext, x x0: Double, _ x1: Double, y y0: Double, _ y1: Double, z near: Double, _ far: Double) {
        box(&context, x: x0, x1, y: y0, y1, z: near, far, front: PierStyle.crate, side: PierStyle.crateSide, top: PierStyle.crateTop)
        let z = max(near, PierCamera.near)
        let scale = cam.scale(z)
        let topLeft = cam.point(x0, y1, z)
        let bottomRight = cam.point(x1, y0, z)
        let inset = scale * 0.035
        let frame = CGRect(x: topLeft.x + inset, y: topLeft.y + inset,
                           width: bottomRight.x - topLeft.x - 2 * inset, height: bottomRight.y - topLeft.y - 2 * inset)
        context.stroke(Path(frame), with: .color(PierStyle.crateFrame), lineWidth: max(0.8, scale * 0.07))
        var brace = Path()
        brace.move(to: CGPoint(x: frame.minX, y: frame.minY))
        brace.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
        context.stroke(brace, with: .color(PierStyle.crateFrame), lineWidth: max(0.6, scale * 0.05))
    }

    private func draw(_ obstacle: Obstacle, z: Double, in context: inout GraphicsContext) {
        let visible = haze(z) * passed(z + obstacle.length)
        guard visible > 0 else { return }
        var layer = context
        layer.opacity = visible
        let x = PierCamera.x(ofLane: Double(obstacle.lane))
        let near = max(z, PierCamera.near)
        let scale = cam.scale(near)
        switch obstacle.kind {
        case .barrier:
            groundShadow(&layer, x: x, z: near, halfWidth: 0.72, depth: 0.3)
            for side in [-1.0, 1.0] {
                box(&layer, x: x + side * 0.6 - 0.05, x + side * 0.6 + 0.05, y: 0, 0.6, z: near, near + 0.1,
                    front: Color(hex: 0xE8E4EE), side: Color(hex: 0xB9B3C6), top: .white)
            }
            stripedBoard(&layer, x: x - 0.66, x + 0.66, y: 0.36, 0.66, z: near, colors: (PierStyle.warningRed, PierStyle.cream), blocks: 6)
        case .beam:
            groundShadow(&layer, x: x, z: near, halfWidth: 0.72, depth: 0.3)
            for side in [-1.0, 1.0] {
                box(&layer, x: x + side * 0.66 - 0.06, x + side * 0.66 + 0.06, y: 0, 1.75, z: near, near + 0.12,
                    front: PierStyle.beamPost, side: PierStyle.beamPostSide, top: PierStyle.beamPostTop)
            }
            stripedBoard(&layer, x: x - 0.74, x + 0.74, y: 1.05, 1.5, z: near, colors: (Theme.highlight, PierStyle.beamPostSide), blocks: 7)
            // A lamp hanging from the bar, at head height.
            let lamp = cam.point(x, 0.98, near)
            layer.fill(Path.disc(x: lamp.x, y: lamp.y, r: scale * 0.06), with: .color(scenery.lamp))
        case .stack:
            groundShadow(&layer, x: x, z: near, halfWidth: 0.74, depth: min(obstacle.length, 3))
            if obstacle.length > 5 {
                container(&layer, obstacle, x: x, z: z)
            } else {
                crate(&layer, x: x - 0.64, x + 0.64, y: 0, 1.28, z: near, z + obstacle.length)
                crate(&layer, x: x - 0.5, x + 0.56, y: 1.28, 2.3, z: near + 0.1, z + obstacle.length - 0.15)
            }
        case .barrel:
            groundShadow(&layer, x: x, z: near, halfWidth: 0.6, depth: 0.6)
            barrel(&layer, x: x, z: near)
        }
    }

    /// A long stack: a shipping container, with ribs and a door bar on its end.
    private func container(_ context: inout GraphicsContext, _ obstacle: Obstacle, x: Double, z: Double) {
        let paint = PierStyle.containers[Int(obstacle.position) % PierStyle.containers.count]
        let near = max(z, PierCamera.near)
        let scale = cam.scale(near)
        let far = z + obstacle.length
        box(&context, x: x - 0.66, x + 0.66, y: 0, 2.5, z: near, far, front: paint.front, side: paint.side, top: paint.top)
        // Ribs down the side the camera sees, so its length reads as it goes by.
        if let side = [x - 0.66, x + 0.66].first(where: { ($0 < x) == (cam.x < $0) }) {
            var ribZ = z + 1.1
            while ribZ < far {
                if ribZ > near {
                    context.stroke(Path.line(cam.point(side, 0.12, ribZ), cam.point(side, 2.38, ribZ)),
                                   with: .color(.black.opacity(0.16)), lineWidth: max(0.6, cam.scale(ribZ) * 0.03))
                }
                ribZ += 1.1
            }
        }
        for rib in 1..<6 {
            let ribX = x - 0.66 + Double(rib) * 1.32 / 6
            context.stroke(Path.line(cam.point(ribX, 0.12, near), cam.point(ribX, 2.38, near)),
                           with: .color(.black.opacity(0.18)), lineWidth: max(0.6, scale * 0.03))
        }
        let bar = cam.point(x - 0.5, 1.25, near)
        context.fill(Path.box(x: bar.x, y: bar.y, width: scale * 0.34, height: max(1, scale * 0.06)), with: .color(.white.opacity(0.75)))
    }

    /// A barrel on its side, rolling: the staves come over the top.
    private func barrel(_ context: inout GraphicsContext, x: Double, z: Double) {
        let scale = cam.scale(z)
        let corner = cam.point(x - 0.52, 0.72, z)
        let width = scale * 1.04
        let height = scale * 0.72
        let body = Path.box(x: corner.x, y: corner.y, width: width, height: height, radius: height * 0.42)
        context.fill(body, with: .color(PierStyle.barrel))
        var staves = context
        staves.clip(to: body)
        let spin = f.reduceMotion ? 0.3 : (f.clock * 2.2).truncatingRemainder(dividingBy: 1)
        for stave in -1..<4 {
            let y = corner.y + height * (Double(stave) + spin) / 3
            staves.stroke(Path.line(Spot(x: corner.x, y: y), Spot(x: corner.x + width, y: y)),
                          with: .color(Color(hex: 0x3C1905, opacity: 0.45)), lineWidth: max(0.6, scale * 0.03))
        }
        staves.fill(Path.box(x: corner.x, y: corner.y, width: width, height: height * 0.3), with: .color(Color(hex: 0xFFDCAA, opacity: 0.18)))
        staves.fill(Path.box(x: corner.x + width * 0.14, y: corner.y, width: width * 0.08, height: height), with: .color(PierStyle.hoop))
        staves.fill(Path.box(x: corner.x + width * 0.78, y: corner.y, width: width * 0.08, height: height), with: .color(PierStyle.hoop))
    }

    private func draw(_ coin: Coin, z: Double, in context: inout GraphicsContext) {
        var x = PierCamera.x(ofLane: Double(coin.lane))
        var y = coin.height
        if run.hasMagnet {
            // With the magnet on, coins swing over to the runner as they come near.
            let pull = min(1, max(0, (9 - (z - PierCamera.back)) / 7))
            x += (runnerX - x) * pull * pull
            y += (run.height + 1 - y) * pull * pull
        }
        let centre = cam.point(x, y, z)
        let radius = max(1.2, cam.scale(z) * 0.21)
        let turn = f.reduceMotion ? 1 : abs(cos(f.clock * 3.2 + coin.position * 0.9))
        let across = radius * (0.22 + 0.78 * turn)
        var layer = context
        layer.opacity = haze(z) * passed(z)
        layer.fill(Path.oval(x: centre.x, y: centre.y, rx: across, ry: radius), with: .color(PierStyle.coinEdge))
        layer.fill(Path.oval(x: centre.x, y: centre.y - radius * 0.06, rx: across * 0.82, ry: radius * 0.84), with: .color(PierStyle.coin))
        if radius > 3 {
            layer.fill(Path.oval(x: centre.x - across * 0.3, y: centre.y - radius * 0.35, rx: across * 0.22, ry: radius * 0.2),
                       with: .color(.white.opacity(0.75)))
        }
    }

    private func draw(_ pickup: Pickup, z: Double, in context: inout GraphicsContext) {
        let bob = f.reduceMotion ? 0 : 0.08 * sin(f.clock * 3 + pickup.position)
        let centre = cam.point(PierCamera.x(ofLane: Double(pickup.lane)), Pickup.height + bob, z)
        let radius = max(2, cam.scale(z) * 0.42)
        let color = pickup.kind == .magnet ? PierStyle.magnet : PierStyle.shield
        var layer = context
        layer.opacity = haze(z) * passed(z)
        // A shaft of light above it, so it is seen from far off.
        layer.fill(Path.box(x: centre.x - radius * 0.5, y: centre.y - radius * 5, width: radius, height: radius * 5),
                   with: .linearGradient(Gradient(colors: [color.opacity(0), color.opacity(0.35)]),
                                         startPoint: CGPoint(x: centre.x, y: centre.y - radius * 5), endPoint: centre.point))
        layer.fill(Path.disc(x: centre.x, y: centre.y, r: radius * 1.7),
                   with: .radialGradient(Gradient(colors: [color.opacity(0.55), color.opacity(0)]),
                                         center: centre.point, startRadius: radius * 0.3, endRadius: radius * 1.7))
        layer.fill(Path.disc(x: centre.x, y: centre.y, r: radius), with: .color(PierStyle.cream))
        layer.stroke(Path.disc(x: centre.x, y: centre.y, r: radius * 0.93), with: .color(color), lineWidth: max(1, radius * 0.14))
        switch pickup.kind {
        case .magnet: PowerUpShape.magnet(in: &layer, x: centre.x, y: centre.y, size: radius * 0.56)
        case .shield: PowerUpShape.shield(in: &layer, x: centre.x, y: centre.y, size: radius * 0.6)
        }
    }

    // MARK: The runner

    private func runner(_ context: inout GraphicsContext) {
        let scale = cam.scale(PierCamera.back)
        let ground = cam.point(runnerX, 0, PierCamera.back)
        let crashed = run.status == .crashed
        let sliding = run.isTucked && !run.isAirborne

        // The shadow shrinks as the feet leave the planks.
        let lift = min(1, run.height / 1.3)
        context.fill(Path.oval(x: ground.x, y: ground.y, rx: scale * 0.42 * (1 - 0.35 * lift), ry: scale * 0.11 * (1 - 0.35 * lift)),
                     with: .color(scenery.shadow))

        let stride = distance * 2 * Double.pi / 2.5
        let moving = !f.standing && !crashed
        let bob = moving && !run.isAirborne && !sliding && !f.reduceMotion ? 0.045 * abs(sin(stride)) : 0
        // The figure is drawn in metres from the middle of the feet, y up.
        var figure = context
        figure.translateBy(x: ground.x, y: ground.y - scale * (run.height + bob))
        if crashed {
            // Knocked flat on the planks.
            figure.rotate(by: .radians(-1.25))
            figure.translateBy(x: -scale * 0.1, y: scale * 0.15)
        } else {
            // Leaning into a change of lane.
            figure.rotate(by: .radians(min(1, max(-1, Double(run.lane) - run.across)) * 0.22))
        }
        figure.scaleBy(x: scale, y: -scale)
        if sliding {
            RunnerFigure.sliding(in: &figure)
        } else {
            RunnerFigure.upright(in: &figure, swing: moving ? sin(stride) : 0, tucked: run.isAirborne || run.isTucked,
                                 armsUp: run.isAirborne && !run.isTucked,
                                 scarfWave: moving && !f.reduceMotion ? sin(f.clock * 9) * 0.05 : 0)
        }

        if sliding && !f.reduceMotion {
            // Dust kicked up behind the slide.
            for puff in 0..<3 {
                let age = (f.clock * 3 + Double(puff) / 3).truncatingRemainder(dividingBy: 1)
                context.fill(Path.disc(x: ground.x + Double(puff - 1) * scale * 0.3, y: ground.y + scale * (0.05 + 0.25 * age), r: scale * (0.06 + 0.1 * age)),
                             with: .color(Color(hex: 0xFFF0DC, opacity: 0.35 * (1 - age))))
            }
        }
        if crashed && !f.reduceMotion {
            // Seeing stars.
            for index in 0..<3 {
                let angle = f.clock * 4 + Double(index) * 2.1
                context.fill(PowerUpShape.star(x: ground.x - scale * 0.9 + cos(angle) * scale * 0.35,
                                               y: ground.y - scale * 0.75 + sin(angle) * scale * 0.12, radius: scale * 0.09),
                             with: .color(Color(hex: 0xFFE27A)))
            }
        }
        aura(&context, ground: ground, scale: scale, sliding: sliding)
    }

    /// What surrounds the runner: the shield's bubble, the magnet's pull, and the flashes of a
    /// coin picked up and of the shield breaking.
    private func aura(_ context: inout GraphicsContext, ground: Spot, scale: Double, sliding: Bool) {
        let middle = Spot(x: ground.x, y: ground.y - scale * (run.height + (sliding ? 0.35 : 0.9)))
        if run.hasShield {
            let radius = scale * (sliding ? 0.7 : 1.08)
            let glass = PierStyle.shield
            context.fill(Path.disc(x: middle.x, y: middle.y, r: radius),
                         with: .radialGradient(Gradient(stops: [.init(color: glass.opacity(0), location: 0), .init(color: glass.opacity(0.28), location: 0.7),
                                                                .init(color: Color(hex: 0xB4DCFF, opacity: 0.75), location: 1)]),
                                               center: middle.point, startRadius: radius * 0.55, endRadius: radius))
        }
        if run.hasMagnet {
            for ring in 0..<2 {
                let age = f.reduceMotion ? 0.3 + Double(ring) * 0.4 : (f.clock * 1.3 + Double(ring) * 0.5).truncatingRemainder(dividingBy: 1)
                context.stroke(Path.disc(x: middle.x, y: middle.y, r: scale * (1.5 - 0.9 * age)),
                               with: .color(PierStyle.magnet.opacity(0.55 * (1 - age))), lineWidth: 2)
            }
        }
        if let since = f.sinceCoin, since < 0.25 {
            let age = since / 0.25
            context.stroke(Path.disc(x: middle.x, y: middle.y, r: scale * (0.5 + 0.5 * age)),
                           with: .color(PierStyle.coin.opacity(0.7 * (1 - age))), lineWidth: 2.5)
        }
        if let since = f.sinceShieldBroke, since < 0.5 {
            let age = since / 0.5
            context.stroke(Path.disc(x: middle.x, y: middle.y, r: scale * (1 + 1.2 * age)),
                           with: .color(Color.white.opacity(0.9 * (1 - age))), lineWidth: 4 * (1 - age) + 1)
        }
    }

    /// Streaks at the edges of the view once the run is fast.
    private func speedLines(_ context: inout GraphicsContext) {
        let rush = min(1, max(0, (run.speed - 13) / 8))
        guard rush > 0, !f.standing, run.status == .running else { return }
        var random = SeededGenerator(seed: 11)
        for index in 0..<14 {
            let side = index % 2 == 0 ? -1.0 : 1.0
            let y = cam.horizon + random.nextUnit() * (h - cam.horizon) * 0.8
            let age = (f.clock * (1.5 + random.nextUnit()) + random.nextUnit()).truncatingRemainder(dividingBy: 1)
            let x = w / 2 + side * w * (0.36 + 0.16 * random.nextUnit() + age * 0.1)
            let length = (10 + 26 * random.nextUnit()) * rush
            let outward = (x - w / 2) / w
            let downward = (y - cam.horizon) / h
            context.stroke(Path.line(Spot(x: x, y: y), Spot(x: x + outward * length, y: y + downward * length * 1.6)),
                           with: .color(.white.opacity(0.25 * rush * (1 - age))), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
    }
}

/// The runner, seen from behind: a yellow hoodie, a rucksack, a bobble hat and a scarf.
/// Drawn in metres from the middle of the feet, y up.
enum RunnerFigure {
    private static func limb(_ context: inout GraphicsContext, _ points: [(Double, Double)], width: Double, color: Color) {
        var path = Path()
        for (index, point) in points.enumerated() {
            let spot = CGPoint(x: point.0, y: point.1)
            if index == 0 { path.move(to: spot) } else { path.addLine(to: spot) }
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private static func head(_ context: inout GraphicsContext, y: Double) {
        context.fill(Path.disc(x: 0, y: y, r: 0.17), with: .color(PierStyle.skin))
        // The hat covers the top half of the head.
        var crown = context
        crown.clip(to: Path.box(x: -0.2, y: y + 0.02, width: 0.4, height: 0.2))
        crown.fill(Path.disc(x: 0, y: y + 0.02, r: 0.185), with: .color(PierStyle.hat))
        context.fill(Path.box(x: -0.19, y: y - 0.03, width: 0.38, height: 0.08, radius: 0.03), with: .color(PierStyle.hatBrim))
        context.fill(Path.disc(x: 0, y: y + 0.22, r: 0.055), with: .color(PierStyle.cream))
    }

    /// Running, standing or in the air.
    /// - Parameters:
    ///   - swing: -1...1 through the stride (0 standing): the legs and arms follow it.
    ///   - tucked: the knees are drawn up, as in a jump.
    static func upright(in context: inout GraphicsContext, swing: Double, tucked: Bool, armsUp: Bool, scarfWave: Double) {
        // From behind, a stride shows as each foot lifting in turn.
        for side in [-1.0, 1.0] {
            let lift = max(0, side < 0 ? swing : -swing)
            let foot: (Double, Double)
            let knee: (Double, Double)
            if tucked {
                foot = (side * 0.17, side > 0 ? 0.38 : 0.3)
                knee = (side * 0.24, 0.62)
            } else {
                foot = (side * 0.13, 0.05 + lift * 0.3)
                knee = (side * (0.15 + lift * 0.05), 0.46 + lift * 0.16)
            }
            limb(&context, [(side * 0.12, 0.86), knee, foot], width: 0.16, color: PierStyle.trousers)
            // The sole shows when the foot is up.
            let raised = tucked ? 1 : lift
            context.fill(Path.box(x: foot.0 - 0.1, y: foot.1 - 0.06, width: 0.2, height: 0.12 + raised * 0.06, radius: 0.05),
                         with: .color(raised > 0.25 ? PierStyle.sole : PierStyle.cream))
        }
        // The arms swing against the legs, and go up in a jump.
        for side in [-1.0, 1.0] {
            let reach = side < 0 ? -swing : swing
            let elbow: (Double, Double) = armsUp ? (side * 0.42, 1.5) : (side * 0.36, 1.1 + reach * 0.05)
            let hand: (Double, Double) = armsUp ? (side * 0.5, 1.78) : (side * 0.33, 0.98 + reach * 0.2)
            limb(&context, [(side * 0.25, 1.36), elbow, hand], width: 0.125, color: PierStyle.hoodie)
            context.fill(Path.disc(x: hand.0, y: hand.1, r: 0.065), with: .color(PierStyle.skin))
        }
        context.fill(Path.box(x: -0.25, y: 0.78, width: 0.5, height: 0.66, radius: 0.16), with: .color(PierStyle.hoodie))
        context.fill(Path.box(x: -0.25, y: 0.78, width: 0.5, height: 0.1, radius: 0.05), with: .color(PierStyle.hoodieHem))
        context.fill(Path.box(x: -0.18, y: 0.9, width: 0.36, height: 0.44, radius: 0.1), with: .color(PierStyle.rucksack))
        context.fill(Path.box(x: -0.18, y: 1.16, width: 0.36, height: 0.18, radius: 0.09), with: .color(PierStyle.rucksackFlap))
        context.fill(Path.box(x: -0.03, y: 1.12, width: 0.06, height: 0.09, radius: 0.02), with: .color(PierStyle.cream))
        // The scarf: round the neck, and streaming out to one side.
        limb(&context, [(-0.17, 1.44), (0.17, 1.44)], width: 0.1, color: PierStyle.scarf)
        var tail = Path()
        tail.move(to: CGPoint(x: 0.14, y: 1.43))
        tail.addQuadCurve(to: CGPoint(x: 0.5, y: 1.3 - scarfWave), control: CGPoint(x: 0.34, y: 1.36 + scarfWave))
        context.stroke(tail, with: .color(PierStyle.scarf), style: StrokeStyle(lineWidth: 0.085, lineCap: .round))
        head(&context, y: 1.62)
    }

    /// Sliding: low on the planks, feet first.
    static func sliding(in context: inout GraphicsContext) {
        limb(&context, [(-0.1, 0.16), (-0.34, 0.5)], width: 0.17, color: PierStyle.trousers)
        limb(&context, [(0.12, 0.16), (0.3, 0.44)], width: 0.17, color: PierStyle.trousers)
        context.fill(Path.box(x: -0.47, y: 0.44, width: 0.24, height: 0.2, radius: 0.07), with: .color(PierStyle.sole))
        context.fill(Path.box(x: 0.2, y: 0.38, width: 0.24, height: 0.2, radius: 0.07), with: .color(PierStyle.sole))
        context.fill(Path.box(x: -0.33, y: 0.04, width: 0.66, height: 0.4, radius: 0.17), with: .color(PierStyle.hoodie))
        context.fill(Path.box(x: -0.2, y: 0.1, width: 0.4, height: 0.3, radius: 0.1), with: .color(PierStyle.rucksack))
        for side in [-1.0, 1.0] {
            limb(&context, [(side * 0.3, 0.3), (side * 0.52, 0.1)], width: 0.12, color: PierStyle.hoodie)
            context.fill(Path.disc(x: side * 0.54, y: 0.08, r: 0.065), with: .color(PierStyle.skin))
        }
        head(&context, y: 0.56)
    }
}

/// The signs on the power-ups (and in the heads-up display), and the stars round a fallen runner.
enum PowerUpShape {
    /// A horseshoe magnet, poles up.
    static func magnet(in context: inout GraphicsContext, x: Double, y: Double, size: Double) {
        var horseshoe = Path()
        horseshoe.move(to: CGPoint(x: x - size * 0.62, y: y - size * 0.75))
        horseshoe.addLine(to: CGPoint(x: x - size * 0.62, y: y + size * 0.05))
        horseshoe.addCurve(to: CGPoint(x: x + size * 0.62, y: y + size * 0.05),
                           control1: CGPoint(x: x - size * 0.62, y: y + size * 0.88), control2: CGPoint(x: x + size * 0.62, y: y + size * 0.88))
        horseshoe.addLine(to: CGPoint(x: x + size * 0.62, y: y - size * 0.75))
        context.stroke(horseshoe, with: .color(PierStyle.warningRed), style: StrokeStyle(lineWidth: size * 0.52, lineCap: .butt, lineJoin: .round))
        for side in [-1.0, 1.0] {
            context.fill(Path.box(x: x + side * size * 0.62 - size * 0.26, y: y - size * 0.82, width: size * 0.52, height: size * 0.32),
                         with: .color(Color(hex: 0xD9D6E6)))
        }
    }

    static func shield(in context: inout GraphicsContext, x: Double, y: Double, size: Double) {
        func outline(_ k: Double) -> Path {
            let s = size * k
            var path = Path()
            path.move(to: CGPoint(x: x, y: y - s))
            path.addLine(to: CGPoint(x: x + s * 0.85, y: y - s * 0.62))
            path.addLine(to: CGPoint(x: x + s * 0.85, y: y + s * 0.05))
            path.addQuadCurve(to: CGPoint(x: x, y: y + s * 1.05), control: CGPoint(x: x + s * 0.8, y: y + s * 0.75))
            path.addQuadCurve(to: CGPoint(x: x - s * 0.85, y: y + s * 0.05), control: CGPoint(x: x - s * 0.8, y: y + s * 0.75))
            path.addLine(to: CGPoint(x: x - s * 0.85, y: y - s * 0.62))
            path.closeSubpath()
            return path
        }
        context.fill(outline(1), with: .color(Color(hex: 0x3F8CF0)))
        // The right half catches the light.
        var half = context
        half.clip(to: Path.box(x: x, y: y - size, width: size, height: size * 2.2))
        half.fill(outline(0.62), with: .color(.white.opacity(0.85)))
    }

    static func star(x: Double, y: Double, radius: Double) -> Path {
        var path = Path()
        for point in 0..<10 {
            let angle = -Double.pi / 2 + Double(point) * Double.pi / 5
            let reach = point % 2 == 0 ? radius : radius * 0.45
            let spot = CGPoint(x: x + reach * cos(angle), y: y + reach * sin(angle))
            if point == 0 { path.move(to: spot) } else { path.addLine(to: spot) }
        }
        path.closeSubpath()
        return path
    }
}
