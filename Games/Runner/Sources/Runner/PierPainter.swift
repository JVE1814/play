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
    /// Debug builds, `-pierDraw`: less than the whole pier, to measure what each part costs.
    var drawn = Drawn.all

    enum Drawn: String {
        case all
        /// Without the radial glows: the sun's, the lighthouse's, the lamps', the power-ups'
        /// and the shield's.
        case noGlows
        /// The sky, the sea, the planks and the runner: nothing standing on the pier.
        case noItems
        /// Only a sky, the planks and the runner.
        case sketch
        /// Without the bollards, ropes and lamps.
        case noFurniture
        /// Without the obstacles.
        case noObstacles
        /// Without the coins and power-ups.
        case noCoins
    }
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
    private var glows: Bool { f.drawn != .noGlows }
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
        if f.drawn == .sketch {
            context.fill(Path.box(x: -10, y: -10, width: w + 20, height: h + 20),
                         with: .linearGradient(Gradient(stops: scenery.sky), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            deck(&context)
            runner(&context)
            return
        }
        sky(&context)
        sea(&context)
        deck(&context)
        // Far-off coins, a couple of pixels across, are gathered while they come one after
        // another in depth and filled together; anything else in between is drawn first.
        var farCoins = Path()
        func drawFarCoins() {
            guard !farCoins.isEmpty else { return }
            context.fill(farCoins, with: .color(PierStyle.coin))
            farCoins = Path()
        }
        for item in f.drawn == .noItems ? [.runner] : items() {
            if case .coin(let coin, let z) = item, f.drawn != .noCoins, let shape = farCoin(coin, z: z) {
                farCoins.addPath(shape)
                continue
            }
            drawFarCoins()
            switch (item, f.drawn) {
            case (.furniture, .noFurniture), (.obstacle, .noObstacles), (.coin, .noCoins), (.pickup, .noCoins): continue
            default: break
            }
            switch item {
            case .furniture(let index, let z): furniture(&context, index: index, z: z)
            case .obstacle(let obstacle, let z): draw(obstacle, z: z, in: &context)
            case .coin(let coin, let z): draw(coin, z: z, in: &context)
            case .pickup(let pickup, let z): draw(pickup, z: z, in: &context)
            case .runner: runner(&context)
            }
        }
        drawFarCoins()
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
    /// Things that fade or twinkle are drawn in this many steps of strength, each step one fill,
    /// rather than one fill each.
    private static let steps = 6

    /// The step of strength (0...steps) for `strength` (0...1).
    private static func step(_ strength: Double) -> Int {
        min(steps, max(0, Int((strength * Double(steps)).rounded())))
    }
    /// Points below which a face is too thin to see (half a point: a pixel and a half), and
    /// is not drawn.
    private static let detail = 0.5
    /// Points per metre below which only the outline of a thing is drawn (about 40 m off).
    private static let farDetail = 7.5
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
        // The stars twinkle in a few steps of brightness, each step one fill.
        var stars = SeededGenerator(seed: 77)
        var twinkling = [Path](repeating: Path(), count: Self.steps + 1)
        for index in 0..<scenery.starCount {
            let x = stars.nextUnit() * w
            let y = stars.nextUnit() * horizon * 0.7
            let size = 0.6 + stars.nextUnit() * 1.2
            let twinkle = f.reduceMotion ? 1 : 0.5 + 0.5 * sin(f.clock * (1 + Double(index % 5) * 0.4) + Double(index))
            twinkling[Self.step(twinkle)].addPath(Path.disc(x: x, y: y, r: size / 2))
        }
        for (step, shape) in twinkling.enumerated() where !shape.isEmpty {
            context.fill(shape, with: .color(scenery.star.opacity(0.2 + 0.8 * Double(step) / Double(Self.steps))))
        }

        // The sun on the horizon, or the moon above it, a little to the right. Nothing of
        // either shows below the horizon: the sea is painted over it next. (Clipping instead
        // costs the renderer a layer of its own every frame.)
        var above = context
        let centre = Spot(x: w * 0.64 - cam.x * 3, y: horizon - horizon * scenery.discHeight)
        let radius = w * scenery.discRadius
        if glows {
            above.fill(Path.disc(x: centre.x, y: centre.y, r: radius * 4.5),
                       with: .radialGradient(Gradient(colors: [scenery.discGlow, scenery.discGlow.opacity(0)]),
                                             center: centre.point, startRadius: radius * 0.6, endRadius: radius * 4.5))
        }
        let disc = Path.disc(x: centre.x, y: centre.y, r: radius)
        if scenery.isNight {
            // A crescent: the dark side covers most of the disc.
            let shade = Path.disc(x: centre.x - radius * 0.45, y: centre.y - radius * 0.2, r: radius * 0.95)
            above.fill(disc, with: .color(scenery.discShade))
            above.fill(disc.subtracting(shade), with: .color(scenery.disc))
        } else {
            above.fill(disc, with: .color(scenery.disc))
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
        if glows {
            context.fill(Path.disc(x: light.x, y: light.y, r: tall * 0.9),
                         with: .radialGradient(Gradient(colors: [lightColor.opacity(0.9 * blink), lightColor.opacity(0)]),
                                               center: light.point, startRadius: 0, endRadius: tall * 0.9))
        }
    }

    private func sea(_ context: inout GraphicsContext) {
        let horizon = cam.horizon
        context.fill(Path.box(x: -10, y: horizon, width: w + 20, height: h - horizon + 10),
                     with: .linearGradient(Gradient(stops: scenery.sea), startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))
        // Glitter under the sun or moon: short dashes, wider towards the viewer.
        let below = w * 0.64 - cam.x * 3
        var random = SeededGenerator(seed: 5)
        var glitter = [Path](repeating: Path(), count: Self.steps + 1)
        for index in 0..<26 {
            let u = random.nextUnit()
            let y = horizon + 2 + u * u * (h - horizon) * 0.55
            let spread = 6 + u * w * 0.16
            let width = 4 + u * 22
            let x = below + (random.nextUnit() - 0.5) * 2 * spread
            let rate = 1.2 + random.nextUnit() * 2
            let shimmer = f.reduceMotion ? 0.6 : 0.35 + 0.65 * abs(sin(f.clock * rate + Double(index) * 1.7))
            glitter[Self.step(shimmer * (1 - u * 0.6))].addPath(Path.box(x: x - width / 2, y: y, width: width, height: 1.2 + u * 1.6, radius: 1))
        }
        for (step, shape) in glitter.enumerated() where step > 0 && !shape.isEmpty {
            context.fill(shape, with: .color(scenery.glitter.opacity(Double(step) / Double(Self.steps))))
        }
    }

    // MARK: The pier

    /// A strip of planks between two distances from the middle, from `z0` out to `z1`.
    private func strip(_ x0: Double, _ x1: Double, from z0: Double, to z1: Double) -> Path {
        Path.quad(cam.point(x0, 0, z0), cam.point(x1, 0, z0), cam.point(x1, 0, z1), cam.point(x0, 0, z1))
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

        // The gaps between the planks, coming towards the runner. Each is level across the
        // view, so it is drawn as a thin bar, and the bars are drawn together, in a few steps
        // of strength as they fade into the distance.
        let plank = 1.25
        let steps = 6
        var gaps = [Path](repeating: Path(), count: steps + 1)
        var z = plank - distance.truncatingRemainder(dividingBy: plank) + near - plank
        while z < 70 {
            if z >= near {
                let left = cam.point(-half + kerb, 0, z)
                let right = cam.point(half - kerb, 0, z)
                let thickness = max(0.5, cam.scale(z) * 0.035)
                let bar = CGRect(x: left.x, y: left.y - thickness / 2, width: right.x - left.x, height: thickness)
                let strength = min(1, (70 - z) / 30)
                gaps[Int((strength * Double(steps)).rounded())].addRect(bar)
            }
            z += plank
        }
        for step in 1...steps {
            context.fill(gaps[step], with: .color(scenery.plankLine.opacity(Double(step) / Double(steps))))
        }

        // The lanes: two pale lines painted in dashes.
        let dash = 5.0
        var dashes = Path()
        for line in 1..<Body.lanes {
            let x = PierCamera.x(ofLane: Double(line) - 0.5)
            var start = dash - distance.truncatingRemainder(dividingBy: dash) + near - dash
            while start < 90 {
                let end = start + dash * 0.55
                if end > near {
                    dashes.addPath(strip(x - 0.035, x + 0.035, from: max(near, start), to: end))
                }
                start += dash
            }
        }
        context.fill(dashes, with: .color(scenery.laneLine))
    }

    /// The faces of boxes the camera can see, gathered so that boxes side by side (which never
    /// overlap) are filled together: each colour once, however many boxes.
    private struct Faces {
        var side = Path()
        var top = Path()
        var front = Path()
    }

    /// Adds a box standing on the planks: the side and top the camera can see, and its front.
    private func add(_ faces: inout Faces, x x0: Double, _ x1: Double, y y0: Double, _ y1: Double, z near: Double, _ far: Double) {
        let z0 = max(near, PierCamera.near)
        let z1 = max(far, z0 + 0.01)
        // A side or a top seen as a sliver thinner than `detail` is left out.
        let shrink = cam.focal * (1 / z0 - 1 / z1)
        if cam.x < x0, (x0 - cam.x) * shrink > Self.detail {
            faces.side.addPath(Path.quad(cam.point(x0, y0, z0), cam.point(x0, y1, z0), cam.point(x0, y1, z1), cam.point(x0, y0, z1)))
        }
        if cam.x > x1, (cam.x - x1) * shrink > Self.detail {
            faces.side.addPath(Path.quad(cam.point(x1, y0, z0), cam.point(x1, y1, z0), cam.point(x1, y1, z1), cam.point(x1, y0, z1)))
        }
        if y1 < PierCamera.height, (PierCamera.height - y1) * shrink > Self.detail {
            faces.top.addPath(Path.quad(cam.point(x0, y1, z0), cam.point(x1, y1, z0), cam.point(x1, y1, z1), cam.point(x0, y1, z1)))
        }
        faces.front.addPath(Path.quad(cam.point(x0, y0, z0), cam.point(x1, y0, z0), cam.point(x1, y1, z0), cam.point(x0, y1, z0)))
    }

    /// Sides and tops, then fronts.
    private func fill(_ faces: Faces, in context: inout GraphicsContext, front: Color, side: Color, top: Color) {
        if !faces.side.isEmpty { context.fill(faces.side, with: .color(side)) }
        if !faces.top.isEmpty { context.fill(faces.top, with: .color(top)) }
        context.fill(faces.front, with: .color(front))
    }

    /// A box standing on the planks: its top and the side the camera can see, then its front.
    private func box(_ context: inout GraphicsContext, x x0: Double, _ x1: Double, y y0: Double, _ y1: Double,
                     z near: Double, _ far: Double, front: Color, side: Color, top: Color) {
        var faces = Faces()
        add(&faces, x: x0, x1, y: y0, y1, z: near, far)
        fill(faces, in: &context, front: front, side: side, top: top)
    }

    /// A bollard on each edge with a rope sagging to the next, and a lamp at every fourth.
    private func furniture(_ context: inout GraphicsContext, index: Int, z: Double) {
        var layer = context
        layer.opacity = haze(z)
        let scale = cam.scale(z)
        // The two edges of the pier never overlap, so each part of both is drawn at once.
        var ropes = Path()
        var posts = Faces()
        var caps = Path()
        var lampPosts = Path()
        var lamps: [Spot] = []
        for side in [-1.0, 1.0] {
            let x = side * (PierCamera.halfWidth + 0.12)
            ropes.move(to: cam.point(x, 0.8, z).point)
            ropes.addQuadCurve(to: cam.point(x, 0.8, z + Self.bollardSpacing).point, control: cam.point(x, 0.1, z + Self.bollardSpacing / 2).point)
            add(&posts, x: x - 0.1, x + 0.1, y: 0, 0.9, z: z, z + 0.2)
            let cap = cam.point(x, 0.9, z)
            if scale > Self.farDetail {
                caps.addPath(Path.box(x: cap.x - scale * 0.13, y: cap.y - scale * 0.07, width: scale * 0.26, height: scale * 0.09, radius: scale * 0.03))
            }
            guard index % 4 == 0 else { continue }
            let arm = cam.point(x - side * 0.5, 3.4, z)
            lampPosts.move(to: cam.point(x + side * 0.05, 0, z).point)
            lampPosts.addLine(to: cam.point(x + side * 0.05, 3.4, z).point)
            lampPosts.addLine(to: arm.point)
            lamps.append(arm)
        }
        layer.stroke(ropes, with: .color(scenery.rope), style: StrokeStyle(lineWidth: max(0.6, scale * 0.035), lineCap: .round))
        fill(posts, in: &layer, front: scenery.post, side: scenery.postSide, top: scenery.postTop)
        if !caps.isEmpty { layer.fill(caps, with: .color(scenery.postCap)) }
        guard !lamps.isEmpty else { return }
        layer.stroke(lampPosts, with: .color(scenery.lampPost), style: StrokeStyle(lineWidth: max(1, scale * 0.09), lineCap: .round, lineJoin: .round))
        var bulbs = Path()
        for arm in lamps {
            if glows {
                layer.fill(Path.disc(x: arm.x, y: arm.y, r: scale * 1.1),
                           with: .radialGradient(Gradient(colors: [scenery.lampGlow, scenery.lampGlow.opacity(0)]),
                                                 center: arm.point, startRadius: 0, endRadius: scale * 1.1))
            }
            bulbs.addPath(Path.disc(x: arm.x, y: arm.y + scale * 0.05, r: scale * 0.13))
        }
        layer.fill(bulbs, with: .color(scenery.lamp))
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
        guard width / Double(blocks) > 1.5 else {
            // Blocks under a point and a half wide blur into one colour.
            context.fill(Path.box(x: topLeft.x, y: topLeft.y, width: width, height: height, radius: height * 0.2), with: .color(colors.0))
            return
        }
        // The blocks at the ends carry the board's rounded corners, so it needs no clipping
        // (which costs the renderer a layer of its own for every board).
        let block = width / Double(blocks)
        let radius = min(height * 0.2, block / 2)
        var painted = [Path(), Path()]
        for index in 0..<blocks {
            let first = index == 0
            let last = index == blocks - 1
            let left = topLeft.x + Double(index) * block - (first ? 0 : 0.5)
            let right = topLeft.x + Double(index + 1) * block + (last ? 0 : 0.5)
            let shape = UnevenRoundedRectangle(topLeadingRadius: first ? radius : 0, bottomLeadingRadius: first ? radius : 0,
                                               bottomTrailingRadius: last ? radius : 0, topTrailingRadius: last ? radius : 0)
            painted[index % 2].addPath(shape.path(in: CGRect(x: left, y: topLeft.y, width: right - left, height: height)))
        }
        context.fill(painted[0], with: .color(colors.0))
        context.fill(painted[1], with: .color(colors.1))
        let shadow = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius, bottomTrailingRadius: radius, topTrailingRadius: 0)
        context.fill(shadow.path(in: CGRect(x: topLeft.x, y: topLeft.y + height * 0.72, width: width, height: height * 0.28)),
                     with: .color(.black.opacity(0.12)))
    }

    private func crate(_ context: inout GraphicsContext, x x0: Double, _ x1: Double, y y0: Double, _ y1: Double, z near: Double, _ far: Double) {
        box(&context, x: x0, x1, y: y0, y1, z: near, far, front: PierStyle.crate, side: PierStyle.crateSide, top: PierStyle.crateTop)
        let z = max(near, PierCamera.near)
        let scale = cam.scale(z)
        let topLeft = cam.point(x0, y1, z)
        let bottomRight = cam.point(x1, y0, z)
        guard scale > Self.farDetail else { return }
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
        // Far off (about 40 m and more, where most of the course is), a few points high: drawn
        // as a silhouette in its main colours.
        if scale < Self.farDetail, obstacle.kind != .stack || obstacle.length <= 5 {
            silhouette(of: obstacle, x: x, z: near, in: &layer)
            return
        }
        switch obstacle.kind {
        case .barrier:
            groundShadow(&layer, x: x, z: near, halfWidth: 0.72, depth: 0.3)
            var posts = Faces()
            for side in [-1.0, 1.0] {
                add(&posts, x: x + side * 0.6 - 0.05, x + side * 0.6 + 0.05, y: 0, 0.6, z: near, near + 0.1)
            }
            fill(posts, in: &layer, front: Color(hex: 0xE8E4EE), side: Color(hex: 0xB9B3C6), top: .white)
            stripedBoard(&layer, x: x - 0.66, x + 0.66, y: 0.36, 0.66, z: near, colors: (PierStyle.warningRed, PierStyle.cream), blocks: 6)
        case .beam:
            groundShadow(&layer, x: x, z: near, halfWidth: 0.72, depth: 0.3)
            var posts = Faces()
            for side in [-1.0, 1.0] {
                add(&posts, x: x + side * 0.66 - 0.06, x + side * 0.66 + 0.06, y: 0, 1.75, z: near, near + 0.12)
            }
            fill(posts, in: &layer, front: PierStyle.beamPost, side: PierStyle.beamPostSide, top: PierStyle.beamPostTop)
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

    /// An obstacle far off, as the flat shapes of its front: a board on two posts, a stack of
    /// crates, a barrel.
    private func silhouette(of obstacle: Obstacle, x: Double, z: Double, in context: inout GraphicsContext) {
        func face(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double) -> CGRect {
            let topLeft = cam.point(x0, y1, z)
            let bottomRight = cam.point(x1, y0, z)
            return CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
        }
        switch obstacle.kind {
        case .barrier, .beam:
            let barrier = obstacle.kind == .barrier
            let reach = barrier ? 0.6 : 0.66
            let thick = barrier ? 0.05 : 0.06
            var posts = Path()
            for side in [-1.0, 1.0] {
                posts.addRect(face(x + side * reach - thick, x + side * reach + thick, 0, barrier ? 0.6 : 1.75))
            }
            context.fill(posts, with: .color(barrier ? Color(hex: 0xE8E4EE) : PierStyle.beamPost))
            let board = barrier ? face(x - 0.66, x + 0.66, 0.36, 0.66) : face(x - 0.74, x + 0.74, 1.05, 1.5)
            context.fill(Path(roundedRect: board, cornerRadius: board.height * 0.2), with: .color(barrier ? PierStyle.warningRed : Theme.highlight))
        case .stack:
            var crates = Path(face(x - 0.64, x + 0.64, 0, 1.28))
            crates.addRect(face(x - 0.5, x + 0.56, 1.28, 2.3))
            context.fill(crates, with: .color(PierStyle.crate))
        case .barrel:
            let body = face(x - 0.52, x + 0.52, 0, 0.72)
            context.fill(Path(roundedRect: body, cornerRadius: body.height * 0.42), with: .color(PierStyle.barrel))
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
        let outline = RoundedOutline(rect: CGRect(x: corner.x, y: corner.y, width: width, height: height), radius: height * 0.42)
        context.fill(Path(roundedRect: outline.rect, cornerRadius: outline.radius), with: .color(PierStyle.barrel))
        // The staves, the light along the top and the hoops are cut to the barrel's outline
        // here, rather than clipped to it (which costs the renderer a layer of its own).
        let spin = f.reduceMotion ? 0.3 : (f.clock * 2.2).truncatingRemainder(dividingBy: 1)
        var staves = Path()
        for stave in -1..<4 {
            let y = corner.y + height * (Double(stave) + spin) / 3
            guard y > outline.rect.minY, y < outline.rect.maxY else { continue }
            let inset = outline.inset(atY: y)
            staves.move(to: CGPoint(x: outline.rect.minX + inset, y: y))
            staves.addLine(to: CGPoint(x: outline.rect.maxX - inset, y: y))
        }
        context.stroke(staves, with: .color(Color(hex: 0x3C1905, opacity: 0.45)), lineWidth: max(0.6, scale * 0.03))
        context.fill(outline.rows(from: corner.y, to: corner.y + height * 0.3), with: .color(Color(hex: 0xFFDCAA, opacity: 0.18)))
        var hoops = outline.columns(from: corner.x + width * 0.14, to: corner.x + width * 0.22)
        hoops.addPath(outline.columns(from: corner.x + width * 0.78, to: corner.x + width * 0.86))
        context.fill(hoops, with: .color(PierStyle.hoop))
    }

    /// Where a coin is drawn, its size and how far it is turned.
    private func look(of coin: Coin, z: Double) -> (centre: Spot, radius: Double, across: Double) {
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
        return (centre, radius, radius * (0.22 + 0.78 * turn))
    }

    /// The face of a coin far enough off to be a couple of pixels across, and seen in full; nil
    /// for any other.
    private func farCoin(_ coin: Coin, z: Double) -> Path? {
        guard haze(z) * passed(z) >= 1 else { return nil }
        let (centre, radius, across) = look(of: coin, z: z)
        guard radius <= 2.5 else { return nil }
        return Path.oval(x: centre.x, y: centre.y, rx: across, ry: radius)
    }

    private func draw(_ coin: Coin, z: Double, in context: inout GraphicsContext) {
        let (centre, radius, across) = look(of: coin, z: z)
        var layer = context
        layer.opacity = haze(z) * passed(z)
        guard radius > 2.5 else {
            // A couple of pixels across: the face alone.
            layer.fill(Path.oval(x: centre.x, y: centre.y, rx: across, ry: radius), with: .color(PierStyle.coin))
            return
        }
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
        if glows {
            layer.fill(Path.disc(x: centre.x, y: centre.y, r: radius * 1.7),
                       with: .radialGradient(Gradient(colors: [color.opacity(0.55), color.opacity(0)]),
                                             center: centre.point, startRadius: radius * 0.3, endRadius: radius * 1.7))
        }
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
            if glows {
                context.fill(Path.disc(x: middle.x, y: middle.y, r: radius),
                             with: .radialGradient(Gradient(stops: [.init(color: glass.opacity(0), location: 0), .init(color: glass.opacity(0.28), location: 0.7),
                                                                    .init(color: Color(hex: 0xB4DCFF, opacity: 0.75), location: 1)]),
                                                   center: middle.point, startRadius: radius * 0.55, endRadius: radius))
            }
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
        var streaks = [Path](repeating: Path(), count: Self.steps + 1)
        for index in 0..<14 {
            let side = index % 2 == 0 ? -1.0 : 1.0
            let y = cam.horizon + random.nextUnit() * (h - cam.horizon) * 0.8
            let age = (f.clock * (1.5 + random.nextUnit()) + random.nextUnit()).truncatingRemainder(dividingBy: 1)
            let x = w / 2 + side * w * (0.36 + 0.16 * random.nextUnit() + age * 0.1)
            let length = (10 + 26 * random.nextUnit()) * rush
            let outward = (x - w / 2) / w
            let downward = (y - cam.horizon) / h
            streaks[Self.step(1 - age)].addPath(Path.line(Spot(x: x, y: y), Spot(x: x + outward * length, y: y + downward * length * 1.6)))
        }
        for (step, shape) in streaks.enumerated() where step > 0 && !shape.isEmpty {
            context.stroke(shape, with: .color(.white.opacity(0.25 * rush * Double(step) / Double(Self.steps))),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
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
        // The hat covers the top half of the head (y is up here).
        var crown = Path()
        crown.addArc(center: CGPoint(x: 0, y: y + 0.02), radius: 0.185, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
        crown.closeSubpath()
        context.fill(crown, with: .color(PierStyle.hat))
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
        let s = size * 0.62
        var half = Path()
        half.move(to: CGPoint(x: x, y: y - s))
        half.addLine(to: CGPoint(x: x + s * 0.85, y: y - s * 0.62))
        half.addLine(to: CGPoint(x: x + s * 0.85, y: y + s * 0.05))
        half.addQuadCurve(to: CGPoint(x: x, y: y + s * 1.05), control: CGPoint(x: x + s * 0.8, y: y + s * 0.75))
        half.closeSubpath()
        context.fill(half, with: .color(.white.opacity(0.85)))
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

/// A rounded rectangle, and the parts of it between two heights or two widths: what a clip to
/// it would leave, without the clip.
struct RoundedOutline {
    let rect: CGRect
    let radius: Double

    init(rect: CGRect, radius: Double) {
        self.rect = rect
        self.radius = min(radius, Double(min(rect.width, rect.height)) / 2)
    }

    /// How far in from the left and right sides the outline is at height `y`.
    func inset(atY y: Double) -> Double {
        Self.inset(depth: max(0, Double(rect.minY) + radius - y, y - (Double(rect.maxY) - radius)), radius: radius)
    }

    /// How far in from the top and bottom the outline is at `x`.
    func inset(atX x: Double) -> Double {
        Self.inset(depth: max(0, Double(rect.minX) + radius - x, x - (Double(rect.maxX) - radius)), radius: radius)
    }

    private static func inset(depth: Double, radius: Double) -> Double {
        let d = min(depth, radius)
        return radius - (radius * radius - d * d).squareRoot()
    }

    private static let steps = 6

    /// The part between heights `y0` and `y1`, its rounded ends followed in a few straight steps.
    func rows(from y0: Double, to y1: Double) -> Path {
        let top = max(y0, Double(rect.minY))
        let bottom = min(y1, Double(rect.maxY))
        guard bottom > top else { return Path() }
        var path = Path()
        for step in 0...Self.steps {
            let y = top + (bottom - top) * Double(step) / Double(Self.steps)
            let point = CGPoint(x: Double(rect.minX) + inset(atY: y), y: y)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        for step in (0...Self.steps).reversed() {
            let y = top + (bottom - top) * Double(step) / Double(Self.steps)
            path.addLine(to: CGPoint(x: Double(rect.maxX) - inset(atY: y), y: y))
        }
        path.closeSubpath()
        return path
    }

    /// The part between `x0` and `x1`.
    func columns(from x0: Double, to x1: Double) -> Path {
        let left = max(x0, Double(rect.minX))
        let right = min(x1, Double(rect.maxX))
        guard right > left else { return Path() }
        var path = Path()
        for step in 0...Self.steps {
            let x = left + (right - left) * Double(step) / Double(Self.steps)
            let point = CGPoint(x: x, y: Double(rect.minY) + inset(atX: x))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        for step in (0...Self.steps).reversed() {
            let x = left + (right - left) * Double(step) / Double(Self.steps)
            path.addLine(to: CGPoint(x: x, y: Double(rect.maxY) - inset(atX: x)))
        }
        path.closeSubpath()
        return path
    }
}
