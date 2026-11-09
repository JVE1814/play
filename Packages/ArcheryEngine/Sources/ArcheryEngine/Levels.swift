import Foundation

/// The five venues, one per six levels, from a calm morning to a windy championship at night.
public enum Chapter: Int, CaseIterable, Codable, Sendable, Identifiable {
    case practiceField = 1, meadow, lakeside, hilltop, floodlights

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .practiceField: return "Practice Field"
        case .meadow: return "Meadow"
        case .lakeside: return "Lakeside"
        case .hilltop: return "Hilltop"
        case .floodlights: return "Floodlights"
        }
    }

    /// Time of day, which sets the sky and light.
    public var timeOfDay: String {
        switch self {
        case .practiceField: return "Morning"
        case .meadow: return "Midday"
        case .lakeside: return "Afternoon"
        case .hilltop: return "Sunset"
        case .floodlights: return "Night"
        }
    }

    public var levels: ClosedRange<Int> {
        let first = (rawValue - 1) * LevelCatalog.levelsPerChapter + 1
        return first...(first + LevelCatalog.levelsPerChapter - 1)
    }
}

/// One level: a distance, a target, a number of arrows and the conditions to shoot them in.
public struct Level: Hashable, Codable, Sendable, Identifiable {
    public let number: Int
    public let name: String
    public let chapter: Chapter
    /// Metres from the shooting line to the target.
    public let distance: Double
    public let layout: TargetLayout
    public let arrows: Int
    public let wind: Wind
    public let motion: Motion
    /// Sight sway multiplier: nerves rise as the venues get bigger.
    public let sway: Double
    /// Seconds for all the arrows, counted from the first draw. nil means no clock.
    public let timeLimit: Double?
    /// Scores needed for one, two and three stars. One star passes the level.
    public let starScores: [Int]
    /// What is new in this level, if anything ("Wind", "Moving target", …).
    public let feature: String?
    /// One or two sentences shown before the first arrow.
    public let tip: String

    public var id: Int { number }
    public var maxScore: Int { arrows * 10 }

    public func stars(for score: Int) -> Int {
        starScores.filter { score >= $0 }.count
    }

    /// Short conditions summary, e.g. "50 m · 122 cm face · gusty wind · moving".
    public var summary: String {
        var parts = ["\(Int(distance)) m"]
        if layout.spots.count > 1 {
            parts.append("\(layout.spots.count) spots")
        } else {
            parts.append("\(Int((layout.spots[0].face.size * 100).rounded())) cm face")
        }
        if wind.isCalm {
            parts.append("calm")
        } else if abs(wind.gust) > abs(wind.base) {
            parts.append("swirling wind")
        } else if wind.gust > 0.4 {
            parts.append("gusty")
        } else {
            parts.append("breeze")
        }
        switch motion {
        case .still: break
        case .slide: parts.append("sliding")
        case .swing: parts.append("swinging")
        }
        if let timeLimit { parts.append("\(Int(timeLimit)) s") }
        return parts.joined(separator: " · ")
    }
}

/// The 30 hand-made levels. Each venue adds something: wind, gusts, a clock, a moving target,
/// a swinging target, small faces and longer distances, up to 90 metres at night.
public enum LevelCatalog {
    public static let levelsPerChapter = 6
    public static var count: Int { all.count }

    public static func level(_ number: Int) -> Level {
        all[min(max(number, 1), all.count) - 1]
    }

    private static func make(_ number: Int, _ name: String, distance: Double, layout: TargetLayout = .single(.full122),
                             arrows: Int, wind: Wind = .calm, motion: Motion = .still, sway: Double,
                             time: Double? = nil, stars: [Int], feature: String? = nil, tip: String) -> Level {
        Level(number: number, name: name,
              chapter: Chapter(rawValue: (number - 1) / levelsPerChapter + 1)!,
              distance: distance, layout: layout, arrows: arrows,
              wind: wind.shifted(by: Double(number) * 0.9), motion: motion, sway: sway, timeLimit: time,
              starScores: stars, feature: feature, tip: tip)
    }

    public static let all: [Level] = [
        // Practice Field, morning: learn to aim, hold and read a breeze.
        make(1, "First Arrows", distance: 10, arrows: 3, sway: 0.4, stars: [15, 21, 27],
             tip: "Touch and hold anywhere to draw. Slide to put the sight on the gold, then let go."),
        make(2, "Hold Steady", distance: 15, arrows: 3, sway: 1.0, stars: [18, 23, 27], feature: "Sway",
             tip: "The sight drifts. It settles just after full draw, then your arms tire, so don't hold too long."),
        make(3, "A Light Breeze", distance: 18, arrows: 3, wind: Wind(base: 1.4), sway: 1.0,
             stars: [22, 25, 27], feature: "Wind",
             tip: "Wind from the left carries arrows to the right. Aim a little into it, and watch the flag."),
        make(4, "Other Side", distance: 20, arrows: 3, wind: Wind(base: -1.8), sway: 1.0, stars: [22, 25, 27],
             tip: "Now it blows from the right. Aim right of the gold."),
        make(5, "Smaller Face", distance: 20, layout: .single(.full80), arrows: 4,
             wind: Wind(base: 1.2, gust: 0.6, period: 9), sway: 1.0, stars: [30, 34, 36], feature: "80 cm face",
             tip: "An 80 cm face: every ring is a third narrower."),
        make(6, "Three Spots", distance: 18, layout: .threeSpots(size: 0.6), arrows: 3,
             wind: Wind(base: -1.0), sway: 1.0, stars: [22, 25, 27], feature: "Three spots",
             tip: "One arrow in each spot. A second arrow in the same spot scores nothing."),

        // Meadow, midday: further, gustier, and the first clock and moving target.
        make(7, "Thirty Metres", distance: 30, arrows: 4, wind: Wind(base: 1.8), sway: 1.0, stars: [30, 34, 36],
             tip: "At 30 metres the same breeze carries an arrow much further."),
        make(8, "Gusts", distance: 30, arrows: 4, wind: Wind(base: 1.2, gust: 1.8, period: 7), sway: 1.0,
             stars: [30, 34, 36], feature: "Gusts",
             tip: "The wind comes and goes. Watch the flag and let go in a lull."),
        make(9, "Against the Clock", distance: 25, arrows: 3, wind: Wind(base: -1.3), sway: 1.0, time: 20,
             stars: [22, 25, 27], feature: "Time limit",
             tip: "Three arrows in 20 seconds. The clock starts when you first draw."),
        make(10, "On the Move", distance: 25, arrows: 3, motion: .slide(amplitude: 0.45, period: 6), sway: 1.0,
             stars: [22, 25, 27], feature: "Moving target",
             tip: "The target slides on a rail. Arrows take a moment to arrive, so aim ahead of it."),
        make(11, "Forty Metres", distance: 40, arrows: 4, wind: Wind(base: -1.8, gust: 1.2, period: 8),
             sway: 1.05, stars: [30, 34, 36],
             tip: "Forty metres with a gusty breeze from the right."),
        make(12, "Meadow Medal", distance: 40, layout: .single(.full80), arrows: 5,
             wind: Wind(base: 1.4, gust: 1.2, period: 8), sway: 1.05, stars: [36, 41, 45],
             tip: "The meadow final: five arrows at 40 metres on the small face."),

        // Lakeside, afternoon: swinging targets and wind that changes sides.
        make(13, "Across the Water", distance: 50, arrows: 4, wind: Wind(base: 2.0, gust: 1.0, period: 9),
             sway: 1.1, stars: [28, 33, 36],
             tip: "Fifty metres across the lake. The breeze off the water is steady but strong."),
        make(14, "The Swing", distance: 30, arrows: 3, motion: .swing(length: 1.4, angle: 0.32, period: 3.4),
             sway: 1.0, stars: [21, 25, 27], feature: "Swinging target",
             tip: "Hung on ropes, the target swings. It is slowest at the ends of each swing."),
        make(15, "Swirling", distance: 45, arrows: 4, wind: Wind(base: 0, gust: 3.0, period: 10), sway: 1.1,
             stars: [28, 33, 36], feature: "Swirling wind",
             tip: "The wind swings from one side to the other. Read the flag before every arrow."),
        make(16, "Gliding", distance: 35, arrows: 4, wind: Wind(base: 1.0),
             motion: .slide(amplitude: 0.55, period: 4.6), sway: 1.1, stars: [28, 33, 36],
             tip: "A faster rail, and a breeze from the left as well."),
        make(17, "Quick Five", distance: 45, arrows: 5, wind: Wind(base: -1.6, gust: 1.0, period: 8), sway: 1.1,
             time: 35, stars: [35, 41, 45],
             tip: "Five arrows in 35 seconds, with the wind from the right."),
        make(18, "Lakeside Medal", distance: 60, arrows: 5, wind: Wind(base: 2.4, gust: 1.4, period: 9),
             sway: 1.15, stars: [32, 40, 45],
             tip: "The lakeside final: 60 metres in a gusty breeze."),

        // Hilltop, sunset: long distances, small spots and stronger gusts.
        make(19, "Up the Hill", distance: 60, arrows: 4, wind: Wind(base: -2.8, gust: 0.8, period: 10),
             sway: 1.15, stars: [24, 31, 36],
             tip: "A strong breeze from the right. Trust your aim off."),
        make(20, "Evening Spots", distance: 20, layout: .threeSpots(size: 0.4), arrows: 3,
             wind: Wind(base: 1.2, gust: 0.9, period: 7), sway: 1.2, stars: [19, 24, 27],
             tip: "Small spots in gusty air, one arrow each."),
        make(21, "Long Swing", distance: 45, arrows: 4, wind: Wind(base: 1.2),
             motion: .swing(length: 1.6, angle: 0.3, period: 3.8), sway: 1.15, stars: [27, 32, 36],
             tip: "A swinging target at 45 metres, with a breeze to allow for too."),
        make(22, "Seventy", distance: 70, arrows: 5, wind: Wind(base: 2.2, gust: 1.6, period: 8), sway: 1.2,
             stars: [32, 38, 42],
             tip: "Seventy metres: the Olympic distance."),
        make(23, "Last Light", distance: 50, layout: .single(.full80), arrows: 4,
             wind: Wind(base: -1.8, gust: 1.8, period: 7), sway: 1.2, time: 30, stars: [25, 30, 33],
             tip: "Four arrows before the light goes: 30 seconds, small face."),
        make(24, "Hilltop Medal", distance: 70, arrows: 6, wind: Wind(base: -2.6, gust: 2.0, period: 9),
             sway: 1.25, stars: [36, 44, 49],
             tip: "The hilltop final: six arrows at 70 metres."),

        // Floodlights, night: everything at once, out to 90 metres.
        make(25, "Under the Lights", distance: 75, arrows: 4, wind: Wind(base: 1.8, gust: 1.3, period: 9),
             sway: 1.3, stars: [27, 32, 36],
             tip: "The championship field at 75 metres, under floodlights."),
        make(26, "Night Rail", distance: 65, arrows: 4, wind: Wind(base: -1.2, gust: 0.8, period: 9),
             motion: .slide(amplitude: 0.5, period: 5.2), sway: 1.25, stars: [27, 32, 36],
             tip: "A moving target at 65 metres. Lead it, and allow for the wind."),
        make(27, "Ninety", distance: 90, arrows: 4, wind: Wind(base: 1.8, gust: 0.8, period: 10), sway: 1.3,
             stars: [25, 32, 36], feature: "90 metres",
             tip: "Ninety metres, the longest distance. An arrow is in the air for a second and a half."),
        make(28, "Night Gusts", distance: 80, arrows: 5, wind: Wind(base: -2.2, gust: 2.4, period: 9), sway: 1.3,
             stars: [29, 33, 36],
             tip: "Strong gusts that can change sides. Wait for your moment."),
        make(29, "Pendulum", distance: 70, arrows: 4, wind: Wind(base: 1.4, gust: 1.4, period: 8),
             motion: .swing(length: 1.6, angle: 0.28, period: 4.2), sway: 1.3, stars: [23, 30, 34],
             tip: "A swinging target in the wind at 70 metres."),
        make(30, "Championship", distance: 90, arrows: 6, wind: Wind(base: 2.6, gust: 2.2, period: 9), sway: 1.4,
             time: 75, stars: [31, 38, 43],
             tip: "The final: six arrows at 90 metres in 75 seconds. Good luck."),
    ]
}
