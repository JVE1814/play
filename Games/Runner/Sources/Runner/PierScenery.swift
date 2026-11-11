import PlayKit
import RunnerEngine
import SwiftUI

/// The light the pier is seen in: sunset in light mode, a moonlit night in dark mode.
struct Scenery {
    let isNight: Bool
    let sky: [Gradient.Stop]
    let star: Color
    let starCount: Int
    /// The sun, or the moon.
    let disc: Color
    let discGlow: Color
    /// How far above the horizon it stands (as a share of the sky's height) and how big it is
    /// (as a share of the view's width).
    let discHeight: Double
    let discRadius: Double
    /// The moon's dark side.
    let discShade: Color
    let cloud: Color
    let headland: Color
    let farShore: Color
    let lighthouse: Color
    let sea: [Gradient.Stop]
    let glitter: Color
    let deck: Color
    /// The far end of the pier takes on the colour of the horizon.
    let deckFar: Color
    let plankLine: Color
    let laneLine: Color
    let kerb: Color
    let post: Color
    let postSide: Color
    let postTop: Color
    let postCap: Color
    let rope: Color
    let lampPost: Color
    let lamp: Color
    let lampGlow: Color
    let shadow: Color

    static func of(_ colorScheme: ColorScheme) -> Scenery {
        colorScheme == .dark ? night : dusk
    }

    static let dusk = Scenery(
        isNight: false,
        sky: [.init(color: Color(hex: 0x241A5E), location: 0), .init(color: Color(hex: 0x6A3D9A), location: 0.45),
              .init(color: Color(hex: 0xE8748A), location: 0.82), .init(color: Color(hex: 0xFFBE7D), location: 1)],
        star: Color.white.opacity(0.55), starCount: 18,
        disc: Color(hex: 0xFFE2AE), discGlow: Color(hex: 0xFFBE7D, opacity: 0.55), discHeight: 0, discRadius: 0.11,
        discShade: Color(hex: 0x6A3D9A),
        cloud: Color(hex: 0xFFAAA0, opacity: 0.35),
        headland: Color(hex: 0x3B2A6B), farShore: Color(hex: 0x5A3A86), lighthouse: Color(hex: 0xE9D8C0),
        sea: [.init(color: Color(hex: 0xD9788F), location: 0), .init(color: Color(hex: 0x5B3B8F), location: 0.25),
              .init(color: Color(hex: 0x261F5C), location: 1)],
        glitter: Color(hex: 0xFFE2AE, opacity: 0.85),
        deck: Color(hex: 0xB78657), deckFar: Color(hex: 0xC9879A),
        plankLine: Color(hex: 0x3C1E14, opacity: 0.28), laneLine: Color(hex: 0xFFF0DC, opacity: 0.2),
        kerb: Color(hex: 0x7A5238),
        post: Color(hex: 0x4A3050), postSide: Color(hex: 0x33203A), postTop: Color(hex: 0x66496D), postCap: Color(hex: 0xE9D8C0),
        rope: Color(hex: 0xF0E1C8, opacity: 0.75),
        lampPost: Color(hex: 0x2B2147), lamp: Color(hex: 0xFFF1C4), lampGlow: Color(hex: 0xFFDC96, opacity: 0.5),
        shadow: Color(hex: 0x1E0A28, opacity: 0.28))

    static let night = Scenery(
        isNight: true,
        sky: [.init(color: Color(hex: 0x05071C), location: 0), .init(color: Color(hex: 0x101848), location: 0.5),
              .init(color: Color(hex: 0x2B2F7A), location: 0.88), .init(color: Color(hex: 0x4A4A9C), location: 1)],
        star: Color.white.opacity(0.9), starCount: 70,
        disc: Color(hex: 0xF4F1E4), discGlow: Color(hex: 0xC8D2FF, opacity: 0.35), discHeight: 0.55, discRadius: 0.06,
        discShade: Color(hex: 0x101848),
        cloud: Color(hex: 0x7882C8, opacity: 0.22),
        headland: Color(hex: 0x0C1030), farShore: Color(hex: 0x161C4A), lighthouse: Color(hex: 0xB9B4D8),
        sea: [.init(color: Color(hex: 0x3A3F8F), location: 0), .init(color: Color(hex: 0x141A4A), location: 0.25),
              .init(color: Color(hex: 0x080B26), location: 1)],
        glitter: Color(hex: 0xE6EBFF, opacity: 0.7),
        deck: Color(hex: 0x5D4A63), deckFar: Color(hex: 0x3E3F85),
        plankLine: Color(hex: 0x0A081E, opacity: 0.35), laneLine: Color(hex: 0xDCE1FF, opacity: 0.14),
        kerb: Color(hex: 0x3A2D48),
        post: Color(hex: 0x1B1633), postSide: Color(hex: 0x100D22), postTop: Color(hex: 0x2E2850), postCap: Color(hex: 0xB9B4D8),
        rope: Color(hex: 0xC8C8EB, opacity: 0.6),
        lampPost: Color(hex: 0x0E0B22), lamp: Color(hex: 0xFFF3C9), lampGlow: Color(hex: 0xFFE196, opacity: 0.6),
        shadow: Color(hex: 0x00000A, opacity: 0.4))
}

/// The colours of the things on the pier, the same by day and by night.
enum PierStyle {
    static let coin = Color(hex: 0xFFD23F)
    static let coinEdge = Color(hex: 0xE09A00)
    static let magnet = Color(hex: 0xFF5A5F)
    static let shield = Color(hex: 0x50AAFF)
    static let warningRed = Color(hex: 0xF0484E)
    static let cream = Color(hex: 0xFFF6EE)
    static let crate = Color(hex: 0xC8914F)
    static let crateSide = Color(hex: 0x9B6C38)
    static let crateTop = Color(hex: 0xE0AD6C)
    static let crateFrame = Color(hex: 0x8A5A2B)
    static let barrel = Color(hex: 0xA8622F)
    static let hoop = Color(hex: 0x4B3A45)
    static let beamPost = Color(hex: 0x3D3557)
    static let beamPostSide = Color(hex: 0x2A2440)
    static let beamPostTop = Color(hex: 0x57507A)
    /// A long stack is a shipping container, in one of three paints: front, side, top.
    static let containers: [(front: Color, side: Color, top: Color)] = [
        (Color(hex: 0x2A9D8F), Color(hex: 0x1F7A70), Color(hex: 0x3FB8A9)),
        (Color(hex: 0xD1495B), Color(hex: 0xA83A49), Color(hex: 0xE56B7B)),
        (Color(hex: 0x3D7DD8), Color(hex: 0x2F62AD), Color(hex: 0x5B96EA)),
    ]

    // The runner.
    static let hoodie = Color(hex: 0xFFC531)
    static let hoodieHem = Color(hex: 0xE0A312)
    static let trousers = Color(hex: 0x2B2A55)
    static let sole = Color(hex: 0xF0484E)
    static let skin = Color(hex: 0xF2B58A)
    static let hat = Color(hex: 0x9B6BFF)
    static let hatBrim = Color(hex: 0x7A4DE0)
    static let rucksack = Color(hex: 0x27B7A8)
    static let rucksackFlap = Color(hex: 0x17877C)
    static let scarf = Color(hex: 0xF0484E)

    /// The dark chips of the heads-up display, readable over sky and sea alike.
    static let hudFill = Color.black.opacity(0.42)
}

/// Where the camera stands and how the pier is projected onto the view.
///
/// World coordinates are metres: x to the right of the middle of the pier, y up from the
/// planks, z ahead of the camera.
struct PierCamera {
    static let laneWidth = 1.5
    /// From the middle of the pier to its edge.
    static let halfWidth = 2.6
    static let height = 4.6
    /// How far behind the runner the camera follows.
    static let back = 5.0
    /// The nearest anything is drawn.
    static let near = 0.7

    let width: Double
    let height: Double
    let focal: Double
    let horizon: Double
    /// Where the camera is across the pier: it follows the runner part of the way.
    let x: Double

    init(size: CGSize, across: Double) {
        width = Double(size.width)
        height = Double(size.height)
        focal = min(width * 0.8, height * 0.52)
        horizon = height * 0.26
        x = Self.x(ofLane: across) * 0.4
    }

    /// The middle of a lane (or a place between lanes), in metres from the middle of the pier.
    static func x(ofLane lane: Double) -> Double {
        (lane - Double(Body.lanes - 1) / 2) * laneWidth
    }

    func point(_ x: Double, _ y: Double, _ z: Double) -> Spot {
        Spot(x: width / 2 + focal * (x - self.x) / z, y: horizon + focal * (Self.height - y) / z)
    }

    /// Points per metre at depth `z`.
    func scale(_ z: Double) -> Double {
        focal / z
    }
}

/// A point of the view. Plain doubles, so the painter's arithmetic stays in one type.
struct Spot {
    var x: Double
    var y: Double

    var point: CGPoint { CGPoint(x: x, y: y) }
}

extension Path {
    static func polygon(_ spots: [Spot]) -> Path {
        var path = Path()
        for (index, spot) in spots.enumerated() {
            if index == 0 { path.move(to: spot.point) } else { path.addLine(to: spot.point) }
        }
        path.closeSubpath()
        return path
    }

    static func quad(_ a: Spot, _ b: Spot, _ c: Spot, _ d: Spot) -> Path {
        var path = Path()
        path.move(to: a.point)
        path.addLine(to: b.point)
        path.addLine(to: c.point)
        path.addLine(to: d.point)
        path.closeSubpath()
        return path
    }

    static func line(_ from: Spot, _ to: Spot) -> Path {
        var path = Path()
        path.move(to: from.point)
        path.addLine(to: to.point)
        return path
    }

    static func oval(x: Double, y: Double, rx: Double, ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
    }

    static func disc(x: Double, y: Double, r: Double) -> Path {
        oval(x: x, y: y, rx: r, ry: r)
    }

    static func box(x: Double, y: Double, width: Double, height: Double, radius: Double = 0) -> Path {
        let rect = CGRect(x: x, y: y, width: width, height: height)
        return radius > 0 ? Path(roundedRect: rect, cornerRadius: min(radius, min(abs(width), abs(height)) / 2)) : Path(rect)
    }
}
