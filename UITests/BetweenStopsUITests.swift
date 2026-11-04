import XCTest

/// End-to-end tests. Each launch wipes saved data (`-resetState`) unless a test is checking
/// what survives a relaunch, and disables animations so taps settle immediately.
final class BetweenStopsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Gameplay

    func testHomeListsSolitaireAndOpensIt() {
        launch()
        XCTAssertTrue(waitFor("homeTitle").exists)
        XCTAssertFalse(element("game-testgame").exists, "the test game only appears when requested")
        openSolitaire()
        for id in ["undo", "hint", "newGame", "moves", "timer", "back", "settings", "stock"] {
            XCTAssertTrue(element(id).exists, "\(id) missing")
        }
        element("back").tap()
        XCTAssertTrue(waitFor("homeTitle").exists)
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
        XCTAssertTrue(waitFor("winScreen", timeout: 15).exists)
        XCTAssertTrue(app.staticTexts["You won!"].exists)
        XCTAssertTrue(signature().contains("F0:AD,2D,3D,4D,5D,6D,7D,8D,9D,10D,JD,QD,KD"), signature())
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

        XCTAssertTrue(waitFor("stock").exists, "reopens straight into the game")
        XCTAssertFalse(element("homeTitle").exists)
        XCTAssertEqual(signature(), board)
        XCTAssertEqual(moves(), "4")
        element("undo").tap()                // the undo history survived too
        XCTAssertEqual(moves(), "3")
    }

    func testTestOnlyGameAppearsOnHomeAndOpens() {
        launch(["-includeTestGames"])
        let tile = waitFor("game-testgame")
        XCTAssertTrue(element("game-klondike").exists)
        tile.tap()
        XCTAssertTrue(waitFor("testGameTitle").exists)
        element("testGameTap").tap()
        XCTAssertEqual(element("testGameCount").value as? String, "1")
        element("back").tap()
        XCTAssertTrue(waitFor("game-testgame").exists)
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
    }

    func testAccessibilityAudit() throws {
        launch(["-scenario", "midGame", "-seed", "11"])
        _ = waitFor("homeTitle")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion])
        openSolitaire()
        try app.performAccessibilityAudit(for: [.sufficientElementDescription])
        element("back").tap()
        waitFor("settingsButton").tap()
        _ = waitFor("done")
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
        _ = waitFor("homeTitle")
        snap("20-large-text-home-light")
        openSolitaire()
        snap("21-large-text-game-light")
        element("back").tap()
        waitFor("statsButton").tap()
        _ = waitFor("done")
        snap("22-large-text-stats-light")
    }

    private func captureScreens(appearance: String) {
        // A game in progress, with a hint showing.
        launch(["-scenario", "midGame", "-seed", "11"], appearance: appearance)
        _ = waitFor("homeTitle")
        openSolitaire()
        snap("02-game-\(appearance)")
        element("hint").tap()
        _ = waitFor("toast")
        snap("03-hint-\(appearance)")
        element("back").tap()
        _ = waitFor("homeTitle")
        snap("01-home-\(appearance)")
        element("settingsButton").tap()
        _ = waitFor("done")
        snap("06-settings-\(appearance)")
        element("done").tap()

        // A game played to the end.
        launch(["-scenario", "nearWin", "-seed", "5"], appearance: appearance)
        openSolitaire()
        tapCenter(element("stock"))
        tapCenter(waitFor("card-QD"))
        waitFor("autoFinish").tap()
        _ = waitFor("winScreen", timeout: 15)
        snap("04-win-\(appearance)")
        element("winNewGame").tap()
        _ = waitFor("stock")
        snap("05-new-deal-\(appearance)")
        tapCenter(element("stock"))
        element("newGame").tap()
        let newDeal = app.buttons["New Deal"]
        XCTAssertTrue(newDeal.waitForExistence(timeout: 5))
        snap("08-confirm-new-deal-\(appearance)")
        // iOS 26 shows the dialog as a popover without a cancel button; tap outside to dismiss.
        if app.buttons["Keep Playing"].exists {
            app.buttons["Keep Playing"].tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        }
        XCTAssertTrue(newDeal.waitForNonExistence(timeout: 5))
        XCTAssertEqual(moves(), "1", "dismissing keeps the current game")
        element("back").tap()
        waitFor("statsButton").tap()
        _ = waitFor("done")
        snap("07-stats-\(appearance)")
        element("done").tap()
    }

    // MARK: Helpers

    private func launch(_ arguments: [String] = [], reset: Bool = true, appearance: String? = nil) {
        let app = XCUIApplication()
        var all = ["-disableAnimations"]
        if reset { all.append("-resetState") }
        if let appearance { all += ["-forceAppearance", appearance] }
        app.launchArguments = all + arguments
        app.launch()
        self.app = app
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func labelled(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @discardableResult
    private func waitFor(_ identifier: String, timeout: TimeInterval = 10,
                         file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let found = element(identifier)
        XCTAssertTrue(found.waitForExistence(timeout: timeout), "\(identifier) did not appear", file: file, line: line)
        return found
    }

    /// Taps the middle of an element by coordinate (cards overlap, so hit-testing decides).
    private func tapCenter(_ target: XCUIElement) {
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func openSolitaire() {
        waitFor("game-klondike").tap()
        _ = waitFor("stock")
    }

    private func signature() -> String {
        waitFor("boardSignature").label
    }

    private func moves() -> String {
        waitFor("moves").value as? String ?? ""
    }

    /// Saves a screenshot to the result bundle and, on CI, straight into ci-output/screenshots.
    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !directory.isEmpty {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
            try? shot.pngRepresentation.write(to: url)
        }
    }
}
