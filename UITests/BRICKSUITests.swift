import XCTest

/// Plays real moves with each platform's own controls: the Siri Remote on Apple TV,
/// taps on Apple Watch, a mouse on the Mac, a finger on iPhone and iPad.
///
/// Every test launches the `-demo` board, whose bricks are fixed: rows 0 and 2–3 are
/// mostly open, and the region around row 2, column 5 fits any piece the tray can deal.
final class BRICKSUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
    }

    // MARK: - Helpers

    private var scoreText: XCUIElement { app.staticTexts["score"] }
    private var board: XCUIElement { app.descendants(matching: .any)["board"].firstMatch }
    private func tray(_ i: Int) -> XCUIElement { app.descendants(matching: .any)["tray-\(i)"].firstMatch }

    /// The score as shown. Text reads as the label on iOS-family platforms and as the
    /// value on the Mac.
    private var score: Int {
        let shown = scoreText.label.isEmpty ? (scoreText.value as? String ?? "") : scoreText.label
        return Int(shown.filter(\.isNumber)) ?? -1
    }

    /// Waits for the score to move past `old`; placing any piece scores at least 1.
    private func waitForScore(above old: Int, timeout: TimeInterval = 4) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if score > old { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    #if !os(tvOS)
    /// A point on the board by cell, allowing for its 0.18-cell padding.
    private func boardPoint(row: Double, col: Double, liftCells: Double = 0) -> XCUICoordinate {
        let span = 10.36
        return board.coordinate(withNormalizedOffset: CGVector(
            dx: (0.18 + col + 0.5) / span,
            dy: (0.18 + row + 0.5 + liftCells) / span
        ))
    }
    #endif

    /// Keeps a screenshot in the test results, for checking layouts by eye.
    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - Apple TV

    #if os(tvOS)
    private let remote = XCUIRemote.shared

    private var aimValue: String { (board.value as? String) ?? "" }

    func testRemotePicksAndPlacesAPiece() {
        XCTAssertTrue(scoreText.waitForExistence(timeout: 5))
        let before = score

        remote.press(.select)                        // pick up the focused piece
        snapshot("picked")
        XCTAssertTrue(board.hasFocus, "picking a piece hands the remote to the board")
        XCTAssertFalse(aimValue.isEmpty, "the board says where it is aiming")
        XCTAssertFalse(aimValue.contains("doesn't fit"), "a picked piece starts somewhere it fits")

        remote.press(.select)                        // drop it there
        XCTAssertTrue(waitForScore(above: before), "placing scores (was \(before), now \(score))")
        XCTAssertFalse(board.hasFocus, "after placing, focus goes back to the tray")
    }

    func testRemoteMovesTheAimAndMenuCancels() {
        XCTAssertTrue(scoreText.waitForExistence(timeout: 5))
        let before = score

        remote.press(.select)
        let start = aimValue
        remote.press(.up)
        remote.press(.left)
        XCTAssertNotEqual(aimValue, start, "arrows move the piece (\(start) → \(aimValue))")

        remote.press(.menu)
        XCTAssertFalse(board.hasFocus, "Menu puts the piece back")
        XCTAssertEqual(score, before, "cancelling places nothing")
    }

    func testRemoteAimsTheHammer() {
        let hammer = app.buttons["power-hammer"]
        XCTAssertTrue(hammer.waitForExistence(timeout: 5))
        XCTAssertTrue(hammer.label.contains("3 left"), "the demo board starts with 3 hammers")

        // Walk focus from the tray down to the power-ups, then left to the hammer.
        for _ in 0..<12 where !hammer.hasFocus {
            let onPowerUps = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'power-'"))
                .allElementsBoundByIndex.contains { $0.hasFocus }
            remote.press(onPowerUps ? .left : .down)
        }
        XCTAssertTrue(hammer.hasFocus, "the hammer chip can be reached with the remote")

        remote.press(.select)                        // arm it: the board takes over
        XCTAssertTrue(board.hasFocus)
        for _ in 0..<5 { remote.press(.down) }       // the demo's bottom row is full of bricks
        remote.press(.select)                        // smash
        XCTAssertTrue(hammer.label.contains("2 left"), "smashing a brick spends a hammer (\(hammer.label))")
    }
    #endif

    // MARK: - Apple Watch

    #if os(watchOS)
    func testTapToAimThenTapToPlace() {
        XCTAssertTrue(scoreText.waitForExistence(timeout: 5))
        let before = score

        tray(0).tap()
        let spot = boardPoint(row: 2, col: 5)
        spot.tap()                                   // aim
        snapshot("aimed")
        XCTAssertEqual(score, before, "the first tap only aims")
        spot.tap()                                   // place
        snapshot("placed")
        XCTAssertTrue(waitForScore(above: before), "the second tap places (was \(before), now \(score))")
    }
    #endif

    // MARK: - iPhone Duo's outer display

    #if os(iOS)
    /// Where the power-ups fold into the trailing system column (the Duo's outer
    /// display), they stay folded until asked for and fold away again after a use.
    func testPowerUpRailFoldsAway() throws {
        let rail = app.buttons["power-rail"]
        guard rail.waitForExistence(timeout: 5) else {
            throw XCTSkip("This screen has room for the power-up bar, so there is no rail")
        }
        let hammer = app.buttons["power-hammer"]
        XCTAssertFalse(hammer.exists, "the chips start folded away")

        rail.tap()
        XCTAssertTrue(hammer.waitForExistence(timeout: 2), "the rail fans the chips out")
        snapshot("rail-open")

        hammer.tap()
        XCTAssertTrue(app.staticTexts["Tap a brick to smash it"].waitForExistence(timeout: 2), "the hammer is armed")
        XCTAssertFalse(hammer.waitForExistence(timeout: 1) && hammer.isHittable, "using a chip folds the rail")
        snapshot("rail-armed")
    }
    #endif

    // MARK: - Widget switch (iPhone, iPad)

    #if os(iOS)
    /// Settings can switch the widget off, and the widget then shows nothing of the game.
    func testWidgetCanBeSwitchedOff() {
        let widgetSwitch = app.switches["Widget"]
        func setWidget(_ on: Bool) {
            app.buttons["Settings"].tap()
            XCTAssertTrue(widgetSwitch.waitForExistence(timeout: 3), "Settings has a Widget switch")
            if (widgetSwitch.value as? String == "1") != on { widgetSwitch.switches.firstMatch.tap() }
            XCTAssertEqual(widgetSwitch.value as? String, on ? "1" : "0")
        }
        let isOff = NSPredicate(format: "label CONTAINS 'Widget is off'")

        setWidget(false)
        app.terminate()
        app.launchArguments = ["-widgetPreview"]
        app.launch()
        XCTAssertTrue(app.staticTexts.matching(isOff).firstMatch.waitForExistence(timeout: 3),
                      "a switched-off widget says so instead of showing the game")
        snapshot("widget-off")

        // Leave it on, as a player would expect.
        app.terminate()
        app.launchArguments = ["-demo"]
        app.launch()
        setWidget(true)
    }
    #endif

    // MARK: - Mac and iPhone/iPad

    #if os(macOS) || os(iOS)
    func testDragPlacesAPiece() {
        XCTAssertTrue(scoreText.waitForExistence(timeout: 5))
        let before = score

        // A finger drags the piece 2.9 cells above itself so the hand doesn't hide it;
        // a mouse pointer drags it right under the pointer.
        #if os(macOS)
        let lift = 0.0
        #else
        let lift = 2.9
        #endif
        let start = tray(0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        snapshot("before-drag")
        let target = boardPoint(row: 2, col: 5, liftCells: lift)
        #if os(macOS)
        start.click(forDuration: 0.2, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.2)
        #else
        start.press(forDuration: 0.2, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.2)
        #endif
        snapshot("after-drag")

        XCTAssertTrue(waitForScore(above: before), "dropping on open board scores (was \(before), now \(score))")
    }
    #endif
}
