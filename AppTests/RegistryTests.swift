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
        let games = GameRegistry.games(options: TestEnvironment.options(["-includeTestGames"]))
        XCTAssertEqual(games.map { $0.id }, ["klondike", "bubbles", "testgame"])
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

    func testEveryGameProvidesItsViews() {
        let env = TestEnvironment()
        let model = AppModel(options: TestEnvironment.options(["-includeTestGames"]), storage: env.storage,
                             defaults: env.defaults)
        for game in model.games {
            let context = model.context(for: game)
            XCTAssertTrue(context === model.context(for: game), "one context per game")
            _ = game.module.makeIcon()
            _ = game.module.makeGameView(context: context)
            XCTAssertFalse(game.module.title.isEmpty)
        }
    }
}
