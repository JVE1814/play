import XCTest

/// End-to-end tests for the Archery game.
final class ArcheryUITests: UITestCase {
    func testArcheryIsOnHomeAndStartsAtLevelOne() {
        launch()
        waitFor("game-bubbles")
        openArchery()
        XCTAssertEqual(element("archeryLevel").value as? String, "1 of 30")
        XCTAssertEqual(element("arrowsLeft").value as? String, "3")
        XCTAssertEqual(element("distance").value as? String, "10 metres")
        XCTAssertEqual(element("wind").value as? String, "calm")
        XCTAssertTrue(element("tipCard").exists)
        XCTAssertTrue(element("scoreCard").exists)
        // A quick tap is let go before full draw: the bow comes down without shooting.
        waitFor("range").tap()
        waitFor("toast")
        XCTAssertEqual(element("arrowsLeft").value as? String, "3")
        element("back").tap()
        waitFor("homeTitle")
        XCTAssertTrue(labelled("Archery").exists)
    }

    func testAFullEndPlaysThroughToTheResultAndUnlocksTheNextLevel() {
        launch(["-scenario", "archeryNearWin"])
        openArchery()
        XCTAssertEqual(element("arrowsLeft").value as? String, "1")
        shoot()
        waitFor("archeryResult")
        XCTAssertTrue(labelled("Level 1 complete").exists)
        XCTAssertEqual(element("resultStars").label, "3 of 3 stars")
        element("resultNext").tap()
        XCTAssertEqual(waitFor("archeryLevel").value as? String, "2 of 30")
        XCTAssertEqual(element("arrowsLeft").value as? String, "3")
        element("levels").tap()
        XCTAssertTrue((waitFor("level-1").value as? String ?? "").hasPrefix("3 of 3 stars, best "))
        XCTAssertEqual(element("level-2").value as? String, "0 of 3 stars, current")
        XCTAssertEqual(element("level-3").value as? String, "Locked")
        element("done").tap()
        element("back").tap()
        waitFor("statsButton").tap()
        XCTAssertTrue(labelled("Won: 1").waitForExistence(timeout: 5))
    }

    func testAPoorEndOffersAnotherTry() {
        launch(["-scenario", "archeryLastArrow"])
        openArchery()
        shoot()
        waitFor("archeryResult")
        XCTAssertTrue(labelled("Not quite").exists)
        XCTAssertEqual(element("resultStars").label, "0 of 3 stars")
        element("resultRetry").tap()
        XCTAssertFalse(element("archeryResult").exists)
        XCTAssertEqual(waitFor("arrowsLeft").value as? String, "3", "a fresh attempt")
        XCTAssertEqual(element("archeryScore").value as? String, "0")
    }

    func testForceQuitMidLevelRestoresTheEnd() {
        launch(["-level", "7", "-showBoardSignature"])
        openArchery()
        shoot()
        shoot()
        let end = signature()
        XCTAssertTrue(end.contains("arrows:2/4"), end)
        XCTAssertEqual(element("arrowsLeft").value as? String, "2")

        app.terminate()
        launch(["-showBoardSignature"], reset: false)

        waitFor("range")
        XCTAssertEqual(signature(), end)
        XCTAssertEqual(element("arrowsLeft").value as? String, "2")
        XCTAssertEqual(element("archeryLevel").value as? String, "7 of 30")
    }

    // MARK: Screenshots

    func testArcheryScreenshotsLight() {
        captureArchery(appearance: "light")
    }

    func testArcheryScreenshotsDark() {
        captureArchery(appearance: "dark")
    }

    private func captureArchery(appearance: String) {
        launch(appearance: appearance)
        waitFor("homeTitle")
        // Solitaire's dark set already shows the home screen in dark mode.
        if appearance == "light" { snap("50-home-three-games-\(appearance)") }
        openArchery()
        snap("51-archery-start-\(appearance)")

        launch(["-scenario", "archeryShowcase", "-demoAim", "0.16"], appearance: appearance)
        openArchery()
        snap("52-archery-aim-\(appearance)")
        element("levels").tap()
        // The level list: all thirty, the current one, and the next locked.
        XCTAssertTrue(waitFor("levelSummary").label.contains("30 levels"))
        XCTAssertEqual(waitFor("level-22").value as? String, "0 of 3 stars, current")
        XCTAssertEqual(element("level-23").value as? String, "Locked")
        snap("56-archery-levels-\(appearance)")
        element("done").tap()

        launch(["-scenario", "archeryNight", "-demoAim", "-0.3"], appearance: appearance)
        openArchery()
        snap("54-archery-night-\(appearance)")

        launch(["-scenario", "archeryNearWin"], appearance: appearance)
        openArchery()
        shoot()
        waitFor("archeryResult")
        snap("55-archery-result-\(appearance)")
    }

    // MARK: Helpers

    private func openArchery() {
        open(game: "archery", showing: "range")
    }

    /// Touches the range, holds past full draw without moving, and lets go.
    private func shoot() {
        let before = element("arrowsLeft").value as? String
        waitFor("range").press(forDuration: 1.0)
        waitForValue(of: "arrowsLeft", toChangeFrom: before)
    }
}
