import ArcheryEngine
import PlayKit
import SwiftUI

/// Target archery, registered in the app's `GameRegistry`.
public struct ArcheryModule: GameModule {
    public init() {}

    public var id: String { "archery" }
    public var title: String { "Archery" }
    public var tagline: String { "Read the wind and find the gold, from 10 to 90 metres" }
    public var accent: Accent { .coral }

    @MainActor public func makeIcon() -> AnyView {
        AnyView(ArcheryIcon())
    }

    @MainActor public func makeGameView(context: GameContext) -> AnyView {
        AnyView(ArcheryScreen(context: context))
    }

    @MainActor public func makeSettingsSection(context: GameContext) -> AnyView? {
        AnyView(ArcherySettingsRows(preferences: context.preferences(ArcheryPreferences.self)))
    }

    @MainActor public func statusLine(context: GameContext) -> String? {
        guard let save = context.saveSlot.load(ArcherySave.self) else { return nil }
        return save.progress.statusLine(level: save.round.level.number)
    }
}

/// How far the sight moves for a slide of the thumb.
public enum AimSpeed: Int, CaseIterable {
    case slow, normal, fast

    public var title: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        }
    }

    /// Sight points moved per point the thumb slides. Below 1, so the thumb never has to cover
    /// the target and small corrections are easy.
    public var gain: Double {
        switch self {
        case .slow: return 0.3
        case .normal: return 0.45
        case .fast: return 0.65
        }
    }
}

/// Archery's own preferences, shared by the game screen and its settings rows.
@MainActor
public final class ArcheryPreferences: ObservableObject, GamePreferenceSet {
    private let store: GamePreferences

    @Published public var aimSpeed: AimSpeed {
        didSet { store.set(aimSpeed.rawValue, for: "aimSpeed") }
    }

    /// Much less sway, for shaky hands or a bumpy ride.
    @Published public var steadyAim: Bool {
        didSet { store.set(steadyAim, for: "steadyAim") }
    }

    /// Holds the bow in the right hand, so the bow appears on the other side of the sight.
    @Published public var leftHanded: Bool {
        didSet { store.set(leftHanded, for: "leftHanded") }
    }

    public init(preferences: GamePreferences) {
        store = preferences
        aimSpeed = AimSpeed(rawValue: preferences.int("aimSpeed", default: AimSpeed.normal.rawValue)) ?? .normal
        steadyAim = preferences.bool("steadyAim", default: false)
        leftHanded = preferences.bool("leftHanded", default: false)
    }

    /// Multiplier for the level's sway.
    public var swayStrength: Double { steadyAim ? 0.3 : 1 }
}

/// What is written to disk after every arrow.
public struct ArcherySave: Codable, Equatable {
    public var progress: LevelProgress
    /// The attempt in progress (or just finished).
    public var round: ArcheryRound
    /// Where the sight rests between arrows (target coordinates).
    public var aim: Vec2
    /// Seconds spent on this attempt, for statistics.
    public var elapsed: TimeInterval
    public var resultRecorded: Bool
}
