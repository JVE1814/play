import XCTest
@testable import BubbleEngine

final class GameTests: XCTestCase {
    let up = Point(0, -1)

    private func game(_ rows: [String], palette: [BubbleColor] = [.red, .yellow], shots: Int = 10,
                      current: BubbleColor? = nil, next: BubbleColor? = nil) -> BubbleGame {
        BubbleGame(grid: BubbleGrid(rows: rows), palette: palette, shotLimit: shots, par: 2, seed: 1,
                   current: current, next: next)
    }

    func testClearingTheBoardWinsWithStars() throws {
        var g = game(["...rr..."], current: .red, next: .red)
        let outcome = try XCTUnwrap(g.shoot(direction: up))
        XCTAssertEqual(outcome.result.popped.count, 3)
        XCTAssertEqual(g.status, .won)
        XCTAssertEqual(g.stars, 3)
        XCTAssertNil(g.shoot(direction: up), "no shots after the game ends")
    }

    func testStarsDependOnShotsUsed() {
        XCTAssertEqual(BubbleGame.stars(shotsUsed: 10, par: 10, shotLimit: 14), 3)
        XCTAssertEqual(BubbleGame.stars(shotsUsed: 12, par: 10, shotLimit: 14), 2)
        XCTAssertEqual(BubbleGame.stars(shotsUsed: 14, par: 10, shotLimit: 14), 1)
    }

    func testRunningOutOfShotsLoses() {
        var g = game(["yy......"], shots: 1, current: .red, next: .red)
        g.shoot(direction: up)
        XCTAssertEqual(g.status, .outOfShots)
        XCTAssertEqual(g.shotsLeft, 0)
        XCTAssertEqual(g.stars, 0)
    }

    func testABubbleInTheDeathRowLoses() {
        // A yellow column hangs down to row 11; a red landing under it ends up in row 12.
        let rows = (0..<12).map { $0 % 2 == 0 ? "....y..." : "...y...." }
        var g = game(rows, shots: 20, current: .red, next: .red)
        let outcome = g.shoot(direction: Point(-0.25, -1))
        XCTAssertEqual(outcome?.trace.cell.row, 12)
        XCTAssertEqual(g.status, .reachedLine)
    }

    func testTheQueueOnlyOffersColoursStillOnTheBoard() {
        var g = game(["yyyyyyyy"], palette: [.red, .yellow, .blue], shots: 50)
        for _ in 0..<20 {
            XCTAssertEqual(g.current, .yellow)
            XCTAssertEqual(g.next, .yellow)
            g.shoot(direction: Point(0.3, -1))
            if g.status != .playing { break }
        }
    }

    func testSwapExchangesTheTwoBubbles() {
        var g = game(["rryy...."], current: .red, next: .yellow)
        g.swap()
        XCTAssertEqual(g.current, .yellow)
        XCTAssertEqual(g.next, .red)
    }

    func testOnlyStonesAndBombsLeftStillGetBubbles() {
        // Straight up glances off the stone and settles beside the bomb.
        var g = game(["....B...", "....S..."], palette: [.blue], shots: 5)
        XCTAssertEqual(g.current, .blue)
        XCTAssertEqual(g.shoot(direction: up)?.result.exploded.count, 3)
        XCTAssertEqual(g.status, .won, "the bomb blast takes the stone with it")
    }

    func testAttemptsDealDifferentQueuesButTheSameBoard() {
        let level = LevelCatalog.level(120)
        let first = BubbleGame(level: level, attempt: 0)
        let again = BubbleGame(level: level, attempt: 0)
        XCTAssertEqual(first, again)
        var queues = Set<String>()
        for attempt in 0..<8 {
            var g = BubbleGame(level: level, attempt: attempt)
            XCTAssertEqual(g.grid, level.layout.grid)
            var queue = ""
            for _ in 0..<6 {
                queue.append(Bubble.color(g.current).code)
                g.swap(); g.swap()
                g.shoot(direction: Point(4, -1))
            }
            queues.insert(queue)
        }
        XCTAssertGreaterThan(queues.count, 1)
    }

    func testSavedGamesRestoreExactly() throws {
        var g = BubbleGame(level: LevelCatalog.level(77), attempt: 2)
        g.shoot(direction: Point(-1, -1))
        g.swap()
        g.shoot(direction: Point(1.5, -1))
        let data = try JSONEncoder().encode(g)
        var restored = try JSONDecoder().decode(BubbleGame.self, from: data)
        XCTAssertEqual(restored, g)
        XCTAssertEqual(restored.signature, g.signature)
        // The restored game continues identically, queue included.
        g.shoot(direction: Point(0.2, -1))
        restored.shoot(direction: Point(0.2, -1))
        XCTAssertEqual(restored, g)
    }

    func testTheBotClearsAHandBuiltBoard() {
        let g = game(["rryyrryy", "yyrryyrr"], shots: 100)
        XCTAssertNotNil(Bot.play(g))
    }
}
