import AppKit
import Testing
import WebKit

@testable import Den_Browser

@MainActor
private final class InspectionBoardProbe: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private var navigation: WKNavigation?
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private(set) var pageEvents: [[String: String]] = []

    func load(_ html: String, in webView: WKWebView) async {
        await withCheckedContinuation { continuation in
            loadContinuation = continuation
            webView.navigationDelegate = self
            navigation = webView.loadHTMLString(html, baseURL: URL(string: "https://inspection.test/"))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === self.navigation else { return }
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(navigation)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(navigation)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let event = message.body as? [String: String] else { return }
        pageEvents.append(event)
    }

    private func finish(_ navigation: WKNavigation?) {
        guard navigation === self.navigation else { return }
        loadContinuation?.resume()
        loadContinuation = nil
    }
}

@MainActor
@Suite(.serialized)
struct InspectionBoardCapabilityTests {
    private func fixture() -> (WKWebView, NSWindow, InspectionBoardProbe) {
        let probe = InspectionBoardProbe()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(probe, name: "inspectionProbe")
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: """
                    (() => {
                      const post = (kind, data) => window.webkit.messageHandlers.inspectionProbe.postMessage({ kind, data: String(data) });
                      for (const kind of ['log', 'warn', 'error']) {
                        const original = console[kind].bind(console);
                        console[kind] = (...args) => {
                          post(`console.${kind}`, args.map(String).join(' '));
                          original(...args);
                        };
                      }
                      window.addEventListener('error', event => post('error', event.message));
                      window.addEventListener('unhandledrejection', event => post('unhandledrejection', event.reason));
                    })();
                    """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        let window = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 640, height: 480),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(webView)
        webView.frame = window.contentView?.bounds ?? .zero
        window.makeKeyAndOrderFront(nil)
        return (webView, window, probe)
    }

    @Test func mountedWebViewAccessibilityHierarchyDoesNotExposeFixtureTarget() async {
        // Arrange
        let (webView, window, probe) = fixture()
        defer { window.close() }
        await probe.load(
            """
            <!doctype html><html><body>
              <h1>Native AX heading</h1>
              <button aria-label="PoC AX target">Visible Action</button>
              <input aria-label="PoC AX field">
            </body></html>
            """,
            in: webView
        )

        // Act
        var rows: [String] = []
        func walk(_ value: Any, depth: Int) {
            guard depth < 8, rows.count < 200, let element = value as? NSAccessibilityProtocol else { return }
            let role = element.accessibilityRole()?.rawValue ?? "unknown-role"
            let label = element.accessibilityLabel() ?? ""
            let value = String(describing: element.accessibilityValue() ?? "")
            if !label.isEmpty || !value.isEmpty {
                rows.append("\(role) label=\(label.debugDescription) value=\(value.debugDescription)")
            }
            for child in element.accessibilityChildren() ?? [] {
                walk(child, depth: depth + 1)
            }
        }
        walk(webView, depth: 0)

        // Assert
        print("INSPECTION_BOARD_AX rows=\(rows)")
        #expect(webView.window === window)
        #expect(!rows.contains { $0.contains("PoC AX target") }, "AX rows: \(rows)")
    }

    @Test func documentStartBridgeCapturesPageConsoleAndScriptErrors() async throws {
        // Arrange
        let (webView, window, probe) = fixture()
        defer { window.close() }
        await probe.load(
            """
            <!doctype html><html><body><p>Console probe</p>
            <script>
              console.log('fixture-log', 7);
              console.warn('fixture-warn');
              console.error('fixture-console-error');
              setTimeout(() => { throw new Error('fixture-uncaught-error'); }, 0);
              Promise.reject(new Error('fixture-unhandled-rejection'));
            </script></body></html>
            """,
            in: webView
        )

        // Act
        for _ in 0..<100 where probe.pageEvents.count < 5 {
            try await Task.sleep(for: .milliseconds(10))
        }
        let events = probe.pageEvents
        let kinds = Set(events.compactMap { $0["kind"] })

        // Assert
        print("INSPECTION_BOARD_PAGE_EVENTS=\(events)")
        #expect(kinds.contains("console.log"))
        #expect(events.contains { $0["kind"] == "console.log" && $0["data"] == "fixture-log 7" })
        #expect(kinds.contains("console.warn"))
        #expect(kinds.contains("console.error"))
        #expect(events.contains { $0["kind"] == "error" && $0["data"]?.contains("fixture-uncaught-error") == true })
        #expect(
            events.contains {
                $0["kind"] == "unhandledrejection" && $0["data"]?.contains("fixture-unhandled-rejection") == true
            })
    }

    @Test func inspectionHooksCanStopAndRestartOnTheSameDocument() async throws {
        // Arrange
        let (webView, window, probe) = fixture()
        defer { window.close() }
        await probe.load("<!doctype html><html><body>Restart probe</body></html>", in: webView)

        // Act
        _ = try await webView.evaluateJavaScript(InspectionPageScript.startPicking)
        _ = try await webView.evaluateJavaScript("console.log('first-session')")
        _ = try await webView.evaluateJavaScript(InspectionPageScript.stop)
        _ = try await webView.evaluateJavaScript("console.log('stopped-session')")
        _ = try await webView.evaluateJavaScript(InspectionPageScript.startPicking)
        _ = try await webView.evaluateJavaScript("console.warn('restarted-session')")
        let json = try #require(try await webView.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String)

        // Assert
        #expect(json.contains("restarted-session"))
        #expect(!json.contains("first-session"))
        #expect(!json.contains("stopped-session"))
    }

    @Test func pickingElementReportsItsAccessibleLabelAndRelatedLabelElement() async throws {
        // Arrange
        let (webView, window, probe) = fixture()
        defer { window.close() }
        await probe.load(
            """
            <!doctype html><html><body>
              <label for="target">Account name</label>
              <input id="target" aria-label="Account field">
            </body></html>
            """,
            in: webView
        )

        // Act
        _ = try await webView.evaluateJavaScript(InspectionPageScript.startPicking)
        _ = try await webView.evaluateJavaScript(
            "document.querySelector('#target').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))"
        )
        let json = try #require(try await webView.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String)
        let snapshot = try JSONDecoder().decode(InspectionPageSnapshot.self, from: Data(json.utf8))

        // Assert
        let selection = try #require(snapshot.selection)
        #expect(selection.tag == "input")
        #expect(selection.id == "target")
        #expect(selection.ariaLabel == "Account field")
        #expect(selection.labels.contains("Account name"))
        #expect(!snapshot.isPicking)
    }

    @Test func hoverHighlightIsRemovedOnSelectionStopAndNavigation() async throws {
        // Arrange
        let (webView, window, probe) = fixture()
        defer { window.close() }
        await probe.load(
            """
            <!doctype html><html><body>
              <button id="hover-target">Hover target</button>
              <button id="selection-target">Selection target</button>
            </body></html>
            """,
            in: webView
        )
        func highlightIsVisible() async throws -> Bool {
            try await webView.evaluateJavaScript(
                "(() => { const item = document.querySelector('[data-den-inspection-highlight]'); return !!item && item.style.display === 'block' && item.style.position === 'fixed' && item.style.pointerEvents === 'none'; })()"
            ) as? Bool ?? false
        }
        func movePointerToHoverTarget() async throws {
            _ = try await webView.evaluateJavaScript(
                "document.querySelector('#hover-target').dispatchEvent(new MouseEvent('pointermove', { bubbles: true, clientX: 4, clientY: 4 }))"
            )
        }
        func leavePage() async throws {
            _ = try await webView.evaluateJavaScript(
                "document.querySelector('#hover-target').dispatchEvent(new MouseEvent('pointerout', { bubbles: true, relatedTarget: null }))"
            )
        }

        // Act: hover, then select a different element
        _ = try await webView.evaluateJavaScript(InspectionPageScript.startPicking)
        try await movePointerToHoverTarget()
        let visibleOnHover = try await highlightIsVisible()
        try await leavePage()
        let removedOnPointerLeave = try await highlightIsVisible()
        try await movePointerToHoverTarget()
        _ = try await webView.evaluateJavaScript(
            "document.querySelector('#selection-target').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))"
        )
        let removedOnSelection = try await highlightIsVisible()

        // Act: restart, hover, then stop
        _ = try await webView.evaluateJavaScript(InspectionPageScript.startPicking)
        try await movePointerToHoverTarget()
        _ = try await webView.evaluateJavaScript(InspectionPageScript.stop)
        let removedOnStop = try await highlightIsVisible()

        // Act: a fresh document does not retain the previous overlay
        _ = try await webView.evaluateJavaScript(InspectionPageScript.startPicking)
        try await movePointerToHoverTarget()
        await probe.load("<!doctype html><html><body>New document</body></html>", in: webView)
        let remainsAfterNavigation = try await highlightIsVisible()

        // Assert
        #expect(visibleOnHover)
        #expect(!removedOnPointerLeave)
        #expect(!removedOnSelection)
        #expect(!removedOnStop)
        #expect(!remainsAfterNavigation)
    }
}
