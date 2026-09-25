import Carbon.HIToolbox
import Darwin
import XCTest

private final class UITestProcessLock {
    private let handle: FileHandle

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "dev.nekonata.denbrowser.ui-tests.lock")
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forUpdating: url)
        guard flock(handle.fileDescriptor, LOCK_EX) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    deinit {
        flock(handle.fileDescriptor, LOCK_UN)
        try? handle.close()
    }
}

private func uiTestDefaultsSuiteName(runID: String) -> String {
    "dev.nekonata.denbrowser.ui-testing.\(runID)"
}

final class Den_BrowserUITests: XCTestCase, BDD {
    private var previousInputSource: TISInputSource?
    private var processLock: UITestProcessLock?
    private var defaultsSuiteNames: [String] = []
    private var fixtureDirectories: [URL] = []

    override func setUpWithError() throws {
        processLock = try UITestProcessLock()
        continueAfterFailure = false
        // Keep synthetic text input on Apple's ABC layout; restore user's IME in tearDown.
        previousInputSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        try selectInputSource(id: "com.apple.keylayout.ABC")
    }

    override func tearDownWithError() throws {
        MainActor.assumeIsolated {
            uiTestApplication().terminate()
        }
        if let previousInputSource {
            XCTAssertEqual(TISSelectInputSource(previousInputSource), noErr)
        }
        for suiteName in defaultsSuiteNames {
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
        for directory in fixtureDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        processLock = nil
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
    func testOpenProfilePanelCanConfirmFromKeyboard() throws {
        let app = launchApp(boardCount: .one)
        let input = app.textFields["open-profile-input"]

        given("the Open Profile panel is opened") {
            app.typeKey("p", modifierFlags: [.control, .command])
            XCTAssertTrue(input.waitForExistence(timeout: 5))
        }

        when("moving to the profile row and confirming with the keyboard") {
            app.typeKey(.downArrow, modifierFlags: [])
            app.typeKey(.return, modifierFlags: [])
        }

        then("the Profile panel closes") {
            XCTAssertTrue(input.waitForNonExistence(timeout: 5))
        }
    }

    // Protects AppKit toolbar and shortcut delivery plus native split-view geometry, which unit tests cannot observe.
    @MainActor
    func testBoardRailShortcutPushesDeskSwitcherAndResizesBoardStrip() throws {
        let app = launchApp(boardCount: .two)
        let rail = app.descendants(matching: .any).matching(identifier: "board-rail").firstMatch
        let strip = app.scrollViews["board-strip"].firstMatch
        let mainDesk = desk(.main, in: app)
        let notifications = app.toolbars.buttons["Notifications"].firstMatch
        let saveDeskPreset = app.toolbars.buttons["Save Desk as Preset"].firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertTrue(mainDesk.waitForExistence(timeout: 5))
        XCTAssertTrue(notifications.waitForExistence(timeout: 5))
        XCTAssertTrue(saveDeskPreset.exists)
        let initialStripWidth = strip.frame.width
        let initialStripHeight = strip.frame.height
        let initialDeskSwitcherMinX = mainDesk.frame.minX

        given("BoardRail is hidden and BoardStrip fills the detail column") {
            XCTAssertFalse(rail.isHittable)
        }

        when("opening BoardRail with Command-S") {
            app.typeKey("s", modifierFlags: [.command])
            XCTAssertTrue(rail.wait(for: \.isHittable, toEqual: true, timeout: 5))
            assertEventually("BoardRail should reduce BoardStrip width") {
                strip.frame.width < initialStripWidth
            }
            assertEventually("DeskSwitcher should move with BoardStrip into the detail column") {
                mainDesk.frame.minX > initialDeskSwitcherMinX
            }
            XCTAssertEqual(strip.frame.height, initialStripHeight, accuracy: 1)
        }

        let bravoInRail = app.descendants(matching: .any)
            .matching(identifier: "board-rail-board.\(FixtureBoard.bravo.rawValue)")
            .firstMatch

        when("selecting Bravo from BoardRail") {
            XCTAssertTrue(bravoInRail.waitForExistence(timeout: 5))
            bravoInRail.click()
        }

        then("Bravo is focused and BoardRail remains open") {
            XCTAssertTrue(board(.bravo, in: app).isSelected)
            XCTAssertTrue(rail.isHittable)
            XCTAssertTrue(bravoInRail.isSelected)
        }

        when("closing BoardRail with Command-S") {
            app.typeKey("s", modifierFlags: [.command])
        }

        then("BoardStrip regains the available width") {
            XCTAssertTrue(rail.wait(for: \.isHittable, toEqual: false, timeout: 5))
            assertEventually("BoardStrip should regain its original width") {
                strip.frame.width >= initialStripWidth
            }
            assertEventually("DeskSwitcher should return to its original position") {
                abs(mainDesk.frame.minX - initialDeskSwitcherMinX) < 1
            }
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
    func testDrawerPreviewReceivesVimAndFormInputAndRetainsAfterDiscarding() throws {
        let app = launchApp(
            boardCount: .one,
            sheetNavigationEnabled: true,
            multipleDrawerItems: true)

        let drawer = app.descendants(matching: .any).matching(identifier: "drawer").firstMatch
        let previewContent = drawer.staticTexts["result:pending"].firstMatch
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
            app.typeKey(.return, modifierFlags: [])
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

        when("discarding the focused Drawer Item") {
            app.typeKey("w", modifierFlags: [.command])
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
            start.click(forDuration: 0.5, thenDragTo: end)
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
            start.click(forDuration: 0.5, thenDragTo: end)
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
            start.click(forDuration: 0.5, thenDragTo: end)
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
    func testCloseProfileWindowShortcutWorksFromTerminalBoard() throws {
        let app = launchApp(boardCount: .one, terminalBoard: true)
        let window = app.windows["UI Testing · TERMINAL INPUT"]

        given("a Terminal Board is focused") {
            XCTAssertTrue(window.waitForExistence(timeout: 5))
        }

        when("closing the Profile Window with Command-Shift-W") {
            app.typeKey("w", modifierFlags: [.command, .shift])
        }

        then("the Profile Window closes") {
            XCTAssertTrue(window.waitForNonExistence(timeout: 5))
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

    // Protects SwiftUI ScrollView visibility callback ordering; a unit test cannot observe this native boundary.
    @MainActor
    func testOffscreenTerminalWaitsForInitialAlignmentAndDeskReturn() throws {
        let app = launchApp(fixture: .focusedTerminalBeforeAlignment, terminalBoard: true)
        let charlie = board(.charlie, in: app)
        let mainDesk = desk(.main, in: app)
        let secondDesk = desk(.second, in: app)
        let alphaActivityRow = app.buttons[
            "board-activity-board.\(FixtureBoard.alpha.rawValue.lowercased())"
        ]

        given("the focused Charlie Board is visible after the initial alignment") {
            XCTAssertTrue(charlie.wait(for: \.isHittable, toEqual: true, timeout: 5))
        }

        when("opening Board Activity after the initial alignment") {
            app.typeKey(.escape, modifierFlags: [.shift])
            XCTAssertTrue(app.staticTexts["Board Activity"].waitForExistence(timeout: 5))
        }

        then("the offscreen Terminal Board remains inactive") {
            XCTAssertTrue(alphaActivityRow.waitForExistence(timeout: 5))
            XCTAssertTrue(alphaActivityRow.label.contains("Not active"), alphaActivityRow.label)
        }

        when("switching to Main and returning to Second") {
            app.typeKey(.escape, modifierFlags: [])
            enterDenMode(in: app)
            app.typeKey("1", modifierFlags: [])
            XCTAssertTrue(mainDesk.wait(for: \.isSelected, toEqual: true, timeout: 5))
            enterDenMode(in: app)
            app.typeKey("2", modifierFlags: [])
            XCTAssertTrue(secondDesk.wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertTrue(charlie.wait(for: \.isHittable, toEqual: true, timeout: 5))
        }

        when("checking Board Activity again") {
            app.typeKey(.escape, modifierFlags: [.shift])
            XCTAssertTrue(app.staticTexts["Board Activity"].waitForExistence(timeout: 5))
        }

        then("alignment on the returned Desk still has not activated Alpha") {
            XCTAssertTrue(alphaActivityRow.label.contains("Not active"), alphaActivityRow.label)
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
        let app = uiTestApplication()
        let runID = UUID().uuidString
        let runDirectory = FileManager.default.temporaryDirectory
            .appending(path: "DenBrowserUITests", directoryHint: .isDirectory)
            .appending(path: runID, directoryHint: .isDirectory)
        let seedURL = runDirectory.appending(path: "initial-profile.json")
        fixtureDirectories.append(runDirectory)
        do {
            try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
            try uiTestProfile(
                fixture: fixture,
                boardCount: boardCount,
                terminalBoard: terminalBoard,
                multipleDrawerItems: multipleDrawerItems
            )
            .write(to: seedURL, options: .atomic)
        } catch {
            XCTFail("Could not write UI test profile seed: \(error)")
        }
        var args = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing", "--initial-profile", seedURL.path,
        ]
        if sheetNavigationEnabled {
            args.append("--enable-sheet-navigation")
        }
        app.launchArguments = args
        defaultsSuiteNames.append(uiTestDefaultsSuiteName(runID: runID))
        app.launchEnvironment["DEN_UI_TEST_RUN_ID"] = runID
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
    private var processLock: UITestProcessLock?
    private var defaultsSuiteName: String?
    private var fixtureDirectory: URL?

    override func setUpWithError() throws {
        processLock = try UITestProcessLock()
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        MainActor.assumeIsolated {
            uiTestApplication().terminate()
        }
        if let defaultsSuiteName {
            UserDefaults().removePersistentDomain(forName: defaultsSuiteName)
        }
        if let fixtureDirectory {
            try? FileManager.default.removeItem(at: fixtureDirectory)
        }
        processLock = nil
        try super.tearDownWithError()
    }

    func testApplicationLaunchPerformance() {
        let app = uiTestApplication()
        let runID = UUID().uuidString
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appending(path: "DenBrowserUITests", directoryHint: .isDirectory)
            .appending(path: runID, directoryHint: .isDirectory)
        self.fixtureDirectory = fixtureDirectory
        let seedURL = fixtureDirectory.appending(path: "initial-profile.json")
        do {
            try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
            try uiTestProfile(fixture: .interactionBasics, boardCount: .one)
                .write(to: seedURL, options: .atomic)
        } catch {
            XCTFail("Could not write UI test profile seed: \(error)")
        }
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing", "--initial-profile", seedURL.path,
        ]
        defaultsSuiteName = uiTestDefaultsSuiteName(runID: runID)
        app.launchEnvironment["DEN_UI_TEST_RUN_ID"] = runID

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

private func uiTestProfile(
    fixture: UITestFixture,
    boardCount: UITestBoardCount = .three,
    terminalBoard: Bool = false,
    multipleDrawerItems: Bool = false
) throws -> Data {
    let alphaID = "00000000-0000-0000-0000-000000000301"
    let bravoID = "00000000-0000-0000-0000-000000000302"
    let charlieID = "00000000-0000-0000-0000-000000000303"
    let mainDeskID = "00000000-0000-0000-0000-000000000200"
    let secondDeskID = "00000000-0000-0000-0000-000000000201"
    let thirdDeskID = "00000000-0000-0000-0000-000000000202"
    let sheetURL = uiTestSheetURL().absoluteString
    func webBoard(_ id: String, _ label: String, width: Double = 320) -> [String: Any] {
        [
            "id": id, "label": label, "width": width,
            "content": ["kind": "web", "currentSheetURL": sheetURL, "firstSheetURL": sheetURL],
            "sheetNavigationPaused": false,
        ]
    }
    func makeTerminalBoard(_ id: String, _ label: String, width: Double = 320) -> [String: Any] {
        [
            "id": id, "label": label, "width": width,
            "content": ["kind": "terminal", "workingDirectory": "/tmp"],
            "sheetNavigationPaused": false,
        ]
    }
    let alpha = terminalBoard ? makeTerminalBoard(alphaID, "Terminal") : webBoard(alphaID, "Alpha")
    let bravo = webBoard(bravoID, "Bravo")
    let charlie = webBoard(charlieID, "Charlie")
    let mainBoards: [[String: Any]]
    let secondBoards: [[String: Any]]
    let secondFocusedBoardID: String?
    let mainFocusedBoardID: String
    let focusedDeskID: String
    switch fixture {
    case .interactionBasics:
        switch boardCount {
        case .one: mainBoards = [alpha]
        case .two: mainBoards = [alpha, bravo]
        case .three: mainBoards = [alpha, bravo, charlie]
        }
        secondBoards = []
        secondFocusedBoardID = nil
        mainFocusedBoardID = alphaID
        focusedDeskID = mainDeskID
    case .overviewBoardPair:
        mainBoards = [bravo, charlie]
        secondBoards = []
        secondFocusedBoardID = nil
        mainFocusedBoardID = bravoID
        focusedDeskID = mainDeskID
    case .focusedNonLeadingBoard:
        mainBoards = [alpha]
        secondBoards = [bravo, charlie]
        secondFocusedBoardID = charlieID
        mainFocusedBoardID = alphaID
        focusedDeskID = secondDeskID
    case .focusedTerminalBeforeAlignment:
        let leadingBoard =
            terminalBoard
            ? makeTerminalBoard(alphaID, "Terminal", width: 1_400)
            : webBoard(alphaID, "Alpha", width: 1_400)
        let middleBoard = webBoard(bravoID, "Bravo", width: 1_400)
        let focusedBoard = webBoard(charlieID, "Charlie", width: 1_400)
        let mainBoard = webBoard("00000000-0000-0000-0000-000000000304", "Main")
        mainBoards = [mainBoard]
        secondBoards = [leadingBoard, middleBoard, focusedBoard]
        secondFocusedBoardID = charlieID
        mainFocusedBoardID = "00000000-0000-0000-0000-000000000304"
        focusedDeskID = secondDeskID
    }
    let desk: [String: Any] = [
        "id": mainDeskID, "label": "Main", "boards": mainBoards,
        "focusedBoardID": mainFocusedBoardID,
    ]
    let secondDesk: [String: Any] = [
        "id": secondDeskID, "label": "Second", "boards": secondBoards,
        "focusedBoardID": secondFocusedBoardID as Any? ?? NSNull(),
    ]
    let thirdDesk: [String: Any] = ["id": thirdDeskID, "label": "Third", "boards": [] as [[String: Any]]]
    let drawerItem: [String: Any] = [
        "id": "00000000-0000-0000-0000-000000000401", "url": sheetURL, "title": "Drawer Fixture",
    ]
    let secondDrawerItem: [String: Any] = [
        "id": "00000000-0000-0000-0000-000000000402", "url": sheetURL, "title": "Next Drawer Fixture",
    ]
    let drawerItems = multipleDrawerItems ? [secondDrawerItem, drawerItem] : [drawerItem]
    let seed: [String: Any] = [
        "schemaVersion": 2,
        "profile": [
            "id": "00000000-0000-0000-0000-000000000100", "name": "UI Testing",
            "color": "blue", "webProfileStore": ["kind": "default"],
        ],
        "den": [
            "desks": [desk, secondDesk, thirdDesk], "focusedDeskID": focusedDeskID,
            "drawerItems": drawerItems,
        ],
        "deskPresets": [],
    ]
    return try JSONSerialization.data(withJSONObject: seed)
}

private func uiTestSheetURL() -> URL {
    guard
        let url = uiTestAppBundle().url(
            forResource: "interaction-basics", withExtension: "html"),
        let html = try? String(contentsOf: url, encoding: .utf8)
    else {
        preconditionFailure("Could not load UI test fixture")
    }
    let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "#"))
    guard
        let encoded = html.addingPercentEncoding(withAllowedCharacters: allowed),
        let url = URL(string: "data:text/html,\(encoded)")
    else {
        preconditionFailure("Could not encode UI test fixture")
    }
    return url
}

private func uiTestApplication() -> XCUIApplication {
    XCUIApplication(url: uiTestAppBundle().bundleURL)
}

private func uiTestAppBundle() -> Bundle {
    let productsURL = Bundle(for: Den_BrowserUITests.self).bundleURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let appURL = productsURL.appending(path: "Den Browser.app", directoryHint: .isDirectory)
    guard let appBundle = Bundle(url: appURL) else {
        preconditionFailure("Could not load the app bundle for UI tests")
    }
    return appBundle
}

private enum UITestFixture: String {
    case interactionBasics = "interaction-basics"
    case overviewBoardPair = "overview-board-pair"
    case focusedNonLeadingBoard = "focused-non-leading-board"
    case focusedTerminalBeforeAlignment = "focused-terminal-before-alignment"

    var initialBoard: FixtureBoard {
        switch self {
        case .focusedNonLeadingBoard, .focusedTerminalBeforeAlignment: .charlie
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
    case main = "00000000-0000-0000-0000-000000000200"
    case second = "00000000-0000-0000-0000-000000000201"
    case third = "00000000-0000-0000-0000-000000000202"
}

private enum UITestBoardCount: String {
    case one
    case two
    case three
}
