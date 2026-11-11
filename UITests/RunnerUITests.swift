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

    /// Runs a busy course live for six seconds and prints how evenly the frames came, what each
    /// cost and where the main thread's time went (`RUNNER-PERF` lines in the test log). A
    /// frame's own work, from its view update to the end of its painting, has to fit a 120 Hz
    /// frame.
    ///
    /// The simulator's frame rate says more about how busy the CI machine is than about the
    /// app; the main thread's CPU time (`main_cpu_*`, `cpu_*`) and the frame's work do not.
    func testThePierIsDrawnSmoothly() {
        // Once, in the dark (the night sky has the most stars), with the whole pier: with five
        // games the job has little time to spare. (-pierDraw noItems, noGlows, noFurniture,
        // noObstacles, noCoins and sketch draw part of it, to compare on the same machine.) Each run costs the suite about 15
        // seconds, and the job has little to spare on a slow machine.
        for (appearance, drawn) in [("dark", "all")] {
            launch(["-scenario", "runnerProbe", "-frameProbe", "5", "-pierDraw", drawn], appearance: appearance, animated: true)
            waitFor("game-runner").tap()
            // The run starts by itself and pauses once measured. Nothing asks the app anything
            // meanwhile: a query of what is on screen holds up the frames it would measure.
            Thread.sleep(forTimeInterval: 7)
            let probe = element("frameProbe")
            XCTAssertTrue(probe.waitForExistence(timeout: 30), "no report from the probe (\(appearance))")
            let report = probe.value as? String ?? ""
            print("RUNNER-PERF live appearance=\(appearance) drawn=\(drawn) \(report)")
            let attachment = XCTAttachment(string: report)
            attachment.name = "frame-probe-\(appearance)-\(drawn)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertGreaterThan(measure("frames", in: report), 60, report)
            XCTAssertLessThan(measure("work_p95", in: report), 1_000.0 / 120, "a frame's work does not fit 120 Hz: \(report)")
        }
    }

    /// The number after `name=` in a probe's report.
    private func measure(_ name: String, in report: String) -> Double {
        let field = report.split(separator: " ").first { $0.hasPrefix("\(name)=") }
        return field.flatMap { Double($0.dropFirst(name.count + 1)) } ?? .nan
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
