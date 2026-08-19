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
        let app = launchApp(boardCount: .one)
        let sheetInput = app.textFields["Sheet input"].firstMatch

        given("the initial Sheet input is visible") {
            XCTAssertTrue(sheetInput.waitForExistence(timeout: 10))
            XCTAssertTrue(app.windows["UI Testing · SHEET INPUT"].waitForExistence(timeout: 5))
        }

        when("entering Den Mode after typing into the Sheet input") {
            sheetInput.click()
            sheetInput.typeText("a")
            sheetInput.typeKey(",", modifierFlags: .control)
            assertDenMode(in: app)
        }

        when("returning to Sheet mode") {
            app.typeKey(",", modifierFlags: .control)
            XCTAssertTrue(app.windows["UI Testing · SHEET INPUT"].waitForExistence(timeout: 5))
        }

        when("typing more input") {
            XCTAssertTrue(sheetInput.waitForExistence(timeout: 5))
            app.typeText("!")
        }

        then("the Sheet input regains focus and retains the previous text") {
            XCTAssertEqual(sheetInput.value as? String, "a!")
        }
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
    func testDrawerPreviewReceivesVimAndFormInput() throws {
        let app = launchApp(boardCount: .one, sheetNavigationEnabled: true)

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
            app.typeText("a")
        }

        then("the Drawer preview forwards input to the Sheet") {
            XCTAssertEqual(sheetInput.value as? String, "a")
        }
    }

    @MainActor
    func testDrawerPreviewRetainsSheetNavigationAfterDiscardingIntoNextPreview() throws {
        let app = launchApp(
            boardCount: .one,
            sheetNavigationEnabled: true,
            multipleDrawerItems: true)

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
            app.typeText("a")
        }

        then("the remaining preview accepts Sheet input") {
            XCTAssertEqual(sheetInput.value as? String, "a")
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
    func testNewBoardAnimatesIntoBoardStrip() throws {
        let app = launchApp(boardCount: .one)
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

        then("the new Board is selected and settles at the trailing edge") {
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
                actual: { newBoardSurface.frame.maxX },
                expected: boardStrip.frame.maxX,
                tolerance: 50,
                message: "New Board should finish at the trailing edge after its insertion animation"
            )
        }
    }

    @MainActor
    func testTerminalBoardStartsAndExitRemovesIt() throws {
        let app = launchApp(boardCount: .one)
        let boardStrip = app.scrollViews["board-strip"].firstMatch
        let surfacePredicate = NSPredicate(format: "identifier BEGINSWITH 'board-surface.'")
        let surfaces = boardStrip.descendants(matching: .any).matching(surfacePredicate)

        when("creating a Terminal Board from the Open Board panel") {
            app.typeKey("t", modifierFlags: .command)
            let input = app.textFields["open-board-input"].firstMatch
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
    func testTerminalBoardDenModeToggleDoesNotExitImmediately() throws {
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
    func testDirectDeskSwitchActivatesFocusedNonLeadingBoard() throws {
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

        when("switching away and returning by Desk number") {
            enterDenMode(in: app)
            app.typeKey("1", modifierFlags: [])
            XCTAssertTrue(alpha.wait(for: \.isSelected, toEqual: true, timeout: 5))
            enterDenMode(in: app)
            app.typeKey("2", modifierFlags: [])
            XCTAssertTrue(charlie.wait(for: \.isSelected, toEqual: true, timeout: 5))
        }

        then("the Focused Board receives Sheet Input") {
            XCTAssertTrue(charlieInput.waitForExistence(timeout: 5))
            app.typeText("b")
            XCTAssertEqual(charlieInput.value as? String, "ab")
        }
    }

    @MainActor
    func testOverviewEnterCentersBoardOnAnotherDesk() throws {
        let app = launchApp(fixture: .overflowingSecondDesk, centerBoardsAlways: true)
        let boardStrip = app.scrollViews["board-strip"].firstMatch
        let alpha = board(.alpha, in: app)
        let charlie = board(.charlie, in: app)
        let charlieSurface = boardSurface(.charlie, in: app)

        given("the next Desk has enough Boards to require scrolling") {
            XCTAssertTrue(alpha.wait(for: \.isSelected, toEqual: true, timeout: 5))
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
        let app = launchApp(fixture: .focusedSecondBoard)
        let boardStrip = app.scrollViews["board-strip"].firstMatch
        let alpha = boardSurface(.alpha, in: app)
        let bravo = boardSurface(.bravo, in: app)
        let alphaHeader = boardHeader(.alpha, in: app)
        let bravoHeader = boardHeader(.bravo, in: app)

        given("Bravo starts as the focused Board") {
            XCTAssertTrue(bravoHeader.wait(for: \.isSelected, toEqual: true, timeout: 5))
        }

        when("removing the focused Board") {
            enterDenMode(in: app)
            app.typeText("x")
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
        let alpha = board(.alpha, in: app)
        let bravo = board(.bravo, in: app)
        let charlie = board(.charlie, in: app)
        let charlieSurface = boardSurface(.charlie, in: app)
        let charlieInput = charlieSurface.textFields["Sheet input"].firstMatch

        given("Charlie has prior input focus and Alpha is focused before filtering") {
            XCTAssertTrue(charlieInput.waitForExistence(timeout: 5))
            charlieInput.click()
            app.typeText("p")
            enterDenMode(in: app)
            app.typeKey("h", modifierFlags: [])
            app.typeKey("h", modifierFlags: [])
            app.typeKey(",", modifierFlags: [.control])
            XCTAssertTrue(alpha.wait(for: \.isSelected, toEqual: true, timeout: 5))
            enterDenMode(in: app)
            app.typeText("/")
            XCTAssertTrue(filter.waitForExistence(timeout: 5))
        }

        when("filtering for Charlie") {
            app.typeText("arl")
        }

        then("only Charlie remains visible") {
            assertEventually("Only the matching Board should remain visible") {
                self.board(.charlie, in: app).exists
                    && !self.board(.alpha, in: app).exists
                    && !self.board(.bravo, in: app).exists
            }
        }

        when("confirming the filtered selection") {
            app.typeKey(.return, modifierFlags: [])
            app.typeKey(.return, modifierFlags: [])
        }

        then("all Boards return, Charlie is centered, and receives Sheet input") {
            XCTAssertTrue(charlie.wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertTrue(charlieInput.waitForExistence(timeout: 5))
            XCTAssertTrue(alpha.waitForExistence(timeout: 5))
            XCTAssertTrue(bravo.waitForExistence(timeout: 5))
            assertEventuallyEqual(
                actual: { charlieSurface.frame.midX },
                expected: boardStrip.frame.midX,
                tolerance: 30,
                message: "Filtered Board should center before receiving input"
            )
            app.typeText("a")
            XCTAssertEqual(charlieInput.value as? String, "pa")
        }
    }

    @MainActor
    private func launchApp(
        fixture: UITestFixture = .interactionBasics,
        boardCount: UITestBoardCount = .three,
        terminalBoard: Bool = false,
        sheetNavigationEnabled: Bool = false,
        multipleDrawerItems: Bool = false,
        centerBoardsOnOverflow: Bool = false,
        centerBoardsAlways: Bool = false
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
    case focusedSecondBoard = "focused-second-board"
    case overviewBoardPair = "overview-board-pair"
    case focusedNonLeadingBoard = "focused-non-leading-board"
    case overflowingSecondDesk = "overflowing-second-desk"

    var initialBoard: FixtureBoard {
        switch self {
        case .focusedSecondBoard: .bravo
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
