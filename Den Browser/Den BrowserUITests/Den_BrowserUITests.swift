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
    func testSheetInputAndDenModeFocusCycle() throws {
        let app = launchApp()
        let sheetInput = app.textFields["Sheet input"].firstMatch

        given("the initial Sheet input is visible") {
            XCTAssertTrue(sheetInput.waitForExistence(timeout: 10))
            XCTAssertTrue(app.windows["UI Testing · SHEET INPUT"].waitForExistence(timeout: 5))
        }

        when("entering Den Mode after typing into the Sheet input") {
            sheetInput.click()
            sheetInput.typeText("hello")
            sheetInput.typeKey(",", modifierFlags: .control)
            assertDenMode(in: app)
        }

        when("returning to Sheet mode") {
            app.typeKey(",", modifierFlags: .control)
            XCTAssertTrue(app.windows["UI Testing · SHEET INPUT"].waitForExistence(timeout: 5))
        }

        when("typing more input") {
            XCTAssertTrue(sheetInput.waitForExistence(timeout: 5))
            sheetInput.click()
            sheetInput.typeText("!")
        }

        then("the Sheet input regains focus and retains the previous text") {
            XCTAssertEqual(sheetInput.value as? String, "hello!")
        }
    }

    @MainActor
    func testDrawerPreviewReceivesVimAndFormInput() throws {
        let app = launchApp(sheetNavigationEnabled: true)

        let drawer = app.descendants(matching: .any).matching(identifier: "drawer").firstMatch
        let previewContent = app.staticTexts["result:pending"].firstMatch
        let sheetInput = app.textFields["Sheet input"].firstMatch

        given("Sheet Navigation is enabled and a Drawer preview is focused") {
            enterDenMode(in: app)
            app.typeKey(.tab, modifierFlags: [])
            XCTAssertTrue(drawer.waitForExistence(timeout: 5))
            XCTAssertTrue(previewContent.waitForExistence(timeout: 10))
        }

        when("moving to the Sheet input and typing") {
            app.typeText("gi")
            XCTAssertTrue(sheetInput.waitForExistence(timeout: 5))
            app.typeText("drawer input")
        }

        then("the Drawer preview forwards input to the Sheet") {
            XCTAssertEqual(sheetInput.value as? String, "drawer input")
        }
    }

    @MainActor
    func testDrawerPreviewRetainsSheetNavigationAfterDiscardingIntoNextPreview() throws {
        let app = launchApp(sheetNavigationEnabled: true, multipleDrawerItems: true)

        let drawer = app.descendants(matching: .any).matching(identifier: "drawer").firstMatch
        let nextDrawerItem = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Next Drawer Fixture"))
            .firstMatch
        let drawerItem = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Drawer Fixture"))
            .firstMatch

        given("two Drawer items exist and the first preview is focused") {
            enterDenMode(in: app)
            app.typeKey(.tab, modifierFlags: [])
            XCTAssertTrue(drawer.waitForExistence(timeout: 5))
            XCTAssertTrue(nextDrawerItem.waitForExistence(timeout: 10))
            XCTAssertTrue(drawerItem.exists)
        }

        when("discarding the focused Drawer preview") {
            app.typeText("x")
        }

        then("the next Drawer preview remains visible") {
            XCTAssertTrue(nextDrawerItem.waitForNonExistence(timeout: 5))
            XCTAssertTrue(drawerItem.exists)
        }

        let sheetInput = app.textFields["Sheet input"].firstMatch
        when("using Sheet Navigation in the remaining preview") {
            app.typeText("gi")
        }

        when("typing into the Sheet input from the remaining preview") {
            XCTAssertTrue(sheetInput.waitForExistence(timeout: 5))
            app.typeText("next preview input")
        }

        then("the remaining preview accepts Sheet input") {
            XCTAssertEqual(sheetInput.value as? String, "next preview input")
        }
    }

    @MainActor
    func testDrawerSearchAppearsOnDemand() throws {
        let app = launchApp()

        let drawer = app.descendants(matching: .any).matching(identifier: "drawer").firstMatch
        let search = app.textFields["drawer-search"].firstMatch

        given("the Drawer is open without its search field") {
            enterDenMode(in: app)
            app.typeKey(.tab, modifierFlags: [])
            XCTAssertTrue(drawer.waitForExistence(timeout: 5))
            XCTAssertFalse(search.exists)
        }

        when("opening Drawer search and entering a query") {
            app.buttons["Search Drawer Items"].click()
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            app.typeText("drawer")
            app.typeKey(.return, modifierFlags: [])
        }

        then("the entered query remains visible") {
            XCTAssertEqual(search.value as? String, "drawer")
            XCTAssertTrue(search.exists)
        }

        when("dismissing Drawer search") {
            app.typeKey(.escape, modifierFlags: [])
        }

        then("Drawer search disappears") {
            XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        }
    }

    @MainActor
    func testOrganizesBoardsUsingPointer() throws {
        let app = launchApp()
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
    func testReordersDesksUsingPointer() throws {
        let app = launchApp()
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
    func testNewBoardAnimatesIntoBoardStrip() throws {
        let app = launchApp(singleBoard: true)
        let boardStrip = app.scrollViews["board-strip"].firstMatch

        given("one Board fills the Board Strip") {
            XCTAssertTrue(board(.alpha, in: app).wait(for: \.isSelected, toEqual: true, timeout: 5))
            enterDenMode(in: app)
            app.typeText("w1")
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(boardStrip.waitForExistence(timeout: 5))
            assertEventually("The initial Board should fill most of the Board Strip") {
                self.boardSurface(.alpha, in: app).frame.width > boardStrip.frame.width * 0.85
            }
        }

        when("duplicating the focused Board") {
            if !app.windows["UI Testing · DEN MODE"].exists {
                enterDenMode(in: app)
            }
            app.typeKey("\r", modifierFlags: [])
        }

        let surfacePredicate = NSPredicate(format: "identifier BEGINSWITH 'board-surface.'")
        let surfacesQuery = boardStrip.descendants(matching: .any).matching(surfacePredicate)

        then("the new Board is selected and settles at the center") {
            assertEventually("New board surface should appear") {
                surfacesQuery.allElementsBoundByIndex.count == 2
            }

            guard
                let newBoardSurface = surfacesQuery.allElementsBoundByIndex.first(where: {
                    !FixtureBoard.allSurfaceIdentifiers.contains($0.identifier)
                })
            else {
                XCTFail("Failed to find the newly created board surface")
                return
            }
            let newBoardID = String(newBoardSurface.identifier.dropFirst("board-surface.".count))
            let newBoardHeader = app.descendants(matching: .any)
                .matching(identifier: "board-header.\(newBoardID)")
                .firstMatch
            XCTAssertTrue(newBoardHeader.wait(for: \.isSelected, toEqual: true, timeout: 5))

            assertEventuallyEqual(
                actual: { newBoardSurface.frame.midX },
                expected: boardStrip.frame.midX,
                tolerance: 50,
                message: "New Board should finish centered after its insertion animation"
            )
        }
    }

    @MainActor
    func testTerminalBoardStartsAndExitRemovesIt() throws {
        let app = launchApp(singleBoard: true)
        let boardStrip = app.scrollViews["board-strip"].firstMatch
        let surfacePredicate = NSPredicate(format: "identifier BEGINSWITH 'board-surface.'")
        let surfaces = boardStrip.descendants(matching: .any).matching(surfacePredicate)

        when("creating a Terminal Board from the Open Board panel") {
            app.typeKey("t", modifierFlags: .command)
            let input = app.textFields["Open URL or search"].firstMatch
            XCTAssertTrue(input.waitForExistence(timeout: 5))
            input.typeText(":terminal /tmp")
            input.typeKey(.return, modifierFlags: [])
        }

        then("a second Board appears") {
            assertEventually("Terminal Board should appear", timeout: 10) {
                surfaces.allElementsBoundByIndex.count == 2
            }
        }

        when("the Shell exits") {
            app.typeText("exit")
            app.typeKey(.return, modifierFlags: [])
        }

        then("the Terminal Board is removed") {
            assertEventually("Terminal Board should be removed", timeout: 10) {
                surfaces.allElementsBoundByIndex.count == 1
            }
        }
    }

    @MainActor
    func testDenModeCommaOpensSettingsAboveTerminalBoard() throws {
        let app = launchApp(singleBoard: true, terminalBoard: true)

        let profileWindowCount = app.windows.count
        enterDenMode(in: app)
        app.typeKey(",", modifierFlags: [])

        assertEventually("Den Mode comma should open Settings", timeout: 5) {
            app.windows.count > profileWindowCount
        }
    }

    @MainActor
    func testTerminalBoardDenModeToggleDoesNotExitImmediately() throws {
        let app = launchApp(terminalBoard: true)
        let alpha = board(.alpha, in: app)
        let bravo = board(.bravo, in: app)
        let sheetInputWindow = app.windows["UI Testing · SHEET INPUT"]
        let terminalInputWindow = app.windows["UI Testing · TERMINAL INPUT"]

        for _ in 0..<4 {
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
        }
    }

    @MainActor
    func testOverviewEnterFromTerminalInputFocusesAnotherDesk() throws {
        let app = launchApp(terminalBoard: true)
        let alpha = board(.alpha, in: app)
        let bravo = board(.bravo, in: app)
        let sheetInputWindow = app.windows["UI Testing · SHEET INPUT"]
        let terminalInputWindow = app.windows["UI Testing · TERMINAL INPUT"]

        given("a Web Board is on the next Desk and Terminal Input is focused") {
            enterDenMode(in: app)
            app.typeKey("l", modifierFlags: [])
            XCTAssertTrue(bravo.wait(for: \.isSelected, toEqual: true, timeout: 5))
            app.typeKey("2", modifierFlags: [.shift])
            app.typeKey(.tab, modifierFlags: [.control, .shift])
            XCTAssertTrue(alpha.wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertTrue(terminalInputWindow.waitForExistence(timeout: 5))
        }

        when("selecting that Desk in Overview and pressing Enter") {
            enterDenMode(in: app)
            app.typeKey("o", modifierFlags: [])
            app.typeKey("j", modifierFlags: [])
            app.typeKey(.return, modifierFlags: [])
        }

        then("the selected Board on the other Desk receives focus") {
            XCTAssertTrue(bravo.wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertTrue(sheetInputWindow.waitForExistence(timeout: 5))

            let stableUntil = Date(timeIntervalSinceNow: 1)
            while Date() < stableUntil {
                if !bravo.isSelected || terminalInputWindow.exists || !sheetInputWindow.exists {
                    XCTFail("Overview Enter should keep the target Desk focused")
                    break
                }
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            }
        }
    }

    @MainActor
    func testOverviewEnterCentersBoardOnAnotherDesk() throws {
        let app = launchApp(centerBoardsAlways: true)
        let boardStrip = app.scrollViews["board-strip"].firstMatch
        let bravo = board(.bravo, in: app)
        let charlie = board(.charlie, in: app)
        let charlieSurface = boardSurface(.charlie, in: app)

        given("the next Desk has enough Boards to require scrolling") {
            enterDenMode(in: app)
            app.typeKey("l", modifierFlags: [])
            XCTAssertTrue(bravo.wait(for: \.isSelected, toEqual: true, timeout: 5))
            app.typeKey("2", modifierFlags: [.shift])
            app.typeKey(.tab, modifierFlags: [.control, .shift])

            enterDenMode(in: app)
            app.typeKey("l", modifierFlags: [])
            XCTAssertTrue(charlie.wait(for: \.isSelected, toEqual: true, timeout: 5))
            app.typeKey("2", modifierFlags: [.shift])

            for _ in 0..<4 {
                enterDenMode(in: app)
                app.typeKey(.return, modifierFlags: [])
            }
            app.typeKey(.tab, modifierFlags: [.control, .shift])
        }

        when("selecting a middle Board in Overview and pressing Enter") {
            enterDenMode(in: app)
            app.typeKey("o", modifierFlags: [])
            app.typeKey("j", modifierFlags: [])
            app.typeKey("l", modifierFlags: [])
            app.typeKey(.return, modifierFlags: [])
        }

        then("the selected Board is centered in the Board Strip") {
            XCTAssertTrue(charlie.wait(for: \.isSelected, toEqual: true, timeout: 5))
            assertEventuallyEqual(
                actual: { charlieSurface.frame.midX },
                expected: boardStrip.frame.midX,
                tolerance: 15,
                message: "Overview selection should center the Board on the target Desk"
            )
        }
    }

    @MainActor
    func testRemovingFocusedBoardSettlesAtLeadingEdge() throws {
        let app = launchApp()
        let boardStrip = app.scrollViews["board-strip"].firstMatch
        let alpha = boardSurface(.alpha, in: app)
        let bravo = boardSurface(.bravo, in: app)
        let alphaHeader = boardHeader(.alpha, in: app)
        let bravoHeader = boardHeader(.bravo, in: app)

        given("Bravo is the focused Board") {
            bravoHeader.click()
            XCTAssertTrue(bravoHeader.wait(for: \.isSelected, toEqual: true, timeout: 5))
        }

        when("removing the focused Board") {
            enterDenMode(in: app)
            app.typeText("d")
        }

        then("Alpha remains focused and settles at the leading edge") {
            XCTAssertTrue(bravo.waitForNonExistence(timeout: 5))
            XCTAssertTrue(alphaHeader.wait(for: \.isSelected, toEqual: true, timeout: 5))
            assertEventually("Remaining Boards should settle at the leading edge") {
                abs(alpha.frame.minX - boardStrip.frame.minX) < 30
            }
        }
    }

    @MainActor
    func testOnOverflowKeepsBoardCoordinatesStableAcrossBoundary() throws {
        let app = launchApp(centerBoardsOnOverflow: true)
        let boardStrip = app.scrollViews["board-strip"].firstMatch
        let alpha = boardSurface(.alpha, in: app)
        let charlie = boardSurface(.charlie, in: app)

        given("the Boards start centered without overflowing") {
            enterDenMode(in: app)
            app.typeText("w3")
            app.typeKey(.escape, modifierFlags: [])
            boardHeader(.bravo, in: app).click()

            assertEventuallyEqual(
                actual: { (alpha.frame.minX + charlie.frame.maxX) / 2 },
                expected: boardStrip.frame.midX,
                tolerance: 50,
                message: "Boards should start centered without overflowing"
            )
        }

        let initialAlphaX = alpha.frame.minX

        when("duplicating a Board across the overflow boundary") {
            if !app.windows["UI Testing · DEN MODE"].exists {
                enterDenMode(in: app)
            }
            app.typeKey(.return, modifierFlags: [])
        }

        let surfacePredicate = NSPredicate(format: "identifier BEGINSWITH 'board-surface.'")
        let surfacesQuery = boardStrip.descendants(matching: .any).matching(surfacePredicate)
        then("the new Board appears after crossing the boundary") {
            assertEventually("New board surface should appear") {
                surfacesQuery.allElementsBoundByIndex.count == 4
            }
        }

        let newBoardSurfaceElement = surfacesQuery.allElementsBoundByIndex.first {
            !FixtureBoard.allSurfaceIdentifiers.contains($0.identifier)
        }
        let newBoardIdentifier = try XCTUnwrap(newBoardSurfaceElement?.identifier)
        let newBoardSurface =
            app.descendants(matching: .any)
            .matching(identifier: newBoardIdentifier)
            .firstMatch

        then("the new Board centers after crossing the boundary") {
            assertEventuallyEqual(
                actual: { newBoardSurface.frame.midX },
                expected: boardStrip.frame.midX,
                tolerance: 50,
                message: "New Board should center after crossing the overflow boundary"
            )
        }

        when("removing the newly created Board") {
            enterDenMode(in: app)
            app.typeText("d")
        }

        then("the original Boards return to their centered coordinates") {
            XCTAssertTrue(newBoardSurface.waitForNonExistence(timeout: 5))
            assertEventuallyEqual(
                actual: { alpha.frame.minX },
                expected: initialAlphaX,
                tolerance: 30,
                message: "Boards should return to the same centered coordinates"
            )
        }
    }

    @MainActor
    func testFiltersBoardsInFocusedDeskAndEntersSelection() throws {
        let app = launchApp(centerBoardsAlways: true)
        let filter = app.descendants(matching: .any).matching(identifier: "desk-filter").firstMatch
        let boardStrip = app.scrollViews["board-strip"].firstMatch
        let charlieSurface = boardSurface(.charlie, in: app)

        given("the focused Desk contains Alpha, Bravo, and Charlie") {
            enterDenMode(in: app)
            app.typeText("/")
            XCTAssertTrue(filter.waitForExistence(timeout: 5))
        }

        when("filtering for Charlie") {
            app.typeText("Charlie")
        }

        then("only Charlie remains visible") {
            assertEventually("Only the matching Board should remain visible") {
                self.board(.charlie, in: app).exists
                    && !self.board(.alpha, in: app).exists
                    && !self.board(.bravo, in: app).exists
            }
        }

        when("confirming the filtered selection") {
            app.typeKey("\r", modifierFlags: [])
            app.typeKey("\r", modifierFlags: [])
        }

        then("Charlie is focused and all Boards are visible again") {
            XCTAssertTrue(board(.charlie, in: app).wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertTrue(app.windows["UI Testing · SHEET INPUT"].waitForExistence(timeout: 5))
            XCTAssertTrue(board(.alpha, in: app).waitForExistence(timeout: 5))
            XCTAssertTrue(board(.charlie, in: app).waitForExistence(timeout: 5))
            assertEventuallyEqual(
                actual: { charlieSurface.frame.midX },
                expected: boardStrip.frame.midX,
                tolerance: 30,
                message: "Filtered Board should center after all Boards return"
            )
        }
    }

    @MainActor
    private func launchApp(
        singleBoard: Bool = false,
        terminalBoard: Bool = false,
        sheetNavigationEnabled: Bool = false,
        multipleDrawerItems: Bool = false,
        centerBoardsOnOverflow: Bool = false,
        centerBoardsAlways: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var args = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing", "--fixture", "interaction-basics",
        ]
        if singleBoard {
            args.append("--single-board")
        }
        if terminalBoard {
            args.append("--terminal-board")
        }
        if sheetNavigationEnabled {
            args.append("--enable-sheet-navigation")
        }
        if multipleDrawerItems {
            args.append("--multiple-drawer-items")
        }
        if centerBoardsOnOverflow {
            args.append("--center-boards-on-overflow")
        }
        if centerBoardsAlways {
            args.append("--center-boards-always")
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
            XCTAssertTrue(board(.bravo, in: app).exists)
            XCTAssertTrue(board(.charlie, in: app).exists)
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

    static var allSurfaceIdentifiers: Set<String> {
        Set(allCases.map { "board-surface.\($0.rawValue)" })
    }
}

private enum FixtureDesk: String {
    case second = "00000000-0000-0000-0000-000000000201"
    case third = "00000000-0000-0000-0000-000000000202"
}
