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
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing", "--fixture", "interaction-basics",
        ]
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
}

private enum FixtureBoard: String {
    case alpha = "00000000-0000-0000-0000-000000000301"
    case bravo = "00000000-0000-0000-0000-000000000302"
    case charlie = "00000000-0000-0000-0000-000000000303"
}
