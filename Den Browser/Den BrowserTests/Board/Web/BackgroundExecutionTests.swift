import AppKit
import DenDomain
import DenModels
import DenViews
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
struct BackgroundExecutionTests {
    @Test func restoresOnlyEnabledBoardsAndTogglePreservesDeskFocus() throws {
        // Arrange
        let normal = BoardState(label: "Normal", width: 520, currentSheetURL: nil)
        let enabled = BoardState(
            label: "Background",
            width: 520,
            currentSheetURL: nil,
            backgroundExecutionEnabled: true
        )
        let shown = DeskState(label: "Shown", boards: [normal], focusedBoardID: normal.id)
        let hidden = DeskState(label: "Hidden", boards: [enabled], focusedBoardID: enabled.id)
        var saved: DenState?
        let resources = DenProfileResources(
            state: DenState(desks: [shown, hidden], focusedDeskID: shown.id),
            onSave: {
                saved = $0
                return true
            }
        )
        try withTestSession(resources: resources) { session in
            defer { session.runtimes.releaseRuntimes() }
            // Assert restored execution
            #expect(resources.webRuntimes[normal.id] == nil)
            let runtime = try #require(resources.webRuntimes[enabled.id])
            #expect((runtime.webView as? RuntimeWKWebView)?.backgroundExecutionEnabled == true)
            // Act
            session.boardNavigation.toggleBoardBackgroundExecution(enabled.id)
            // Assert
            #expect(saved?.board(for: enabled.id)?.backgroundExecutionEnabled == false)
            #expect((runtime.webView as? RuntimeWKWebView)?.backgroundExecutionEnabled == false)
            #expect(session.navigation.presentedDeskID == shown.id)
        }
    }

    @Test func defaultsOffAndPersistsOnlyWhenEnabled() throws {
        // Arrange
        var board = BoardState(label: "Board", width: 520, currentSheetURL: nil)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let legacyData = try encoder.encode(board)
        // Assert default and compatibility
        let json = try #require(String(data: legacyData, encoding: .utf8))
        #expect(!json.contains("backgroundExecutionEnabled"))
        #expect(try !decoder.decode(BoardState.self, from: legacyData).backgroundExecutionEnabled)
        board.backgroundExecutionEnabled = true
        // Assert enabled round trip
        #expect(try decoder.decode(BoardState.self, from: encoder.encode(board)).backgroundExecutionEnabled)
    }

    @Test(.timeLimit(.minutes(1)))
    func hiddenPageReceivesClickButOnlyRendersWithBackgroundExecution() async throws {
        // Arrange
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = RuntimeWKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        let originalPolicy = webView.configuration.preferences.inactiveSchedulingPolicy
        let originalOcclusion = webView._windowOcclusionDetectionEnabled
        defer {
            webView.setBackgroundExecutionEnabled(false)
            webView.stopLoading()
        }
        webView.setBackgroundExecutionEnabled(true)
        webView.loadHTMLString(
            """
            <button id="click">Click</button>
            <script>
            window.clicks = 0; window.rendered = 0;
            document.querySelector('button').onclick = () => {
                clicks++;
                requestAnimationFrame(() => rendered++);
            };
            </script>
            """,
            baseURL: nil
        )
        try await wait(webView, for: "document.readyState === 'complete' && typeof window.clicks === 'number'")
        webView.setBackgroundExecutionEnabled(false)
        try await wait(webView, for: "document.visibilityState === 'hidden'")
        webView.isHidden = true
        // Act and assert: events arrive while animation callbacks wait.
        _ = try await webView.evaluateJavaScript("document.querySelector('button').click()")
        #expect(try await webView.evaluateJavaScript("window.clicks") as? Int == 1)
        #expect(try await webView.evaluateJavaScript("window.rendered") as? Int == 0)

        webView.setBackgroundExecutionEnabled(true)
        // Assert enabling resumes the queued callback without showing the page.
        try await wait(webView, for: "window.rendered === 1")
        #expect(webView.isHidden)
        #expect(webView.hitTest(.zero) == nil)
        #expect(try await webView.evaluateJavaScript("document.visibilityState") as? String == "visible")
        let host = try #require(webView.window)
        #expect(!host.canBecomeKey)
        #expect(!host.canBecomeMain)

        // Simulate a SurfaceHost taking the page, then being detached on a Desk switch.
        let surface = NSView(frame: webView.frame)
        surface.addSubview(webView)
        await Task.yield()
        try await wait(webView, for: "document.visibilityState === 'visible'")
        _ = try await webView.evaluateJavaScript("document.querySelector('button').click()")
        try await wait(webView, for: "window.rendered === 2")
        #expect(webView.window === host)

        webView.setBackgroundExecutionEnabled(false)
        try await wait(webView, for: "document.visibilityState === 'hidden'")
        #expect(webView.window == nil)
        #expect(webView.configuration.preferences.inactiveSchedulingPolicy == originalPolicy)
        #expect(webView._windowOcclusionDetectionEnabled == originalOcclusion)
        _ = try await webView.evaluateJavaScript("document.querySelector('button').click()")
        try await Task.sleep(for: .milliseconds(150))
        #expect(try await webView.evaluateJavaScript("window.clicks") as? Int == 3)
        #expect(try await webView.evaluateJavaScript("window.rendered") as? Int == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func temporaryBackgroundExecutionKeepsHiddenPageActiveWithoutChangingPersistedSetting() async throws {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = RuntimeWKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        defer {
            webView.setBackgroundExecutionEnabled(false)
            webView.setTemporaryBackgroundExecutionEnabled(false)
            webView.stopLoading()
        }
        webView.loadHTMLString("<script>window.ready = true;</script>", baseURL: nil)
        try await wait(webView, for: "window.ready === true")
        webView.isHidden = true
        try await wait(webView, for: "document.visibilityState === 'hidden'")

        webView.setTemporaryBackgroundExecutionEnabled(true)
        #expect(!webView.backgroundExecutionEnabled)
        #expect(webView.temporaryBackgroundExecutionEnabled)
        #expect(webView.isEffectiveBackgroundExecutionEnabled)
        try await wait(webView, for: "document.visibilityState === 'visible'")
        #expect(webView.window != nil)

        // Persisted setting stays independent when toggled alongside temporary execution.
        webView.setBackgroundExecutionEnabled(true)
        webView.setTemporaryBackgroundExecutionEnabled(false)
        #expect(webView.backgroundExecutionEnabled)
        #expect(!webView.temporaryBackgroundExecutionEnabled)
        #expect(webView.isEffectiveBackgroundExecutionEnabled)
        #expect(webView.window != nil)

        webView.setBackgroundExecutionEnabled(false)
        #expect(!webView.isEffectiveBackgroundExecutionEnabled)
        try await wait(webView, for: "document.visibilityState === 'hidden'")
        #expect(webView.window == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func pictureInPictureEventsToggleTemporaryBackgroundExecution() async throws {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = RuntimeWKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        let bridge = PictureInPictureStateBridge(webView: webView) { active in
            webView.setTemporaryBackgroundExecutionEnabled(active)
        }
        defer {
            bridge.dispose()
            webView.setTemporaryBackgroundExecutionEnabled(false)
            webView.stopLoading()
        }
        webView.loadHTMLString("<video id='v'></video>", baseURL: nil)
        try await wait(webView, for: "document.readyState === 'complete' && document.getElementById('v') !== null")

        _ = try await webView.evaluateJavaScript(
            "document.getElementById('v').dispatchEvent(new Event('enterpictureinpicture'))"
        )
        try await waitUntil("enterpictureinpicture") { webView.temporaryBackgroundExecutionEnabled }
        #expect(!webView.backgroundExecutionEnabled)

        _ = try await webView.evaluateJavaScript(
            "document.getElementById('v').dispatchEvent(new Event('leavepictureinpicture'))"
        )
        try await waitUntil("leavepictureinpicture") { !webView.temporaryBackgroundExecutionEnabled }

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
                const v = document.getElementById('v');
                Object.defineProperty(v, 'webkitPresentationMode', { value: 'picture-in-picture', configurable: true });
                v.dispatchEvent(new Event('webkitpresentationmodechanged'));
            })()
            """,
            in: nil,
            in: .defaultClient
        )
        try await waitUntil("webkitpresentationmodechanged enter") { webView.temporaryBackgroundExecutionEnabled }

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
                const v = document.getElementById('v');
                Object.defineProperty(v, 'webkitPresentationMode', { value: 'inline', configurable: true });
                v.dispatchEvent(new Event('webkitpresentationmodechanged'));
            })()
            """,
            in: nil,
            in: .defaultClient
        )
        try await waitUntil("webkitpresentationmodechanged exit") { !webView.temporaryBackgroundExecutionEnabled }
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceHostReclaimsWebViewAfterBackgroundHosting() async throws {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = RuntimeWKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        defer {
            webView.setTemporaryBackgroundExecutionEnabled(false)
            webView.stopLoading()
        }
        webView.setTemporaryBackgroundExecutionEnabled(true)

        let surfaceHost = SurfaceHost<BoardFocusRequest, NSView>(content: webView)
        // Let RuntimeWKWebView's detached hosting task reclaim webView while SurfaceHost is off-window.
        try await waitUntil("background window reclaims off-window webView") {
            webView.superview !== surfaceHost && webView.window != nil
        }

        let hostWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        hostWindow.contentView?.addSubview(surfaceHost)
        #expect(webView.superview === surfaceHost)
        #expect(webView.window === hostWindow)
    }

    private func waitUntil(_ label: String, _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting for \(label)")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func wait(_ webView: WKWebView, for condition: String) async throws {
        try await SheetInteraction.waitForFunction(expression: condition, in: webView, timeout: 15)
    }
}
