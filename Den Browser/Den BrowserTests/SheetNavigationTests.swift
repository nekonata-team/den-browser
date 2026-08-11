import AppKit
import Combine
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
private final class WebViewLoadWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?

    func load(_ html: String, baseURL: URL, in webView: WKWebView) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.navigationDelegate = self
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resume()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resume()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resume()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        resume()
    }

    private func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
struct SheetNavigationTests {
    @Test func sheetURLPolicyAcceptsWebAndAbsoluteLocalFileURLs() {
        let supported = [
            URL(string: "http://example.com/")!,
            URL(string: "HTTPS://EXAMPLE.COM/path")!,
            URL(string: "file:///tmp/example.html")!,
            URL(string: "file://localhost/tmp/example.html")!,
        ]
        let unsupported = [
            URL(string: "https://")!,
            URL(string: "file:relative.html")!,
            URL(string: "file://server/share/example.html")!,
            URL(string: "data:text/plain,example")!,
            URL(string: "about:blank")!,
            URL(string: "mailto:user@example.com")!,
        ]

        #expect(supported.allSatisfy(SheetURLPolicy.isSupported))
        #expect(unsupported.allSatisfy { !SheetURLPolicy.isSupported($0) })
        #expect(ExternalURLPolicy.isSupported(URL(string: "testapp://open/example")!))
        #expect(!ExternalURLPolicy.isSupported(URL(string: "https://example.com/")!))
        #expect(!ExternalURLPolicy.isSupported(URL(string: "file:///tmp/example")!))
    }

    @Test func sheetURLPolicyNormalizesRootPathAndHostCase() {
        #expect(
            SheetURLPolicy.canonicalSheetURL(URL(string: "HTTP://EXAMPLE.TEST")!)
                == URL(string: "http://example.test/")!)
        #expect(
            SheetURLPolicy.canonicalSheetURL(URL(string: "http://example.test/app")!)
                == URL(string: "http://example.test/app")!)
        #expect(
            SheetURLPolicy.canonicalSheetURL(
                URL(string: "file://localhost/tmp/a%20b.html?mode=test#section")!)
                == URL(string: "file:///tmp/a%20b.html?mode=test#section")!)
    }

    @Test func boardRuntimeLoadsLocalHTMLAndSiblingScript() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "DenBrowserFileURLTests-(UUID().uuidString)",
            directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let htmlURL = directory.appending(path: "index.html")
        let scriptURL = directory.appending(path: "title.js")
        try "<html><head><script src=\"title.js\"></script></head></html>".write(
            to: htmlURL, atomically: true, encoding: .utf8)
        try "document.title = 'Sibling script loaded';".write(
            to: scriptURL, atomically: true, encoding: .utf8)

        var continuation: AsyncStream<(URL?, String?)>.Continuation?
        let changes = AsyncStream<(URL?, String?)> { continuation = $0 }
        let runtime = BoardRuntime(
            board: BoardState(label: "Local", width: 520, currentSheetURL: htmlURL),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: SheetNavigationManager(scriptSource: ""),
            sheetScale: AppPreferences.defaultSheetScale,
            sheetNavigationActions: noOpSheetNavigationActions(),
            events: boardRuntimeEvents { _, url, title in
                continuation?.yield((url, title))
            })
        defer {
            continuation?.finish()
            runtime.dispose()
        }

        let observed = try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await change in changes where change.1 == "Sibling script loaded" {
                    return true
                }
                return false
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                return false
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        #expect(observed)
    }

    @Test func boardRuntimeAppliesSafariUserAgent() {
        let navigation = SheetNavigationManager(
            defaults: UserDefaults(suiteName: "UserAgentTest-\(UUID().uuidString)") ?? .standard,
            scriptSource: "")
        let board = BoardState(label: "Test", width: 520, currentSheetURL: nil)
        let runtime = BoardRuntime(
            board: board,
            websiteDataStore: .nonPersistent(),
            sheetNavigation: navigation,
            sheetScale: 100,
            sheetNavigationActions: noOpSheetNavigationActions(),
            events: boardRuntimeEvents()
        )

        #expect(runtime.webView.customUserAgent == BoardRuntime.defaultUserAgent)
        #expect(runtime.webView.customUserAgent?.contains("Version/") == true)
        #expect(runtime.webView.customUserAgent?.contains("Safari/") == true)
    }

    @Test func sheetNavigationPreferencesPersist() {
        let suiteName = "SheetNavigationManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = SheetNavigationManager(defaults: defaults, scriptSource: "")
        #expect(!manager.isEnabled)
        #expect(manager.hintAlphabet == "asdfghjkl")
        #expect(manager.userContentController.userScripts[0].source.contains("\"enabled\":false"))

        manager.setEnabled(true)
        #expect(manager.setHintAlphabet("Aa1a"))
        #expect(manager.setIgnoredSites("Example.com\nhttps://www.apple.com/path\nexample.com"))
        #expect(manager.userContentController.userScripts[0].source.contains("\"enabled\":true"))
        #expect(manager.userContentController.userScripts[0].source.contains("\"alphabet\":\"a1\""))
        #expect(manager.ignoredHosts == ["example.com", "www.apple.com"])
        #expect(
            Set((defaults.persistentDomain(forName: suiteName) ?? [:]).keys) == [
                "preferences.sheet-navigation.enabled",
                "preferences.sheet-navigation.hint-alphabet",
                "preferences.sheet-navigation.ignored-hosts",
            ])

        let restored = SheetNavigationManager(defaults: defaults, scriptSource: "")
        #expect(restored.isEnabled)
        #expect(restored.hintAlphabet == "a1")
        #expect(restored.ignoredHosts == ["example.com", "www.apple.com"])
    }

    @Test func pausedBoardsPersistIndependently() {
        let suiteName = "SheetNavigationPausedBoardsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = SheetNavigationManager(defaults: defaults, scriptSource: "")
        let firstBoardID = UUID()
        let secondBoardID = UUID()

        manager.setBoardPaused(true, for: firstBoardID)
        manager.setBoardPaused(true, for: secondBoardID)

        #expect(
            Set((defaults.persistentDomain(forName: suiteName) ?? [:]).keys) == [
                "preferences.sheet-navigation.paused-board-ids"
            ])

        #expect(manager.isBoardPaused(firstBoardID))
        #expect(manager.isBoardPaused(secondBoardID))

        manager.setBoardPaused(false, for: firstBoardID)

        #expect(!manager.isBoardPaused(firstBoardID))
        #expect(manager.isBoardPaused(secondBoardID))

        let restored = SheetNavigationManager(defaults: defaults, scriptSource: "")
        #expect(!restored.isBoardPaused(firstBoardID))
        #expect(restored.isBoardPaused(secondBoardID))
    }

    @Test func pauseConfigurationRemainsAfterDocumentReload() async throws {
        let source = try sheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let suiteName = "SheetNavigationPauseConfigurationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = SheetNavigationManager(defaults: defaults, scriptSource: source)
        let boardID = UUID()
        let webView = makeSheetNavigationWebView(manager: manager)
        let waiter = WebViewLoadWaiter()
        let baseURL = URL(string: "https://example.com/")!

        manager.setEnabled(true)
        manager.didOpen(webView, boardID: boardID, actions: noOpSheetNavigationActions())
        await waiter.load(sheetNavigationTestHTML, baseURL: baseURL, in: webView)

        manager.setBoardPaused(true, for: boardID)

        await waiter.load(sheetNavigationTestHTML, baseURL: baseURL, in: webView)
        manager.refreshConfiguration(for: webView)
        try await dispatchSheetKey("j", in: webView)

        let pausedScrollY = try #require(await webView.evaluateJavaScript("scrollY") as? Int)
        #expect(pausedScrollY == 0)

        manager.setBoardPaused(false, for: boardID)
        _ = try await webView.evaluateJavaScript("scrollTo(0, 0)")
        manager.refreshConfiguration(for: webView)
        try await dispatchSheetKey("j", in: webView)

        let resumedScrollY = try #require(await webView.evaluateJavaScript("scrollY") as? Int)
        #expect(resumedScrollY > 0)
    }

    @Test func bundledSheetNavigationScriptIsAvailable() throws {
        let url = try #require(Bundle.main.url(forResource: "SheetNavigation", withExtension: "js"))
        let source = try String(contentsOf: url, encoding: .utf8)

        #expect(source.contains("window.__denSheetNavigation"))
    }

    @Test func sheetNavigationScriptIsIsolatedFromPageScripts() async throws {
        let manager = SheetNavigationManager(scriptSource: try sheetNavigationScriptSource())
        manager.setEnabled(true)
        let webView = makeSheetNavigationWebView(manager: manager)
        let waiter = WebViewLoadWaiter()

        await waiter.load(sheetNavigationTestHTML, baseURL: URL(string: "https://example.com/")!, in: webView)
        let pageCanSeeBridge =
            (try await webView.evaluateJavaScript(
                "typeof window.webkit?.messageHandlers?.denSheetNavigation !== 'undefined'") as? Bool) ?? true
        let pageCanSeeConfiguration =
            (try await webView.evaluateJavaScript(
                "typeof window.__denSheetNavigation !== 'undefined'") as? Bool) ?? true
        try await dispatchSheetKey("f", in: webView)
        let hintCount = try #require(
            await webView.evaluateJavaScript(
                "document.querySelectorAll('[data-den-sheet-hints] span').length") as? Int)

        #expect(!pageCanSeeBridge)
        #expect(!pageCanSeeConfiguration)
        #expect(hintCount == 0)
    }

    @Test func modifiedLinkClicksAreKeptWhenSheetNavigationIsDisabled() async throws {
        let source = try sheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted || event.button",
            with: "if (event.button"
        )
        let manager = SheetNavigationManager(scriptSource: source)
        let webView = makeSheetNavigationWebView(manager: manager)
        let waiter = WebViewLoadWaiter()

        await waiter.load(
            """
            <a href="https://destination.example/">Destination</a>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )
        let commandClickWasAllowed =
            try await webView.evaluateJavaScript(
                """
                document.querySelector("a").dispatchEvent(new MouseEvent("click", {
                  metaKey: true,
                  button: 0,
                  bubbles: true,
                  cancelable: true,
                  composed: true
                }))
                """) as? Bool
        let optionClickWasAllowed =
            try await webView.evaluateJavaScript(
                """
                document.querySelector("a").dispatchEvent(new MouseEvent("click", {
                  altKey: true,
                  button: 0,
                  bubbles: true,
                  cancelable: true,
                  composed: true
                }))
                """) as? Bool

        #expect(commandClickWasAllowed == false)
        #expect(optionClickWasAllowed == false)
    }

    @Test func sheetNavigationScriptHandlesCoreMotionsAndModes() async throws {
        let source = try sheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if (")
        let manager = SheetNavigationManager(scriptSource: source)
        manager.setEnabled(true)
        let webView = makeSheetNavigationWebView(manager: manager)
        let waiter = WebViewLoadWaiter()

        await waiter.load(sheetNavigationTestHTML, baseURL: URL(string: "https://example.com/")!, in: webView)
        _ = try await webView.evaluateJavaScript("scrollTo(300, 300)")
        try await dispatchSheetKey("G", shift: true, in: webView)
        let afterBottom = try #require(await webView.evaluateJavaScript("[scrollX, scrollY]") as? [Int])
        _ = try await webView.evaluateJavaScript("scrollTo(300, 300)")
        try await dispatchSheetKey("0", in: webView)
        let afterLeft = try #require(await webView.evaluateJavaScript("[scrollX, scrollY]") as? [Int])
        _ = try await webView.evaluateJavaScript("scrollTo(0, 0)")
        try await dispatchSheetKey("3", in: webView)
        try await dispatchSheetKey("j", in: webView)
        let afterCountedScroll = try #require(await webView.evaluateJavaScript("scrollY") as? Int)
        _ = try await webView.evaluateJavaScript("scrollTo(0, 0)")
        try await dispatchSheetKey("f", in: webView)
        let hintCount = try #require(
            await webView.evaluateJavaScript(
                "document.querySelectorAll('[data-den-sheet-hints] span').length") as? Int)
        try await dispatchSheetKey("Escape", in: webView)
        try await dispatchSheetKey("/", in: webView)
        let hasFindBar =
            (try await webView.evaluateJavaScript(
                "document.querySelector('[data-den-sheet-find]') !== null") as? Bool) ?? false

        #expect(afterBottom[0] == 300)
        #expect(afterBottom[1] > 300)
        #expect(afterLeft == [0, 300])
        #expect(afterCountedScroll == 180)
        #expect(hintCount == 1)
        #expect(hasFindBar)
    }

    @Test func sheetNavigationFocusesEditableControlsInDocumentOrder() async throws {
        let source = try sheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if (")
        let manager = SheetNavigationManager(scriptSource: source)
        manager.setEnabled(true)
        let webView = makeSheetNavigationWebView(manager: manager)
        let waiter = WebViewLoadWaiter()

        await waiter.load(editableControlsTestHTML, baseURL: URL(string: "https://example.com/")!, in: webView)

        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("i", in: webView)
        let firstFocused = try #require(
            await webView.evaluateJavaScript("document.activeElement.id") as? String)
        #expect(firstFocused == "first-text")

        try await dispatchSheetKey("Escape", in: webView)
        try await dispatchSheetKey("2", in: webView)
        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("i", in: webView)
        let secondFocused = try #require(
            await webView.evaluateJavaScript("document.activeElement.id") as? String)
        #expect(secondFocused == "message")

        try await dispatchSheetKey("Escape", in: webView)
        try await dispatchSheetKey("3", in: webView)
        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("i", in: webView)
        let thirdFocused = try #require(
            await webView.evaluateJavaScript("document.activeElement.id") as? String)
        let scrollY = try #require(await webView.evaluateJavaScript("scrollY") as? Int)
        #expect(thirdFocused == "composer")
        #expect(scrollY > 0)
    }

    @Test func invalidHintAlphabetIsNotPersisted() {
        let suiteName = "SheetNavigationAlphabetTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = SheetNavigationManager(defaults: defaults, scriptSource: "")

        #expect(!manager.setHintAlphabet("a"))
        #expect(!manager.setHintAlphabet("ab!"))
        #expect(!manager.setHintAlphabet("あい"))
        #expect(manager.hintAlphabet == "asdfghjkl")
    }

    @Test func invalidIgnoredSiteIsNotPersisted() {
        let suiteName = "SheetNavigationIgnoredSitesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = SheetNavigationManager(defaults: defaults, scriptSource: "")

        #expect(!manager.setIgnoredSites("https://"))
        #expect(!manager.setIgnoredSites("not a host"))
        #expect(manager.ignoredHosts.isEmpty)
        #expect(manager.setIgnoredSites(""))
    }

    @Test func boardWebViewUsesSharedSheetNavigationController() {
        let manager = SheetNavigationManager(scriptSource: "")
        let runtime = BoardRuntime(
            board: board("Navigation", url: "about:blank"),
            websiteDataStore: .default(),
            sheetNavigation: manager,
            sheetScale: AppPreferences.defaultSheetScale,
            sheetNavigationActions: noOpSheetNavigationActions(),
            events: boardRuntimeEvents())

        #expect(runtime.webView.configuration.userContentController === manager.userContentController)
        #expect(manager.userContentController.userScripts.count == 1)
    }

    @Test func sheetNavigationCanOpenLinkAsAdjacentBoard() {
        let manager = SheetNavigationManager(scriptSource: "")
        let source = board("Source", url: "https://source.example/")
        let focused = board("Focused", url: "https://focused.example/")
        let currentDesk = desk("Desk", boards: [source, focused], focusedBoardID: focused.id)
        let store = DenStore(
            state: DenState(desks: [currentDesk], focusedDeskID: currentDesk.id),
            sheetNavigation: manager
        )
        let sourceWebView = store.runtime(for: source).webView
        manager.setEnabled(true)

        #expect(
            manager.handleScriptMessage(
                [
                    "action": "openBoard",
                    "url": "https://destination.example/path",
                ], from: sourceWebView))
        #expect(
            store.focusedDesk?.boards.map(\.currentSheetURL) == [
                URL(string: "https://source.example/"),
                URL(string: "https://destination.example/path"),
                URL(string: "https://focused.example/"),
            ])
        #expect(store.focusedDesk?.focusedBoardID == store.focusedDesk?.boards[1].id)
    }

    @Test func sheetNavigationCanOpenAndKeepLocalFileLinks() throws {
        let manager = SheetNavigationManager(scriptSource: "")
        let source = board("Source", url: "https://source.example/")
        let currentDesk = desk("Desk", boards: [source], focusedBoardID: source.id)
        let store = DenStore(
            state: DenState(desks: [currentDesk], focusedDeskID: currentDesk.id),
            sheetNavigation: manager)
        let sourceWebView = store.runtime(for: source).webView
        let fileURL = try #require(URL(string: "file:///tmp/Den%20Browser/reference.html"))
        manager.setEnabled(true)

        #expect(
            manager.handleScriptMessage(
                ["action": "openBoard", "url": fileURL.absoluteString],
                from: sourceWebView))
        #expect(store.focusedBoard?.currentSheetURL == fileURL)

        #expect(
            manager.handleScriptMessage(
                ["action": "keepInDrawer", "url": fileURL.absoluteString],
                from: sourceWebView))
        #expect(store.state.drawerItems.first?.url == fileURL)
    }

    @Test func sheetNavigationShowsToastForCopyAndInvalidPaste() async throws {
        let manager = SheetNavigationManager(scriptSource: "")
        let source = board("Source", url: "https://source.example/")
        let currentDesk = desk("Desk", boards: [source], focusedBoardID: source.id)
        let store = DenStore(
            state: DenState(desks: [currentDesk], focusedDeskID: currentDesk.id),
            sheetNavigation: manager
        )
        let webView = store.runtime(for: source).webView
        let waiter = WebViewLoadWaiter()

        manager.setEnabled(true)
        await waiter.load("<html>Current Sheet</html>", baseURL: URL(string: "https://source.example/")!, in: webView)
        defer { NSPasteboard.general.clearContents() }

        #expect(manager.handleScriptMessage(["action": "copyURL"], from: webView))
        #expect(store.toastMessage?.message == "Copied Current Sheet URL.")

        NSPasteboard.general.clearContents()
        for action in ["pasteURL", "pasteURLInNewBoard"] {
            #expect(!manager.handleScriptMessage(["action": action], from: webView))
            #expect(store.toastMessage?.message == "Clipboard does not contain a supported URL.")
        }
    }

    @Test func sheetNavigationReportsCopyFailureWithoutCurrentURL() {
        let manager = SheetNavigationManager(scriptSource: "")
        let webView = WKWebView()
        var didReportFailure = false
        manager.didOpen(
            webView,
            actions: .init(onCopyURLFailed: { didReportFailure = true })
        )
        manager.setEnabled(true)

        #expect(!manager.handleScriptMessage(["action": "copyURL"], from: webView))
        #expect(didReportFailure)
    }

    @Test func commandClickCanOpenLinkWhenSheetNavigationIsDisabled() {
        let manager = SheetNavigationManager(scriptSource: "")
        let source = board("Source", url: "https://source.example/")
        let currentDesk = desk("Desk", boards: [source], focusedBoardID: source.id)
        let store = DenStore(
            state: DenState(desks: [currentDesk], focusedDeskID: currentDesk.id),
            sheetNavigation: manager
        )
        let sourceWebView = store.runtime(for: source).webView

        #expect(
            manager.handleScriptMessage(
                [
                    "action": "commandOpenBoard",
                    "url": "https://destination.example/path",
                ], from: sourceWebView))
        #expect(
            store.focusedDesk?.boards.map(\.currentSheetURL) == [
                URL(string: "https://source.example/"),
                URL(string: "https://destination.example/path"),
            ])
        #expect(store.focusedDesk?.focusedBoardID == source.id)

        #expect(
            manager.handleScriptMessage(
                [
                    "action": "commandOpenBoard",
                    "url": "https://focused.example/path",
                    "focused": true,
                ], from: sourceWebView))
        #expect(
            store.focusedDesk?.boards.map(\.currentSheetURL) == [
                URL(string: "https://source.example/"),
                URL(string: "https://focused.example/path"),
                URL(string: "https://destination.example/path"),
            ])
        #expect(store.focusedDesk?.focusedBoardID == store.focusedDesk?.boards[1].id)
    }

    @Test func optionClickKeepsLinkInDrawerWithoutOpeningIt() {
        let manager = SheetNavigationManager(scriptSource: "")
        let source = board("Source", url: "https://source.example/")
        let currentDesk = desk("Desk", boards: [source], focusedBoardID: source.id)
        let store = DenStore(
            state: DenState(desks: [currentDesk], focusedDeskID: currentDesk.id),
            sheetNavigation: manager
        )
        let sourceWebView = store.runtime(for: source).webView
        let destination = URL(string: "https://destination.example/path")!

        #expect(
            manager.handleScriptMessage(
                [
                    "action": "keepInDrawer",
                    "url": destination.absoluteString,
                ], from: sourceWebView))
        #expect(store.state.drawerItems.map(\.url) == [destination])
        #expect(!store.isDrawerOpen)
        #expect(store.focusedDesk?.focusedBoardID == source.id)
        #expect(store.focusedBoard?.currentSheetURL == source.currentSheetURL)
    }

    @Test func sheetNavigationRoutesRemoveAndRestoreBoardActions() {
        let manager = SheetNavigationManager(scriptSource: "")
        let source = board("First", url: "https://first.example/")
        let second = board("Second", url: "https://second.example/")
        let currentDesk = desk("Desk", boards: [source, second], focusedBoardID: source.id)
        let store = DenStore(
            state: DenState(desks: [currentDesk], focusedDeskID: currentDesk.id),
            sheetNavigation: manager
        )
        let sourceWebView = store.runtime(for: source).webView
        let secondWebView = store.runtime(for: second).webView
        manager.setEnabled(true)

        #expect(store.focusedDesk?.boards.count == 2)
        #expect(manager.handleScriptMessage(["action": "removeBoard"], from: sourceWebView))
        #expect(store.focusedDesk?.boards.count == 1)

        #expect(manager.handleScriptMessage(["action": "restoreBoard"], from: secondWebView))
        #expect(store.focusedDesk?.boards.count == 2)
    }

    @Test func sheetNavigationRejectsUnsupportedMessages() {
        let manager = SheetNavigationManager(scriptSource: "")
        let webView = WKWebView()

        #expect(
            !manager.handleScriptMessage(
                ["action": "openBoard", "url": "https://example.com/"], from: webView))
        manager.setEnabled(true)
        #expect(
            !manager.handleScriptMessage(
                ["action": "openBoard", "url": "mailto:user@example.com"], from: webView))
        #expect(
            !manager.handleScriptMessage(
                ["action": "unknown", "url": "https://example.com/"], from: webView))
        #expect(!manager.handleScriptMessage(["action": "openBoard"], from: webView))
    }

    @Test func sheetNavigationRoutesCurrentSheetActionsToDenPanels() async throws {
        let source = try sheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if (")
        let manager = SheetNavigationManager(scriptSource: source)
        let board = board("Source", url: "https://source.example/")
        let desk = desk("Desk", boards: [board], focusedBoardID: board.id)
        let store = DenStore(
            state: DenState(desks: [desk], focusedDeskID: desk.id),
            sheetNavigation: manager
        )
        let webView = store.runtime(for: board).webView
        let waiter = WebViewLoadWaiter()
        let url = URL(string: "https://source.example/current")!

        manager.setEnabled(true)
        await waiter.load("<html>Current Sheet</html>", baseURL: url, in: webView)

        #expect(manager.handleScriptMessage(["action": "editCurrentSheet"], from: webView))
        #expect(store.isEditBoardLinkPanelPresented)

        store.hideEditBoardLinkPanel()
        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("Shift", shift: true, in: webView)
        try await dispatchSheetKey("E", shift: true, in: webView)
        #expect(store.isOpenBoardPanelPresented)
        #expect(store.openBoardPanelInitialURL == url)

        store.hideOpenBoardPanel()
        try await dispatchSheetKey("t", in: webView)
        #expect(store.isOpenBoardPanelPresented)

        store.hideOpenBoardPanel()
        try await dispatchSheetKey("T", shift: true, in: webView)
        #expect(store.isOverviewPresented)
    }

    @Test func sheetNavigationRoutesBoardBoundaryCommands() async throws {
        let source = try sheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let manager = SheetNavigationManager(scriptSource: source)
        let boards = [board("First"), board("Middle"), board("Last")]
        let currentDesk = desk("Desk", boards: boards, focusedBoardID: boards[1].id)
        let store = DenStore(
            state: DenState(desks: [currentDesk], focusedDeskID: currentDesk.id),
            sheetNavigation: manager
        )
        let webView = store.runtime(for: boards[1]).webView
        let waiter = WebViewLoadWaiter()

        manager.setEnabled(true)
        await waiter.load("<html>Current Sheet</html>", baseURL: URL(string: "https://example.com/")!, in: webView)

        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("T", shift: true, in: webView)
        #expect(store.focusedDesk?.focusedBoardID == boards[0].id)

        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("t", in: webView)
        #expect(store.focusedDesk?.focusedBoardID == boards[2].id)

        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("0", in: webView)
        #expect(store.focusedDesk?.focusedBoardID == boards[0].id)

        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("$", shift: true, in: webView)
        #expect(store.focusedDesk?.focusedBoardID == boards[2].id)

        #expect(manager.handleScriptMessage(["action": "goToFirstSheet"], from: webView))
        #expect(manager.handleScriptMessage(["action": "goToLatestSheet"], from: webView))
    }

    @Test func sheetNavigationRemovesBoardAndFocusesNextBoard() async throws {
        let source = try sheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let manager = SheetNavigationManager(scriptSource: source)
        let boards = [board("First"), board("Middle"), board("Last")]
        let currentDesk = desk("Desk", boards: boards, focusedBoardID: boards[1].id)
        let store = DenStore(
            state: DenState(desks: [currentDesk], focusedDeskID: currentDesk.id),
            sheetNavigation: manager
        )
        let webView = store.runtime(for: boards[1]).webView
        let waiter = WebViewLoadWaiter()

        manager.setEnabled(true)
        await waiter.load("<html>Current Sheet</html>", baseURL: URL(string: "https://example.com/")!, in: webView)

        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("x", in: webView)

        #expect(store.focusedDesk?.boards.map(\.id) == [boards[0].id, boards[2].id])
        #expect(store.focusedDesk?.focusedBoardID == boards[2].id)
    }

    @Test func boardRuntimeObservesUrlAndTitleChanges() async throws {
        let manager = SheetNavigationManager(scriptSource: "")
        var changeContinuation: AsyncStream<(URL?, String?)>.Continuation?
        let changes = AsyncStream<(URL?, String?)> { continuation in
            changeContinuation = continuation
        }

        let runtime = BoardRuntime(
            board: board("Initial", url: "about:blank"),
            websiteDataStore: .default(),
            sheetNavigation: manager,
            sheetScale: AppPreferences.defaultSheetScale,
            sheetNavigationActions: noOpSheetNavigationActions(),
            events: boardRuntimeEvents { _, url, title in
                changeContinuation?.yield((url, title))
            })

        let waiter = WebViewLoadWaiter()
        let testURL = URL(string: "https://example.com/test-page")!

        await waiter.load(
            "<html><head><title>Test Page Title</title></head><body>Hello</body></html>",
            baseURL: testURL,
            in: runtime.webView
        )

        let observedChange = try await withThrowingTaskGroup(of: (URL?, String?)?.self) { group in
            group.addTask {
                for await change in changes {
                    if change.0 == testURL && change.1 == "Test Page Title" {
                        return change
                    }
                }
                return nil
            }

            group.addTask {
                try await Task.sleep(for: .seconds(2))
                return nil
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
        changeContinuation?.finish()

        #expect(observedChange?.0 == testURL)
        #expect(observedChange?.1 == "Test Page Title")
    }

    @Test func boardRuntimeFindsPageFavicon() async throws {
        let runtime = BoardRuntime(
            board: BoardState(label: "Initial", width: 520, currentSheetURL: nil),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: SheetNavigationManager(scriptSource: ""),
            sheetScale: AppPreferences.defaultSheetScale,
            sheetNavigationActions: noOpSheetNavigationActions(),
            events: boardRuntimeEvents())
        let expectedURL = URL(string: "https://example.com/assets/favicon.png")!
        var continuation: AsyncStream<URL?>.Continuation?
        let faviconURLs = AsyncStream<URL?> { continuation = $0 }
        let observation = runtime.$faviconURL.sink { continuation?.yield($0) }

        runtime.webView.loadHTMLString(
            """
            <html><head><link rel="icon" href="/assets/favicon.png"></head></html>
            """,
            baseURL: URL(string: "https://example.com/"))

        let observedURL = try await withThrowingTaskGroup(of: URL?.self) { group in
            group.addTask {
                for await url in faviconURLs where url == expectedURL {
                    return url
                }
                return nil
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                return nil
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
        observation.cancel()
        continuation?.finish()

        #expect(observedURL == expectedURL)
    }

    private var sheetNavigationTestHTML: String {
        """
        <!doctype html>
        <style>
          html, body { margin: 0; width: 2400px; height: 4000px; }
        </style>
        <a href="https://destination.example/">Destination</a>
        <p>find target</p>
        """
    }

    private var editableControlsTestHTML: String {
        """
        <!doctype html>
        <style>
          body { margin: 0; height: 4000px; }
          #composer { margin-top: 3800px; }
        </style>
        <input id="first-text" type="text">
        <input id="hidden-input" type="text" hidden>
        <input id="disabled-input" type="text" disabled>
        <input id="readonly-input" type="text" readonly>
        <input id="file-input" type="file">
        <textarea id="message"></textarea>
        <div id="composer" contenteditable="true" role="textbox"></div>
        """
    }

    private func sheetNavigationScriptSource() throws -> String {
        let url = try #require(Bundle.main.url(forResource: "SheetNavigation", withExtension: "js"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeSheetNavigationWebView(manager: SheetNavigationManager) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = manager.userContentController
        return WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
    }

    private func noOpSheetNavigationActions() -> SheetNavigationManager.Actions {
        .init(
            onOpenBoard: { _ in },
            onOpenBoardInBackground: { _ in },
            onKeepInDrawer: { _ in },
            onEditCurrentSheet: {},
            onOpenCurrentSheetInNewBoard: { _ in },
            onPasteURLInNewBoard: { _ in },
            onCopyURLSucceeded: {},
            onCopyURLFailed: {},
            onPasteURLFailed: {},
            onOpenBoardPanel: {},
            onShowOverview: {},
            onRemoveBoard: {},
            onRemoveBoardAndFocusNext: {},
            onRestoreBoard: {},
            onFocusFirstBoard: {},
            onFocusLastBoard: {},
            onFocusPreviousBoard: {},
            onFocusNextBoard: {},
            onGoToFirstSheet: {},
            onGoToLatestSheet: {},
            isSupportedSheetURL: SheetURLPolicy.isSupported,
            onNavigateCurrentSheet: { _ in }
        )
    }

    private func boardRuntimeEvents(
        onChange: @escaping (UUID, URL?, String?) -> Void = { _, _, _ in },
        onFullscreenChange: ((UUID, Bool) -> Void)? = nil,
        onDownloadFinished: @escaping (String) -> Void = { _ in },
        onDownloadFailed: @escaping (String) -> Void = { _ in }
    ) -> BoardRuntime.Events {
        .init(
            onChange: onChange,
            onFullscreenChange: onFullscreenChange,
            onDownloadFinished: onDownloadFinished,
            onDownloadFailed: onDownloadFailed
        )
    }

    private func dispatchSheetKey(_ key: String, shift: Bool = false, in webView: WKWebView) async throws {
        let keyData = try JSONEncoder().encode(key)
        guard let keyLiteral = String(data: keyData, encoding: .utf8) else { return }
        _ = try await webView.evaluateJavaScript(
            "document.dispatchEvent(new KeyboardEvent('keydown', "
                + "{key: \(keyLiteral), shiftKey: \(shift), bubbles: true, cancelable: true}))")
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: UUID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: URL(string: url))
    }
}
