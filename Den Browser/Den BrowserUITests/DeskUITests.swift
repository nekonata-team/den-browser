import XCTest

final class DeskUITests: UITestCase {
    // Protects native TextField submission while SwiftUI removes the New Desk panel.
    // Unit tests cannot deliver queued Return events to the outgoing native responder.
    @MainActor
    func testRepeatedReturnCreatesOnlyOneDesk() throws {
        let app = launchApp(boardCount: .one)
        let search = app.textFields.matching(NSPredicate(format: "placeholderValue == 'Filter presets'")).firstMatch
        let desks = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'desk-switcher.'"))
        let label = "Repeated Return"
        let initialDeskCount = desks.count

        given("New Desk search offers to create a named empty Desk") {
            app.buttons["New Desk"].click()
            XCTAssertTrue(search.waitUntilExists(timeout: 5))
            search.click()
            app.typeText(label)
            XCTAssertTrue(
                app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Create \"\(label)\""))
                    .firstMatch.waitUntilExists(timeout: 5)
            )
        }

        when("pressing Return repeatedly while the panel closes") {
            app.typeText(String(repeating: "\r", count: 5))
        }

        then("only one Desk is created") {
            XCTAssertTrue(search.waitUntilAbsent(timeout: 5))
            XCTAssertEqual(desks.count, initialDeskCount + 1)
            XCTAssertEqual(desks.matching(NSPredicate(format: "label CONTAINS %@", label)).count, 1)
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
}
