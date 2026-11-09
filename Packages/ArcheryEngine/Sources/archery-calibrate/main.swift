import ArcheryEngine
import Foundation

// Plays every level many times with the expert and novice bots and prints how they score
// against each level's star thresholds. Used to tune `starScores` in Levels.swift.
//
//   swift run -c release archery-calibrate [attempts]

let attempts = CommandLine.arguments.dropFirst().first.flatMap { Int($0) } ?? 400

/// Per venue: the share of novices who should pass, and of experts who should earn three stars.
let novicePass = [0.97, 0.9, 0.8, 0.7, 0.6]
let expertThree = [0.9, 0.8, 0.7, 0.6, 0.5]
var suggestions: [String] = []

func percentile(_ sorted: [Int], _ p: Double) -> Int {
    sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
}

print("lvl  name                 max | expert p25 p50 p75  pass  3★ | novice p25 p50 p75  pass  3★ | stars")
for level in LevelCatalog.all {
    var line = String(format: "%3d  %-20@ %3d", level.number, level.name as NSString, level.maxScore)
    var sortedBySkill: [[Int]] = []
    for skill in [ArcherSkill.expert, .novice] {
        var scores: [Int] = []
        var passes = 0
        var threes = 0
        for attempt in 0..<attempts {
            var round = ArcheryRound(level: level, attempt: attempt)
            var archer = Archer(skill: skill, seed: UInt64(attempt * 7919 + level.number))
            archer.play(&round)
            scores.append(round.score)
            if round.passed { passes += 1 }
            if round.stars == 3 { threes += 1 }
        }
        scores.sort()
        sortedBySkill.append(scores)
        line += String(format: " |        %3d %3d %3d  %3d%% %3d%%", percentile(scores, 0.25), percentile(scores, 0.5),
                       percentile(scores, 0.75), passes * 100 / attempts, threes * 100 / attempts)
    }
    line += " | \(level.starScores.map(String.init).joined(separator: "/"))"
    print(line)
    // Suggested thresholds: one star where the target share of novices pass, three where the
    // target share of experts get there; never below an average of 4 an arrow, and three stars
    // never need every arrow in the ten.
    let venue = level.chapter.rawValue - 1
    let maximum = level.maxScore
    // The bots have learned the controls; a first-time player hasn't, so passing never asks for
    // more than three quarters of the maximum (seven tenths from the third venue on).
    let cap = maximum * (venue < 2 ? 75 : 70) / 100
    let one = min(cap, max(maximum * 4 / 10, percentile(sortedBySkill[1], 1 - novicePass[venue])))
    let three = max(one + 2, min(maximum * 9 / 10, percentile(sortedBySkill[0], 1 - expertThree[venue])))
    let two = max(one + 1, min(three - 1, Int((0.4 * Double(one) + 0.6 * Double(three)).rounded())))
    suggestions.append("\(level.number): [\(one), \(two), \(three)]")
}
print("suggested stars:")
print(suggestions.joined(separator: "  "))
