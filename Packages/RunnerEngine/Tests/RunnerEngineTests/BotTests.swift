import XCTest
@testable import RunnerEngine

/// Whole runs, played by bots: the course can always be run, and is neither trivial nor brutal.
final class BotTests: XCTestCase {
    func testEveryCourseCanBeRun() {
        for seed in 1...12 as ClosedRange<UInt64> {
            let run = RunnerBot.expert.play(Run(seed: seed), to: 3_000)
            XCTAssertEqual(run.status, .running, "seed \(seed) ended at \(Int(run.distance)) m, in \(String(describing: run.crashedInto))")
        }
    }

    func testStandingStillNeverGetsFar() {
        for seed in 1...30 as ClosedRange<UInt64> {
            var run = Run(seed: seed)
            while run.status == .running, run.distance < 1_500 { run.advance(by: 0.1) }
            XCTAssertEqual(run.status, .crashed, "seed \(seed)")
        }
    }

    func testANewcomerGetsStartedAndPracticeTakesThemFurther() {
        func median(_ bot: RunnerBot) -> Double {
            let metres = (1...30).map { bot.play(Run(seed: UInt64($0)), to: 4_000, seed: UInt64($0)).distance }.sorted()
            return metres[metres.count / 2]
        }
        let newcomer = median(.newcomer)
        let regular = median(.regular)
        XCTAssertGreaterThan(newcomer, 150, "the opening must not be brutal")
        XCTAssertLessThan(newcomer, 1_200, "nor the game a stroll")
        XCTAssertGreaterThan(regular, 1.5 * newcomer)
    }
}
