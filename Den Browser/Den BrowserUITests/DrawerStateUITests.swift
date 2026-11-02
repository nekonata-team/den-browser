import XCTest

final class DrawerStateUITests: UITestCase {
    @MainActor
    func testDrawerPeekReceivesVimAndFormInputAndRetainsAfterDiscarding() throws {
        let app = launchApp(
            boardCount: .one,
            sheetNavigationEnabled: true,
            multipleDrawerItems: true)

        let drawer = app.descendants(matching: .any).matching(identifier: "drawer").firstMatch
        let peekContent = drawer.staticTexts["result:pending"].firstMatch
        let sheetInput = drawer.textFields["Sheet input"].firstMatch
        let nextDrawerItem = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Next Drawer Fixture"))
            .firstMatch
        let drawerItem = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Drawer Fixture"))
            .firstMatch

        given("Sheet Navigation is enabled, two Drawer items exist, and the first peek is focused") {
            enterDenMode(in: app)
            app.typeKey(.tab, modifierFlags: [])
            XCTAssertTrue(drawer.waitUntilExists(timeout: 5))
            app.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(peekContent.waitUntilExists(timeout: 10))
            XCTAssertTrue(nextDrawerItem.waitUntilExists(timeout: 10))
            XCTAssertTrue(drawerItem.exists)
        }

        when("moving to the Sheet input and typing in the first peek") {
            app.typeText("gi")
            XCTAssertTrue(sheetInput.waitUntilExists(timeout: 5))
            app.typeText("a")
        }

        then("the first Drawer peek accepts Sheet input") {
            XCTAssertEqual(sheetInput.value as? String, "a")
        }

        when("discarding the focused Drawer Item") {
            app.typeKey("w", modifierFlags: [.command])
        }

        then("the next Drawer peek remains visible") {
            XCTAssertTrue(nextDrawerItem.waitUntilAbsent(timeout: 5))
            XCTAssertTrue(drawerItem.exists)
        }

        when("using Sheet Navigation in the remaining peek") {
            app.typeText("gi")
        }

        when("typing into the Sheet input from the remaining peek") {
            XCTAssertTrue(sheetInput.waitUntilExists(timeout: 5))
            app.typeText("b")
        }

        then("the remaining peek accepts Sheet input") {
            XCTAssertEqual(sheetInput.value as? String, "b")
        }
    }

    // Protects WebView remounting and responder activation after switching and closing Drawer.
    // Unit tests cannot observe form state and key delivery through the mounted native surface.
    @MainActor
    func testDrawerRetainsFormAndReceivesInputAfterSwitchingAndReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fixtureDirectories.append(directory)
        let url = directory.appending(path: "retained.html")
        try "<html><head><title>Drawer Fixture</title></head><body><input aria-label='Retained input'></body></html>"
            .write(
                to: url, atomically: true, encoding: .utf8)
        let app = launchApp(boardCount: .one, multipleDrawerItems: true, drawerSheetURL: url)
        let drawer = app.descendants(matching: .any).matching(identifier: "drawer").firstMatch
        let input = drawer.textFields["Retained input"].firstMatch
        let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Drawer Fixture")).firstMatch
        let otherItem = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Next Drawer Fixture"))
            .firstMatch

        given("an opened Drawer Item holds a form value") {
            enterDenMode(in: app)
            app.typeKey(.tab, modifierFlags: [])
            XCTAssertTrue(item.waitUntilExists(timeout: 5))
            item.click()
            XCTAssertTrue(input.waitUntilExists(timeout: 10))
            input.click()
            app.typeText("seed")
        }

        when("switching to another Item and returning") {
            otherItem.click()
            XCTAssertTrue(input.waitUntilAbsent(timeout: 5))
            item.click()
        }

        then("the original form value survives") {
            XCTAssertTrue(input.waitUntilExists(timeout: 5))
            XCTAssertEqual(input.value as? String, "seed")
        }

        when("closing and reopening Drawer, then typing without clicking the form") {
            app.typeKey(.escape, modifierFlags: [.control])
            XCTAssertTrue(drawer.waitUntilAbsent(timeout: 5))
            enterDenMode(in: app)
            app.typeKey(.tab, modifierFlags: [])
            XCTAssertTrue(input.waitUntilExists(timeout: 5))
            app.typeText("continued")
        }

        then("the retained form receives the input") {
            XCTAssertEqual(input.value as? String, "seedcontinued")
        }
    }

    // Protects WebView reparenting and responder activation through SwiftUI placement.
    // Unit tests cannot observe keyboard delivery to the newly mounted Board surface.
    @MainActor
    func testDrawerPlacementPreservesLivePageAndReceivesBoardInput() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fixtureDirectories.append(directory)
        let url = directory.appending(path: "drawer.html")
        try """
        <html><head><title>Live Drawer Fixture</title></head><body>
          <input aria-label="Live input" spellcheck="false" autocorrect="off" autocapitalize="off">
        </body></html>
        """.write(to: url, atomically: true, encoding: .utf8)
        let app = launchApp(boardCount: .one)
        let drawer = app.descendants(matching: .any).matching(identifier: "drawer").firstMatch
        let peekInput = drawer.textFields["Live input"].firstMatch
        let placedInput = app.textFields["Live input"].firstMatch

        given("a Drawer Peek holds a live value") {
            app.buttons["drawer-button"].click()
            XCTAssertTrue(drawer.waitUntilExists(timeout: 5))
            drawer.buttons["drawer-add-item"].click()
            let input = app.textFields["open-board-input"].firstMatch
            XCTAssertTrue(input.waitUntilExists(timeout: 5))
            input.click()
            paste(url.absoluteString, in: app)
            app.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(peekInput.waitUntilExists(timeout: 10))
            peekInput.click()
            app.typeText("seed")
            XCTAssertEqual(peekInput.value as? String, "seed")
        }

        when("opening and canceling another addition over the filtered live Drawer") {
            drawer.buttons["Search Drawer Items"].click()
            let search = drawer.textFields["drawer-search"].firstMatch
            XCTAssertTrue(search.waitUntilExists(timeout: 5))
            search.click()
            paste("Live", in: app)
            drawer.buttons["drawer-add-item"].click()
            let input = app.textFields["open-board-input"].firstMatch
            XCTAssertTrue(input.waitUntilExists(timeout: 5))
            input.click()
            app.typeKey("a", modifierFlags: [.command])
            paste("https://example.com/cancel", in: app)
            XCTAssertEqual(input.value as? String, "https://example.com/cancel")
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(input.waitUntilAbsent(timeout: 5))
            XCTAssertEqual(search.value as? String, "Live")
            app.typeKey(.rightArrow, modifierFlags: [.command])
            app.typeText(" Drawer Fixture")
            XCTAssertEqual(search.value as? String, "Live Drawer Fixture")
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(peekInput.waitUntilExists(timeout: 5))
            XCTAssertEqual(peekInput.value as? String, "seed")
        }

        when("placing the Peek into the Desk") {
            app.buttons["Place Live Drawer Fixture as Board"].click()
        }

        then("the Board keeps the live value") {
            XCTAssertTrue(drawer.waitUntilAbsent(timeout: 5))
            XCTAssertTrue(placedInput.waitUntilExists(timeout: 5))
            XCTAssertEqual(placedInput.value as? String, "seed")
        }

        when("typing after placement without clicking the Sheet again") {
            app.typeText("continued")
        }

        then("the placed Board receives that input") {
            XCTAssertEqual(placedInput.value as? String, "seedcontinued")
        }

        when("moving the live Web Board back to Drawer from its header menu") {
            let header = app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "identifier BEGINSWITH 'board-header.' AND label CONTAINS 'Board: Live Drawer Fixture'"
                )
            ).firstMatch
            header.rightClick()
            app.menuItems["Move to Drawer"].click()
            enterDenMode(in: app)
            app.typeKey(.tab, modifierFlags: [])
            XCTAssertTrue(peekInput.waitUntilExists(timeout: 5))
            XCTAssertEqual(peekInput.value as? String, "seedcontinued")
            app.typeKey(.rightArrow, modifierFlags: [.command])
            app.typeText("drawer")
        }

        then("the same page retains its form state and receives Drawer input") {
            XCTAssertEqual(peekInput.value as? String, "seedcontinueddrawer")
        }
    }

    // Protects Terminal input across creation, remounting, placement and moving back to Drawer.
    // Unit tests cannot observe keyboard delivery to the mounted Ghostty surface.
    @MainActor
    func testDrawerTerminalKeepsShellStateAndReceivesInputAfterPlacement() throws {
        let app = launchApp(boardCount: .one)
        let drawer = app.descendants(matching: .any).matching(identifier: "drawer").firstMatch
        let place = drawer.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Place ", " as Board")
        ).firstMatch
        let surfaces = app.scrollViews["board-strip"].firstMatch.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'board-surface.'"))

        given("Drawer is open in Den Mode") {
            enterDenMode(in: app)
            app.typeKey(.tab, modifierFlags: [])
            XCTAssertTrue(drawer.waitUntilExists(timeout: 5))
        }

        when("opening the Terminal in Drawer and setting Shell state") {
            app.typeKey(" ", modifierFlags: [])
            let input = app.textFields["open-board-input"].firstMatch
            XCTAssertTrue(input.waitUntilExists(timeout: 5))
            XCTAssertEqual(input.value as? String, "")
            paste(":terminal /tmp", in: app)
            app.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(drawer.waitUntilExists(timeout: 5))
            XCTAssertTrue(place.waitUntilExists(timeout: 5))
            paste("drawer_probe_value=retained", in: app)
            app.typeKey(.return, modifierFlags: [])
        }

        when("canceling another addition without sending text to the live Terminal") {
            drawer.buttons["drawer-add-item"].click()
            let input = app.textFields["open-board-input"].firstMatch
            XCTAssertTrue(input.waitUntilExists(timeout: 5))
            input.click()
            app.typeKey("a", modifierFlags: [.command])
            paste("https://example.com/cancel", in: app)
            XCTAssertEqual(input.value as? String, "https://example.com/cancel")
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(input.waitUntilAbsent(timeout: 5))
            XCTAssertTrue(place.waitUntilExists(timeout: 5))
        }

        when("closing Drawer, reopening it, and placing the Terminal as a Board") {
            app.typeKey(.escape, modifierFlags: [.control])
            XCTAssertTrue(drawer.waitUntilAbsent(timeout: 5))
            enterDenMode(in: app)
            app.typeKey(.tab, modifierFlags: [])
            XCTAssertTrue(place.waitUntilExists(timeout: 5))
            place.click()
            XCTAssertTrue(drawer.waitUntilAbsent(timeout: 5))
            assertEventually("The Terminal should be placed beside the original Board") {
                surfaces.allElementsBoundByIndex.count == 2
            }
        }

        when("moving the Board back into Drawer with Den Mode a") {
            enterDenMode(in: app)
            app.typeKey("a", modifierFlags: [])
            app.typeKey(.tab, modifierFlags: [])
            XCTAssertTrue(place.waitUntilExists(timeout: 5))
        }

        let discardItems = drawer.buttons.matching(
            NSPredicate(
                format: "label BEGINSWITH %@ AND label != %@", "Discard ", "Discard All Drawer Items"))
        XCTAssertEqual(discardItems.count, 2)

        when("typing a command that exits only if the original Shell state survived") {
            paste("if [[ \"$drawer_probe_value\" == retained ]]; then exit; fi", in: app)
            app.typeKey(.return, modifierFlags: [])
        }

        then("the same Terminal Session receives the command and exits") {
            assertEventually("Only the initial Drawer Item should remain after the Terminal exits", timeout: 10) {
                discardItems.count == 1
            }
        }
    }
}
