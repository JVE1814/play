import PlayKit
import RunnerEngine
import SwiftUI

/// Runner: an endless run down a pier, registered in the app's `GameRegistry`.
public struct RunnerModule: GameModule {
    public init() {}

    public var id: String { "runner" }
    public var title: String { "Runner" }
    public var tagline: String { "Dodge, jump and slide down an endless pier" }
    public var accent: Accent { .grape }

    @MainActor public func makeIcon() -> AnyView {
        AnyView(RunnerIcon())
    }

    @MainActor public func makeGameView(context: GameContext) -> AnyView {
        AnyView(RunnerScreen(context: context))
    }

    @MainActor public func statusLine(context: GameContext) -> String? {
        guard let save = context.saveSlot.load(RunnerSave.self) else { return nil }
        if save.isInProgress { return "Resume · \(save.run.score.formatted()) points" }
        guard save.best > 0 else { return nil }
        return "Best \(save.best.formatted()) · goal \(Goals.next(after: save.best).formatted())"
    }
}

/// What is written to disk: every couple of seconds while running, and whenever the run stops.
public struct RunnerSave: Codable, Equatable {
    public var run: Run
    /// The best score of any finished run.
    public var best: Int
    /// The score this run has to reach to count as a win.
    public var goal: Int
    /// How many runs this install has started (used to vary seeded test courses).
    public var runsStarted: Int
    /// The runner has left the start line.
    public var isUnderWay: Bool
    /// Whether this run's result is already in the statistics.
    public var resultRecorded: Bool

    public init(run: Run, best: Int, goal: Int, runsStarted: Int, isUnderWay: Bool, resultRecorded: Bool) {
        self.run = run
        self.best = best
        self.goal = goal
        self.runsStarted = runsStarted
        self.isUnderWay = isUnderWay
        self.resultRecorded = resultRecorded
    }

    public var isInProgress: Bool { isUnderWay && !resultRecorded }
}
