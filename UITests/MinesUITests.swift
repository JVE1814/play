import XCTest

/// End-to-end tests for Mines, on prepared boards. Squares are found by row and column
/// (`cell-R-C`, from zero) and read back through what VoiceOver would say about them.
final class MinesUITests: UITestCase {
    /// The near-win board: Easy, with four safe squares left among the mines of the top two
    /// rows. (0,3), (1,0) and (1,1) are mines.
    func testMinesOpensFlagsForgivesOneSlipAndIsWon() {
        // In dark mode: the screenshot test below covers light, so this one shows the dark board.
        launch(["-scenario", "minesNearWin", "-showBoardSignature"], appearance: "dark")
        openMines()
        XCTAssertEqual(element("minesLeft").value as? String, "12")

        element("cell-1-2").tap()
        XCTAssertEqual(element("cell-1-2").value as? String, "5 mines around")

        element("cell-1-0").press(forDuration: 0.6)
        XCTAssertEqual(element("cell-1-0").value as? String, "flagged")
        XCTAssertEqual(element("minesLeft").value as? String, "11")

        element("minesFlag").tap()
        XCTAssertEqual(element("minesFlag").value as? String, "On")
        element("cell-1-1").tap()
        XCTAssertEqual(element("cell-1-1").value as? String, "flagged")
        element("cell-1-1").tap()
        XCTAssertEqual(element("cell-1-1").value as? String, "covered")
        element("minesFlag").tap()
        XCTAssertEqual(element("minesFlag").value as? String, "Off")

        let board = rows(signature())
        element("cell-0-3").tap()
        waitFor("minesSlipPanel")
        element("slipTakeBack").tap()
        XCTAssertFalse(element("minesSlipPanel").exists)
        XCTAssertTrue(signature().hasPrefix("easy|playing|slip:1|"), signature())
        XCTAssertEqual(rows(signature()), board, "taking it back leaves the board as it was")

        for square in ["cell-1-5", "cell-0-0", "cell-0-7"] { element(square).tap() }
        waitFor("minesResult")
        XCTAssertTrue(labelled("Board cleared!").exists)
        snap("75-mines-won-dark")
        element("resultNewBoard").tap()
        XCTAssertFalse(element("minesResult").exists)
        XCTAssertEqual(element("minesLeft").value as? String, "16", "the next board is Medium")
    }

    // MARK: Screenshots

    func testMinesScreenshotsLight() {
        captureScreens(appearance: "light")
    }

    /// A Medium board part-way through; (4,4) is a mine next to the opening.
    private func captureScreens(appearance: String) {
        launch(["-scenario", "minesShowcase"], appearance: appearance)
        openMines()
        snap("70-mines-board-\(appearance)")

        element("cell-4-4").tap()
        waitFor("minesSlipPanel")
        snap("71-mines-slip-\(appearance)")
        element("slipTakeBack").tap()

        element("minesFlag").tap()
        XCTAssertEqual(element("minesFlag").value as? String, "On")
        snap("72-mines-flag-mode-\(appearance)")
        element("minesFlag").tap()

        element("cell-4-4").tap()
        waitFor("minesResult")
        XCTAssertTrue(labelled("Board lost").exists)
        snap("73-mines-lost-\(appearance)")
        element("resultSeeBoard").tap()
        XCTAssertFalse(element("minesResult").exists)
        snap("74-mines-revealed-\(appearance)")
    }

    /// Mines is the fifth tile, at the bottom of the home screen.
    private func openMines() {
        waitFor("homeTitle")
        app.swipeUp()
        open(game: "mines", showing: "minesBoard")
    }

    /// The board part of a signature, without the status.
    private func rows(_ signature: String) -> String {
        String(signature.split(separator: "|").last ?? "")
    }
}
