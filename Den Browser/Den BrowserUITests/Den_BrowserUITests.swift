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
    func testNewBoardIsCenteredAfterCreation_Always() throws {
        let app = launchApp(centering: "always")

        // 1. Alpha is focused. Enter Den Mode and resize 3 boards to fit the strip.
        XCTAssertTrue(board(.alpha, in: app).wait(for: \.isSelected, toEqual: true, timeout: 5))
        enterDenMode(in: app)
        resizeBoardsToFit(3, in: app)

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
    func testNewBoardIsRightAlignedAfterCreation_Never() throws {
        let app = launchApp(centering: "never")

        // 1. Alpha is focused. Enter Den Mode and resize 3 boards to fit the strip.
        XCTAssertTrue(board(.alpha, in: app).wait(for: \.isSelected, toEqual: true, timeout: 5))
        enterDenMode(in: app)
        resizeBoardsToFit(3, in: app)

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

        // 4. Without trailing centering padding, the new last board stops at the right edge.
        assertEventuallyEqual(
            actual: { newBoardHeader.frame.maxX },
            expected: boardStrip.frame.maxX - 10,
            tolerance: 15,
            message: "New board should remain right-aligned in Never mode"
        )
    }

    @MainActor
    func testNewBoardIsCenteredAfterCreation_OnOverflow() throws {
        let app = launchApp(centering: "on-overflow")

        // 1. Alpha is focused. Enter Den Mode and resize 3 boards to fit the strip.
        XCTAssertTrue(board(.alpha, in: app).wait(for: \.isSelected, toEqual: true, timeout: 5))
        enterDenMode(in: app)
        resizeBoardsToFit(3, in: app)

        let boardStrip = app.scrollViews["board-strip"].firstMatch
        XCTAssertTrue(boardStrip.waitForExistence(timeout: 5))

        // Verify that initially (with 3 boards under fit-3 config), it is NOT overflowed,
        // meaning no centering scroll occurs. Alpha should be on the left part of the viewport.
        let alphaHeader = boardHeader(.alpha, in: app)
        XCTAssertTrue(alphaHeader.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            alphaHeader.frame.midX,
            boardStrip.frame.midX - 50,
            "Initially Alpha should not be centered in OnOverflow mode since it hasn't overflowed"
        )

        // 2. Press Return to duplicate Alpha. The duplicate is created to its right and focused.
        app.typeKey("\r", modifierFlags: [])

        // 3. Find the new board header. Its identifier starts with "board-header."
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

        // 4. The fourth board overflows, so the new focused board is centered.
        assertEventuallyEqual(
            actual: { newBoardHeader.frame.midX },
            expected: boardStrip.frame.midX,
            tolerance: 50,
            message: "New board should be centered after overflow in OnOverflow mode"
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
    private func resizeBoardsToFit(_ count: Int, in app: XCUIApplication) {
        app.typeKey("w", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.1)  // Wait for panel to open
        app.typeKey(String(count), modifierFlags: [])
        // Successful resize automatically closes the panel, wait for layout and focus to settle
        Thread.sleep(forTimeInterval: 0.2)
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
