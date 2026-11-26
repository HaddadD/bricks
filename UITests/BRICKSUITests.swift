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
        // Each flag gets a value: on the Mac a bare flag followed by another pairs with it,
        // and the leftover word is taken as a file to open, which opens no window.
        // Float pieces is on by default where there's room; the drag tests aim with the
        // piece under the finger, and testFloatPieces checks the default itself.
        app.launchArguments = ["-demo", "YES", "-noGameCenter", "YES", "-bricks.floatPieces", "NO", "-bricks.sensory", "NO"]
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
    private func boardPoint(row: Double, col: Double) -> XCUICoordinate {
        let span = 10.36
        return board.coordinate(withNormalizedOffset: CGVector(
            dx: (0.18 + col + 0.5) / span,
            dy: (0.18 + row + 0.5) / span
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
        app.launchArguments = ["-widgetPreview", "YES", "-noGameCenter", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts.matching(isOff).firstMatch.waitForExistence(timeout: 3),
                      "a switched-off widget says so instead of showing the game")
        snapshot("widget-off")

        // Leave it on, as a player would expect.
        app.terminate()
        app.launchArguments = ["-demo", "YES", "-noGameCenter", "YES"]
        app.launch()
        setWidget(true)
    }
    #endif

    // MARK: - Sensory enhancement (iPhone, iPad)

    #if os(iOS)
    /// Sensory enhancement starts off. Switched on, its three choices sit together under
    /// it, the runner's worlds show only while the runner is chosen, and the choice plays
    /// under the board.
    func testSensoryEnhancement() {
        app.terminate()
        app.launchArguments = ["-demo", "YES", "-noGameCenter", "YES", "-bricks.floatPieces", "NO",
                               "-bricks.sensory", "NO", "-bricks.sensoryMode", "runner"]
        app.launch()
        app.buttons["Settings"].tap()
        let sensory = app.switches["Sensory enhancement"]
        func choice(_ title: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        }
        XCTAssertTrue(sensory.waitForExistence(timeout: 3), "Settings has Sensory enhancement")
        XCTAssertEqual(sensory.value as? String, "0", "it starts off")
        XCTAssertFalse(choice("Oddly Satisfying").exists, "its choices stay hidden while it's off")

        sensory.switches.firstMatch.tap()
        for title in ["Runner", "Oddly Satisfying", "Impossible Satisfying"] {
            XCTAssertTrue(choice(title).waitForExistence(timeout: 2), "\(title) is offered under it")
        }
        XCTAssertTrue(app.segmentedControls.buttons["Street"].exists, "the runner's worlds show while it's chosen")
        snapshot("sensory-runner")

        choice("Oddly Satisfying").tap()
        XCTAssertTrue(choice("Oddly Satisfying").isSelected, "a tap chooses it")
        XCTAssertFalse(app.segmentedControls.buttons["Street"].exists, "the worlds go with the runner")
        snapshot("sensory-oddly")

        // Close the sheet; the show is under the board.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["sensory"].firstMatch.waitForExistence(timeout: 3),
                      "it plays under the board")
        snapshot("sensory-playing")
    }
    #endif

    // MARK: - Float pieces (regular iPhones)

    #if os(iOS)
    /// Only a regular, tall iPhone offers "Float pieces", and there it starts on. A dragged
    /// piece floats 2.9 cells above the finger and lands under the piece, not the finger.
    func testFloatPieces() throws {
        app.terminate()
        app.launchArguments = ["-demo", "YES", "-noGameCenter", "YES"]
        app.launch()
        let floatSwitch = app.switches["Float pieces"]
        app.buttons["Settings"].tap()
        let screen = app.windows.firstMatch.frame.size
        guard UIDevice.current.userInterfaceIdiom == .phone, screen.height > screen.width * 1.8 else {
            XCTAssertFalse(floatSwitch.waitForExistence(timeout: 2), "only a regular iPhone offers Float pieces")
            snapshot("no-float-setting")
            throw XCTSkip("Float pieces is only offered on regular iPhones")
        }
        XCTAssertTrue(floatSwitch.waitForExistence(timeout: 3), "a regular iPhone offers Float pieces")
        XCTAssertEqual(floatSwitch.value as? String, "1", "it starts on")
        snapshot("float-setting")

        app.terminate()
        app.launchArguments = ["-demo", "YES", "-noGameCenter", "YES", "-bricks.floatPieces", "YES"]
        app.launch()
        XCTAssertTrue(scoreText.waitForExistence(timeout: 5))
        let before = score

        let start = tray(0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: boardPoint(row: 2 + 2.9, col: 5),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        snapshot("after-float-drag")
        XCTAssertTrue(waitForScore(above: before), "a floating piece drops onto open board (was \(before), now \(score))")
    }
    #endif

    // MARK: - App Store screenshots (iPhone Duo)

    #if os(iOS)
    /// Not a check: stages each App Store screenshot and keeps it in the test results, for
    /// screens `simctl io` can't capture (the iPhone Duo). Runs only when asked, with
    /// `TEST_RUNNER_STORE_SHOTS=1`; see appstore/tools/capture-duo.sh.
    func testStoreScreenshots() throws {
        guard ProcessInfo.processInfo.environment["STORE_SHOTS"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_STORE_SHOTS=1 to capture the App Store screenshots")
        }
        let states = [
            ["-demo", "YES", "-bricks.darkMode", "NO", "-noGameCenter", "YES"],
            ["-celebrate", "3", "-bricks.darkMode", "NO", "-noGameCenter", "YES"],
            ["-gameOver", "YES", "-gameCenterPreview", "YES", "-bricks.darkMode", "NO"],
            ["-demo", "YES", "-bricks.darkMode", "YES", "-noGameCenter", "YES"],
        ]
        for (i, args) in states.enumerated() {
            app.terminate()
            app.launchArguments = args + ["-bricks.bestScore", "4820"]
            app.launch()
            XCTAssertTrue(scoreText.waitForExistence(timeout: 5))
            sleep(2)
            snapshot("store-\(i + 1)")
        }
    }
    #endif

    // MARK: - Mac and iPhone/iPad

    #if os(macOS) || os(iOS)
    func testDragPlacesAPiece() {
        XCTAssertTrue(scoreText.waitForExistence(timeout: 5))
        let before = score

        // The piece sits right under the finger or pointer, so drop it on the cell itself.
        let start = tray(0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        snapshot("before-drag")
        let target = boardPoint(row: 2, col: 5)
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
