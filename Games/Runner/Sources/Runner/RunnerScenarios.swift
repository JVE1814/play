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
        case "runnerProbe":
            return probeCourse
        default:
            return nil
        }
    }

    /// A busy course that never ends a run left in the middle lane: something in both outer
    /// lanes every few metres, a line of coins down the middle, the magnet and then the shield.
    /// For measuring how smoothly the pier is drawn (`-frameProbe`).
    static var probeCourse: Run {
        let kinds: [(Obstacle.Kind, Double?)] = [(.barrier, nil), (.beam, nil), (.stack, nil), (.stack, 8), (.barrel, nil)]
        var obstacles: [Obstacle] = []
        var position = 24.0
        var index = 0
        while position < 600 {
            for lane in [0, 2] {
                let (kind, length) = kinds[(index + lane) % kinds.count]
                if kind == .barrel {
                    obstacles.append(Obstacle(.barrel, lane: lane, position: position, rollSpeed: 4, meetTime: position / Pace.speed(at: position)))
                } else {
                    obstacles.append(Obstacle(kind, lane: lane, position: position, length: length))
                }
            }
            position += 9
            index += 1
        }
        let coins = Swift.stride(from: 10.0, to: 600, by: 1.7).map { Coin(lane: 1, position: $0) }
        return Run(obstacles: obstacles, coins: coins,
                   pickups: [Pickup(kind: .magnet, lane: 1, position: 20), Pickup(kind: .shield, lane: 1, position: 60)])
    }
}
