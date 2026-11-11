import XCTest

/// Shared helpers for the UI tests. Each launch wipes saved data (`-resetState`) unless a test
/// is checking what survives a relaunch, and disables animations so taps settle immediately.
class UITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// - Parameter animated: time passes and things move as they do for a player, instead of
    ///   standing still between steps.
    func launch(_ arguments: [String] = [], reset: Bool = true, appearance: String? = nil, animated: Bool = false) {
        let app = XCUIApplication()
        var all = animated ? [] : ["-disableAnimations"]
        if reset { all.append("-resetState") }
        if let appearance { all += ["-forceAppearance", appearance] }
        app.launchArguments = all + arguments
        app.launch()
        self.app = app
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func labelled(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @discardableResult
    func waitFor(_ identifier: String, timeout: TimeInterval = 10,
                 file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let found = element(identifier)
        // Looking first: waiting for something that is already there still takes a second.
        XCTAssertTrue(found.exists || found.waitForExistence(timeout: timeout), "\(identifier) did not appear", file: file, line: line)
        return found
    }

    /// Opens a game from the home screen and waits for `landmark`, an element only its screen has.
    func open(game id: String, showing landmark: String) {
        waitFor("game-\(id)").tap()
        waitFor(landmark)
    }

    /// Waits until the value of `identifier` is no longer `before`.
    func waitForValue(of identifier: String, toChangeFrom before: String?) {
        let changed = NSPredicate { _, _ in self.element(identifier).value as? String != before }
        expectation(for: changed, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
    }

    /// Taps the middle of an element by coordinate (cards overlap, so hit-testing decides).
    func tapCenter(_ target: XCUIElement) {
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// The textual board description exposed with `-showBoardSignature`.
    func signature() -> String {
        waitFor("boardSignature").label
    }

    /// Saves a screenshot to the result bundle and, on CI, straight into ci-output/screenshots.
    func snap(_ name: String) {
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
