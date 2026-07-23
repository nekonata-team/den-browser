import Carbon.HIToolbox
import XCTest

final class Den_BrowserUITests: XCTestCase {
    private var previousInputSource: TISInputSource?

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Keep synthetic text input on Apple's ABC layout; restore user's IME in tearDown.
        previousInputSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        try selectInputSource(id: "com.apple.keylayout.ABC")
    }

    override func tearDownWithError() throws {
        MainActor.assumeIsolated {
            XCUIApplication().terminate()
        }
        if let previousInputSource {
            XCTAssertEqual(TISSelectInputSource(previousInputSource), noErr)
        }
    }

    private func selectInputSource(id: String) throws {
        let sources =
            TISCreateInputSourceList(
                [kTISPropertyInputSourceID: id] as CFDictionary,
                false
            ).takeRetainedValue() as Array
        let source = try XCTUnwrap(sources.first as! TISInputSource?)
        XCTAssertEqual(TISSelectInputSource(source), noErr)
    }

    @MainActor
    func testSheetInputAndDenModeFocusCycle() throws {
        let app = launchApp()
        let sheetInput = app.textFields["Sheet input"].firstMatch
        XCTAssertTrue(sheetInput.waitForExistence(timeout: 10))

        sheetInput.click()
        sheetInput.typeText("hello")
        sheetInput.typeKey(",", modifierFlags: .control)
        assertDenMode(in: app)

        app.typeKey(",", modifierFlags: .control)

        XCTAssertTrue(sheetInput.waitForExistence(timeout: 5))
        sheetInput.click()
        sheetInput.typeText(" world")
        XCTAssertEqual(sheetInput.value as? String, "hello world")
    }

    @MainActor
    func testOrganizesBoardsUsingPointer() throws {
        let app = launchApp()
        let bravo = board(.bravo, in: app)
        let charlie = board(.charlie, in: app)

        boardHeader(.bravo, in: app).click()
        XCTAssertTrue(bravo.wait(for: \.isSelected, toEqual: true, timeout: 5))

        let start = boardHeader(.bravo, in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = charlie.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.1))

        start.press(forDuration: 0.5, thenDragTo: end)

        assertEventually("Bravo should move to the right of Charlie") {
            bravo.frame.minX > charlie.frame.minX
        }
    }

    @MainActor
    func testReordersDesksUsingPointer() throws {
        let app = launchApp()
        let second = desk(.second, in: app)
        let third = desk(.third, in: app)

        let start = second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = third.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.5, thenDragTo: end)

        assertEventually("Second should move to the right of Third") {
            second.frame.minX > third.frame.minX
        }
    }

    @MainActor
    func testNewBoardAnimatesIntoBoardStrip() throws {
        let app = launchApp(singleBoard: true)

        // Start from one Board sized to the viewport.
        XCTAssertTrue(board(.alpha, in: app).wait(for: \.isSelected, toEqual: true, timeout: 5))
        enterDenMode(in: app)
        app.typeText("w1")
        app.typeKey(.escape, modifierFlags: [])

        let boardStrip = app.scrollViews["board-strip"].firstMatch
        XCTAssertTrue(boardStrip.waitForExistence(timeout: 5))
        assertEventually("The initial Board should fill most of the Board Strip") {
            self.board(.alpha, in: app).frame.width > boardStrip.frame.width * 0.85
        }

        // Duplicate Alpha. The new Board must become visible and finish centered.
        if !app.windows["UI Testing · DEN MODE"].exists {
            enterDenMode(in: app)
        }
        app.typeKey("\r", modifierFlags: [])

        let headerPredicate = NSPredicate(format: "identifier BEGINSWITH 'board-header.'")
        let headersQuery = boardStrip.descendants(matching: .any).matching(headerPredicate)

        assertEventually("New board header should appear") {
            headersQuery.allElementsBoundByIndex.count == 2
        }

        let allHeaders = headersQuery.allElementsBoundByIndex

        guard
            let newBoardHeader = allHeaders.first(where: {
                !FixtureBoard.allHeaderIdentifiers.contains($0.identifier)
            })
        else {
            XCTFail("Failed to find the newly created board header")
            return
        }
        XCTAssertTrue(newBoardHeader.wait(for: \.isSelected, toEqual: true, timeout: 5))

        assertEventuallyEqual(
            actual: { newBoardHeader.frame.midX },
            expected: boardStrip.frame.midX,
            tolerance: 50,
            message: "New Board should finish centered after its insertion animation"
        )
    }

    @MainActor
    private func launchApp(singleBoard: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var args = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing", "--fixture", "interaction-basics",
        ]
        if singleBoard {
            args.append("--single-board")
        }
        app.launchArguments = args
        app.launchEnvironment["DEN_UI_TEST_RUN_ID"] = UUID().uuidString
        app.launch()

        if !app.windows.firstMatch.waitForExistence(timeout: 2) {
            let profileMenu = app.menuBars.menuBarItems["Profile"]
            XCTAssertTrue(profileMenu.waitForExistence(timeout: 10), "Profile menu bar item should exist")
            profileMenu.click()

            let uiTestingMenuItem = app.menuItems["UI Testing"]
            XCTAssertTrue(uiTestingMenuItem.waitForExistence(timeout: 10), "UI Testing menu item should exist")
            uiTestingMenuItem.click()
        }

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10), "Application window should appear")
        XCTAssertTrue(board(.alpha, in: app).waitForExistence(timeout: 20))
        if !singleBoard {
            XCTAssertTrue(board(.bravo, in: app).waitForExistence(timeout: 20))
            XCTAssertTrue(board(.charlie, in: app).waitForExistence(timeout: 20))
        }
        return app
    }

    @MainActor
    private func enterDenMode(in app: XCUIApplication) {
        app.typeKey(",", modifierFlags: .control)
        assertDenMode(in: app)
    }

    @MainActor
    private func assertDenMode(in app: XCUIApplication) {
        XCTAssertTrue(
            app.windows["UI Testing · DEN MODE"].waitForExistence(timeout: 5),
            "Den should enter Den Mode")
    }

    @MainActor
    private func board(_ board: FixtureBoard, in app: XCUIApplication) -> XCUIElement {
        boardHeader(board, in: app)
    }

    @MainActor
    private func boardHeader(_ board: FixtureBoard, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "board-header.\(board.rawValue)").firstMatch
    }

    @MainActor
    private func desk(_ desk: FixtureDesk, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "desk-switcher.\(desk.rawValue)").firstMatch
    }

    @MainActor
    private func assertEventually(
        _ message: String,
        timeout: TimeInterval = 5,
        condition: @escaping () -> Bool
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() },
            object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
    }

    @MainActor
    private func assertEventuallyEqual(
        actual: @escaping () -> CGFloat,
        expected: CGFloat,
        tolerance: CGFloat,
        message: String,
        timeout: TimeInterval = 5
    ) {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            let actVal = actual()
            if abs(actVal - expected) < tolerance {
                return
            }
            // Run loop spin to allow UI updates
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        let actVal = actual()
        XCTAssertEqual(actVal, expected, accuracy: tolerance, message)
    }
}

private enum FixtureBoard: String, CaseIterable {
    case alpha = "00000000-0000-0000-0000-000000000301"
    case bravo = "00000000-0000-0000-0000-000000000302"
    case charlie = "00000000-0000-0000-0000-000000000303"

    static var allHeaderIdentifiers: Set<String> {
        Set(allCases.map { "board-header.\($0.rawValue)" })
    }
}

private enum FixtureDesk: String {
    case second = "00000000-0000-0000-0000-000000000201"
    case third = "00000000-0000-0000-0000-000000000202"
}
