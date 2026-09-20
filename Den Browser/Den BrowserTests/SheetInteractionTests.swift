import AppKit
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
final class SheetInteractionWebViewLoadWaiter: NSObject, WKNavigationDelegate {
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

    @Test func fillAndValueWorkOnContentEditableAndAriaTextbox() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <div id="editable" contenteditable="true">initial content</div>
            <div id="aria-box" role="textbox" tabindex="0">initial aria</div>
            <script>
                window.editableEvents = [];
                window.ariaEvents = [];
                const record = (arr, e) => arr.push(e.type + ':' + (e.inputType || '') + ':' + (e.data || ''));
                document.getElementById('editable').addEventListener('input', e => record(window.editableEvents, e));
                document.getElementById('editable').addEventListener('change', e => record(window.editableEvents, e));
                document.getElementById('aria-box').addEventListener('input', e => record(window.ariaEvents, e));
                document.getElementById('aria-box').addEventListener('change', e => record(window.ariaEvents, e));
            </script>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        // Act & Assert contenteditable
        let initialEditable = try await SheetInteraction.value(target: "#editable", in: webView)
        #expect(initialEditable == "initial content")

        try await SheetInteraction.fill(target: "#editable", value: "updated rich text", in: webView)
        let updatedEditable = try await SheetInteraction.value(target: "#editable", in: webView)
        #expect(updatedEditable == "updated rich text")

        try await SheetInteraction.fill(target: "#editable", value: "", in: webView)
        let clearedEditable = try await SheetInteraction.value(target: "#editable", in: webView)
        #expect(clearedEditable == "")

        // Act & Assert ARIA textbox
        let initialAria = try await SheetInteraction.value(target: "#aria-box", in: webView)
        #expect(initialAria == "initial aria")

        try await SheetInteraction.fill(target: "#aria-box", value: "custom textbox value", in: webView)
        let updatedAria = try await SheetInteraction.value(target: "#aria-box", in: webView)
        #expect(updatedAria == "custom textbox value")

        try await SheetInteraction.fill(target: "#aria-box", value: "", in: webView)
        let clearedAria = try await SheetInteraction.value(target: "#aria-box", in: webView)
        #expect(clearedAria == "")

        // Verify events fired
        let editableCount = try await webView.evaluateJavaScript("window.editableEvents.length") as? Int ?? 0
        let ariaCount = try await webView.evaluateJavaScript("window.ariaEvents.length") as? Int ?? 0
        #expect(editableCount >= 2)
        #expect(ariaCount >= 2)
    }

    @Test func fillTriggersInputEventsInPageWorld() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <input id="test-input" value="initial">
            <script>
                window.receivedValue = null;
                window.inputEventFired = false;
                document.getElementById('test-input').addEventListener('input', (e) => {
                    window.inputEventFired = true;
                    window.receivedValue = e.target.value;
                });
            </script>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        // Act
        try await SheetInteraction.fill(target: "#test-input", value: "dispatched", in: webView)
        let value = try await SheetInteraction.value(target: "#test-input", in: webView)
        let eventFired = try await webView.evaluateJavaScript("window.inputEventFired") as? Bool ?? false
        let receivedValue = try await webView.evaluateJavaScript("window.receivedValue") as? String

        // Assert
        #expect(value == "dispatched")
        #expect(eventFired == true)
        #expect(receivedValue == "dispatched")
    }

    @Test func dragWithDxDyDispatchesPointerAndMouseEvents() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <div id="drag-source" style="position: absolute; left: 10px; top: 10px; width: 100px; height: 100px; background: red;"></div>
            <script>
                window.recordedEvents = [];
                const record = (e) => window.recordedEvents.push({
                    type: e.type,
                    x: Math.round(e.clientX),
                    y: Math.round(e.clientY),
                    buttons: e.buttons
                });
                const el = document.getElementById('drag-source');
                ['pointerdown', 'pointermove', 'pointerup', 'mousedown', 'mousemove', 'mouseup'].forEach(type => {
                    window.addEventListener(type, record);
                });
            </script>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        // Act
        try await SheetInteraction.drag(source: "#drag-source", deltaX: 100, deltaY: 50, steps: 2, in: webView)

        // Assert
        let eventTypes = try #require(
            await webView.evaluateJavaScript("window.recordedEvents.map(event => event.type).join(',')") as? String
        )
        #expect(eventTypes == "pointerdown,mousedown,pointermove,mousemove,pointermove,mousemove,pointerup,mouseup")

        let lastX =
            try await webView.evaluateJavaScript("window.recordedEvents[window.recordedEvents.length - 1].x") as? Int
            ?? 0
        let lastY =
            try await webView.evaluateJavaScript("window.recordedEvents[window.recordedEvents.length - 1].y") as? Int
            ?? 0
        // Source center is (60, 60), dx=100, dy=50 => end is (160, 110)
        #expect(lastX == 160)
        #expect(lastY == 110)
    }

    @Test func dragToTargetDispatchesEvents() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <div id="source" style="position: absolute; left: 0px; top: 0px; width: 50px; height: 50px;"></div>
            <div id="target" style="position: absolute; left: 200px; top: 200px; width: 50px; height: 50px;"></div>
            <script>
                window.targetEvents = [];
                const tgt = document.getElementById('target');
                tgt.addEventListener('pointerup', () => window.targetEvents.push('pointerup'));
                tgt.addEventListener('mouseup', () => window.targetEvents.push('mouseup'));
            </script>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        // Act
        try await SheetInteraction.drag(source: "#source", target: "#target", steps: 3, in: webView)

        // Assert
        let targetEventsCount = try await webView.evaluateJavaScript("window.targetEvents.length") as? Int ?? 0
        #expect(targetEventsCount == 2)
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

    @Test(arguments: [
        ("<input id='field'>", false, true),
        ("<textarea id='field'></textarea>", false, false),
        ("<input id='field'>", true, false),
    ])
    func pressSubmitsOnlyFromUncancelledSingleLineFormControls(
        control: String,
        preventsDefault: Bool,
        submits: Bool
    ) async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <form id="form">\(control)</form>
            <script>
                window.submitCount = 0;
                document.getElementById('form').addEventListener('submit', event => {
                    event.preventDefault();
                    window.submitCount += 1;
                });
                if (\(preventsDefault)) {
                    document.getElementById('field').addEventListener('keydown', event => event.preventDefault());
                }
            </script>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )
        try await SheetInteraction.focus(target: "#field", in: webView)

        // Act
        try await SheetInteraction.press(key: "Enter", in: webView)

        // Assert
        let submitCount = try await webView.evaluateJavaScript("window.submitCount") as? Int ?? 0
        #expect(submitCount == (submits ? 1 : 0))
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

    @Test func clickResultExtractsHrefForLinkElement() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        let html = """
            <!DOCTYPE html>
            <html>
            <body>
                <a id="nav-link" href="https://example.com/target"><span>Click me</span></a>
                <button id="regular-btn">Button</button>
            </body>
            </html>
            """
        await waiter.load(html, baseURL: URL(string: "https://example.com")!, in: webView)

        // Act
        let linkResult = try await SheetInteraction.clickResult(
            target: "#nav-link span",
            newBoard: true,
            in: webView
        )
        let btnResult = try await SheetInteraction.clickResult(
            target: "#regular-btn",
            newBoard: true,
            in: webView
        )

        // Assert
        #expect(linkResult.href == "https://example.com/target")
        #expect(btnResult.href == nil)
    }

    @Test func dblclickDispatchesDoubleClickEvents() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        let html = """
            <!DOCTYPE html>
            <button id="target" ondblclick="this.dataset.dbl = 'yes'">Double me</button>
            <script>
                window.clickDetails = [];
                document.getElementById('target').addEventListener('click', e => window.clickDetails.push(e.detail));
                document.getElementById('target').addEventListener('dblclick', e => window.clickDetails.push('dbl:' + e.detail));
            </script>
            """
        await waiter.load(html, baseURL: URL(string: "https://example.com")!, in: webView)

        // Act
        try await SheetInteraction.dblclick(target: "#target", in: webView)

        // Assert
        let dblAttr = try await SheetInteraction.attribute(target: "#target", name: "data-dbl", in: webView)
        #expect(dblAttr == "yes")
        let details = try await webView.evaluateJavaScript("window.clickDetails") as? [Any]
        #expect(details?.count == 3)
    }

    @Test func focusSetsActiveElement() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        let html = """
            <!DOCTYPE html>
            <input id="first" type="text">
            <input id="second" type="text">
            """
        await waiter.load(html, baseURL: URL(string: "https://example.com")!, in: webView)

        // Act
        try await SheetInteraction.focus(target: "#second", in: webView)

        // Assert
        let activeID = try await webView.evaluateJavaScript("document.activeElement.id") as? String
        #expect(activeID == "second")
    }

    @Test func typeInsertsTextAndDispatchesInput() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        let html = """
            <!DOCTYPE html>
            <input id="inp" type="text" value="hello ">
            <script>
                window.inputEvents = [];
                document.getElementById('inp').addEventListener('input', e => window.inputEvents.push(e.data));
            </script>
            """
        await waiter.load(html, baseURL: URL(string: "https://example.com")!, in: webView)

        // Act
        try await SheetInteraction.type(target: "#inp", text: "world", in: webView)

        // Assert
        let val = try await SheetInteraction.value(target: "#inp", in: webView)
        #expect(val == "hello world")
        let eventsCount = try await webView.evaluateJavaScript("window.inputEvents.length") as? Int ?? 0
        #expect(eventsCount > 0)
    }

    @Test func typeIntoFocusedElementWhenTargetIsNil() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        let html = """
            <!DOCTYPE html>
            <textarea id="txt"></textarea>
            <script>
                document.getElementById('txt').focus();
            </script>
            """
        await waiter.load(html, baseURL: URL(string: "https://example.com")!, in: webView)

        // Act
        try await SheetInteraction.type(target: nil, text: "typed text", in: webView)

        // Assert
        let val = try await SheetInteraction.value(target: "#txt", in: webView)
        #expect(val == "typed text")
    }

    @Test func boxReturnsElementBoundingBox() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        let html = """
            <!DOCTYPE html>
            <div id="box" style="position: absolute; left: 50px; top: 100px; width: 200px; height: 80px;"></div>
            """
        await waiter.load(html, baseURL: URL(string: "https://example.com")!, in: webView)

        // Act
        let rect = try await SheetInteraction.box(target: "#box", in: webView)

        // Assert
        #expect(rect.origin.x == 50)
        #expect(rect.origin.y == 100)
        #expect(rect.size.width == 200)
        #expect(rect.size.height == 80)
    }

    @Test func mouseEventsDispatchCorrectly() async throws {
        // Arrange
        let webView = makeWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        let html = """
            <!DOCTYPE html>
            <div id="target" style="position: absolute; left: 0px; top: 0px; width: 200px; height: 200px;"></div>
            <script>
                window.mouseLog = [];
                const el = document.getElementById('target');
                ['mousedown', 'mouseup', 'click', 'mousemove', 'wheel'].forEach(type => {
                    el.addEventListener(type, e => window.mouseLog.push(type));
                });
            </script>
            """
        await waiter.load(html, baseURL: URL(string: "https://example.com")!, in: webView)

        // Act
        try await SheetInteraction.mouseMove(coordX: 100, coordY: 100, in: webView)
        try await SheetInteraction.mouseDown(button: 0, in: webView)
        try await SheetInteraction.mouseUp(button: 0, in: webView)
        try await SheetInteraction.mouseClick(coordX: 100, coordY: 100, button: 0, count: 1, in: webView)
        try await SheetInteraction.mouseWheel(deltaX: 0, deltaY: 50, in: webView)

        // Assert
        let log = try await webView.evaluateJavaScript("window.mouseLog") as? [String] ?? []
        #expect(log.contains("mousemove"))
        #expect(log.contains("mousedown"))
        #expect(log.contains("mouseup"))
        #expect(log.contains("click"))
        #expect(log.contains("wheel"))
    }
}
