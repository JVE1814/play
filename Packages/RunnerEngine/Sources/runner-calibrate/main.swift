import Foundation
import RunnerEngine

// Runs many courses with bots of different skill and prints how far they get. Used to tune
// `Pace` and the chances in `CourseBuilder`.
//
//   swift run -c release runner-calibrate [courses]

let courses = CommandLine.arguments.dropFirst().first.flatMap { Int($0) } ?? 60
let limit = 6_000.0

func percentile(_ sorted: [Int], _ p: Double) -> Int {
    sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
}

print("bot        p10    p25    p50    p75    p90   seconds at p50")
for (name, bot) in [("newcomer", RunnerBot.newcomer), ("regular", .regular), ("expert", .expert)] {
    let runs = (1...courses).map { bot.play(Run(seed: UInt64($0)), to: limit, seed: UInt64($0)) }
    let metres = runs.map { Int($0.distance) }.sorted()
    let seconds = runs.map { Int($0.time) }.sorted()
    print(String(format: "%-8@ %5d  %5d  %5d  %5d  %5d   %d", name as NSString, percentile(metres, 0.1),
                 percentile(metres, 0.25), percentile(metres, 0.5), percentile(metres, 0.75),
                 percentile(metres, 0.9), percentile(seconds, 0.5)))
}
