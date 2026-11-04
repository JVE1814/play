import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    /// A fixed sRGB colour from a hex value such as `0x1DB37A`.
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: CGFloat(opacity)))
    }

    /// A colour that adapts to light and dark mode.
    public init(light: UInt32, dark: UInt32, opacity: Double = 1) {
        self.init(light: light, lightOpacity: opacity, dark: dark, darkOpacity: opacity)
    }

    /// A colour that adapts to light and dark mode, with separate opacities.
    public init(light: UInt32, lightOpacity: Double, dark: UInt32, darkOpacity: Double) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: CGFloat(darkOpacity))
                : UIColor(hex: light, alpha: CGFloat(lightOpacity))
        })
    }
}

/// Shared design tokens. Flat colour, generous space, no textures.
public enum Theme {
    // MARK: Neutral colours
    public static let background = Color(light: 0xF6F4EE, dark: 0x0F0F12)
    public static let surface = Color(light: 0xFFFFFF, dark: 0x1C1C21)
    public static let ink = Color(light: 0x17171C, dark: 0xF4F4F6)
    public static let inkSecondary = Color(light: 0x5D5C66, dark: 0xA3A3AE)
    public static let hairline = Color(light: 0x000000, lightOpacity: 0.10, dark: 0xFFFFFF, darkOpacity: 0.12)
    /// Hints, focus and the most important call to action. Identical in both modes.
    public static let highlight = Color(hex: 0xFFC531)
    public static let onHighlight = Color(hex: 0x2B2000)
    public static let danger = Color(light: 0xC81E3A, dark: 0xFF6B72)

    // MARK: Layout
    public enum Space {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    public enum Radius {
        public static let s: CGFloat = 8
        public static let m: CGFloat = 14
        public static let l: CGFloat = 22
        public static let xl: CGFloat = 28
    }

    /// Minimum touch target. Deliberately larger than Apple's 44 pt: the phone is on a moving train.
    public static let minTouchTarget: CGFloat = 52
}

/// Shared type scale. Every style is a Dynamic Type text style in SF Rounded.
public enum Typography {
    public static let display = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    public static let title = Font.system(.title2, design: .rounded).weight(.bold)
    public static let headline = Font.system(.headline, design: .rounded).weight(.bold)
    public static let body = Font.system(.body, design: .rounded)
    public static let label = Font.system(.subheadline, design: .rounded).weight(.semibold)
    public static let caption = Font.system(.caption, design: .rounded).weight(.medium)
    public static let numeric = Font.system(.headline, design: .rounded).weight(.bold).monospacedDigit()
}

/// A game's accent colour and the colours derived from it. Each game picks one.
public struct Accent {
    public let name: String
    /// Bold, saturated fill for tiles and primary buttons. Same in light and dark mode.
    public let fill: Color
    /// Text and icons drawn on `fill`.
    public let onFill: Color
    /// The accent as text or icons on the neutral background, contrast-tuned per mode.
    public let strong: Color
    /// The game table: the bold fill in light mode, a deep tint in dark mode.
    public let table: Color
    /// Text and icons drawn on `table`.
    public let onTable: Color
    /// Buttons and empty slots on the table.
    public let tableControl: Color
    /// A darker companion colour, for example card backs.
    public let deep: Color

    public init(name: String, fill: UInt32, onFill: UInt32, strongLight: UInt32, strongDark: UInt32,
                tableDark: UInt32, onTableDark: UInt32, deepLight: UInt32) {
        self.name = name
        self.fill = Color(hex: fill)
        self.onFill = Color(hex: onFill)
        self.strong = Color(light: strongLight, dark: strongDark)
        self.table = Color(light: fill, dark: tableDark)
        self.onTable = Color(light: onFill, dark: onTableDark)
        self.tableControl = Color(light: 0xFFFFFF, lightOpacity: 0.32, dark: 0xFFFFFF, darkOpacity: 0.10)
        self.deep = Color(light: deepLight, dark: fill)
    }

    public static let jade = Accent(name: "Jade", fill: 0x1DB37A, onFill: 0x062A1C, strongLight: 0x0A7A50,
                                    strongDark: 0x3EDC9A, tableDark: 0x0D2219, onTableDark: 0xEAF7F0, deepLight: 0x0A5A3C)
    public static let grape = Accent(name: "Grape", fill: 0x9B6BFF, onFill: 0x14062E, strongLight: 0x6A3FD9,
                                     strongDark: 0xB99AFF, tableDark: 0x1A1030, onTableDark: 0xF1EBFF, deepLight: 0x4B2AA8)
    public static let coral = Accent(name: "Coral", fill: 0xFF6B57, onFill: 0x3A0B05, strongLight: 0xB8321F,
                                     strongDark: 0xFF8A7A, tableDark: 0x2A1210, onTableDark: 0xFFEDEA, deepLight: 0x8C2416)
    public static let sun = Accent(name: "Sun", fill: 0xFFC531, onFill: 0x2B2000, strongLight: 0x8A6400,
                                   strongDark: 0xFFD666, tableDark: 0x2A2208, onTableDark: 0xFFF6DD, deepLight: 0x8A6400)
    public static let sky = Accent(name: "Sky", fill: 0x38A3FF, onFill: 0x04213D, strongLight: 0x0B62B3,
                                   strongDark: 0x7CC4FF, tableDark: 0x0B1B2C, onTableDark: 0xE7F3FF, deepLight: 0x0B4F8F)
}

private struct AccentKey: EnvironmentKey {
    static let defaultValue: Accent = .jade
}

extension EnvironmentValues {
    /// The accent of the game currently on screen.
    public var accent: Accent {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}
