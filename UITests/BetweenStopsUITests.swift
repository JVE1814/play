import XCTest

/// End-to-end tests for Solitaire and the screens every game shares.
final class BetweenStopsUITests: UITestCase {

    // MARK: Gameplay

    func testHomeListsSolitaireAndOpensIt() {
        launch()
        waitFor("homeTitle")
        XCTAssertFalse(element("game-testgame").exists, "the test game only appears when requested")
        openSolitaire()
        for id in ["undo", "hint", "newGame", "moves", "timer", "back", "settings", "stock"] {
            XCTAssertTrue(element(id).exists, "\(id) missing")
        }
        element("back").tap()
        waitFor("homeTitle")
    }

    func testDrawingFromTheStockAndUndo() {
        launch(["-seed", "42", "-showBoardSignature"])
        openSolitaire()
        let deal = signature()
        tapCenter(element("stock"))
        XCTAssertEqual(moves(), "1")
        XCTAssertNotEqual(signature(), deal)
        XCTAssertTrue(signature().contains("|W:10S|"), signature())
        element("undo").tap()
        XCTAssertEqual(signature(), deal)
        XCTAssertEqual(moves(), "0")
    }

    func testTappingACardPlaysItsBestMove() {
        launch(["-seed", "4", "-showBoardSignature"])
        openSolitaire()
        let six = waitFor("card-6D")
        let seven = waitFor("card-7S")
        tapCenter(six)
        XCTAssertEqual(moves(), "1")
        XCTAssertTrue(signature().contains("|T0:7S,6D|"), signature())
        XCTAssertEqual(six.frame.midX, seven.frame.midX, accuracy: 2)
        XCTAssertGreaterThan(six.frame.minY, seven.frame.minY)
    }

    func testDraggingACardOntoAColumn() {
        launch(["-seed", "6", "-showBoardSignature"])
        openSolitaire()
        let nine = waitFor("card-9D")
        let ten = waitFor("card-10C")
        nine.press(forDuration: 0.2, thenDragTo: ten)
        XCTAssertEqual(moves(), "1")
        XCTAssertTrue(signature().contains("|T3:7h,5d,8d,10C,9D|"), signature())
    }

    func testIllegalDragSnapsBack() {
        launch(["-seed", "6", "-showBoardSignature"])
        openSolitaire()
        let deal = signature()
        waitFor("card-9D").press(forDuration: 0.2, thenDragTo: waitFor("card-AD"))
        XCTAssertEqual(moves(), "0")
        XCTAssertEqual(signature(), deal)
    }

    func testHintShowsAMove() {
        launch(["-seed", "4"])
        openSolitaire()
        element("hint").tap()
        // The best move is the 6 of Diamonds onto the 7 of Spades: a short sentence appears,
        // and both cards stay highlighted (and say so to VoiceOver) until the next move.
        XCTAssertTrue(labelled("Move the 6 of Diamonds onto the 7 of Spades").waitForExistence(timeout: 4))
        let six = waitFor("card-6D")
        XCTAssertTrue((six.value as? String ?? "").contains("suggested by hint"), six.value as? String ?? "")
        XCTAssertTrue((element("card-7S").value as? String ?? "").contains("suggested by hint"))
        XCTAssertEqual(moves(), "0", "a hint never moves anything by itself")
        tapCenter(six)
        XCTAssertEqual(moves(), "1")
        XCTAssertFalse((element("card-6D").value as? String ?? "").contains("suggested"), "the highlight clears after a move")
    }

    func testNearlyFinishedGamePlaysThroughToTheWinScreen() {
        launch(["-scenario", "nearWin", "-seed", "3", "-showBoardSignature"])
        openSolitaire()
        XCTAssertFalse(element("autoFinish").exists, "a card is still face down")
        tapCenter(element("stock"))          // draws the last card, the Queen of Diamonds
        tapCenter(waitFor("card-QD"))        // plays it to the diamonds foundation
        XCTAssertEqual(moves(), "2")
        waitFor("autoFinish").tap()          // every card is face up, so finish automatically
        waitFor("winScreen", timeout: 15)
        XCTAssertTrue(app.staticTexts["You won!"].exists)
        element("winHome").tap()
        waitFor("statsButton").tap()
        XCTAssertTrue(labelled("Won: 1").waitForExistence(timeout: 5))
        XCTAssertTrue(labelled("Current streak: 1").exists)
    }

    func testForceQuitMidGameRestoresTheExactBoard() {
        launch(["-seed", "7", "-showBoardSignature"])
        openSolitaire()
        tapCenter(element("stock"))
        tapCenter(element("stock"))
        tapCenter(element("stock"))
        tapCenter(waitFor("card-6H"))        // onto the 7 of Clubs, turning a card face up
        let board = signature()
        XCTAssertEqual(moves(), "4")
        XCTAssertTrue(board.contains("7C,6H"), board)

        app.terminate()                      // like swiping the app away: no chance to save
        launch(["-showBoardSignature"], reset: false)

        waitFor("stock")
        XCTAssertFalse(element("homeTitle").exists)
        XCTAssertEqual(signature(), board)
        XCTAssertEqual(moves(), "4")
        element("undo").tap()                // the undo history survived too
        XCTAssertEqual(moves(), "3")
    }

    func testTestOnlyGameAppearsOnHomeAndOpens() {
        launch(["-includeTestGames"], appearance: "light")
        let tile = waitFor("game-testgame")
        XCTAssertTrue(element("game-klondike").exists)
        snap("30-test-game-on-home-light")
        tile.tap()
        waitFor("testGameTitle")
        snap("31-test-game-open-light")
        element("testGameTap").tap()
        XCTAssertEqual(element("testGameCount").value as? String, "1")
        element("back").tap()
        waitFor("game-testgame")
    }

    func testDrawThreeSettingAppliesToTheNextDeal() {
        launch(["-seed", "42", "-showBoardSignature"])
        waitFor("settingsButton").tap()
        let drawThree = app.buttons["Draw 3"]
        XCTAssertTrue(drawThree.waitForExistence(timeout: 5))
        drawThree.tap()
        element("done").tap()
        openSolitaire()
        XCTAssertTrue(signature().hasSuffix("|D:3"), signature())
        tapCenter(element("stock"))
        let waste = signature().split(separator: "|").first { $0.hasPrefix("W:") } ?? ""
        XCTAssertEqual(waste.split(separator: ",").count, 3, String(waste))
        snap("09-draw-three-light")
    }

    func testLeftHandedLayoutPutsTheStockOnTheLeft() {
        launch(["-seed", "42"], appearance: "light")
        openSolitaire()
        XCTAssertGreaterThan(element("stock").frame.midX, app.frame.midX)
        element("back").tap()
        waitFor("settingsButton").tap()
        let toggle = waitFor("leftHanded")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        element("done").tap()
        openSolitaire()
        XCTAssertLessThan(element("stock").frame.midX, app.frame.midX)
        XCTAssertLessThan(element("undo").frame.midX, element("newGame").frame.midX)
        tapCenter(element("stock"))
        XCTAssertEqual(moves(), "1")
        snap("10-left-handed-light")
    }

    func testAccessibilityAudit() throws {
        launch(["-scenario", "midGame", "-seed", "11"])
        waitFor("homeTitle")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion])
        openSolitaire()
        try app.performAccessibilityAudit(for: [.sufficientElementDescription])
        element("back").tap()
        waitFor("settingsButton").tap()
        waitFor("done")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion])
    }

    // MARK: Screenshots (light and dark, every screen)

    func testScreenshotsLight() {
        captureScreens(appearance: "light")
    }

    func testScreenshotsDark() {
        captureScreens(appearance: "dark")
    }

    func testScreenshotsLargeText() {
        launch(["-scenario", "midGame", "-seed", "11",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"], appearance: "light")
        waitFor("homeTitle")
        snap("20-large-text-home-light")
        openSolitaire()
        snap("21-large-text-game-light")
        element("back").tap()
        waitFor("statsButton").tap()
        waitFor("done")
        snap("22-large-text-stats-light")
    }

    private func captureScreens(appearance: String) {
        // A game in progress, with a hint showing.
        launch(["-scenario", "midGame", "-seed", "11"], appearance: appearance)
        waitFor("homeTitle")
        openSolitaire()
        snap("02-game-\(appearance)")
        element("hint").tap()
        waitFor("toast")
        snap("03-hint-\(appearance)")
        element("back").tap()
        waitFor("homeTitle")
        snap("01-home-\(appearance)")
        element("settingsButton").tap()
        waitFor("done")
        snap("06-settings-\(appearance)")
        element("done").tap()

        // A game played to the end.
        launch(["-scenario", "nearWin", "-seed", "5"], appearance: appearance)
        openSolitaire()
        tapCenter(element("stock"))
        tapCenter(waitFor("card-QD"))
        waitFor("autoFinish").tap()
        waitFor("winScreen", timeout: 15)
        snap("04-win-\(appearance)")
        element("winNewGame").tap()
        waitFor("stock")
        snap("05-new-deal-\(appearance)")
        tapCenter(element("stock"))
        element("newGame").tap()
        let newDeal = app.buttons["New Deal"]
        XCTAssertTrue(newDeal.waitForExistence(timeout: 5))
        snap("08-confirm-new-deal-\(appearance)")
        app.buttons["Keep Playing"].tap()
        XCTAssertTrue(newDeal.waitForNonExistence(timeout: 5))
        XCTAssertEqual(moves(), "1", "Keep Playing keeps the current game")
        element("back").tap()
        waitFor("statsButton").tap()
        waitFor("done")
        snap("07-stats-\(appearance)")
        element("done").tap()
    }

    // MARK: Solitaire helpers

    private func openSolitaire() {
        open(game: "klondike", showing: "stock")
    }

    private func moves() -> String {
        waitFor("moves").value as? String ?? ""
    }
}
