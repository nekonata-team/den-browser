import XCTest

final class DrawerEntryUITests: UITestCase {
    // Protects Option Return delivery from the native field through SwiftUI to Drawer Peek.
    // Unit tests cannot observe native text-field key handling.
    @MainActor
    func testOpenBoardOptionReturnOpensDrawerPeek() throws {
        let url = try makeDrawerEntryFixture()
        let app = launchApp(boardCount: .one)
        let input = app.textFields["open-board-input"]
        let drawer = app.descendants(matching: .any).matching(identifier: "drawer").firstMatch

        given("Open Board contains a local web URL") {
            app.typeKey("t", modifierFlags: [.command])
            XCTAssertTrue(input.waitUntilExists(timeout: 5))
            paste(url.absoluteString, in: app)
        }

        when("pressing Option Return in the native input field") {
            app.typeKey(.return, modifierFlags: [.option])
        }

        then("the input opens as a Drawer Peek") {
            XCTAssertTrue(input.waitUntilAbsent(timeout: 5))
            XCTAssertTrue(drawer.textFields["Opened in Drawer"].firstMatch.waitUntilExists(timeout: 10))
        }
    }

    // Protects Router -> observable request -> SwiftUI execution from a native text field.
    @MainActor
    func testDrawerEntryUniversalSearchOptionReturn() throws {
        let url = try makeDrawerEntryFixture()
        let app = launchApp(boardCount: .one)
        let input = app.textFields["universal-search-input"]
        let drawer = app.descendants(matching: .any).matching(identifier: "drawer").firstMatch

        given("Universal Search contains a local URL") {
            app.typeKey("p", modifierFlags: [.command])
            XCTAssertTrue(input.waitUntilExists(timeout: 5))
            paste(url.absoluteString, in: app)
        }
        when("pressing Option Return") {
            app.typeKey(.return, modifierFlags: [.option])
        }
        then("the URL is presented inside Drawer Peek") {
            XCTAssertTrue(input.waitUntilAbsent(timeout: 5))
            XCTAssertTrue(drawer.textFields["Opened in Drawer"].firstMatch.waitUntilExists(timeout: 10))
        }
    }

    // Protects Option state reaching a SwiftUI Button action; unit tests cannot simulate a native click.
    @MainActor
    func testDrawerEntryRecentOptionClick() throws {
        let url = try makeDrawerEntryFixture()
        let app = launchApp(boardCount: .one, recentURL: url)
        let recent = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Recent Drawer Fixture"))
            .firstMatch
        let drawer = app.descendants(matching: .any).matching(identifier: "drawer").firstMatch

        given("Open Board shows a Recent Item") {
            app.typeKey("t", modifierFlags: [.command])
            XCTAssertTrue(recent.waitUntilExists(timeout: 5))
        }
        when("Option clicking the Recent Item") {
            XCUIElement.perform(withKeyModifiers: [.option]) { recent.click() }
        }
        then("the Recent Item opens in Drawer Peek") {
            XCTAssertTrue(drawer.textFields["Opened in Drawer"].firstMatch.waitUntilExists(timeout: 10))
        }
    }

    // Protects modifier delivery through SwiftUI's tap gesture on an Essential row.
    @MainActor
    func testDrawerEntryEssentialOptionClick() throws {
        let url = try makeDrawerEntryFixture()
        let app = launchApp(boardCount: .one, recentURL: url)
        let drawer = app.descendants(matching: .any).matching(identifier: "drawer").firstMatch
        let essential = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "essential.")).firstMatch

        given("an Essential has been saved from the Recent Item") {
            app.typeKey("t", modifierFlags: [.command])
            let save = app.buttons["Save as Essential…"].firstMatch
            XCTAssertTrue(save.waitUntilExists(timeout: 5))
            save.click()
            let key = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "e.g. c or C")).firstMatch
            XCTAssertTrue(key.waitUntilExists(timeout: 5))
            key.click()
            key.typeText("e")
            app.buttons["Save Essential"].click()
            XCTAssertTrue(key.waitUntilAbsent(timeout: 5))
            enterDenMode(in: app)
            app.typeKey("g", modifierFlags: [])
            XCTAssertTrue(essential.waitUntilExists(timeout: 5))
        }
        when("Option clicking the Essential") {
            XCUIElement.perform(withKeyModifiers: [.option]) { essential.click() }
        }
        then("the Essential opens in Drawer Peek") {
            XCTAssertTrue(drawer.textFields["Opened in Drawer"].firstMatch.waitUntilExists(timeout: 10))
        }
    }

    private func makeDrawerEntryFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "drawer-entry.html")
        try "<html><body><input aria-label='Opened in Drawer'></body></html>"
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
