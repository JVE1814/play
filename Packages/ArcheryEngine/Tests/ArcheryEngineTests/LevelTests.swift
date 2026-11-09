import XCTest
@testable import ArcheryEngine

final class LevelTests: XCTestCase {
    let levels = LevelCatalog.all

    func testThereAreThirtyLevelsInFiveVenues() {
        XCTAssertEqual(levels.count, 30)
        XCTAssertEqual(levels.map(\.number), Array(1...30))
        XCTAssertEqual(Set(levels.map(\.name)).count, 30, "every level has its own name")
        for chapter in Chapter.allCases {
            let inChapter = levels.filter { $0.chapter == chapter }
            XCTAssertEqual(inChapter.map(\.number), Array(chapter.levels))
        }
        XCTAssertEqual(LevelCatalog.level(0).number, 1)
        XCTAssertEqual(LevelCatalog.level(31).number, 30)
    }

    func testEveryLevelIsWellFormed() {
        for level in levels {
            XCTAssertTrue((3...6).contains(level.arrows), "level \(level.number)")
            XCTAssertEqual(level.starScores.count, 3)
            XCTAssertEqual(level.starScores, level.starScores.sorted(), "level \(level.number)")
            XCTAssertEqual(Set(level.starScores).count, 3, "level \(level.number)")
            XCTAssertLessThanOrEqual(level.starScores[2], level.maxScore * 9 / 10, "three stars never need all tens")
            XCTAssertGreaterThanOrEqual(level.starScores[0], level.maxScore * 4 / 10, "level \(level.number)")
            XCTAssertFalse(level.tip.isEmpty)
            XCTAssertTrue((10...90).contains(level.distance))
            if let limit = level.timeLimit {
                XCTAssertGreaterThanOrEqual(limit, Double(level.arrows) * 6, "time enough to read the wind")
            }
            XCTAssertLessThanOrEqual(level.layout.largestFace.radius, level.layout.bossSize / 2)
        }
    }

    func testTheGameGetsHarderVenueByVenue() {
        let longest = Chapter.allCases.map { chapter in levels.filter { $0.chapter == chapter }.map(\.distance).max()! }
        XCTAssertEqual(longest, longest.sorted())
        XCTAssertEqual(longest.last, 90)
        let windiest = Chapter.allCases.map { chapter in
            levels.filter { $0.chapter == chapter }.map(\.wind.strongest).max()!
        }
        XCTAssertEqual(windiest, windiest.sorted())
        let nerves = Chapter.allCases.map { chapter in levels.filter { $0.chapter == chapter }.map(\.sway).max()! }
        XCTAssertEqual(nerves, nerves.sorted())
        XCTAssertTrue(levels.prefix(2).allSatisfy(\.wind.isCalm), "the first levels are calm")
    }

    func testEachNewIdeaIsIntroducedOnItsOwn() {
        let firstWind = levels.first { !$0.wind.isCalm }!
        XCTAssertEqual(firstWind.feature, "Wind")
        XCTAssertEqual(levels.first { $0.wind.gust > 0.9 }?.feature, "Gusts")
        XCTAssertEqual(levels.first { $0.timeLimit != nil }?.feature, "Time limit")
        let firstMoving = levels.first { $0.motion.isMoving }!
        XCTAssertEqual(firstMoving.feature, "Moving target")
        XCTAssertTrue(firstMoving.wind.isCalm, "the first moving target has no wind to think about")
        XCTAssertEqual(levels.first { if case .swing = $0.motion { return true } else { return false } }?.feature,
                       "Swinging target")
        XCTAssertEqual(levels.first { $0.layout.onePerSpot }?.feature, "Three spots")
    }

    func testSummariesDescribeTheConditions() {
        XCTAssertEqual(LevelCatalog.level(1).summary, "10 m · 122 cm face · calm")
        XCTAssertEqual(LevelCatalog.level(6).summary, "18 m · 3 spots · breeze")
        XCTAssertEqual(LevelCatalog.level(9).summary, "25 m · 122 cm face · breeze · 20 s")
        XCTAssertEqual(LevelCatalog.level(15).summary, "45 m · 122 cm face · swirling wind")
        XCTAssertEqual(LevelCatalog.level(29).summary, "70 m · 122 cm face · gusty · swinging")
    }

    // MARK: Played by the bots

    private func results(_ level: Level, _ skill: ArcherSkill, attempts: Int) -> (scores: [Int], pass: Double, three: Double) {
        var scores: [Int] = []
        var passes = 0
        var threes = 0
        for attempt in 0..<attempts {
            var round = ArcheryRound(level: level, attempt: attempt)
            var archer = Archer(skill: skill, seed: UInt64(attempt * 104_729 + level.number))
            archer.play(&round)
            XCTAssertEqual(round.status, .finished)
            scores.append(round.score)
            if round.passed { passes += 1 }
            if round.stars == 3 { threes += 1 }
        }
        return (scores, Double(passes) / Double(attempts), Double(threes) / Double(attempts))
    }

    func testAnExpertPassesEveryLevel() {
        for level in levels {
            let expert = results(level, .expert, attempts: 150)
            XCTAssertGreaterThanOrEqual(expert.pass, 0.9, "level \(level.number) \(level.name)")
            XCTAssertGreaterThanOrEqual(expert.three, 0.35, "three stars are within an expert's reach on level \(level.number)")
        }
    }

    func testStarsAreHardEarnedAndTheVenuesGetHarder() {
        var passByChapter: [Double] = []
        var expertThreeByChapter: [Double] = []
        for chapter in Chapter.allCases {
            var novicePass = 0.0
            var expertThree = 0.0
            for level in levels where level.chapter == chapter {
                let novice = results(level, .novice, attempts: 150)
                let expert = results(level, .expert, attempts: 150)
                novicePass += novice.pass
                expertThree += expert.three
                XCTAssertGreaterThanOrEqual(novice.pass, 0.5, "a newcomer can pass level \(level.number) with a few tries")
                XCTAssertLessThanOrEqual(novice.three, expert.three + 0.02, "level \(level.number)")
                if level.number > 10 {
                    XCTAssertLessThanOrEqual(novice.three, 0.4, "three stars mean something on level \(level.number)")
                }
            }
            passByChapter.append(novicePass / 6)
            expertThreeByChapter.append(expertThree / 6)
        }
        XCTAssertGreaterThanOrEqual(passByChapter[0], 0.95, "the practice field is for everyone")
        XCTAssertEqual(passByChapter, passByChapter.sorted(by: >), "each venue is harder to pass than the last")
        XCTAssertGreaterThan(expertThreeByChapter[0], expertThreeByChapter[4])
    }

    func testABotThatIgnoresTheWindStrugglesLater() {
        let stubborn = ArcherSkill(name: "stubborn", aimError: 2, windAllowance: 0, windLearning: 0, windError: 0,
                                   leading: 0, leadError: 0, swayControl: 0.3, patient: true, pace: 1...2)
        let early = results(LevelCatalog.level(3), stubborn, attempts: 60)
        let late = results(LevelCatalog.level(27), stubborn, attempts: 60)
        XCTAssertGreaterThan(early.pass, 0.9)
        XCTAssertLessThan(late.pass, 0.2, "at 90 m you have to aim off for the wind")
    }
}
