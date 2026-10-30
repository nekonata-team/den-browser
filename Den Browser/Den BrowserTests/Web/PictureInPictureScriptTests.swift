import Foundation
import Testing
import WebKit

@MainActor
struct PictureInPictureScriptTests {
    @Test func bundledScriptReturnsItsAsyncResultWithTheNativeCallPattern() async throws {
        // Arrange
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            "<html><body>No videos</body></html>", baseURL: URL(string: "https://example.com/")!, in: webView)
        let url = try #require(Bundle.main.url(forResource: "PictureInPicture", withExtension: "js"))
        let source = try String(contentsOf: url, encoding: .utf8)

        // Act
        let result = try await webView.callAsyncJavaScript(
            "\(source)\nreturn await denPictureInPicture.run(mode);", arguments: ["mode": "enter"], in: nil,
            contentWorld: .page)

        // Assert
        #expect(result as? String == "no-playing-video")
    }
}
