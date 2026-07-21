import XCTest

final class Den_BrowserUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
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
    func testNewBoardIsCenteredAfterCreation() throws {
        let app = launchApp(centering: "always")

        // 1. Alpha is focused.
        XCTAssertTrue(board(.alpha, in: app).wait(for: \.isSelected, toEqual: true, timeout: 5))
        enterDenMode(in: app)

        // 2. Press Return to duplicate Alpha. The duplicate is created to its right and focused.
        app.typeKey("\r", modifierFlags: [])

        // 3. Find the new board header. Its identifier starts with "board-header."
        let boardStrip = app.scrollViews["board-strip"].firstMatch
        XCTAssertTrue(boardStrip.waitForExistence(timeout: 5))

        let headerPredicate = NSPredicate(format: "identifier BEGINSWITH 'board-header.'")
        let headersQuery = boardStrip.descendants(matching: .any).matching(headerPredicate)

        // Wait for the new header to appear
        assertEventually("New board header should appear") {
            headersQuery.allElementsBoundByIndex.count == 4
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

        // 4. Assert that the new board is centered in the viewport in Always mode
        assertEventuallyEqual(
            actual: { newBoardHeader.frame.midX },
            expected: boardStrip.frame.midX,
            tolerance: 50,
            message: "New board should be centered in the viewport in Always mode"
        )
    }

    @MainActor
    private func launchApp(centering: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var args = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing", "--fixture", "interaction-basics",
        ]
        if let centering {
            args.append(contentsOf: ["--board-centering", centering])
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
        XCTAssertTrue(board(.bravo, in: app).waitForExistence(timeout: 20))
        XCTAssertTrue(board(.charlie, in: app).waitForExistence(timeout: 20))
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
