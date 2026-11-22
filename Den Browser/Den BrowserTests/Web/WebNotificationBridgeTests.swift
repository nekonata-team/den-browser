import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
struct WebNotificationBridgeTests {
    @Test(.timeLimit(.minutes(1)))
    func forwardsWindowNotificationAndRoutesByWebView() async throws {
        // Arrange
        let controller = WKUserContentController()
        let firstConfig = WKWebViewConfiguration()
        firstConfig.websiteDataStore = .nonPersistent()
        firstConfig.userContentController = controller
        let secondConfig = WKWebViewConfiguration()
        secondConfig.websiteDataStore = .nonPersistent()
        secondConfig.userContentController = controller

        let first = WKWebView(frame: .zero, configuration: firstConfig)
        let second = WKWebView(frame: .zero, configuration: secondConfig)

        var firstReceived: [(String?, String)] = []
        var secondReceived: [(String?, String)] = []
        let firstBridge = WebNotificationBridge(webView: first) { title, body in
            firstReceived.append((title, body))
        }
        let secondBridge = WebNotificationBridge(webView: second) { title, body in
            secondReceived.append((title, body))
        }
        defer {
            firstBridge.dispose()
            secondBridge.dispose()
        }

        let waiter = SheetInteractionWebViewLoadWaiter()
        let baseURL = URL(string: "https://example.com/")!
        await waiter.load("<p>First</p>", baseURL: baseURL, in: first)
        await waiter.load("<p>Second</p>", baseURL: baseURL, in: second)

        // Act
        let permission =
            try await first.callAsyncJavaScript(
                "return await window.Notification.requestPermission();",
                in: nil,
                contentWorld: .page
            ) as? String
        _ = try await first.callAsyncJavaScript(
            "new window.Notification('ChatGPT', { body: 'Done' });",
            in: nil,
            contentWorld: .page
        )
        _ = try await second.callAsyncJavaScript(
            "new window.Notification('Other', { body: 'Ping' });",
            in: nil,
            contentWorld: .page
        )

        // Allow WKScriptMessageHandler delivery on main run loop.
        for _ in 0..<20 where firstReceived.isEmpty || secondReceived.isEmpty {
            try await Task.sleep(for: .milliseconds(25))
        }

        // Assert
        #expect(permission == "granted")
        #expect(firstReceived.count == 1)
        #expect(firstReceived.first?.0 == "ChatGPT")
        #expect(firstReceived.first?.1 == "Done")
        #expect(secondReceived.count == 1)
        #expect(secondReceived.first?.0 == "Other")
        #expect(secondReceived.first?.1 == "Ping")
    }
}
