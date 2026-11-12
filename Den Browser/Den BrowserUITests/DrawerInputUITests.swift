import XCTest

final class DrawerInputUITests: UITestCase {
    // Protects native responder restoration when SwiftUI dismisses Open Board over Drawer search.
    // Unit tests cannot observe which mounted text field receives the next keystroke.
    @MainActor
    func testCancelingAdditionRestoresFilteredWebPeekInput() throws {
        let url = try makeHTMLFixture(
            """
            <html><head><title>Live Drawer Fixture</title></head><body>
              <input aria-label="Live input" spellcheck="false" autocorrect="off">
            </body></html>
            """
        )
        let app = launchApp(boardCount: .one, drawerSheetURL: url)
        let drawer = app.descendants(matching: .any).matching(identifier: "drawer").firstMatch
        let peekInput = drawer.textFields["Live input"].firstMatch
        let search = drawer.textFields["drawer-search"].firstMatch
        let additionInput = app.textFields["open-board-input"].firstMatch

        given("a filtered Drawer holds a live form value") {
            app.buttons["drawer-button"].click()
            XCTAssertTrue(drawer.waitUntilExists(timeout: 5))
            let item = drawer.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Drawer Fixture")).firstMatch
            XCTAssertTrue(item.waitUntilExists(timeout: 5))
            item.click()
            XCTAssertTrue(peekInput.waitUntilExists(timeout: 10))
            peekInput.click()
            app.typeText("a")
            assertValue("a", in: peekInput)
            drawer.buttons["Search Drawer Items"].click()
            XCTAssertTrue(search.waitUntilExists(timeout: 5))
            search.click()
            paste("Live", in: app)
            assertValue("Live", in: search)
        }

        when("canceling an addition and continuing to type without clicking search again") {
            drawer.buttons["drawer-add-item"].click()
            XCTAssertTrue(additionInput.waitUntilExists(timeout: 5))
            paste("https://example.com/cancel", in: app)
            assertValue("https://example.com/cancel", in: additionInput)
            app.typeKey(.escape, modifierFlags: [])
            app.typeKey(.rightArrow, modifierFlags: [.command])
            app.typeText(" Drawer Fixture")
        }

        then("search retains its filter and receives the next input") {
            XCTAssertTrue(additionInput.waitUntilAbsent(timeout: 5))
            assertValue("Live Drawer Fixture", in: search)
        }

        when("leaving search") {
            app.typeKey(.escape, modifierFlags: [])
        }

        then("the original Web Peek still holds its form value") {
            XCTAssertTrue(peekInput.waitUntilExists(timeout: 5))
            assertValue("a", in: peekInput)
        }
    }

    // Protects AppKit-to-Ghostty responder handoff when the addition panel is dismissed.
    // Unit tests cannot deliver real input through the remounted Terminal surface.
    @MainActor
    func testCancelingAdditionRestoresTerminalInput() throws {
        let app = launchApp(boardCount: .one)
        let drawer = app.descendants(matching: .any).matching(identifier: "drawer").firstMatch
        let additionInput = app.textFields["open-board-input"].firstMatch
        let discardItems = drawer.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ AND label != %@", "Discard ", "Discard All Drawer Items")
        )

        given("a Terminal Peek holds Shell state") {
            enterDenMode(in: app)
            app.typeKey(.tab, modifierFlags: [])
            XCTAssertTrue(drawer.waitUntilExists(timeout: 5))
            app.typeKey(" ", modifierFlags: [])
            XCTAssertTrue(additionInput.waitUntilExists(timeout: 5))
            paste(":terminal /tmp", in: app)
            app.typeKey(.return, modifierFlags: [])
            assertEventually("The Terminal Item should appear beside the initial Web Item") {
                discardItems.count == 2
            }
            paste("cancel_probe=retained", in: app)
            app.typeKey(.return, modifierFlags: [])
        }

        when("canceling an addition that must not reach the live Shell") {
            drawer.buttons["drawer-add-item"].click()
            XCTAssertTrue(additionInput.waitUntilExists(timeout: 5))
            paste("cancel_probe=changed;", in: app)
            assertValue("cancel_probe=changed;", in: additionInput)
            app.typeKey(.escape, modifierFlags: [])
            paste("if [[ \"$cancel_probe\" == retained ]]; then exit; fi", in: app)
            app.typeKey(.return, modifierFlags: [])
        }

        then("the original Shell receives the command with its state intact and exits") {
            assertEventually("Only the initial Web Item should remain", timeout: 10) {
                discardItems.count == 1
            }
        }
    }
}
