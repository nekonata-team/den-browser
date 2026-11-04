import DenDomain
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
struct DenAPIBridgeTests {
    @Test(.timeLimit(.minutes(1)))
    func sharedPopupControllerKeepsEachWebViewsGrantAndLifetimeSeparate() async throws {
        // Arrange
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let first = WKWebView(frame: .zero, configuration: configuration)
        let popup = WKWebView(frame: .zero, configuration: configuration)
        let target = URL(fileURLWithPath: "/tmp/sketch.html")
        let id = BoardID()
        var firstCalls = 0
        var popupCalls = 0
        let firstBridge = DenAPIBridge(webView: first) { _ in firstCalls += 1 }
        defer { firstBridge.dispose() }
        firstBridge.setEnabled(true)
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load("<p>Popup</p>", baseURL: target, in: popup)

        // Act / Assert: inherited scripts do not grant the popup permission.
        let denied = try await popup.callAsyncJavaScript(
            "try { await den.boards.focus(id); return false; } catch { return true; }",
            arguments: ["id": id.rawValue.uuidString], in: nil, contentWorld: .page)
        #expect(denied as? Bool == true)
        #expect(firstCalls == 0)

        // Act / Assert: explicitly authorizing the popup must not steal the original's handler.
        let popupBridge = DenAPIBridge(webView: popup) { _ in popupCalls += 1 }
        defer { popupBridge.dispose() }
        popupBridge.setEnabled(true)
        await waiter.load("<p>First</p>", baseURL: target, in: first)
        await waiter.load("<p>Popup</p>", baseURL: target, in: popup)
        for webView in [first, popup] {
            _ = try await webView.callAsyncJavaScript(
                "await den.boards.focus(id);", arguments: ["id": id.rawValue.uuidString], in: nil,
                contentWorld: .page)
        }
        #expect(firstCalls == 1)
        #expect(popupCalls == 1)
        firstBridge.dispose()
        _ = try await popup.callAsyncJavaScript(
            "await den.boards.focus(id);", arguments: ["id": id.rawValue.uuidString], in: nil,
            contentWorld: .page)
        #expect(popupCalls == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func localHTMLFilesShareTheBoardFlagWhileRemotePagesAndFramesCannotUseIt() async throws {
        // Arrange
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let target = URL(fileURLWithPath: "/tmp/Sketch notes.html")
        let id = BoardID()
        var focused: [BoardID] = []
        let bridge = DenAPIBridge(webView: webView) { focused.append($0) }
        defer { bridge.dispose() }
        bridge.setEnabled(true)
        let waiter = SheetInteractionWebViewLoadWaiter()
        let html = """
            <script>window.apiAtStart = typeof window.den;</script>
            <iframe srcdoc="<p>Child</p>"></iframe><p>Sketch</p>
            """

        // Act / Assert
        await waiter.load(html, baseURL: target, in: webView)
        #expect(try await webView.evaluateJavaScript("window.apiAtStart") as? String == "object")
        _ = try await webView.callAsyncJavaScript(
            "await den.boards.focus(id);", arguments: ["id": id.rawValue.uuidString], in: nil, contentWorld: .page)
        #expect(focused == [id])
        let child = try await webView.evaluateJavaScript("typeof frames[0].den") as? String
        #expect(child == "undefined")
        let rawCall = """
            try {
                await window.webkit.messageHandlers[handler].postMessage({ action: 'board.focus', boardId: id });
                return 'allowed';
            } catch { return 'denied'; }
            """
        let childResult = try await webView.callAsyncJavaScript(
            """
            try {
                await frames[0].webkit.messageHandlers[handler].postMessage({action: 'board.focus', boardId: id});
                return 'allowed';
            } catch { return 'denied'; }
            """, arguments: ["handler": DenAPIBridge.handlerName, "id": id.rawValue.uuidString], in: nil,
            contentWorld: .page)
        #expect(childResult as? String == "denied")
        await waiter.load(html, baseURL: URL(fileURLWithPath: "/tmp/other.html"), in: webView)
        #expect(try await webView.evaluateJavaScript("window.apiAtStart") as? String == "object")
        _ = try await webView.callAsyncJavaScript(
            "await den.boards.focus(id);", arguments: ["id": id.rawValue.uuidString], in: nil, contentWorld: .page)
        #expect(focused == [id, id])
        await waiter.load(html, baseURL: URL(string: "https://example.com/other.html")!, in: webView)
        #expect(try await webView.evaluateJavaScript("typeof window.den") as? String == "undefined")
        let denied = try await webView.callAsyncJavaScript(
            rawCall, arguments: ["handler": DenAPIBridge.handlerName, "id": id.rawValue.uuidString], in: nil,
            contentWorld: .page)
        #expect(denied as? String == "denied")
        #expect(focused == [id, id])
        await waiter.load(html, baseURL: target, in: webView)
        _ = try await webView.callAsyncJavaScript(
            "await den.boards.focus(id);", arguments: ["id": id.rawValue.uuidString], in: nil, contentWorld: .page)
        #expect(focused == [id, id, id])
        bridge.setEnabled(false)
        // An already-captured function must lose permission immediately, before a reload finishes.
        let disabled = try await webView.callAsyncJavaScript(
            "try { await den.boards.focus(id); return 'allowed'; } catch { return 'denied'; }",
            arguments: ["id": id.rawValue.uuidString], in: nil, contentWorld: .page)
        #expect(disabled as? String == "denied")
        await waiter.load(html, baseURL: target, in: webView)
        #expect(try await webView.evaluateJavaScript("typeof window.den") as? String == "undefined")
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidIDsAndOperationFailuresRejectThePromise() async throws {
        // Arrange
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let target = URL(fileURLWithPath: "/tmp/sketch.html")
        let bridge = DenAPIBridge(webView: webView) { _ in
            throw DenAPIBridge.Failure(message: "Board not found")
        }
        defer { bridge.dispose() }
        bridge.setEnabled(true)
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load("<p>Sketch</p>", baseURL: target, in: webView)

        // Act / Assert
        for id in ["invalid", UUID().uuidString] {
            let error =
                try await webView.callAsyncJavaScript(
                    "try { await den.boards.focus(id); return ''; } catch (error) { return String(error); }",
                    arguments: ["id": id], in: nil, contentWorld: .page) as? String
            #expect(error?.contains(id == "invalid" ? "UUID" : "Board not found") == true)
        }
    }
}
