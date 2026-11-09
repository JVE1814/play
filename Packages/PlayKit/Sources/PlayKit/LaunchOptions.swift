import Foundation

/// Launch arguments understood by the app. They exist for UI tests and screenshots, and are
/// ignored in release builds so the shipping app always behaves normally.
public struct LaunchOptions: Equatable, Sendable {
    private var arguments: [String] = []

    public init() {}

    /// - Parameter arguments: the process's arguments, the program's own path first.
    public init(arguments: [String]) {
        #if DEBUG
        self.arguments = Array(arguments.dropFirst())
        #endif
    }

    public static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

    /// `-resetState`: wipe saved games, statistics and settings before launching.
    public var resetState: Bool { arguments.contains("-resetState") }
    /// `-includeTestGames`: add test-only games to the registry.
    public var includeTestGames: Bool { arguments.contains("-includeTestGames") }
    /// `-scenario NAME`: each game starts from the prepared position it knows by that name.
    public var scenario: String? { value(after: "-scenario") }
    /// `-forceAppearance light|dark`: override the colour scheme.
    public var forcedAppearance: Appearance? { value(after: "-forceAppearance").flatMap { Appearance(rawValue: $0) } }
    /// `-showBoardSignature`: expose a textual description of the game's state for tests.
    public var showBoardSignature: Bool { arguments.contains("-showBoardSignature") }
    /// `-disableAnimations`: skip animations to keep tests fast and deterministic.
    public var disableAnimations: Bool { arguments.contains("-disableAnimations") }

    /// The value that follows `flag`. Games read their own flags (such as `-seed 42`) with this.
    public func value(after flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }
}
