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
struct SheetWebRuntimeTests {
    @Test func boardRuntimeObservesUrlAndTitleChanges() async throws {
        let manager = makeTestSheetNavigationManager(scriptSource: "")
        var changeContinuation: AsyncStream<(URL?, String?)>.Continuation?
        let changes = AsyncStream<(URL?, String?)> { continuation in
            changeContinuation = continuation
        }

        let runtime = WebRuntime(
            board: makeTestBoard("Initial", url: "about:blank"),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: manager,
            sheetScale: AppPreferences.defaultSheetScale,
            sheetNavigationActions: makeNoOpSheetNavigationActions(),
            events: boardRuntimeEvents { _, url, title in
                changeContinuation?.yield((url, title))
            }
        )

        let waiter = WebViewLoadWaiter()
        let testURL = URL(string: "https://example.com/test-page")!

        await waiter.load(
            "<html><head><title>Test Page Title</title></head><body>Hello</body></html>",
            baseURL: testURL,
            in: runtime.webView
        )

        let observedChange = try await withThrowingTaskGroup(of: (URL?, String?)?.self) { group in
            group.addTask {
                for await change in changes where change.0 == testURL && change.1 == "Test Page Title" {
                    return change
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
        let runtime = WebRuntime(
            board: BoardState(label: "Initial", width: 520, currentSheetURL: nil),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: makeTestSheetNavigationManager(scriptSource: ""),
            sheetScale: AppPreferences.defaultSheetScale,
            sheetNavigationActions: makeNoOpSheetNavigationActions(),
            events: boardRuntimeEvents()
        )
        let expectedURL = URL(string: "https://example.com/assets/favicon.png")!
        var continuation: AsyncStream<URL?>.Continuation?
        let faviconURLs = AsyncStream<URL?> { continuation = $0 }
        let observation = runtime.$faviconURL.sink { continuation?.yield($0) }

        runtime.webView.loadHTMLString(
            """
            <html><head><link rel="icon" href="/assets/favicon.png"></head></html>
            """,
            baseURL: URL(string: "https://example.com/")
        )

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

    @Test func sheetInteractionClickAndFillReturnRectAndLeaveDOMUntouched() async throws {
        let configuration = WKWebViewConfiguration()
        SheetDOMRuntime.install(on: configuration.userContentController)
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        webView.pageZoom = 1.5
        let waiter = WebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <html>
            <body>
              <button id="test-btn" style="position:absolute;left:20px;top:30px;width:100px;height:40px;" onclick="this.textContent = 'clicked'">Click Me</button>
              <input id="test-input" style="box-sizing:border-box;position:absolute;left:20px;top:80px;width:150px;height:30px;" type="text" value="">
            </body>
            </html>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        let clickRect = try await SheetInteraction.click(target: "#test-btn", in: webView)
        let clickedText =
            try await webView.evaluateJavaScript("document.getElementById('test-btn').textContent") as? String
        #expect(clickedText == "clicked")
        #expect(clickRect == CGRect(x: 30, y: 45, width: 150, height: 60))

        let clickHighlight =
            try await webView.evaluateJavaScript("document.querySelector('[data-den-highlight]')")
        #expect(clickHighlight is NSNull || clickHighlight == nil)

        let fillRect = try await SheetInteraction.fill(target: "#test-input", value: "hello agent", in: webView)
        let inputValue = try await webView.evaluateJavaScript("document.getElementById('test-input').value") as? String
        #expect(inputValue == "hello agent")
        #expect(fillRect == CGRect(x: 30, y: 120, width: 225, height: 45))

        let fillHighlight =
            try await webView.evaluateJavaScript("document.querySelector('[data-den-highlight]')")
        #expect(fillHighlight is NSNull || fillHighlight == nil)
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
}
