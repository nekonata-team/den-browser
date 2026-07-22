import AppKit
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
    @Test func sheetURLPolicyAcceptsOnlyHTTPWithHost() {
        let supported = [
            URL(string: "http://example.com/")!,
            URL(string: "HTTPS://EXAMPLE.COM/path")!,
        ]
        let unsupported = [
            URL(string: "https://")!,
            URL(string: "file:///tmp/example")!,
            URL(string: "data:text/plain,example")!,
            URL(string: "about:blank")!,
            URL(string: "mailto:user@example.com")!,
        ]

        #expect(supported.allSatisfy(SheetURLPolicy.isSupported))
        #expect(unsupported.allSatisfy { !SheetURLPolicy.isSupported($0) })
    }

    @Test func sheetNavigationPreferencesPersist() {
        let suiteName = "SheetNavigationManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "features.vimium-c.enabled")

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

        let restored = SheetNavigationManager(defaults: defaults, scriptSource: "")
        #expect(restored.isEnabled)
        #expect(restored.hintAlphabet == "a1")
        #expect(restored.ignoredHosts == ["example.com", "www.apple.com"])
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
            onOpenBoard: { _ in },
            onChange: { _, _, _ in })

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
            onOpenBoard: { _ in },
            onChange: { _, url, title in
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

    private func sheetNavigationScriptSource() throws -> String {
        let url = try #require(Bundle.main.url(forResource: "SheetNavigation", withExtension: "js"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeSheetNavigationWebView(manager: SheetNavigationManager) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = manager.userContentController
        return WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
    }

    private func dispatchSheetKey(_ key: String, shift: Bool = false, in webView: WKWebView) async throws {
        let keyData = try JSONEncoder().encode(key)
        let keyLiteral = String(decoding: keyData, as: UTF8.self)
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
