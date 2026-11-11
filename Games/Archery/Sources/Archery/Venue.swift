import ArcheryEngine
import PlayKit
import SwiftUI

/// The light and colours of each venue.
struct Venue {
    enum Particle { case seeds, pollen, leaves, motes, moths }

    let skyTop: Color
    let skyMiddle: Color
    let skyHorizon: Color
    /// Sun or moon: x as a share of the width, y as a share of the sky's height above the horizon.
    let sun: (x: CGFloat, y: CGFloat, radius: CGFloat, color: Color, glow: Color)
    let farHills: Color
    let nearHills: Color
    let trees: Color
    let groundFar: Color
    let groundNear: Color
    let stripe: Color
    let line: Color
    let boss: Color
    let bossEdge: Color
    let wood: Color
    let shadow: Color
    /// Shadows fall to the side late in the day.
    let shadowLean: CGFloat
    let particle: Particle
    let particleColor: Color
    let label: Color
    let isNight: Bool
    let hasLake: Bool
    let hasMountains: Bool
    let hasFlowers: Bool

    static func of(_ chapter: Chapter) -> Venue {
        switch chapter {
        case .practiceField:
            return Venue(skyTop: Color(hex: 0x6FAFEF), skyMiddle: Color(hex: 0xA9D1F5), skyHorizon: Color(hex: 0xFCE9CB),
                         sun: (0.2, 0.4, 22, Color(hex: 0xFFF6DE), Color(hex: 0xFFE7B0, opacity: 0.55)),
                         farHills: Color(hex: 0xA7C4BA), nearHills: Color(hex: 0x7DAA86), trees: Color(hex: 0x4F8460),
                         groundFar: Color(hex: 0x9CCB6E), groundNear: Color(hex: 0x6CAA4C),
                         stripe: Color.white.opacity(0.09), line: Color.white.opacity(0.72),
                         boss: Color(hex: 0xE8D4A2), bossEdge: Color(hex: 0xBF9F62), wood: Color(hex: 0x8A5C3B),
                         shadow: Color.black.opacity(0.2), shadowLean: -0.25, particle: .seeds,
                         particleColor: Color.white.opacity(0.85), label: Color.white.opacity(0.85),
                         isNight: false, hasLake: false, hasMountains: false, hasFlowers: false)
        case .meadow:
            return Venue(skyTop: Color(hex: 0x2D83E6), skyMiddle: Color(hex: 0x6FB0F2), skyHorizon: Color(hex: 0xD4ECFF),
                         sun: (0.82, 0.8, 20, Color(hex: 0xFFFDF0), Color(hex: 0xFFFFFF, opacity: 0.5)),
                         farHills: Color(hex: 0x86B97D), nearHills: Color(hex: 0x5CA35E), trees: Color(hex: 0x3B7D46),
                         groundFar: Color(hex: 0xA2D25C), groundNear: Color(hex: 0x74B744),
                         stripe: Color.white.opacity(0.1), line: Color.white.opacity(0.75),
                         boss: Color(hex: 0xEBD8A6), bossEdge: Color(hex: 0xC3A365), wood: Color(hex: 0x8D5F3D),
                         shadow: Color.black.opacity(0.24), shadowLean: 0, particle: .pollen,
                         particleColor: Color(hex: 0xFFF1A6, opacity: 0.9), label: Color.white.opacity(0.9),
                         isNight: false, hasLake: false, hasMountains: false, hasFlowers: true)
        case .lakeside:
            return Venue(skyTop: Color(hex: 0x4C8EDC), skyMiddle: Color(hex: 0x9CC4EC), skyHorizon: Color(hex: 0xFFE3B6),
                         sun: (0.74, 0.46, 22, Color(hex: 0xFFF0C2), Color(hex: 0xFFD98A, opacity: 0.5)),
                         farHills: Color(hex: 0x8197BD), nearHills: Color(hex: 0x5F7FA0), trees: Color(hex: 0x41694F),
                         groundFar: Color(hex: 0x98C467), groundNear: Color(hex: 0x6BA34C),
                         stripe: Color.white.opacity(0.09), line: Color.white.opacity(0.72),
                         boss: Color(hex: 0xEAD39D), bossEdge: Color(hex: 0xC09D5E), wood: Color(hex: 0x86583A),
                         shadow: Color.black.opacity(0.22), shadowLean: 0.3, particle: .leaves,
                         particleColor: Color(hex: 0xE9A23B), label: Color.white.opacity(0.88),
                         isNight: false, hasLake: true, hasMountains: false, hasFlowers: false)
        case .hilltop:
            return Venue(skyTop: Color(hex: 0x2A2F6C), skyMiddle: Color(hex: 0xC9567A), skyHorizon: Color(hex: 0xFFBF78),
                         sun: (0.3, 0.07, 34, Color(hex: 0xFFD98E), Color(hex: 0xFF9A5A, opacity: 0.6)),
                         farHills: Color(hex: 0x6C4F84), nearHills: Color(hex: 0x45395F), trees: Color(hex: 0x2F2A45),
                         groundFar: Color(hex: 0x7F9449), groundNear: Color(hex: 0x56702F),
                         stripe: Color(hex: 0xFFD7A0, opacity: 0.08), line: Color(hex: 0xFFF1DC, opacity: 0.7),
                         boss: Color(hex: 0xF0C98C), bossEdge: Color(hex: 0xBF8F55), wood: Color(hex: 0x7A4B33),
                         shadow: Color(hex: 0x2A1530, opacity: 0.32), shadowLean: 1.6, particle: .motes,
                         particleColor: Color(hex: 0xFFE2B0, opacity: 0.8), label: Color(hex: 0xFFF1DC, opacity: 0.9),
                         isNight: false, hasLake: false, hasMountains: true, hasFlowers: false)
        case .floodlights:
            return Venue(skyTop: Color(hex: 0x04070F), skyMiddle: Color(hex: 0x0B1330), skyHorizon: Color(hex: 0x1C2756),
                         sun: (0.84, 0.72, 14, Color(hex: 0xEEF1FA), Color(hex: 0xA9B8F0, opacity: 0.3)),
                         farHills: Color(hex: 0x111A33), nearHills: Color(hex: 0x0C1426), trees: Color(hex: 0x08101E),
                         groundFar: Color(hex: 0x3D7A3E), groundNear: Color(hex: 0x173A20),
                         stripe: Color.white.opacity(0.07), line: Color.white.opacity(0.8),
                         boss: Color(hex: 0xF1DDAE), bossEdge: Color(hex: 0xC3A46A), wood: Color(hex: 0x7C5236),
                         shadow: Color.black.opacity(0.4), shadowLean: 0, particle: .moths,
                         particleColor: Color.white.opacity(0.85), label: Color.white.opacity(0.85),
                         isNight: true, hasLake: false, hasMountains: false, hasFlowers: false)
        }
    }
}

/// Target face colours (as on a real face) and the fletching colours of the six arrows.
enum ArcheryStyle {
    /// The dark panel behind readings shown over the range.
    static let hudFill = Color.black.opacity(0.42)

    static func zoneColor(_ zone: Face.Zone) -> Color {
        switch zone {
        case .white: return Color(hex: 0xF7F5EF)
        case .black: return Color(hex: 0x26262C)
        case .blue: return Color(hex: 0x23A7E0)
        case .red: return Color(hex: 0xEC4637)
        case .gold: return Color(hex: 0xFFD23F)
        }
    }

    /// Lines between rings: dark everywhere except inside the black rings.
    static func ringLine(_ zone: Face.Zone) -> Color {
        zone == .black ? Color.white.opacity(0.85) : Color.black.opacity(0.55)
    }

    /// Text on a ring colour (for score chips).
    static func onZone(_ zone: Face.Zone) -> Color {
        switch zone {
        case .black, .blue, .red: return .white
        case .white, .gold: return Color(hex: 0x1C1C22)
        }
    }

    static let fletching: [Color] = [
        Color(hex: 0xFF6A2B), Color(hex: 0xB6F03C), Color(hex: 0xFFFFFF),
        Color(hex: 0xFF4FA8), Color(hex: 0x35D7FF), Color(hex: 0xFFD60A),
    ]

    static func fletching(_ arrow: Int) -> Color { fletching[arrow % fletching.count] }

    /// Colour of a score chip: the ring's colour, or grey for a miss.
    static func chip(for hit: Hit) -> (fill: Color, text: Color) {
        guard hit.ring > 0 else { return (Color(hex: 0x8A8A93), .white) }
        let zone = Face.zone(ofRing: hit.ring)
        return (zoneColor(zone), onZone(zone))
    }
}
