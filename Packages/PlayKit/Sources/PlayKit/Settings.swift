import SwiftUI

public enum Appearance: String, CaseIterable, Codable, Sendable, Identifiable {
    case system, light, dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "Automatic"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Sound is off and light haptics are on by default.
@MainActor
public final class AppSettings: ObservableObject {
    private static let prefix = "settings."
    private static let soundKey = prefix + "sound"
    private static let hapticsKey = prefix + "haptics"
    private static let appearanceKey = prefix + "appearance"

    private let defaults: UserDefaults

    @Published public var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Self.soundKey) }
    }

    @Published public var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Self.hapticsKey) }
    }

    @Published public var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        soundEnabled = defaults.object(forKey: Self.soundKey) as? Bool ?? false
        hapticsEnabled = defaults.object(forKey: Self.hapticsKey) as? Bool ?? true
        appearance = defaults.string(forKey: Self.appearanceKey).flatMap(Appearance.init(rawValue:)) ?? .system
    }

    /// Forgets every setting and every game's preferences (for `-resetState`).
    public static func eraseAll(in defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(prefix) || key.hasPrefix(GamePreferences.prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Key–value preferences namespaced to one game (stored in UserDefaults).
public struct GamePreferences {
    static let prefix = "game."
    private let gameID: String
    private let defaults: UserDefaults

    public init(gameID: String, defaults: UserDefaults) {
        self.gameID = gameID
        self.defaults = defaults
    }

    private func key(_ name: String) -> String { "\(Self.prefix)\(gameID).\(name)" }

    public func bool(_ name: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key(name)) as? Bool ?? fallback
    }

    public func int(_ name: String, default fallback: Int) -> Int {
        defaults.object(forKey: key(name)) as? Int ?? fallback
    }

    public func set(_ value: Bool, for name: String) { defaults.set(value, forKey: key(name)) }
    public func set(_ value: Int, for name: String) { defaults.set(value, forKey: key(name)) }
}
