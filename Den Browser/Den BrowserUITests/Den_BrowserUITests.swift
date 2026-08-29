import Carbon.HIToolbox
import XCTest

final class Den_BrowserUITests: XCTestCase, BDD {
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
        // Carbon exposes input sources through an untyped CFArray.
        // swiftlint:disable:next force_cast
        let source = try XCTUnwrap(sources.first as! TISInputSource?)
        XCTAssertEqual(TISSelectInputSource(source), noErr)
    }

    @MainActor
    func testClickingInputOnUnfocusedBoardPreservesClickedResponder() throws {
        let app = launchApp(boardCount: .two)
        let alpha = board(.alpha, in: app)
        let bravo = board(.bravo, in: app)
        let bravoInput = boardSurface(.bravo, in: app).textFields["Sheet input"].firstMatch

        given("another Board is focused") {
            XCTAssertTrue(alpha.wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertTrue(bravoInput.waitForExistence(timeout: 5))
        }

        when("clicking the Sheet input in an unfocused Board") {
            bravoInput.click()
            app.typeText("a")
        }

        then("the clicked input receives the first keystroke") {
            XCTAssertTrue(bravo.wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertEqual(bravoInput.value as? String, "a")
        }
    }

    @MainActor
    func testDrawerPreviewReceivesVimAndFormInputAndRetainsAfterDiscarding() throws {
        let app = launchApp(
            boardCount: .one,
            sheetNavigationEnabled: true,
            multipleDrawerItems: true)

        let drawer = app.descendants(matching: .any).matching(identifier: "drawer").firstMatch
        let previewContent = app.staticTexts["result:pending"].firstMatch
        let sheetInput = app.textFields["Sheet input"].firstMatch
        let nextDrawerItem = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Next Drawer Fixture"))
            .firstMatch
        let drawerItem = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Drawer Fixture"))
            .firstMatch

        given("Sheet Navigation is enabled, two Drawer items exist, and the first preview is focused") {
            enterDenMode(in: app)
            app.typeKey(.tab, modifierFlags: [])
            XCTAssertTrue(drawer.waitForExistence(timeout: 5))
            XCTAssertTrue(previewContent.waitForExistence(timeout: 10))
            XCTAssertTrue(nextDrawerItem.waitForExistence(timeout: 10))
            XCTAssertTrue(drawerItem.exists)
        }

        when("moving to the Sheet input and typing in the first preview") {
            app.typeText("gi")
            XCTAssertTrue(sheetInput.waitForExistence(timeout: 5))
            app.typeText("a")
        }

        then("the first Drawer preview accepts Sheet input") {
            XCTAssertEqual(sheetInput.value as? String, "a")
        }

        when("discarding the focused Drawer preview") {
            app.typeKey(.escape, modifierFlags: [])
            app.typeText("x")
        }

        then("the next Drawer preview remains visible") {
            XCTAssertTrue(nextDrawerItem.waitForNonExistence(timeout: 5))
            XCTAssertTrue(drawerItem.exists)
        }

        when("using Sheet Navigation in the remaining preview") {
            app.typeText("gi")
        }

        when("typing into the Sheet input from the remaining preview") {
            XCTAssertTrue(sheetInput.waitForExistence(timeout: 5))
            app.typeText("b")
        }

        then("the remaining preview accepts Sheet input") {
            XCTAssertEqual(sheetInput.value as? String, "b")
        }
    }

    @MainActor
    func testOrganizesBoardsUsingPointer() throws {
        let app = launchApp(boardCount: .three)
        let bravo = board(.bravo, in: app)
        let charlie = board(.charlie, in: app)

        given("Bravo and Charlie are visible Boards") {
            XCTAssertTrue(bravo.exists)
            XCTAssertTrue(charlie.exists)
        }

        when("dragging Bravo to the right of Charlie") {
            boardHeader(.bravo, in: app).click()
            XCTAssertTrue(bravo.wait(for: \.isSelected, toEqual: true, timeout: 5))
            let start = boardHeader(.bravo, in: app)
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = charlie.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.1))
            start.press(forDuration: 0.5, thenDragTo: end)
        }

        then("Bravo is positioned to the right of Charlie") {
            assertEventually("Bravo should move to the right of Charlie") {
                bravo.frame.minX > charlie.frame.minX
            }
        }
    }

    @MainActor
    func testOrganizesOverviewBoardsUsingPointer() throws {
        let app = launchApp(fixture: .overviewBoardPair)

        given("Overview shows the fixture Boards") {
            enterDenMode(in: app)
            app.typeKey("o", modifierFlags: [])
        }

        let bravo = overviewBoard(.bravo, in: app)
        let charlie = overviewBoard(.charlie, in: app)

        given("Bravo and Charlie are exposed as draggable Overview Boards") {
            XCTAssertTrue(
                bravo.wait(for: \.isHittable, toEqual: true, timeout: 5),
                "Bravo should be ready for pointer interaction")
            XCTAssertTrue(
                charlie.wait(for: \.isHittable, toEqual: true, timeout: 5),
                "Charlie should be ready for pointer interaction")
        }

        when("dragging Bravo to the right of Charlie") {
            let start = bravo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = charlie.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
            start.press(forDuration: 0.5, thenDragTo: end)
        }

        then("Bravo is positioned to the right of Charlie in Overview") {
            assertEventually("Overview should reorder Bravo after Charlie") {
                bravo.frame.minX > charlie.frame.minX
            }
        }
    }

    @MainActor
    func testReordersDesksUsingPointer() throws {
        let app = launchApp(boardCount: .one)
        let second = desk(.second, in: app)
        let third = desk(.third, in: app)

        given("Second and Third are visible Desks") {
            XCTAssertTrue(second.exists)
            XCTAssertTrue(third.exists)
        }

        when("dragging Second to the right of Third") {
            let start = second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = third.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            start.press(forDuration: 0.5, thenDragTo: end)
        }

        then("Second is positioned to the right of Third") {
            assertEventually("Second should move to the right of Third") {
                second.frame.minX > third.frame.minX
            }
        }
    }

    @MainActor
    func testTerminalBoardDenModeToggleAndExit() throws {
        let app = launchApp(boardCount: .two, terminalBoard: true)
        let alpha = board(.alpha, in: app)
        let bravo = board(.bravo, in: app)
        let sheetInputWindow = app.windows["UI Testing · SHEET INPUT"]
        let terminalInputWindow = app.windows["UI Testing · TERMINAL INPUT"]
        let surfacePredicate = NSPredicate(format: "identifier BEGINSWITH 'board-surface.'")
        let surfaces = app.scrollViews["board-strip"].firstMatch
            .descendants(matching: .any)
            .matching(surfacePredicate)

        enterDenMode(in: app)
        app.typeKey("l", modifierFlags: [])
        XCTAssertTrue(bravo.wait(for: \.isSelected, toEqual: true, timeout: 5))
        app.typeKey(",", modifierFlags: [.control])
        XCTAssertTrue(
            sheetInputWindow.waitForExistence(timeout: 5),
            "Den Mode should return to Sheet Input after focusing Bravo")
        XCTAssertTrue(bravo.isSelected)

        enterDenMode(in: app)
        app.typeKey("h", modifierFlags: [])
        XCTAssertTrue(alpha.wait(for: \.isSelected, toEqual: true, timeout: 5))
        app.typeKey(",", modifierFlags: [.control])
        XCTAssertTrue(
            terminalInputWindow.waitForExistence(timeout: 5),
            "Den Mode should return to Terminal Input after focusing Alpha")
        XCTAssertTrue(alpha.isSelected)

        when("typing a Shell command after returning from Den Mode") {
            app.typeText("exit")
            app.typeKey(.return, modifierFlags: [])
        }

        then("the Terminal Board receives the command and exits") {
            assertEventually("Terminal Board should be removed after its Shell exits", timeout: 10) {
                surfaces.allElementsBoundByIndex.count == 1
            }
        }
    }

    @MainActor
    func testDirectDeskSwitchAndDenModeFocusCycle() throws {
        let app = launchApp(fixture: .focusedNonLeadingBoard)
        let alpha = board(.alpha, in: app)
        let charlie = board(.charlie, in: app)
        let charlieInput = boardSurface(.charlie, in: app).textFields["Sheet input"].firstMatch

        given("the second Desk has a non-leading Focused Board") {
            XCTAssertTrue(charlie.wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertTrue(charlieInput.waitForExistence(timeout: 5))
            charlieInput.click()
            app.typeText("a")
        }

        when("toggling Den Mode without changing Desks") {
            charlieInput.typeKey(",", modifierFlags: .control)
            assertDenMode(in: app)
            app.typeKey(",", modifierFlags: .control)
            XCTAssertTrue(app.windows["UI Testing · SHEET INPUT"].waitForExistence(timeout: 5))
            app.typeText("b")
        }

        when("switching away and returning by Desk number") {
            enterDenMode(in: app)
            app.typeKey("1", modifierFlags: [])
            XCTAssertTrue(alpha.wait(for: \.isSelected, toEqual: true, timeout: 5))
            enterDenMode(in: app)
            app.typeKey("2", modifierFlags: [])
            XCTAssertTrue(charlie.wait(for: \.isSelected, toEqual: true, timeout: 5))
        }

        then("the Focused Board receives Sheet Input across both cycles") {
            XCTAssertTrue(charlieInput.waitForExistence(timeout: 5))
            app.typeText("c")
            XCTAssertEqual(charlieInput.value as? String, "abc")
        }
    }

    @MainActor
    private func launchApp(
        fixture: UITestFixture = .interactionBasics,
        boardCount: UITestBoardCount = .three,
        terminalBoard: Bool = false,
        sheetNavigationEnabled: Bool = false,
        multipleDrawerItems: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var args = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing", "--fixture", fixture.rawValue,
            "--board-count", boardCount.rawValue,
        ]
        if terminalBoard {
            args.append("--terminal-board")
        }
        if sheetNavigationEnabled {
            args.append("--enable-sheet-navigation")
        }
        if multipleDrawerItems {
            args.append("--multiple-drawer-items")
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
        XCTAssertTrue(board(fixture.initialBoard, in: app).waitForExistence(timeout: 20))
        if fixture == .interactionBasics {
            if boardCount != .one {
                XCTAssertTrue(board(.bravo, in: app).exists)
            }
            if boardCount == .three {
                XCTAssertTrue(board(.charlie, in: app).exists)
            }
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
    private func boardSurface(_ board: FixtureBoard, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "board-surface.\(board.rawValue)")
            .firstMatch
    }

    @MainActor
    private func boardHeader(_ board: FixtureBoard, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "board-header.\(board.rawValue)").firstMatch
    }

    @MainActor
    private func overviewBoard(_ board: FixtureBoard, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "overview-board.\(board.rawValue)")
            .firstMatch
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
}

@MainActor
final class Den_BrowserUIPerformanceTests: XCTestCase {
    override func tearDownWithError() throws {
        MainActor.assumeIsolated {
            XCUIApplication().terminate()
        }
        try super.tearDownWithError()
    }

    func testApplicationLaunchPerformance() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing", "--fixture", UITestFixture.interactionBasics.rawValue,
            "--board-count", UITestBoardCount.one.rawValue,
        ]
        app.launchEnvironment["DEN_UI_TEST_RUN_ID"] = UUID().uuidString

        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(
            metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)],
            options: options
        ) {
            app.launch()
        }
    }
}

private enum UITestFixture: String {
    case interactionBasics = "interaction-basics"
    case overviewBoardPair = "overview-board-pair"
    case focusedNonLeadingBoard = "focused-non-leading-board"

    var initialBoard: FixtureBoard {
        switch self {
        case .focusedNonLeadingBoard: .charlie
        case .overviewBoardPair: .bravo
        default: .alpha
        }
    }
}

private enum FixtureBoard: String, CaseIterable {
    case alpha = "00000000-0000-0000-0000-000000000301"
    case bravo = "00000000-0000-0000-0000-000000000302"
    case charlie = "00000000-0000-0000-0000-000000000303"

    static var allSurfaceIdentifiers: Set<String> {
        Set(allCases.map { "board-surface.\($0.rawValue)" })
    }
}

private enum FixtureDesk: String {
    case second = "00000000-0000-0000-0000-000000000201"
    case third = "00000000-0000-0000-0000-000000000202"
}

private enum UITestBoardCount: String {
    case one
    case two
    case three
}
