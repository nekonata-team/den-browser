import XCTest

final class PerformanceUITests: UITestCase {
    @MainActor
    func testApplicationLaunchPerformance() {
        let app = prepareApp(boardCount: .one)
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(
            metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)],
            options: options
        ) {
            app.launch()
        }
    }

    // Exercises native ScrollView rendering; unit tests cannot observe missed display updates.
    @MainActor
    func testBoardStripScrollHitches() {
        let app = prepareApp(fixture: .rapidBoardFocus, boardCount: .one, standardMotion: true)
        let window = app.windows.firstMatch
        let strip = app.descendants(matching: .any).matching(identifier: "board-strip").firstMatch
        let charlie = window.descendants(matching: .any).matching(
            identifier: "board-header.\(FixtureBoard.charlie.rawValue)"
        ).firstMatch

        given("a loaded overflowing Desk with Standard Motion") {
            app.launch()
            app.typeKey("u", modifierFlags: [.command, .option, .shift])
            XCTAssertTrue(window.waitUntilExists(timeout: 10))
            XCTAssertTrue(charlie.wait(for: \.isHittable, toEqual: true, timeout: 10))
            XCTAssertTrue(app.textFields["Sheet input"].firstMatch.waitUntilExists(timeout: 10))
            app.typeKey(",", modifierFlags: .control)
            XCTAssertTrue(
                app.windows.matching(identifier: "UI Testing · DEN MODE").firstMatch.waitUntilExists(timeout: 5)
            )
        }

        // Swipe in the Strip's top inset so a Web Sheet cannot consume the gesture.
        let gesture = strip.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: strip.frame.width / 2, dy: 16))
        func resetScroll() {
            app.typeKey("c", modifierFlags: [])
        }
        gesture.swipeRight(velocity: .slow)
        resetScroll()
        let surface = app.descendants(matching: .any).matching(
            identifier: "board-surface.\(FixtureBoard.charlie.rawValue)"
        ).firstMatch
        let centered = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in abs(surface.frame.midX - strip.frame.midX) <= 3 },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [centered], timeout: 5), .completed)
        let startingX = charlie.frame.minX
        let windowSize = window.frame.size
        let environment = XCTAttachment(
            string:
                "Window: \(window.frame)\nBoard Strip: \(strip.frame)\nOS: \(ProcessInfo.processInfo.operatingSystemVersionString)"
        )
        environment.name = "Board Strip hitch measurement environment"
        environment.lifetime = .keepAlways
        add(environment)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        options.invocationOptions = .manuallyStop

        when("measuring a rightward swipe across the Board Strip") {
            measure(metrics: [XCTHitchMetric(application: app)], options: options) {
                gesture.swipeRight(velocity: .slow)
                stopMeasuring()
                then("the Strip has actually scrolled") {
                    XCTAssertGreaterThan(charlie.frame.minX, startingX + 10)
                }
                resetScroll()
                then("the next iteration starts at the same position and window size") {
                    XCTAssertEqual(window.frame.size, windowSize)
                    let aligned = XCTNSPredicateExpectation(
                        predicate: NSPredicate { _, _ in abs(charlie.frame.minX - startingX) <= 3 },
                        object: nil
                    )
                    XCTAssertEqual(XCTWaiter.wait(for: [aligned], timeout: 5), .completed)
                }
            }
        }
    }
}
