import SwiftUI

/// A game in progress, as the shared `GameScreen` sees it.
@MainActor
public protocol GameSession: ObservableObject {
    var context: GameContext { get }
    /// The whole state as text, shown to UI tests with `-showBoardSignature`.
    var signature: String { get }
    /// The result panel is up.
    var showsResult: Bool { get }
    /// The game came into view, or left it: the home screen, the background, or something
    /// covering it. Clocks run only while in view. May be called again with the same value.
    func setInView(_ inView: Bool)
}

extension GameSession {
    /// Back to the home screen. The session hears it has left view first, so what it saves is
    /// there for the home screen's tile.
    public func leave() {
        setInView(false)
        context.exit()
    }
}

/// A stopwatch for time spent playing. It runs only while told to.
public struct PlayClock {
    private var banked: TimeInterval
    private var runningSince: Date?

    public init(elapsed: TimeInterval = 0) {
        banked = elapsed
    }

    /// True once the clock has ever run.
    public var hasStarted: Bool { banked > 0 || runningSince != nil }

    public func elapsed(at date: Date = Date()) -> TimeInterval {
        banked + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    public mutating func setRunning(_ running: Bool, at date: Date = Date()) {
        if running, runningSince == nil {
            runningSince = date
        } else if !running, runningSince != nil {
            banked = elapsed(at: date)
            runningSince = nil
        }
    }
}

/// One action waiting to happen. Scheduling another replaces it.
@MainActor
public final class Pending {
    private var task: Task<Void, Never>?

    public init() {}

    /// Runs `action` after `seconds`, or at once when `seconds` is zero.
    public func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        cancel()
        guard seconds > 0 else {
            action()
            return
        }
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}
