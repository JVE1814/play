import KlondikeEngine
import PlayKit
import Solitaire
import XCTest

@MainActor
final class SolitaireTests: XCTestCase {
    private func session(_ env: TestEnvironment, _ arguments: [String] = ["-seed", "42"]) -> SolitaireSession {
        let session = SolitaireSession(context: env.context(for: SolitaireModule(), arguments: arguments))
        session.setInView(true)
        return session
    }

    func testFirstDealFollowsTheSeed() {
        let env = TestEnvironment()
        XCTAssertEqual(session(env).game.board, KlondikeGame(seed: 42).board)
    }

    func testEveryMoveIsSavedSoARelaunchRestoresTheExactBoard() {
        let env = TestEnvironment()
        let first = session(env)
        first.tapPile(.stock)
        first.tapPile(.stock)
        if let top = first.game.waste.last { first.tap(top) }
        XCTAssertGreaterThanOrEqual(first.game.moveCount, 2)
        // A brand-new session on the same storage is what the app sees after a force quit.
        let relaunched = session(env, [])
        XCTAssertEqual(relaunched.game, first.game)
        XCTAssertEqual(relaunched.signature, first.signature)
    }

    func testTapPlaysTheBestMove() {
        let env = TestEnvironment()
        let s = session(env, ["-seed", "4"])
        s.tap(Card(6, .diamonds))
        XCTAssertEqual(s.game.tableau[0].visible.last, Card(6, .diamonds))
        XCTAssertEqual(s.game.moveCount, 1)
    }

    func testTapWithNoMoveChangesNothing() {
        let env = TestEnvironment()
        let s = session(env, ["-seed", "4"])
        let before = s.game
        let stuck = s.game.tableau.compactMap(\.top).first { s.game.bestMove(tapping: $0) == nil }!
        s.tap(stuck)
        XCTAssertEqual(s.game, before)
        XCTAssertEqual(s.rejections[stuck], 1)
    }

    func testDropOnlyAcceptsLegalMoves() {
        let env = TestEnvironment()
        let s = session(env, ["-seed", "6"])
        XCTAssertFalse(s.drop(from: .tableau(4), count: 1, onto: .tableau(0)))
        XCTAssertTrue(s.drop(from: .tableau(4), count: 1, onto: .tableau(3)))
        XCTAssertEqual(s.game.tableau[3].visible.last, Card(9, .diamonds))
    }

    func testUndoRestoresThePreviousBoard() {
        let env = TestEnvironment()
        let s = session(env)
        let deal = s.game.board
        s.tapPile(.stock)
        XCTAssertTrue(s.canUndo)
        s.undo()
        XCTAssertEqual(s.game.board, deal)
        XCTAssertFalse(s.canUndo)
    }

    func testNewGameAfterPlayingCountsAsALoss() {
        let env = TestEnvironment()
        let s = session(env)
        s.requestNewGame()
        XCTAssertFalse(s.confirmingNewGame, "nothing played yet, no confirmation needed")
        XCTAssertEqual(env.stats.stats(for: "klondike").played, 0)
        s.tapPile(.stock)
        s.requestNewGame()
        XCTAssertTrue(s.confirmingNewGame)
        s.startNewGame()
        let stats = env.stats.stats(for: "klondike")
        XCTAssertEqual(stats.played, 1)
        XCTAssertEqual(stats.won, 0)
        XCTAssertEqual(s.game.moveCount, 0)
    }

    func testWinningRecordsStatsOnceAndShowsTheWinScreen() {
        let env = TestEnvironment()
        let s = session(env, ["-scenario", "nearWin", "-seed", "3"])
        s.tapPile(.stock)
        s.tap(Card(12, .diamonds))
        XCTAssertTrue(s.canAutoFinish)
        while !s.game.isWon, let move = s.game.autoFinishMoves()?.first {
            if case let .transfer(from, to, count) = move { s.drop(from: from, count: count, onto: to) } else { s.tapPile(.stock) }
        }
        XCTAssertTrue(s.game.isWon)
        XCTAssertTrue(s.showsResult)
        XCTAssertFalse(s.canUndo, "a won game is final")
        var stats = env.stats.stats(for: "klondike")
        XCTAssertEqual(stats.won, 1)
        XCTAssertEqual(stats.currentStreak, 1)
        XCTAssertNotNil(stats.bestTime)
        s.startNewGame()
        stats = env.stats.stats(for: "klondike")
        XCTAssertEqual(stats.played, 1, "starting a new deal after a win is not a loss")
        XCTAssertFalse(s.showsResult)
    }

    func testDrawThreeAppliesFromTheNextDeal() {
        let env = TestEnvironment()
        let s = session(env)
        s.preferences.drawMode = .three
        XCTAssertEqual(s.game.drawMode, .one)
        s.startNewGame()
        XCTAssertEqual(s.game.drawMode, .three)
        s.tapPile(.stock)
        XCTAssertEqual(s.game.waste.count, 3)
    }

    func testHintSuggestsALegalMove() {
        let env = TestEnvironment()
        let s = session(env, ["-seed", "4"])
        s.showHint()
        let hint = try! XCTUnwrap(s.hint)
        XCTAssertTrue(s.game.isLegal(hint))
        XCTAssertFalse(s.hintedCards.isEmpty)
        XCTAssertNotNil(s.toast)
    }

    func testCorruptSaveIsReplacedByAFreshDeal() {
        let env = TestEnvironment()
        env.storage.write(Data("{\"nonsense\":true}".utf8), to: "saves/klondike.json")
        XCTAssertEqual(session(env).game.board, KlondikeGame(seed: 42).board)
    }

    func testTimerOnlyRunsWhileOnScreen() {
        let env = TestEnvironment()
        let s = session(env)
        s.tapPile(.stock)
        s.setInView(false)
        let paused = s.elapsed()
        XCTAssertEqual(s.elapsed(at: Date().addingTimeInterval(600)), paused, accuracy: 0.001)
    }

    func testStatusLineShowsGameInProgress() {
        let env = TestEnvironment()
        let module = SolitaireModule()
        let context = env.context(for: module, arguments: ["-seed", "42"])
        XCTAssertNil(module.statusLine(context: context))
        let s = SolitaireSession(context: context)
        s.tapPile(.stock)
        XCTAssertEqual(module.statusLine(context: context)?.hasPrefix("Resume · 1 move ·"), true)
    }

    /// Cards stay large enough to hit on a moving train, even on the smallest supported iPhone
    /// with the longest possible column.
    func testLayoutFitsTheSmallestPhoneWithBigTouchTargets() {
        let layout = BoardLayout(size: CGSize(width: 375, height: 500), leftHanded: false)
        XCTAssertGreaterThanOrEqual(layout.card.width, 44)
        let offsets = layout.offsets(hidden: 6, visible: 13)
        let bottom = layout.tableauTop + layout.card.height + 6 * offsets.down + 12 * offsets.up
        XCTAssertLessThanOrEqual(bottom, layout.tableauBottom + 0.5)
        let typical = layout.offsets(hidden: 3, visible: 5)
        XCTAssertGreaterThanOrEqual(typical.up, layout.card.height * 0.3, "rank and suit always visible")
        let game = KlondikeGame(seed: 1)
        for placement in layout.placements(for: game) {
            XCTAssertTrue(CGRect(origin: .zero, size: layout.size).insetBy(dx: -1, dy: -1)
                .contains(CGPoint(x: placement.center.x, y: placement.center.y)), "\(placement.card)")
        }
    }

    func testDrawThreeFanShowsRanksWithoutTouchingTheFoundations() {
        for width in [375.0, 402.0, 440.0] {
            for leftHanded in [false, true] {
                let layout = BoardLayout(size: CGSize(width: width, height: 640), leftHanded: leftHanded)
                XCTAssertGreaterThanOrEqual(layout.wasteStep, layout.card.width * 0.45, "rank visible")
                let deepest = layout.wasteCenter(slot: 0, shown: 3).x
                let nearestFoundation = layout.foundationCenter(leftHanded ? 0 : 3).x
                XCTAssertGreaterThanOrEqual(abs(deepest - nearestFoundation), layout.card.width + 2, "no overlap at \(width)")
                let top = layout.wasteCenter(slot: 2, shown: 3).x
                XCTAssertGreaterThanOrEqual(abs(layout.stockCenter.x - top), layout.card.width, "stock stays clear")
            }
        }
    }

    func testLeftHandedLayoutMirrorsTheBottomRow() {
        let right = BoardLayout(size: CGSize(width: 402, height: 640), leftHanded: false)
        let left = BoardLayout(size: CGSize(width: 402, height: 640), leftHanded: true)
        XCTAssertGreaterThan(right.stockCenter.x, right.foundationCenter(3).x)
        XCTAssertLessThan(left.stockCenter.x, left.foundationCenter(0).x)
    }
}
