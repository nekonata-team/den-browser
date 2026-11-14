import AppKit
import Combine
import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct SheetNavigationScriptTests {
    @Test func sheetNavigationScriptIsIsolatedFromPageScripts() async throws {
        let manager = makeTestSheetNavigationManager(scriptSource: try makeSheetNavigationScriptSource())
        manager.setEnabled(true)
        let webView = makeSheetNavigationWebView(manager: manager)
        let waiter = WebViewLoadWaiter()

        await waiter.load(sheetNavigationTestHTML, baseURL: URL(string: "https://example.com/")!, in: webView)
        let pageCanSeeBridge =
            (try await webView.evaluateJavaScript(
                "typeof window.webkit?.messageHandlers?.denSheetNavigation !== 'undefined'"
            ) as? Bool) ?? true
        let pageCanSeeConfiguration =
            (try await webView.evaluateJavaScript(
                "typeof window.__denSheetNavigation !== 'undefined'"
            ) as? Bool) ?? true
        try await dispatchSheetKey("f", in: webView)
        let hintCount = try #require(
            await webView.evaluateJavaScript(
                "document.querySelectorAll('[data-den-sheet-hints] span').length"
            ) as? Int
        )

        #expect(!pageCanSeeBridge)
        #expect(!pageCanSeeConfiguration)
        #expect(hintCount == 0)
    }

    @Test func modifiedHTMLAndSVGLinkClicksAreKeptWhenSheetNavigationIsDisabled() async throws {
        let source = try makeSheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted || event.button",
            with: "if (event.button"
        )
        let manager = makeTestSheetNavigationManager(scriptSource: source)
        let webView = makeSheetNavigationWebView(manager: manager)
        let waiter = WebViewLoadWaiter()

        await waiter.load(
            """
            <a id="html-link" href="https://destination.example/html">HTML destination</a>
            <svg width="200" height="40">
              <a id="svg-link" href="https://destination.example/svg">
                <text x="0" y="20">SVG destination</text>
              </a>
            </svg>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )
        let commandClickWasAllowed =
            try await webView.evaluateJavaScript(
                """
                document.querySelector("#html-link").dispatchEvent(new MouseEvent("click", {
                  metaKey: true,
                  button: 0,
                  bubbles: true,
                  cancelable: true,
                  composed: true
                }))
                """
            ) as? Bool
        let optionClickWasAllowed =
            try await webView.evaluateJavaScript(
                """
                document.querySelector("#html-link").dispatchEvent(new MouseEvent("click", {
                  altKey: true,
                  button: 0,
                  bubbles: true,
                  cancelable: true,
                  composed: true
                }))
                """
            ) as? Bool
        let svgCommandClickWasAllowed =
            try await webView.evaluateJavaScript(
                """
                document.querySelector("#svg-link").dispatchEvent(new MouseEvent("click", {
                  metaKey: true,
                  button: 0,
                  bubbles: true,
                  cancelable: true,
                  composed: true
                }))
                """
            ) as? Bool
        let svgOptionClickWasAllowed =
            try await webView.evaluateJavaScript(
                """
                document.querySelector("#svg-link").dispatchEvent(new MouseEvent("click", {
                  altKey: true,
                  button: 0,
                  bubbles: true,
                  cancelable: true,
                  composed: true
                }))
                """
            ) as? Bool

        #expect(commandClickWasAllowed == false)
        #expect(optionClickWasAllowed == false)
        #expect(svgCommandClickWasAllowed == false)
        #expect(svgOptionClickWasAllowed == false)
    }

    @Test func sheetNavigationScriptHandlesCoreMotionsAndModes() async throws {
        let source = try makeSheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let manager = makeTestSheetNavigationManager(scriptSource: source)
        manager.setEnabled(true)
        let webView = makeSheetNavigationWebView(manager: manager)
        let waiter = WebViewLoadWaiter()

        manager.setReduceMotion(true)
        await waiter.load(sheetNavigationTestHTML, baseURL: URL(string: "https://example.com/")!, in: webView)
        manager.refreshConfiguration(for: webView)
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
        let spacePreventedDefault = try await dispatchSheetKey(" ", in: webView)
        let hintCountAfterSpace = try #require(
            await webView.evaluateJavaScript(
                "document.querySelectorAll('[data-den-sheet-hints] span').length"
            ) as? Int
        )
        _ = try await webView.evaluateJavaScript("scrollTo(0, 0)")
        try await dispatchSheetKey("f", in: webView)
        let hintCount = try #require(
            await webView.evaluateJavaScript(
                "document.querySelectorAll('[data-den-sheet-hints] span').length"
            ) as? Int
        )
        try await dispatchSheetKey("Escape", in: webView)
        try await dispatchSheetKey("/", in: webView)
        let hasFindBar =
            (try await webView.evaluateJavaScript(
                "document.querySelector('[data-den-sheet-find]') !== null"
            ) as? Bool) ?? false

        #expect(afterBottom[0] == 300)
        #expect(afterBottom[1] > 300)
        #expect(afterLeft == [0, 300])
        #expect(afterCountedScroll == 180)
        #expect(!spacePreventedDefault)
        #expect(hintCountAfterSpace == 0)
        #expect(hintCount == 1)
        #expect(hasFindBar)
    }

    @Test func sheetNavigationHintsScrollableAreasForLocalScrolling() async throws {
        // Arrange
        let source = try makeSheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let manager = makeTestSheetNavigationManager(scriptSource: source)
        manager.setEnabled(true)
        manager.setReduceMotion(true)
        let webView = makeSheetNavigationWebView(manager: manager)
        let waiter = WebViewLoadWaiter()
        let html = """
            <!doctype html>
            <style>
              html, body { margin: 0; height: 4000px; }
              #panel { width: 300px; height: 200px; overflow: auto; }
              #content { height: 4000px; }
            </style>
            <div id="panel"><div id="content">Scrollable panel</div></div>
            """

        await waiter.load(html, baseURL: URL(string: "https://example.com/")!, in: webView)
        manager.refreshConfiguration(for: webView)

        // Act
        try await dispatchSheetKey("f", in: webView)
        let hintCount = try #require(
            await webView.evaluateJavaScript(
                "document.querySelectorAll('[data-den-sheet-hints] span').length"
            ) as? Int
        )
        try await dispatchSheetKey("a", in: webView)
        try await dispatchSheetKey("j", in: webView)
        let panelScrollTop = try #require(
            await webView.evaluateJavaScript("document.getElementById('panel').scrollTop") as? Int
        )
        try await dispatchSheetKey("Escape", in: webView)
        try await dispatchSheetKey("j", in: webView)
        let documentScrollTop = try #require(
            await webView.evaluateJavaScript("document.scrollingElement.scrollTop") as? Int
        )

        // Assert
        #expect(hintCount == 1)
        #expect(panelScrollTop == 60)
        #expect(documentScrollTop == 60)
    }

    @Test func sheetNavigationFindsScrollableAncestorThroughSVGHitTarget() async throws {
        // Arrange
        let source = try makeSheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let manager = makeTestSheetNavigationManager(scriptSource: source)
        manager.setEnabled(true)
        manager.setReduceMotion(true)
        let webView = makeSheetNavigationWebView(manager: manager)
        let waiter = WebViewLoadWaiter()
        let html = """
            <!doctype html>
            <style>
              html, body { margin: 0; height: 4000px; }
              #panel { position: absolute; top: 350px; width: 800px; height: 200px; overflow: auto; }
              svg { display: block; width: 800px; height: 200px; }
              #content { height: 1000px; }
            </style>
            <div id="panel">
              <svg><rect width="800" height="200"></rect></svg>
              <div id="content"></div>
            </div>
            """

        await waiter.load(html, baseURL: URL(string: "https://example.com/")!, in: webView)
        manager.refreshConfiguration(for: webView)

        // Act
        let hitNamespace = try #require(
            await webView.evaluateJavaScript(
                "document.elementFromPoint(innerWidth / 2, innerHeight * 0.75).namespaceURI"
            ) as? String
        )
        try await dispatchSheetKey("j", in: webView)
        let panelScrollTop = try #require(
            await webView.evaluateJavaScript("document.getElementById('panel').scrollTop") as? Int
        )
        let documentScrollTop = try #require(
            await webView.evaluateJavaScript("document.scrollingElement.scrollTop") as? Int
        )

        // Assert
        #expect(hitNamespace == "http://www.w3.org/2000/svg")
        #expect(panelScrollTop == 60)
        #expect(documentScrollTop == 0)
    }

    @Test func sheetNavigationHintsSVGTargets() async throws {
        // Arrange
        let source = try makeSheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let manager = makeTestSheetNavigationManager(scriptSource: source)
        manager.setEnabled(true)
        let webView = makeSheetNavigationWebView(manager: manager)
        let waiter = WebViewLoadWaiter()
        let html = """
            <!doctype html>
            <svg width="200" height="40">
              <a href="https://destination.example/svg">
                <text x="0" y="20">SVG destination</text>
              </a>
              <rect tabindex="0" x="0" y="20" width="200" height="20"></rect>
            </svg>
            """

        await waiter.load(html, baseURL: URL(string: "https://example.com/")!, in: webView)
        manager.refreshConfiguration(for: webView)

        // Act
        try await dispatchSheetKey("F", shift: true, in: webView)
        let linkHintCount = try #require(
            await webView.evaluateJavaScript(
                "document.querySelectorAll('[data-den-sheet-hints] span').length"
            ) as? Int
        )
        try await dispatchSheetKey("Escape", in: webView)
        try await dispatchSheetKey("f", in: webView)
        let activateHintCount = try #require(
            await webView.evaluateJavaScript(
                "document.querySelectorAll('[data-den-sheet-hints] span').length"
            ) as? Int
        )

        // Assert
        #expect(linkHintCount == 1)
        #expect(activateHintCount == 2)
    }

    @Test func sheetNavigationHintsSemanticLinkTargets() async throws {
        // Arrange
        let source = try makeSheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let manager = makeTestSheetNavigationManager(scriptSource: source)
        manager.setEnabled(true)
        let webView = makeSheetNavigationWebView(manager: manager)
        let waiter = WebViewLoadWaiter()
        let html = """
            <!doctype html>
            <div id="account" role="link" tabindex="0">Account</div>
            <div id="status">Not activated</div>
            <script>
              document.getElementById("account").addEventListener(
                "click", () => document.getElementById("status").textContent = "Activated");
            </script>
            """

        await waiter.load(html, baseURL: URL(string: "https://example.com/")!, in: webView)
        manager.refreshConfiguration(for: webView)

        // Act
        try await dispatchSheetKey("f", in: webView)
        let hintCount = try #require(
            await webView.evaluateJavaScript(
                "document.querySelectorAll('[data-den-sheet-hints] span').length"
            ) as? Int
        )
        try await dispatchSheetKey("a", in: webView)
        let status = try #require(
            await webView.evaluateJavaScript("document.getElementById('status').textContent") as? String
        )

        // Assert
        #expect(hintCount == 1)
        #expect(status == "Activated")
    }

    @Test func sheetNavigationFindHighlightsAndNavigatesMatches() async throws {
        let source = try makeSheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let manager = makeTestSheetNavigationManager(scriptSource: source)
        manager.setEnabled(true)
        let webView = makeSheetNavigationWebView(manager: manager)
        let waiter = WebViewLoadWaiter()

        await waiter.load(
            """
            <!doctype html>
            <p>apple banana apple cherry apple</p>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        try await dispatchSheetKey("/", in: webView)
        let hasFindBar =
            (try await webView.evaluateJavaScript(
                "document.querySelector('[data-den-sheet-find]') !== null"
            ) as? Bool) ?? false
        #expect(hasFindBar)

        _ = try await webView.evaluateJavaScript(
            """
            {
                const input = document.querySelector('[data-den-sheet-find] input');
                input.value = 'apple';
                input.dispatchEvent(new Event('input', { bubbles: true }));
            }
            """
        )

        let initialMatchCount = try #require(
            await webView.callAsyncJavaScript(
                "return CSS.highlights.get('den-find')?.size ?? 0;",
                in: nil,
                contentWorld: SheetNavigationManager.contentWorld
            ) as? Int
        )
        let initialStatus = try #require(
            await webView.evaluateJavaScript(
                "document.querySelector('[data-den-sheet-find] span:last-child')?.textContent"
            ) as? String
        )
        #expect(initialMatchCount == 3)
        #expect(initialStatus == "1 / 3")

        _ = try await webView.evaluateJavaScript(
            """
            {
                const input = document.querySelector('[data-den-sheet-find] input');
                input.value = 'nonexistent';
                input.dispatchEvent(new Event('input', { bubbles: true }));
            }
            """
        )

        let noMatchStatus = try #require(
            await webView.evaluateJavaScript(
                "document.querySelector('[data-den-sheet-find] span:last-child')?.textContent"
            ) as? String
        )
        let isInputFocusedOnNoMatch =
            (try await webView.evaluateJavaScript(
                "document.activeElement === document.querySelector('[data-den-sheet-find] input')"
            ) as? Bool) ?? false
        #expect(noMatchStatus == "No matches")
        #expect(isInputFocusedOnNoMatch)

        _ = try await webView.evaluateJavaScript(
            """
            {
                const input = document.querySelector('[data-den-sheet-find] input');
                input.value = 'apple';
                input.dispatchEvent(new Event('input', { bubbles: true }));
            }
            """
        )

        _ = try await webView.evaluateJavaScript(
            """
            {
                const input = document.querySelector('[data-den-sheet-find] input');
                input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
            }
            """
        )

        try await dispatchSheetKey("n", in: webView)
        let secondStatus = try #require(
            await webView.evaluateJavaScript(
                "document.querySelector('[data-den-sheet-find] span:last-child')?.textContent"
            ) as? String
        )
        #expect(secondStatus == "2 / 3")

        try await dispatchSheetKey("n", in: webView)
        let thirdStatus = try #require(
            await webView.evaluateJavaScript(
                "document.querySelector('[data-den-sheet-find] span:last-child')?.textContent"
            ) as? String
        )
        #expect(thirdStatus == "3 / 3")

        try await dispatchSheetKey("n", in: webView)
        let wrappedStatus = try #require(
            await webView.evaluateJavaScript(
                "document.querySelector('[data-den-sheet-find] span:last-child')?.textContent"
            ) as? String
        )
        #expect(wrappedStatus == "1 / 3")

        try await dispatchSheetKey("N", shift: true, in: webView)
        let prevStatus = try #require(
            await webView.evaluateJavaScript(
                "document.querySelector('[data-den-sheet-find] span:last-child')?.textContent"
            ) as? String
        )
        #expect(prevStatus == "3 / 3")
        let findBarBeforeEscape =
            (try await webView.evaluateJavaScript(
                "document.querySelector('[data-den-sheet-find]') !== null"
            ) as? Bool) ?? false
        #expect(findBarBeforeEscape)

        try await dispatchSheetKey("Escape", in: webView)

        let findBarAfterEscape =
            (try await webView.evaluateJavaScript(
                "document.querySelector('[data-den-sheet-find]') !== null"
            ) as? Bool) ?? false
        let hasInContentWorld =
            (try await webView.callAsyncJavaScript(
                "return CSS.highlights.has('den-find');",
                in: nil,
                contentWorld: SheetNavigationManager.contentWorld
            ) as? Bool) ?? false
        let sizeInContentWorld =
            (try await webView.callAsyncJavaScript(
                "return CSS.highlights.get('den-find')?.size ?? 0;",
                in: nil,
                contentWorld: SheetNavigationManager.contentWorld
            ) as? Int) ?? 0
        #expect(!findBarAfterEscape)
        #expect(!hasInContentWorld)
        #expect(sizeInContentWorld == 0)
    }

    @Test func sheetNavigationFocusesEditableControlsInDocumentOrder() async throws {
        let source = try makeSheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let manager = makeTestSheetNavigationManager(scriptSource: source)
        manager.setEnabled(true)
        let webView = makeSheetNavigationWebView(manager: manager)
        let waiter = WebViewLoadWaiter()

        await waiter.load(editableControlsTestHTML, baseURL: URL(string: "https://example.com/")!, in: webView)

        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("i", in: webView)
        let firstFocused = try #require(
            await webView.evaluateJavaScript("document.activeElement.id") as? String
        )
        #expect(firstFocused == "first-text")

        try await dispatchSheetKey("Escape", in: webView)
        try await dispatchSheetKey("2", in: webView)
        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("i", in: webView)
        let secondFocused = try #require(
            await webView.evaluateJavaScript("document.activeElement.id") as? String
        )
        #expect(secondFocused == "message")

        try await dispatchSheetKey("Escape", in: webView)
        try await dispatchSheetKey("3", in: webView)
        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("i", in: webView)
        let thirdFocused = try #require(
            await webView.evaluateJavaScript("document.activeElement.id") as? String
        )
        let scrollY = try #require(await webView.evaluateJavaScript("scrollY") as? Int)
        #expect(thirdFocused == "composer")
        #expect(scrollY > 0)
    }

    @Test func boardWebViewUsesIsolatedSheetNavigationControllerAndActionHighlight() async throws {
        let manager = makeTestSheetNavigationManager(scriptSource: "")
        let runtime = WebRuntime(
            board: makeTestBoard("Navigation", url: "about:blank"),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: manager,
            sheetScale: AppPreferences.defaultSheetScale,
            sheetNavigationActions: makeNoOpSheetNavigationActions(),
            events: boardRuntimeEvents()
        )
        defer { runtime.dispose() }

        let userContentController = runtime.webView.configuration.userContentController
        #expect(userContentController !== manager.userContentController)

        #expect(runtime.actionHighlight == nil)
        runtime.triggerActionHighlight(CGRect(x: 10, y: 10, width: 50, height: 20))
        #expect(runtime.actionHighlight?.rect == CGRect(x: 10, y: 10, width: 50, height: 20))

        let clearDeadline = ContinuousClock.now + .seconds(2)
        while runtime.actionHighlight != nil, ContinuousClock.now < clearDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(runtime.actionHighlight == nil)
    }

    @Test func sheetNavigationWorksOnInitialUnnavigatedAboutBlank() async throws {
        let source = try makeSheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let manager = makeTestSheetNavigationManager(scriptSource: source)
        manager.setEnabled(true)
        let board = BoardState(label: "Blank", width: 520, currentSheetURL: nil)
        let desk = makeTestDesk("Desk", boards: [board], focusedBoardID: board.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration(sheetNavigation: manager)
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let webView = session.runtimes.webRuntime(for: board).webView

        try await dispatchSheetKey("g", in: webView)
        try await dispatchSheetKey("e", in: webView)
        #expect(windowModel.isEditBoardLinkPanelPresented)

        windowModel.hideEditBoardLinkPanel()
        try await dispatchSheetKey("t", in: webView)
        #expect(windowModel.isOpenBoardPanelPresented)
    }
}
