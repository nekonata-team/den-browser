import XCTest

final class PerformanceUITests: XCTestCase, BDD {
    private var processLock: UITestProcessLock?
    private var defaultsSuiteName: String?
    private var fixtureDirectory: URL?

    override func setUpWithError() throws {
        processLock = try UITestProcessLock()
        continueAfterFailure = false
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

    @MainActor
    private func preparedApplication(
        fixture: UITestFixture = .interactionBasics,
        boardCount: UITestBoardCount = .one,
        standardMotion: Bool = false
    ) -> XCUIApplication {
        let app = uiTestApplication()
        let runID = UUID().uuidString
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appending(path: "DenBrowserUITests", directoryHint: .isDirectory)
            .appending(path: runID, directoryHint: .isDirectory)
        self.fixtureDirectory = fixtureDirectory
        let seedURL = fixtureDirectory.appending(path: "initial-profile.json")
        do {
            try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
            try UITestFixtureFactory.makeProfileSeed(fixture: fixture, boardCount: boardCount)
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

        if standardMotion {
            app.launchArguments += ["-preferences.appearance.motion.mode", "standard"]
        }
        return app
    }

    @MainActor
    func testApplicationLaunchPerformance() {
        let app = preparedApplication()
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
        let app = preparedApplication(fixture: .rapidBoardFocus, standardMotion: true)
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
                app.windows.matching(identifier: "UI Testing · DEN MODE").firstMatch.waitUntilExists(timeout: 5))
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
            predicate: NSPredicate { _, _ in abs(surface.frame.midX - strip.frame.midX) <= 3 }, object: nil)
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
                        predicate: NSPredicate { _, _ in abs(charlie.frame.minX - startingX) <= 3 }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [aligned], timeout: 5), .completed)
                }
            }
        }
    }
}
