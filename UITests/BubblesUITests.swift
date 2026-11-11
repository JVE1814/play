import XCTest

/// End-to-end tests for the Bubbles game.
final class BubblesUITests: UITestCase {
    /// The number of levels, as the app's locale writes it.
    private let levelCount = 2000.formatted()

    func testBubblesIsOnHomeAndStartsAtLevelOne() {
        launch()
        waitFor("game-klondike")
        openBubbles()
        XCTAssertEqual(element("bubbleLevel").value as? String, "1 of \(levelCount)")
        XCTAssertGreaterThan(shotsLeft(), 1)
        XCTAssertTrue(element("bubble-0-0").exists)
        XCTAssertTrue(element("swapBubble").exists)
        element("back").tap()
        waitFor("homeTitle")
        XCTAssertTrue(labelled("Bubbles").exists)
    }

    func testANearlyClearedLevelIsWonAndUnlocksTheNext() {
        launch(["-scenario", "bubblesNearWin"])
        openBubbles()
        shoot(dx: 0.5, dy: 0.15)                 // straight up: three reds pop
        waitFor("bubblesResult")
        XCTAssertTrue(labelled("Level 1 cleared!").exists)
        XCTAssertEqual(element("resultStars").label, "3 of 3 stars")
        element("resultNext").tap()
        XCTAssertEqual(waitFor("bubbleLevel").value as? String, "2 of \(levelCount)")
        element("levels").tap()
        XCTAssertEqual(waitFor("level-1").value as? String, "3 of 3 stars")
        XCTAssertEqual(element("level-2").value as? String, "0 of 3 stars, current")
        XCTAssertEqual(element("level-3").value as? String, "Locked")
        element("done").tap()
        element("back").tap()
        waitFor("statsButton").tap()
        XCTAssertTrue(labelled("Won: 1").waitForExistence(timeout: 5))
    }

    func testRunningOutOfShotsOffersAnotherTry() {
        launch(["-scenario", "bubblesLastShot"])
        openBubbles()
        XCTAssertEqual(shotsLeft(), 1)
        shoot(dx: 0.5, dy: 0.15)
        waitFor("bubblesResult")
        XCTAssertTrue(labelled("Out of shots").exists)
        element("resultRetry").tap()
        XCTAssertFalse(element("bubblesResult").exists)
        XCTAssertGreaterThan(shotsLeft(), 1, "a fresh attempt at the real level 1")
    }

    func testSwappingExchangesTheLauncherAndNextBubble() {
        launch(["-scenario", "bubblesLastShot"])
        openBubbles()
        XCTAssertEqual(element("launcher").label, "Launcher, Red triangle")
        XCTAssertEqual(element("swapBubble").label, "Next bubble, Yellow circle")
        element("swapBubble").tap()
        XCTAssertEqual(element("launcher").label, "Launcher, Yellow circle")
        element("swap").tap()
        XCTAssertEqual(element("launcher").label, "Launcher, Red triangle")
    }

    func testForceQuitMidLevelRestoresTheExactBoard() {
        launch(["-level", "210", "-showBoardSignature"])
        openBubbles()
        let start = element("shotsLeft").value as? String
        shoot(dx: 0.25, dy: 0.3)
        shoot(dx: 0.8, dy: 0.25)
        let board = signature()
        let shots = element("shotsLeft").value as? String
        XCTAssertNotEqual(shots, start)
        XCTAssertTrue(board.contains("shots:2/"), board)

        app.terminate()
        launch(["-showBoardSignature"], reset: false)

        waitFor("launcher")
        XCTAssertEqual(signature(), board)
        XCTAssertEqual(element("shotsLeft").value as? String, shots)
    }

    func testTheLevelListShowsAllTwoThousandLevels() {
        launch(["-level", "37"])
        openBubbles()
        XCTAssertEqual(element("bubbleLevel").value as? String, "37 of \(levelCount)")
        element("levels").tap()
        XCTAssertTrue(waitFor("levelSummary").label.contains("\(levelCount) levels"))
        XCTAssertEqual(waitFor("level-37").value as? String, "0 of 3 stars, current")
        XCTAssertEqual(element("level-38").value as? String, "Locked")
        element("level-12").tap()
        XCTAssertEqual(waitFor("bubbleLevel").value as? String, "12 of \(levelCount)")
    }

    // MARK: Screenshots

    func testBubblesScreenshotsLight() {
        captureBubbles(appearance: "light")
    }

    func testBubblesScreenshotsDark() {
        captureBubbles(appearance: "dark")
    }

    private func captureBubbles(appearance: String) {
        launch(["-level", "210", "-demoAim", "-0.42"], appearance: appearance)
        openBubbles()
        snap("41-bubbles-aim-\(appearance)")
        element("levels").tap()
        waitFor("level-210")
        snap("44-bubbles-levels-\(appearance)")
        element("done").tap()

        launch(["-scenario", "bubblesNearWin"], appearance: appearance)
        openBubbles()
        snap("42-bubbles-start-\(appearance)")
        shoot(dx: 0.5, dy: 0.15)
        waitFor("bubblesResult")
        snap("43-bubbles-cleared-\(appearance)")

        launch(["-scenario", "bubblesLastShot"], appearance: appearance)
        openBubbles()
        shoot(dx: 0.5, dy: 0.15)
        waitFor("bubblesResult")
        snap("45-bubbles-out-of-shots-\(appearance)")
    }

    // MARK: Helpers

    private func openBubbles() {
        open(game: "bubbles", showing: "launcher")
    }

    private func shotsLeft() -> Int {
        Int(waitFor("shotsLeft").value as? String ?? "") ?? -1
    }

    /// Drags from the launcher to a point of the field (normalised) and lets go, which shoots.
    private func shoot(dx: CGFloat, dy: CGFloat) {
        let before = element("shotsLeft").value as? String
        let from = waitFor("launcher").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = waitFor("bubbleField").coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy))
        from.press(forDuration: 0.05, thenDragTo: to)
        waitForValue(of: "shotsLeft", toChangeFrom: before)
    }
}
