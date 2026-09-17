import AppKit
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
private final class SheetInteractionWebViewLoadWaiter: NSObject, WKNavigationDelegate {
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

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
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
@Suite(.serialized)
struct SheetInteractionTests {
    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        SheetDOMRuntime.install(on: configuration.userContentController)
        return WKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
    }

    @Test func semanticNamesUseCaptionsRatherThanFormValues() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <button value="save" onclick="this.dataset.clicked = 'yes'">Save changes</button>
            <input type="submit" value="Send">
            <input type="password" value="secret">
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        // Act
        let elements = try await SheetInteraction.query(
            selector: "button, input", visibleOnly: true, all: true, fields: ["name"], in: webView)
        try await SheetInteraction.click(role: "button", name: "Save changes", exact: true, in: webView)
        let clicked = try await SheetInteraction.attribute(target: "button", name: "data-clicked", in: webView)

        // Assert
        #expect(elements.map(\.name) == ["Save changes", "Send", ""])
        #expect(clicked == "yes")
    }

    @Test(arguments: [
        ("<button disabled aria-disabled='false'>Save</button>", false),
        ("<fieldset disabled><button>Save</button></fieldset>", false),
        ("<fieldset disabled><legend><button>Save</button></legend></fieldset>", true),
    ])
    func enabledStateRespectsNativeDisabling(html: String, enabled: Bool) async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(html, baseURL: URL(string: "https://example.com/")!, in: webView)

        // Act
        let actual = try await SheetInteraction.isEnabled(target: "button", in: webView)

        // Assert
        #expect(actual == enabled)
    }

    @Test(arguments: ["*/section*/section", "https://example.com/section*section"])
    func urlGlobCannotReuseAnAlreadyMatchedSegment(pattern: String) async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            "<!doctype html>", baseURL: URL(string: "https://example.com/section")!, in: webView)

        // Act / Assert
        await #expect(throws: SheetInteractionError.self) {
            try await SheetInteraction.waitForURL(pattern: pattern, in: webView, timeout: 0)
        }
    }

    @Test(arguments: ["*section*section", "*/section*/section"])
    func urlGlobMatchesDistinctSegments(pattern: String) async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            "<!doctype html>", baseURL: URL(string: "https://example.com/section/section")!, in: webView)

        // Act / Assert
        try await SheetInteraction.waitForURL(pattern: pattern, in: webView, timeout: 0)
    }

    @Test func queryAndScopedSnapshotReturnVisibleElementsAndRequestedAttributes() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <html>
            <body>
              <h1>Inbox</h1>
              <div id="dialog" role="dialog">
                <button id="github" role="option" aria-label="GitHub" class="choice" data-email="github@example.com">GitHub</button>
                <button id="hidden" style="display:none">Hidden</button>
              </div>
              <button id="outside">Outside</button>
            </body>
            </html>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        // Act
        let elements = try await SheetInteraction.query(
            selector: "button",
            visibleOnly: true,
            all: true,
            fields: ["text", "class", "attr:data-email"],
            in: webView
        )

        // Assert
        #expect(elements.count == 2)
        let github = try #require(elements.first(where: { $0.text == "GitHub" }))
        #expect(github.visible)
        #expect(github.attributes?["class"] == "choice")
        #expect(github.attributes?["data-email"] == "github@example.com")
        #expect(github.ref.hasPrefix("@e"))

        // Act
        let fullSnapshot = try await SheetInteraction.snapshot(
            in: webView,
            interactiveOnly: false
        )

        // Assert
        #expect(fullSnapshot.contains("Inbox"))
        #expect(fullSnapshot.contains("[heading:level=1]"))

        // Act
        let snapshot = try await SheetInteraction.snapshot(
            in: webView,
            interactiveOnly: true,
            within: "#dialog"
        )

        // Assert
        #expect(snapshot.contains("GitHub"))
        #expect(!snapshot.contains("Outside"))
        #expect(!snapshot.contains("Hidden"))
    }

    @Test func semanticClickDispatchesOnePointerAndMouseSequence() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <button id="github" role="option" aria-label="GitHub">GitHub</button>
            <script>
              window.eventLog = [];
              const button = document.getElementById('github');
              ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(type => {
                button.addEventListener(type, event => {
                  window.eventLog.push(type + ':' + event.isTrusted);
                });
              });
            </script>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        // Act
        _ = try await SheetInteraction.click(
            role: "option",
            name: "GitHub",
            exact: true,
            in: webView
        )
        let eventLog = try #require(
            await webView.evaluateJavaScript("window.eventLog.join(',')") as? String)

        // Assert
        #expect(
            eventLog
                == "pointerdown:false,mousedown:false,pointerup:false,mouseup:false,click:false"
        )
    }

    @Test func snapshotStatesAndPointReadsUseTheCurrentElementState() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <input id="check" type="checkbox" checked aria-label="Notifications">
            <button id="disabled" disabled>Save</button>
            <button id="hidden" style="display:none">Hidden</button>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        // Act
        let snapshot = try await SheetInteraction.snapshot(
            in: webView,
            interactiveOnly: true
        )
        let text = try await SheetInteraction.text(target: "#disabled", in: webView)
        let attribute = try await SheetInteraction.attribute(
            target: "#disabled",
            name: "id",
            in: webView
        )
        let count = try await SheetInteraction.count(selector: "button", in: webView)
        let visible = try await SheetInteraction.isVisible(target: "#hidden", in: webView)
        let enabled = try await SheetInteraction.isEnabled(target: "#disabled", in: webView)
        let checked = try await SheetInteraction.isChecked(target: "#check", in: webView)

        // Assert
        #expect(snapshot.contains("[checked]"))
        #expect(snapshot.contains("[disabled]"))
        #expect(!snapshot.contains("Hidden"))
        #expect(text == "Save")
        #expect(attribute == "disabled")
        #expect(count == 2)
        #expect(!visible)
        #expect(!enabled)
        #expect(checked)
    }

    @Test func valueAndFillSupportEmptyState() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <input id="text" value="draft">
            <input id="check" type="checkbox" checked>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        // Act
        let initialValue = try await SheetInteraction.value(target: "#text", in: webView)

        // Assert
        #expect(initialValue == "draft")

        // Act
        try await SheetInteraction.fill(target: "#text", value: "", in: webView)
        let clearedValue = try await SheetInteraction.value(target: "#text", in: webView)
        try await SheetInteraction.fill(target: "#text", value: "filled", in: webView)
        try await SheetInteraction.fill(target: "#text", value: "", in: webView)
        let finalValue = try await SheetInteraction.value(target: "#text", in: webView)
        let initialChecked = try await SheetInteraction.isChecked(target: "#check", in: webView)
        _ = try await SheetInteraction.click(target: "#check", in: webView)
        let finalChecked = try await SheetInteraction.isChecked(target: "#check", in: webView)

        // Assert
        #expect(clearedValue == "")
        #expect(finalValue == "")
        #expect(initialChecked)
        #expect(!finalChecked)
    }

    @Test func pressProvidesLegacyKeyCodes() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <input id="name"
                onkeydown="this.dataset.key = event.key; this.dataset.keyCode = event.keyCode; this.dataset.which = event.which;">
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        // Act
        try await SheetInteraction.fill(target: "#name", value: "", in: webView)
        try await SheetInteraction.press(key: "Enter", in: webView)
        let key = try await SheetInteraction.attribute(target: "#name", name: "data-key", in: webView)
        let keyCode = try await SheetInteraction.attribute(target: "#name", name: "data-key-code", in: webView)
        let which = try await SheetInteraction.attribute(target: "#name", name: "data-which", in: webView)

        // Assert
        #expect(key == "Enter")
        #expect(keyCode == "13")
        #expect(which == "13")
    }

    @Test func scrollAcceptsAnElementTarget() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <div style="height: 2000px"></div>
            <div id="target">Target</div>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        // Act
        let message = try await SheetInteraction.scroll(direction: "#target", in: webView)
        let scrollYString = try #require(
            await webView.evaluateJavaScript("String(window.scrollY)") as? String)
        let scrollY = try #require(Double(scrollYString))

        // Assert
        #expect(message == "Scrolled to #target")
        #expect(scrollY > 0)
    }

    @Test func waitSupportsVisibilityTransitionAndURLGlob() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <div class="item">One</div>
            <div class="item">Two</div>
            <script>
              history.replaceState({}, '', '#settings/filters');
              window.agentReady = false;
            </script>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        // Act
        try await SheetInteraction.waitForElement(
            target: ".item",
            state: .attached,
            in: webView,
            timeout: 1
        )
        try await SheetInteraction.waitForElement(
            target: ".item",
            state: .visible,
            in: webView,
            timeout: 1
        )
        try await SheetInteraction.waitForURL(
            pattern: "*#settings/filters",
            in: webView,
            timeout: 1
        )
        try await SheetInteraction.waitForText(text: "One", in: webView, timeout: 1)
        _ = try await webView.evaluateJavaScript(
            """
            window.agentReady = true;
            document.querySelectorAll('.item').forEach(element => {
                element.style.display = 'none';
            });
            """
        )
        try await SheetInteraction.waitForLoadState(.domcontentloaded, in: webView, timeout: 1)
        try await SheetInteraction.waitForLoadState(.load, in: webView, timeout: 1)
        try await SheetInteraction.waitForLoadState(.networkidle, in: webView, timeout: 1)
        try await SheetInteraction.waitForFunction(
            expression: "window.agentReady === true",
            in: webView,
            timeout: 1
        )
        try await SheetInteraction.waitForElement(
            target: ".item",
            state: .hidden,
            in: webView,
            timeout: 1
        )
        try await SheetInteraction.waitForElement(
            target: ".missing",
            state: .detached,
            in: webView,
            timeout: 1
        )

        // Assert
        let visibleElements = try await SheetInteraction.query(
            selector: ".item",
            visibleOnly: true,
            all: true,
            fields: ["text"],
            in: webView
        )
        #expect(visibleElements.isEmpty)
    }
}
