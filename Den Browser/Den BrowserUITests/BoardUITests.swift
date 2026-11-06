import XCTest

final class BoardUITests: UITestCase {
    @MainActor
    func testClickingInputOnUnfocusedBoardPreservesClickedResponder() throws {
        let app = launchApp(boardCount: .two)
        let alpha = board(.alpha, in: app)
        let bravo = board(.bravo, in: app)
        let bravoInput = boardSurface(.bravo, in: app).textFields["Sheet input"].firstMatch

        given("another Board is focused") {
            XCTAssertTrue(alpha.wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertTrue(bravoInput.waitUntilExists(timeout: 5))
        }

        when("clicking the Sheet input in an unfocused Board") {
            bravoInput.click()
            app.typeText("a")
        }

        then("the clicked input receives the first keystroke") {
            XCTAssertTrue(bravo.wait(for: \.isSelected, toEqual: true, timeout: 5))
            assertValue("a", in: bravoInput)
        }
    }

    // Protects the AppKit responder handoff between a WebKit Sheet and its Inspection Board.
    // A unit test cannot observe which mounted native surface receives real keyboard input.
    @MainActor
    func testInspectionBoardFocusStopsAndRestoresSheetInput() throws {
        let app = launchApp(boardCount: .one)
        let alpha = board(.alpha, in: app)
        let sheetInput = boardSurface(.alpha, in: app).textFields["Sheet input"].firstMatch

        given("Alpha is focused and its Sheet input is available") {
            XCTAssertTrue(alpha.wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertTrue(sheetInput.waitUntilExists(timeout: 5))
        }

        when("focusing the Sheet input and typing a starting value") {
            sheetInput.click()
            app.typeText("a")
        }

        then("the starting value is in the Sheet") {
            assertValue("a", in: sheetInput)
        }

        when("creating a focused Inspection Board with Command-Option-I") {
            app.typeKey("i", modifierFlags: [.command, .option])
            XCTAssertTrue(app.buttons["Pick Element"].waitUntilExists(timeout: 5))
        }

        when("typing while the Inspection Board is focused") {
            app.typeText("x")
        }

        then("Alpha's Sheet input does not receive that typing") {
            XCTAssertEqual(sheetInput.value as? String, "a")
        }

        when("returning focus to Alpha and typing again") {
            app.buttons["Focus"].firstMatch.click()
            app.typeText("b")
        }

        then("Alpha's Sheet input receives typing after focus returns") {
            assertValue("ab", in: sheetInput)
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
            let end = boardSurface(.charlie, in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.1))
            start.click(forDuration: 0.5, thenDragTo: end)
        }

        then("Bravo is positioned to the right of Charlie") {
            assertEventually("Bravo should move to the right of Charlie") {
                bravo.frame.minX > charlie.frame.minX
            }
        }
    }

    // Protects the SwiftUI Board-header drag boundary for a Board Group.
    // Unit tests cannot observe the mounted SwiftUI header gesture committing the Board Group reorder.
    @MainActor
    func testMovesBoardGroupUsingSideBoardHeader() throws {
        let app = launchApp(boardCount: .two)
        let alpha = board(.alpha, in: app)
        let bravo = board(.bravo, in: app)

        given("Alpha and Bravo are visible Web Boards") {
            XCTAssertTrue(alpha.wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertTrue(bravo.exists)
        }

        when("creating Alpha's Inspection Board") {
            app.typeKey("i", modifierFlags: [.command, .option])
        }

        let inspectionHeader = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH 'board-header.' AND label CONTAINS 'Board: Inspection Board'"
                )
            )
            .firstMatch
        XCTAssertTrue(inspectionHeader.waitUntilExists(timeout: 5))
        XCTAssertTrue(app.buttons["Pick Element"].exists)
        let inspectionID = String(inspectionHeader.identifier.dropFirst("board-header.".count))
        let inspectionSurface = app.descendants(matching: .any)
            .matching(identifier: "board-surface.\(inspectionID)")
            .firstMatch
        let alphaSurface = boardSurface(.alpha, in: app)
        XCTAssertTrue(inspectionSurface.waitUntilExists(timeout: 5))
        XCTAssertTrue(alphaSurface.waitUntilExists(timeout: 5))
        let alphaWidth = alphaSurface.frame.width
        let inspectionWidth = inspectionSurface.frame.width

        when("dragging the Inspection Board header past Bravo") {
            let start = inspectionHeader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = boardSurface(.bravo, in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.1))
            start.click(forDuration: 0.5, thenDragTo: end)
        }

        then("Alpha and its Inspection Board move together after Bravo") {
            assertEventually("the Board Group should move after Bravo") {
                bravo.frame.minX < alphaSurface.frame.minX
                    && alphaSurface.frame.minX < inspectionSurface.frame.minX
                    && inspectionSurface.frame.minX - alphaSurface.frame.maxX < 40
            }
            XCTAssertTrue(inspectionHeader.isSelected)
            XCTAssertEqual(alphaSurface.frame.width, alphaWidth, accuracy: 1)
            XCTAssertEqual(inspectionSurface.frame.width, inspectionWidth, accuracy: 1)
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
    func testTerminalBoardDenModeToggleAndExit() throws {
        let app = launchApp(boardCount: .two, terminalBoard: true)
        let alpha = board(.alpha, in: app)
        let bravo = board(.bravo, in: app)
        let sheetInputWindow = app.windows["UI Testing · SHEET INPUT"]
        let surfacePredicate = NSPredicate(format: "identifier BEGINSWITH 'board-surface.'")
        let surfaces = app.scrollViews["board-strip"].firstMatch
            .descendants(matching: .any)
            .matching(surfacePredicate)

        enterDenMode(in: app)
        app.typeKey("l", modifierFlags: [])
        XCTAssertTrue(bravo.wait(for: \.isSelected, toEqual: true, timeout: 5))
        app.typeKey(",", modifierFlags: [.control])
        XCTAssertTrue(
            sheetInputWindow.waitUntilExists(timeout: 5),
            "Den Mode should return to Sheet Input after focusing Bravo")
        XCTAssertTrue(bravo.isSelected)

        enterDenMode(in: app)
        app.typeKey("h", modifierFlags: [])
        XCTAssertTrue(alpha.wait(for: \.isSelected, toEqual: true, timeout: 5))
        app.typeKey(",", modifierFlags: [.control])
        XCTAssertTrue(
            sheetInputWindow.waitUntilExists(timeout: 5),
            "Den Mode should return to Sheet Input after focusing Alpha")
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

    // Protects retargeting an in-flight SwiftUI ScrollView animation, which unit tests cannot observe.
    @MainActor
    func testRapidBoardFocusMovementAlignsTheLastFocusedBoard() throws {
        let app = launchApp(fixture: .rapidBoardFocus, standardMotion: true)
        let charlie = board(.charlie, in: app)
        let bravo = board(.bravo, in: app)
        let strip = app.descendants(matching: .any).matching(identifier: "board-strip").firstMatch
        let bravoSurface = boardSurface(.bravo, in: app)

        given("Charlie is visible on an overflowing Desk with animations enabled") {
            XCTAssertTrue(charlie.wait(for: \.isHittable, toEqual: true, timeout: 5))
            assertEventually("Charlie should be centered before rapid focus changes") {
                abs(self.boardSurface(.charlie, in: app).frame.midX - strip.frame.midX) <= 3
            }
            enterDenMode(in: app)
        }

        when("wrapping to Alpha and moving to Bravo before the first animation finishes") {
            app.typeText("ll")
        }

        then("the last focused Board is fully visible") {
            XCTAssertTrue(bravo.wait(for: \.isSelected, toEqual: true, timeout: 5))
            assertEventually("Bravo should remain fully visible after both focus changes") {
                bravoSurface.frame.minX >= strip.frame.minX
                    && bravoSurface.frame.maxX <= strip.frame.maxX
            }
        }
    }

    // Protects scrolling against shrinking native content during removal; unit tests only calculate the destination.
    @MainActor
    func testRapidBoardRemovalAlignsTheRemainingBoard() throws {
        let app = launchApp(fixture: .rapidBoardFocus, standardMotion: true)
        let charlie = board(.charlie, in: app)
        let bravo = board(.bravo, in: app)
        let alpha = board(.alpha, in: app)
        let alphaSurface = boardSurface(.alpha, in: app)
        let strip = app.descendants(matching: .any).matching(identifier: "board-strip").firstMatch

        given("Charlie is centered on an overflowing Desk with animations enabled") {
            XCTAssertTrue(charlie.wait(for: \.isHittable, toEqual: true, timeout: 5))
            assertEventually("Charlie should be centered before rapid removal") {
                abs(self.boardSurface(.charlie, in: app).frame.midX - strip.frame.midX) <= 3
            }
            enterDenMode(in: app)
        }

        when("removing Charlie and Bravo in succession") {
            // One event sequence avoids XCTest's idle wait between the two removals.
            app.typeText("xx")
        }

        then("Alpha is the only remaining Board and is centered") {
            XCTAssertTrue(alpha.wait(for: \.isSelected, toEqual: true, timeout: 5))
            assertEventually(
                "The remaining Alpha Board should be centered. Alpha: \(alphaSurface.frame), strip: \(strip.frame), "
                    + "Bravo exists: \(bravo.exists), Charlie exists: \(charlie.exists)"
            ) {
                !bravo.exists && !charlie.exists
                    && abs(alphaSurface.frame.midX - strip.frame.midX) <= 3
            }
        }
    }

    // Protects SwiftUI ScrollView visibility callback ordering; a unit test cannot observe this native boundary.
    @MainActor
    func testOffscreenTerminalWaitsForInitialAlignmentAndDeskReturn() throws {
        let app = launchApp(fixture: .focusedTerminalBeforeAlignment, terminalBoard: true)
        let window = app.children(matching: .window).firstMatch
        let charlie = board(.charlie, in: app)
        let mainDesk = desk(.main, in: app)
        let secondDesk = desk(.second, in: app)
        let alphaActivityRow = window.buttons[
            "board-activity-board.\(FixtureBoard.alpha.rawValue.lowercased())"
        ]

        given("the focused Charlie Board is visible after the initial alignment") {
            XCTAssertTrue(charlie.wait(for: \.isHittable, toEqual: true, timeout: 5))
        }

        when("opening Board Activity after the initial alignment") {
            window.typeKey(.escape, modifierFlags: [.shift])
            XCTAssertTrue(window.staticTexts["Board Activity"].waitUntilExists(timeout: 5))
        }

        then("the offscreen Terminal Board remains inactive") {
            XCTAssertTrue(alphaActivityRow.waitUntilExists(timeout: 5))
            XCTAssertTrue(alphaActivityRow.label.contains("Not active"), alphaActivityRow.label)
        }

        when("switching to Main and returning to Second") {
            window.typeKey(.escape, modifierFlags: [])
            enterDenMode(in: app)
            window.typeKey("1", modifierFlags: [])
            XCTAssertTrue(mainDesk.wait(for: \.isSelected, toEqual: true, timeout: 5))
            enterDenMode(in: app)
            window.typeKey("2", modifierFlags: [])
            XCTAssertTrue(secondDesk.wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertTrue(charlie.wait(for: \.isHittable, toEqual: true, timeout: 5))
        }

        when("checking Board Activity again") {
            window.typeKey(.escape, modifierFlags: [.shift])
            XCTAssertTrue(window.staticTexts["Board Activity"].waitUntilExists(timeout: 5))
        }

        then("alignment on the returned Desk still has not activated Alpha") {
            XCTAssertTrue(alphaActivityRow.label.contains("Not active"), alphaActivityRow.label)
        }
    }
}
