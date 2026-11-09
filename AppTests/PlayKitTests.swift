import PlayKit
import XCTest

@MainActor
final class PlayKitTests: XCTestCase {
    func testWinsLossesStreaksAndBestTime() {
        var stats = GameStats()
        XCTAssertEqual(stats.winRate, 0)
        stats.recordWin(time: 300)
        stats.recordWin(time: 240)
        XCTAssertEqual(stats.currentStreak, 2)
        stats.recordLoss()
        stats.recordWin(time: 500)
        XCTAssertEqual(stats.played, 4)
        XCTAssertEqual(stats.won, 3)
        XCTAssertEqual(stats.lost, 1)
        XCTAssertEqual(stats.winRate, 0.75)
        XCTAssertEqual(stats.currentStreak, 1)
        XCTAssertEqual(stats.bestStreak, 2)
        XCTAssertEqual(stats.bestTime, 240)
    }

    func testStatsAreKeptPerGameAndPersisted() {
        let env = TestEnvironment()
        env.stats.recordWin(gameID: "a", time: 100)
        env.stats.recordLoss(gameID: "b")
        let reloaded = StatsStore(storage: env.storage)
        XCTAssertEqual(reloaded.stats(for: "a").won, 1)
        XCTAssertEqual(reloaded.stats(for: "b").played, 1)
        XCTAssertEqual(reloaded.stats(for: "b").won, 0)
        XCTAssertEqual(reloaded.stats(for: "c"), GameStats())
        reloaded.reset(gameID: "a")
        XCTAssertEqual(StatsStore(storage: env.storage).stats(for: "a"), GameStats())
    }

    func testEachGameHasItsOwnSaveSlot() {
        struct Sample: Codable, Equatable { var value: Int }
        let env = TestEnvironment()
        let slot = SaveSlot(storage: env.storage, gameID: "sample")
        XCTAssertNil(slot.load(Sample.self))
        slot.save(Sample(value: 7))
        XCTAssertEqual(SaveSlot(storage: env.storage, gameID: "sample").load(Sample.self), Sample(value: 7))
        XCTAssertNil(SaveSlot(storage: env.storage, gameID: "other").load(Sample.self))
    }

    func testLevelProgressKeepsTheBestAndUnlocksTheNextLevelOnAStar() {
        var progress = LevelProgress()
        XCTAssertTrue(progress.isUnlocked(1))
        XCTAssertFalse(progress.isUnlocked(2))
        progress.record(level: 1, stars: 0, score: 12, of: 30)
        XCTAssertEqual(progress.bestScore(for: 1), 12)
        XCTAssertFalse(progress.isUnlocked(2), "a score without a star doesn't unlock the next level")
        progress.record(level: 1, stars: 2, score: 26, of: 30)
        progress.record(level: 1, stars: 1, score: 20, of: 30)
        XCTAssertEqual(progress.stars(for: 1), 2, "the best result is kept")
        XCTAssertEqual(progress.bestScore(for: 1), 26)
        XCTAssertEqual(progress.unlocked, 2)
        progress.record(level: 2, stars: 3, of: 30)
        XCTAssertEqual(progress.totalStars, 5)
        XCTAssertNil(progress.bestScore(for: 2), "a game that keeps no scores has none")
        progress.record(level: 30, stars: 3, of: 30)
        XCTAssertEqual(progress.unlocked, 30, "never beyond the last level")
    }

    /// Saves written before level progress was shared have no best scores.
    func testLevelProgressReadsASaveWithoutBestScores() throws {
        let old = Data(#"{"unlocked":3,"stars":[3,1]}"#.utf8)
        let progress = try JSONDecoder().decode(LevelProgress.self, from: old)
        XCTAssertEqual(progress.unlocked, 3)
        XCTAssertEqual(progress.stars(for: 2), 1)
        XCTAssertNil(progress.bestScore(for: 1))
    }

    func testOpenGameIsRemembered() {
        let env = TestEnvironment()
        XCTAssertNil(AppStateStore(storage: env.storage).openGameID)
        AppStateStore(storage: env.storage).openGameID = "klondike"
        XCTAssertEqual(AppStateStore(storage: env.storage).openGameID, "klondike")
    }

    func testWipeRemovesEverything() {
        let env = TestEnvironment()
        env.stats.recordLoss(gameID: "a")
        SaveSlot(storage: env.storage, gameID: "a").save(1)
        env.storage.wipe()
        XCTAssertNil(SaveSlot(storage: env.storage, gameID: "a").load(Int.self))
        XCTAssertEqual(StatsStore(storage: env.storage).stats(for: "a"), GameStats())
    }

    func testSoundIsOffAndHapticsOnByDefault() {
        let env = TestEnvironment()
        XCTAssertFalse(env.settings.soundEnabled)
        XCTAssertTrue(env.settings.hapticsEnabled)
        XCTAssertEqual(env.settings.appearance, .system)
        env.settings.soundEnabled = true
        env.settings.appearance = .dark
        let reloaded = AppSettings(defaults: env.defaults)
        XCTAssertTrue(reloaded.soundEnabled)
        XCTAssertEqual(reloaded.appearance, .dark)
    }

    func testGamePreferencesAreNamespaced() {
        let env = TestEnvironment()
        let a = GamePreferences(gameID: "a", defaults: env.defaults)
        let b = GamePreferences(gameID: "b", defaults: env.defaults)
        a.set(3, for: "draw")
        XCTAssertEqual(a.int("draw", default: 1), 3)
        XCTAssertEqual(b.int("draw", default: 1), 1)
    }

    func testEveryFeedbackEventHasASound() {
        for event in FeedbackEvent.allCases {
            XCTAssertNotNil(Feedback.soundURL(for: event), "\(event) has a sound")
        }
    }

    func testLaunchOptionsParsing() {
        let options = TestEnvironment.options(["-resetState", "-seed", "42", "-scenario", "nearWin",
                                               "-forceAppearance", "dark", "-includeTestGames"])
        XCTAssertTrue(options.resetState)
        XCTAssertEqual(options.value(after: "-seed"), "42")
        XCTAssertEqual(options.scenario, "nearWin")
        XCTAssertEqual(options.forcedAppearance, .dark)
        XCTAssertTrue(options.includeTestGames)
        XCTAssertEqual(LaunchOptions(arguments: ["app"]), LaunchOptions())
    }

    func testFormatting() {
        XCTAssertEqual(Format.clock(7), "0:07")
        XCTAssertEqual(Format.clock(754), "12:34")
        XCTAssertEqual(Format.clock(3723), "1:02:03")
        XCTAssertEqual(Format.spokenDuration(65), "1 minute 5 seconds")
        XCTAssertEqual(Format.percent(0.426), "43%")
    }
}
