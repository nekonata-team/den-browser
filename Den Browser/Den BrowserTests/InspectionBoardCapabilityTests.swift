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
    private func initializeInspection(_ webView: WKWebView) async throws {
        _ = try await webView.evaluateJavaScript(InspectionPageScript.initialize)
    }

    private func startPicking(_ webView: WKWebView) async throws {
        try await initializeInspection(webView)
        _ = try await webView.evaluateJavaScript(InspectionPageScript.startPicking)
    }

    private func startCollection(_ webView: WKWebView) async throws {
        try await initializeInspection(webView)
        _ = try await webView.evaluateJavaScript(InspectionPageScript.collect)
    }

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
        try await startCollection(webView)
        _ = try await webView.evaluateJavaScript("console.log('first-session')")
        _ = try await webView.evaluateJavaScript(InspectionPageScript.stop)
        _ = try await webView.evaluateJavaScript("console.log('stopped-session')")
        try await startCollection(webView)
        _ = try await webView.evaluateJavaScript("console.warn('restarted-session')")
        let json = try #require(try await webView.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String)

        // Assert
        #expect(json.contains("restarted-session"))
        #expect(!json.contains("first-session"))
        #expect(!json.contains("stopped-session"))
    }

    @Test func collectionStartsWithoutPickingAndCoversPageConsoleAndErrors() async throws {
        // Arrange
        let (webView, window, probe) = fixture()
        defer { window.close() }
        await probe.load("<!doctype html><html><body><button>Target</button></body></html>", in: webView)

        // Act
        _ = try await webView.evaluateJavaScript(
            "(() => { const levels = ['debug', 'info', 'log', 'warn', 'error']; window.__inspectionOriginalCalls = Object.fromEntries(levels.map(level => [level, 0])); for (const level of levels) { const original = console[level]; console[level] = function (...values) { window.__inspectionOriginalCalls[level] += 1; return original.apply(this, values); }; } })()"
        )
        try await startCollection(webView)
        _ = try await webView.evaluateJavaScript(
            "(() => { console.debug('debug-event'); console.info('info-event'); console.log('log-event'); console.warn('warn-event'); console.error('error-event'); setTimeout(() => { throw new Error('window-error-event'); }, 0); Promise.reject('rejection-event'); })()"
        )
        for _ in 0..<100 {
            let json = try #require(try await webView.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String)
            if json.contains("window-error-event") && json.contains("rejection-event") { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let json = try #require(try await webView.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String)
        let originalCallsJSON = try #require(
            try await webView.evaluateJavaScript("JSON.stringify(window.__inspectionOriginalCalls)") as? String
        )
        let originalCalls = try JSONDecoder().decode([String: Int].self, from: Data(originalCallsJSON.utf8))
        let snapshot = try JSONDecoder().decode(InspectionPageSnapshot.self, from: Data(json.utf8))

        // Assert
        #expect(snapshot.isCollecting)
        #expect(!snapshot.isPicking)
        #expect(originalCalls == ["debug": 1, "info": 1, "log": 1, "warn": 1, "error": 1])
        #expect(
            Set(snapshot.events.map(\.level)).isSuperset(of: ["debug", "info", "log", "warn", "error", "rejection"])
        )
        #expect(snapshot.events.contains { $0.message.contains("window-error-event") })
        #expect(snapshot.events.contains { $0.message.contains("rejection-event") })
    }

    @Test func pickingDoesNotChangeCollectionOrClearCapturedEvents() async throws {
        // Arrange
        let (webView, window, probe) = fixture()
        defer { window.close() }
        await probe.load("<!doctype html><html><body><button id='target'>Target</button></body></html>", in: webView)
        try await startCollection(webView)
        _ = try await webView.evaluateJavaScript("console.log('before-pick')")

        // Act
        try await startPicking(webView)
        let pickingJSON = try #require(
            try await webView.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String)
        _ = try await webView.evaluateJavaScript(
            "document.querySelector('#target').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))"
        )
        let selectedJSON = try #require(
            try await webView.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String)
        let pickingSnapshot = try JSONDecoder().decode(InspectionPageSnapshot.self, from: Data(pickingJSON.utf8))
        let selectedSnapshot = try JSONDecoder().decode(InspectionPageSnapshot.self, from: Data(selectedJSON.utf8))

        // Assert
        #expect(pickingSnapshot.isPicking)
        #expect(pickingSnapshot.isCollecting)
        #expect(selectedSnapshot.isCollecting)
        #expect(selectedSnapshot.events.contains { $0.message.contains("before-pick") })
    }

    @Test func repeatedPickingRestoresTheCursorThatPrecededTheFirstPick() async throws {
        // Arrange
        let (webView, window, probe) = fixture()
        defer { window.close() }
        await probe.load("<!doctype html><html><body><button id='target'>Target</button></body></html>", in: webView)
        _ = try await webView.evaluateJavaScript("document.documentElement.style.cursor = 'wait'")
        try await startPicking(webView)

        // Act
        try await startPicking(webView)
        _ = try await webView.evaluateJavaScript(
            "document.querySelector('#target').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))"
        )
        let cursor = try await webView.evaluateJavaScript("document.documentElement.style.cursor") as? String

        // Assert
        #expect(cursor == "wait")
    }

    @Test func retainedConsoleEventsHaveUniqueIDsAfterBufferOverflow() async throws {
        // Arrange
        let (webView, window, probe) = fixture()
        defer { window.close() }
        await probe.load("<!doctype html><html><body>Console events</body></html>", in: webView)
        try await startCollection(webView)

        // Act
        _ = try await webView.evaluateJavaScript(
            "(() => { const originalNow = Date.now; Date.now = () => 123; for (let i = 0; i < 82; i++) console.log(`event-${i}`); Date.now = originalNow; })()"
        )
        let json = try #require(try await webView.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String)
        let snapshot = try JSONDecoder().decode(InspectionPageSnapshot.self, from: Data(json.utf8))

        // Assert
        #expect(snapshot.events.count == 80)
        #expect(Set(snapshot.events.map(\.id)).count == snapshot.events.count)
        #expect(snapshot.eventsDropped == 2)
        #expect(snapshot.events.allSatisfy { $0.timestamp?.contains("T") == true })
    }

    @Test func repeatedCollectionStartAndNavigationDoNotDuplicateOrRetainOldEvents() async throws {
        // Arrange
        let (webView, window, probe) = fixture()
        defer { window.close() }
        await probe.load("<!doctype html><html><body>First document</body></html>", in: webView)
        try await startCollection(webView)

        // Act
        _ = try await webView.evaluateJavaScript("console.log('first-document-event')")
        _ = try await webView.evaluateJavaScript(InspectionPageScript.collect)
        _ = try await webView.evaluateJavaScript("console.log('once-after-restart')")
        let repeatedStartJSON = try #require(
            try await webView.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String)
        _ = try await webView.evaluateJavaScript("window.dispatchEvent(new Event('pagehide'))")
        try await startCollection(webView)
        _ = try await webView.evaluateJavaScript("console.log('after-pagehide')")
        let pagehideJSON = try #require(
            try await webView.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String)
        await probe.load("<!doctype html><html><body>Second document</body></html>", in: webView)
        try await startCollection(webView)
        _ = try await webView.evaluateJavaScript("console.log('second-document-event')")
        let navigationJSON = try #require(
            try await webView.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String)
        let repeatedStart = try JSONDecoder().decode(InspectionPageSnapshot.self, from: Data(repeatedStartJSON.utf8))
        let afterPagehide = try JSONDecoder().decode(InspectionPageSnapshot.self, from: Data(pagehideJSON.utf8))
        let afterNavigation = try JSONDecoder().decode(InspectionPageSnapshot.self, from: Data(navigationJSON.utf8))

        // Assert
        #expect(repeatedStart.events.filter { $0.message.contains("once-after-restart") }.count == 1)
        #expect(!afterPagehide.events.contains { $0.message.contains("first-document-event") })
        #expect(afterPagehide.events.contains { $0.message.contains("after-pagehide") })
        #expect(afterNavigation.events.contains { $0.message.contains("second-document-event") })
        #expect(!afterNavigation.events.contains { $0.message.contains("first-document-event") })
        #expect(afterNavigation.events.filter { $0.message.contains("second-document-event") }.count == 1)
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
        try await startCollection(webView)
        try await startPicking(webView)
        _ = try await webView.evaluateJavaScript(
            "document.querySelector('#target').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))"
        )
        let json = try #require(try await webView.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String)
        let snapshot = try JSONDecoder().decode(InspectionPageSnapshot.self, from: Data(json.utf8))

        // Assert
        let selection = try #require(snapshot.selection)
        #expect(selection.tag == "input")
        #expect(selection.id == "target")
        #expect(selection.nodeID?.isEmpty == false)
        #expect(selection.selector?.isEmpty == false)
        #expect(selection.capturedAt?.isEmpty == false)
        #expect(selection.ariaLabel == "Account field")
        #expect(selection.labels.contains("Account name"))
        #expect(snapshot.documentID?.isEmpty == false)
        #expect(snapshot.collectionStartedAt?.isEmpty == false)
        #expect(snapshot.selectionConnected == true)
        #expect(!snapshot.isPicking)
    }

    @Test func domTreeReturnsSelectedAncestorPathAndLoadsChildrenOnDemand() async throws {
        // Arrange
        let (webView, window, probe) = fixture()
        defer { window.close() }
        await probe.load(
            """
            <!doctype html><html><body>
              <main id="main"><section aria-label="Group">
                <button id="target" data-kind="action">Choose</button>
                <span id="sibling">Other</span>
              </section></main>
            </body></html>
            """,
            in: webView
        )

        // Act
        try await startPicking(webView)
        _ = try await webView.evaluateJavaScript(
            "document.querySelector('#target').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))"
        )
        let json = try #require(try await webView.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String)
        let snapshot = try JSONDecoder().decode(InspectionPageSnapshot.self, from: Data(json.utf8))
        let section = try #require(snapshot.treePath.first(where: { $0.tag == "section" }))
        let button = try #require(snapshot.treePath.last)
        let childrenJSON = try #require(
            try await webView.evaluateJavaScript(InspectionPageScript.readChildren(section.id)) as? String)
        let children = try JSONDecoder().decode([InspectionDOMNode].self, from: Data(childrenJSON.utf8))
        _ = try await webView.evaluateJavaScript(InspectionPageScript.selectNode(children[1].id))
        let selectedJSON = try #require(
            try await webView.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String)
        let selectedSnapshot = try JSONDecoder().decode(InspectionPageSnapshot.self, from: Data(selectedJSON.utf8))
        _ = try await webView.evaluateJavaScript(InspectionPageScript.highlightNode(button.id))
        let highlightExists =
            try await webView.evaluateJavaScript(
                "!!document.querySelector('[data-den-inspection-highlight]')") as? Bool

        // Assert
        #expect(snapshot.treePath.map(\.tag) == ["html", "body", "main", "section", "button"])
        #expect(button.attributes.contains { $0.name == "data-kind" && $0.value == "action" })
        #expect(section.childCount == 2)
        #expect(children.map(\.tag) == ["button", "span"])
        #expect(selectedSnapshot.selection?.id == "sibling")
        #expect(highlightExists == true)
    }

    @Test func batchedChildrenReadReflectsDOMChangesInTheSameDocument() async throws {
        // Arrange
        let (webView, window, probe) = fixture()
        defer { window.close() }
        await probe.load(
            "<!doctype html><html><body><section id='parent'><button>Before</button></section></body></html>",
            in: webView
        )
        try await startPicking(webView)
        _ = try await webView.evaluateJavaScript(
            "document.querySelector('#parent button').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))"
        )
        let snapshotJSON = try #require(
            try await webView.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String)
        let snapshot = try JSONDecoder().decode(InspectionPageSnapshot.self, from: Data(snapshotJSON.utf8))
        let parent = try #require(snapshot.treePath.first(where: { $0.tag == "section" }))

        // Act
        func readChildren() async throws -> [InspectionDOMNode] {
            let json = try #require(
                try await webView.evaluateJavaScript(InspectionPageScript.readChildren([parent.id])) as? String)
            let children = try JSONDecoder().decode([String: [InspectionDOMNode]].self, from: Data(json.utf8))
            return try #require(children[parent.id])
        }
        let beforeMutation = try await readChildren()
        _ = try await webView.evaluateJavaScript(
            "document.querySelector('#parent').insertAdjacentHTML('beforeend', '<span>After</span>')"
        )
        let afterMutation = try await readChildren()

        // Assert
        #expect(beforeMutation.map(\.tag) == ["button"])
        #expect(afterMutation.map(\.tag) == ["button", "span"])
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
        try await startPicking(webView)
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
        try await startPicking(webView)
        try await movePointerToHoverTarget()
        _ = try await webView.evaluateJavaScript(InspectionPageScript.stop)
        let removedOnStop = try await highlightIsVisible()

        // Act: a fresh document does not retain the previous overlay
        try await startPicking(webView)
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

    @Test func pickAndDOMHoverHighlightUseAndUpdateProfileColor() async throws {
        // Arrange
        let (webView, window, probe) = fixture()
        defer { window.close() }
        await probe.load(
            """
            <!doctype html><html><body><button id="target">Target</button></body></html>
            """,
            in: webView
        )
        let initialColor = ProfileRGB(red: 18, green: 52, blue: 86)
        let changedColor = ProfileRGB(red: 87, green: 101, blue: 121)
        func highlightColors() async throws -> [String] {
            try #require(
                try await webView.evaluateJavaScript(
                    "(() => { const item = document.querySelector('[data-den-inspection-highlight]'); return [item.style.borderTopColor, item.style.backgroundColor]; })()"
                ) as? [String]
            )
        }

        // Act
        try await initializeInspection(webView)
        _ = try await webView.evaluateJavaScript(InspectionPageScript.setHighlightColor(initialColor))
        try await startPicking(webView)
        _ = try await webView.evaluateJavaScript(
            "document.querySelector('#target').dispatchEvent(new MouseEvent('pointermove', { bubbles: true, clientX: 4, clientY: 4 }))"
        )
        let pickColors = try await highlightColors()
        _ = try await webView.evaluateJavaScript(InspectionPageScript.setHighlightColor(changedColor))
        let updatedPickColors = try await highlightColors()
        _ = try await webView.evaluateJavaScript(
            "document.querySelector('#target').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))"
        )
        let json = try #require(try await webView.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String)
        let snapshot = try JSONDecoder().decode(InspectionPageSnapshot.self, from: Data(json.utf8))
        let targetID = try #require(snapshot.treePath.last?.id)
        _ = try await webView.evaluateJavaScript(InspectionPageScript.highlightNode(targetID))
        let domHoverColors = try await highlightColors()

        // Assert
        #expect(pickColors == ["rgb(18, 52, 86)", "rgba(18, 52, 86, 0.12)"])
        #expect(updatedPickColors == ["rgb(87, 101, 121)", "rgba(87, 101, 121, 0.12)"])
        #expect(domHoverColors == updatedPickColors)
    }
}
