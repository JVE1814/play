import Foundation

/// Launch arguments understood by the app. They exist for UI tests and screenshots, and are
/// ignored in release builds so the shipping app always behaves normally.
public struct LaunchOptions: Equatable, Sendable {
    /// `-resetState`: wipe saved games, statistics and settings before launching.
    public var resetState = false
    /// `-includeTestGames`: add test-only games to the registry.
    public var includeTestGames = false
    /// `-seed N`: deal number for the first new game.
    public var seed: UInt64?
    /// `-scenario NAME`: start from a prepared position (for example `nearWin`).
    public var scenario: String?
    /// `-forceAppearance light|dark`: override the colour scheme.
    public var forcedAppearance: Appearance?
    /// `-showBoardSignature`: expose a textual board description for tests.
    public var showBoardSignature = false
    /// `-disableAnimations`: skip animations to keep tests fast and deterministic.
    public var disableAnimations = false
    /// `-level N`: games with levels start (and unlock up to) level N.
    public var level: Int?
    /// `-demoAim X`: games with aiming show a fixed aim (X is a horizontal offset per unit up).
    public var demoAim: Double?

    public init() {}

    public init(arguments: [String]) {
        #if DEBUG
        func value(after flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        resetState = arguments.contains("-resetState")
        includeTestGames = arguments.contains("-includeTestGames")
        seed = value(after: "-seed").flatMap { UInt64($0) }
        scenario = value(after: "-scenario")
        forcedAppearance = value(after: "-forceAppearance").flatMap { Appearance(rawValue: $0) }
        showBoardSignature = arguments.contains("-showBoardSignature")
        disableAnimations = arguments.contains("-disableAnimations")
        level = value(after: "-level").flatMap { Int($0) }
        demoAim = value(after: "-demoAim").flatMap { Double($0) }
        #endif
    }

    public static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
}
