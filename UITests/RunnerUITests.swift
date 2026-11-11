import XCTest

/// End-to-end tests for Runner. With animations off the run's clock stands still, and every
/// touch on the pier moves it on by half a second, so each step lands in a known place.
final class RunnerUITests: UITestCase {
    func testRunnerIsOnHomeStartsWithATapAndTakesSwipes() {
        launch(["-seed", "5", "-showBoardSignature"])
        waitFor("game-archery")
        openRunner()
        XCTAssertTrue(element("startCard").exists)
        XCTAssertEqual(element("runnerScore").value as? String, "0")
        XCTAssertEqual(element("goal").value as? String, "250 points")
        XCTAssertTrue(signature().hasPrefix("ready|"), signature())
        XCTAssertFalse(element("pause").isEnabled, "nothing to pause on the start line")

        let pier = element("pier")
        pier.tap()
        XCTAssertTrue(signature().hasPrefix("running|running|m:0|lane:1|run|"), signature())
        XCTAssertFalse(element("startCard").exists)
        pier.swipeLeft()
        XCTAssertTrue(signature().contains("|lane:0|run|"), signature())
        pier.swipeUp()
        XCTAssertTrue(signature().contains("|lane:0|air|"), signature())
        XCTAssertNotEqual(element("runnerScore").value as? String, "0")

        element("pause").tap()
        waitFor("pausedCard")
        XCTAssertTrue(signature().hasPrefix("paused|"), signature())
        element("back").tap()
        waitFor("homeTitle")
        XCTAssertTrue(labelled("Runner").exists)
    }

    func testRunningIntoCratesEndsTheRunAndRunAgainStartsAfresh() {
        launch(["-scenario", "runnerDeadEnd"])
        openRunner()
        let pier = element("pier")
        pier.tap()
        // Crates right across the pier, a second and a half away.
        for _ in 0..<5 where !element("runnerResult").exists { pier.tap() }
        waitFor("runnerResult")
        XCTAssertTrue(labelled("New best!").exists)
        XCTAssertTrue(labelled("Coins: 3").exists)
        element("resultRunAgain").tap()
        waitFor("startCard")
        XCTAssertFalse(element("runnerResult").exists)
        XCTAssertEqual(element("runnerScore").value as? String, "0")
        XCTAssertNotEqual(element("runnerBest").value as? String, "0")
        element("back").tap()
        waitFor("statsButton").tap()
        waitFor("done")
        app.swipeUp()                        // Runner's panel is the last one, below the fold
        XCTAssertTrue(labelled("Played: 1").waitForExistence(timeout: 5))
    }

    // MARK: Smoothness

    /// Runs a busy course live for eight seconds with each way of drawing and clocking the pier,
    /// and prints how evenly the frames came (`RUNNER-PERF` lines in the test log).
    func testThePierIsDrawnSmoothly() {
        for (tuning, appearance, sound) in [("none", "dark", false), ("gpu,rate,clock", "dark", false),
                                            ("gpu,rate,clock,ax", "dark", false), ("gpu,rate,clock,hud", "dark", false),
                                            ("gpu,rate,clock,ax,hud", "dark", false), ("gpu,rate,clock,ax,hud", "light", false),
                                            ("gpu,rate,clock,ax,hud", "dark", true)] {
            launch(["-scenario", "runnerProbe", "-frameProbe", "8", "-pierTuning", tuning] + (sound ? ["-settings.sound", "YES"] : []),
                   appearance: appearance, animated: true)
            waitFor("game-runner").tap()
            // The run starts by itself and pauses once measured. Nothing asks the app anything
            // meanwhile: a query of what is on screen holds up the frames it would measure.
            Thread.sleep(forTimeInterval: 11)
            let probe = element("frameProbe")
            XCTAssertTrue(probe.waitForExistence(timeout: 90), "no report from the probe (\(tuning))")
            let report = probe.value as? String ?? ""
            print("RUNNER-PERF live tuning=\(tuning) appearance=\(appearance) sound=\(sound) \(report)")
            let attachment = XCTAttachment(string: report)
            attachment.name = "frame-probe-\(tuning)-\(appearance)\(sound ? "-sound" : "")"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertTrue(report.hasPrefix("frames="), report)
        }
    }

    // MARK: Screenshots

    func testRunnerScreenshotsLight() {
        captureScreens(appearance: "light")
    }

    func testRunnerScreenshotsDark() {
        captureScreens(appearance: "dark")
    }

    private func captureScreens(appearance: String) {
        // Mid-run, at the top of a jump.
        launch(["-scenario", "runnerShowcase"], appearance: appearance)
        waitFor("homeTitle")
        if appearance == "light" { snap("60-runner-home-light") }
        openRunner()
        snap("61-runner-run-\(appearance)")

        // A finished run, and the start line of the next.
        launch(["-scenario", "runnerOver"], appearance: appearance)
        openRunner()
        waitFor("runnerResult")
        XCTAssertTrue(labelled("Goal reached!").exists)
        snap("62-runner-result-\(appearance)")
        element("resultRunAgain").tap()
        waitFor("startCard")
        snap("63-runner-start-\(appearance)")
    }

    private func openRunner() {
        open(game: "runner", showing: "pier")
    }
}
