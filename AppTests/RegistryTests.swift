@testable import BetweenStops
import PlayKit
import XCTest

@MainActor
final class RegistryTests: XCTestCase {
    func testSolitaireIsListedAndIdsAreUnique() {
        let games = GameRegistry.games(options: LaunchOptions())
        XCTAssertEqual(games.first?.id, "klondike")
        XCTAssertEqual(Set(games.map { $0.id }).count, games.count)
        XCTAssertFalse(games.contains { $0.id == "testgame" }, "test game hidden unless requested")
    }

    func testTestGameIsAddedOnlyWhenRequested() {
        let shipped = GameRegistry.games(options: LaunchOptions())
        let games = GameRegistry.games(options: TestEnvironment.options(["-includeTestGames"]))
        XCTAssertEqual(games.map { $0.id }, shipped.map { $0.id } + ["testgame"])
    }

    func testAppModelReopensTheLastGame() {
        let env = TestEnvironment()
        let model = AppModel(options: LaunchOptions(), storage: env.storage, defaults: env.defaults)
        XCTAssertNil(model.openGameID)
        model.open(model.games[0])
        let relaunched = AppModel(options: LaunchOptions(), storage: env.storage, defaults: env.defaults)
        XCTAssertEqual(relaunched.openGameID, "klondike")
        relaunched.closeGame()
        XCTAssertNil(AppModel(options: LaunchOptions(), storage: env.storage, defaults: env.defaults).openGameID)
    }

    func testOpeningSettingsTellsTheGamesTheyAreCovered() {
        let env = TestEnvironment()
        let model = AppModel(options: LaunchOptions(), storage: env.storage, defaults: env.defaults)
        let context = model.context(for: model.games[0])
        XCTAssertFalse(context.isCovered)
        model.showingSettings = true
        XCTAssertTrue(context.isCovered)
        model.showingSettings = false
        XCTAssertFalse(context.isCovered)
    }

    func testEachGameHasOneContext() {
        let env = TestEnvironment()
        let model = AppModel(options: LaunchOptions(), storage: env.storage, defaults: env.defaults)
        for game in model.games {
            XCTAssertTrue(model.context(for: game) === model.context(for: game), game.id)
        }
        XCTAssertFalse(model.context(for: model.games[0]) === model.context(for: model.games[1]))
    }
}
