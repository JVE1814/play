import Foundation
import MinesEngine

// Generates many boards for each difficulty and kind of first tap, and prints how often a
// random layout is fair, how many layouts a board takes, how long it takes to make, which
// rules clearing it needs, and how much the first tap opens. Used to set the difficulties.
//
//   swift run -c release mines-calibrate [boards]

let boards = CommandLine.arguments.dropFirst().first.flatMap { Int($0) } ?? 2_000

let taps: [(name: String, cell: (UInt64) -> Int)] = [
    ("corner", { _ in MinesGrid.index(row: 0, column: 0) }),
    ("edge", { _ in MinesGrid.index(row: 5, column: 0) }),
    ("centre", { _ in MinesGrid.index(row: 5, column: 3) }),
    ("random", { seed in Int(seed % UInt64(MinesGrid.cellCount)) }),
]

func percentile<T>(_ sorted: [T], _ p: Double) -> T {
    sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
}

func now() -> Double { ProcessInfo.processInfo.systemUptime }

func pad(_ text: String, _ width: Int) -> String { text.padding(toLength: width, withPad: " ", startingAt: 0) }

print("difficulty tap     fair%  layouts p50/p99/max  fallback  ms p50/p99/max      needs count/pairs  first opening p50")
for difficulty in Difficulty.allCases {
    for tap in taps {
        var attempts: [Int] = [], times: [Double] = [], openings: [Int] = []
        var fallbacks = 0, needCount = 0, needPairs = 0
        for board in 1...boards {
            let seed = UInt64(board)
            let cell = tap.cell(seed)
            let start = now()
            let (field, report) = MinesGenerator.generate(seed: seed, difficulty: difficulty, firstTap: cell)
            times.append((now() - start) * 1000)
            attempts.append(report.attempts)
            if report.usedFallback { fallbacks += 1 }
            let rules = MinesSolver(reasoning: difficulty.reasoning).solve(field, firstTap: cell).rules
            if rules.count > 0 { needCount += 1 }
            if rules.pairs > 0 { needPairs += 1 }
            openings.append(field.flood(from: cell).count)
        }
        let fair = 100 * Double(boards) / Double(attempts.reduce(0, +))
        attempts.sort(); times.sort(); openings.sort()
        print(pad(difficulty.name, 11) + pad(tap.name, 8) + String(format: "%5.1f  %4d %4d %4d       %4d     %5.2f %5.2f %6.2f      %4.0f%% %4.0f%%     %d of %d",
                     fair,
                     percentile(attempts, 0.5), percentile(attempts, 0.99), attempts.last ?? 0, fallbacks,
                     percentile(times, 0.5), percentile(times, 0.99), times.last ?? 0,
                     100 * Double(needCount) / Double(boards), 100 * Double(needPairs) / Double(boards),
                     percentile(openings, 0.5), MinesGrid.cellCount - difficulty.mineCount))
    }
}

// How fair random layouts are at the other reasoning, to see what moving a difficulty would do.
print("")
print("difficulty reasoning  fair% (random first taps)")
for difficulty in Difficulty.allCases {
    for reasoning in [MinesSolver.Reasoning.single, .pairs] where reasoning != difficulty.reasoning {
        var total = 0
        for board in 1...boards {
            let seed = UInt64(board)
            total += MinesGenerator.generate(seed: seed, difficulty: difficulty,
                                             firstTap: Int(seed % UInt64(MinesGrid.cellCount)),
                                             reasoning: reasoning).report.attempts
        }
        print(pad(difficulty.name, 11) + pad(reasoning == .single ? "single" : "pairs", 11)
              + String(format: "%5.1f", 100 * Double(boards) / Double(total)))
    }
}
