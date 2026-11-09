import RunnerEngine

/// Prepared runs for UI tests and screenshots, by `-scenario` name.
enum Scenarios {
    static func run(_ name: String?) -> Run? {
        switch name {
        case "runnerDeadEnd":
            // A few coins, then crates right across the pier: the run cannot last.
            return Run(obstacles: (0..<Body.lanes).map { Obstacle(.stack, lane: $0, position: 14) },
                       coins: [4, 6, 8].map { Coin(lane: Body.startLane, position: $0) })
        case "runnerShowcase":
            // Well into a run, at the top of a jump.
            var run = RunnerBot.expert.play(Run(seed: 3), to: 150)
            while !run.isAirborne || run.height < 0.9 {
                run = RunnerBot.expert.play(run, to: run.distance + 1)
            }
            return run
        case "runnerOver":
            // A run that ended a good way past the first goal.
            return RunnerBot.newcomer.play(Run(seed: 8), to: 5_000, seed: 8)
        default:
            return nil
        }
    }
}
