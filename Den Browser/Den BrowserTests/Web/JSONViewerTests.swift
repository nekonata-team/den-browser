import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct JSONViewerTests {
    @Test func formatsApplicationJsonAndRecoversLatin1Mojibake() async throws {
        // Arrange
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        JSONViewerRuntime.install(on: configuration.userContentController)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let delegate = NavigationCompletionDelegate()
        webView.navigationDelegate = delegate

        let jsonData = Data(#"{"title":"日本語テスト","items":[1,true,null]}"#.utf8)

        // Act
        webView.load(
            jsonData,
            mimeType: "application/json",
            characterEncodingName: "iso-8859-1",
            baseURL: URL(string: "https://example.com/api.json")!
        )
        try await delegate.waitForFinish()

        // Assert
        let result =
            try await webView.evaluateJavaScript(
                """
                (() => {
                    const root = document.getElementById('den-json-viewer-root');
                    const str = root?.querySelector('.jv-str')?.textContent ?? '';
                    const pre = document.body.querySelector(':scope > pre')?.textContent ?? '';
                    const detailsCount = root?.querySelectorAll('details.jv-node').length ?? 0;
                    return { hasRoot: Boolean(root), str, pre, detailsCount };
                })()
                """
            ) as? [String: Any]

        #expect(result?["hasRoot"] as? Bool == true)
        #expect(result?["str"] as? String == #""日本語テスト""#)
        #expect((result?["pre"] as? String)?.contains("日本語テスト") == true)
        #expect(result?["detailsCount"] as? Int == 2)
    }

    @Test func loadsLocalJsonFileAsUtf8WithoutMojibake() async throws {
        // Arrange
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        JSONViewerRuntime.install(on: configuration.userContentController)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let delegate = NavigationCompletionDelegate()
        webView.navigationDelegate = delegate

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("den-json-viewer-\(UUID().uuidString).json")
        let jsonText = #"{"summary":"日本語テスト","timeline":[{"speaker":"test"}]}"#
        try Data(jsonText.utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Act
        webView.loadSheetURL(tempURL)
        try await delegate.waitForFinish()

        // Assert
        let str =
            try await webView.evaluateJavaScript(
                "document.getElementById('den-json-viewer-root')?.querySelector('.jv-str')?.textContent"
            ) as? String
        #expect(str == #""日本語テスト""#)
        #expect(webView.url == tempURL)
    }

    @Test func ignoresHtmlDocuments() async throws {
        // Arrange
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        JSONViewerRuntime.install(on: configuration.userContentController)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let delegate = NavigationCompletionDelegate()
        webView.navigationDelegate = delegate

        // Act
        webView.loadHTMLString(
            #"<html><body><pre>{"ok":true}</pre></body></html>"#,
            baseURL: URL(string: "https://example.com/page.html")!
        )
        try await delegate.waitForFinish()

        // Assert
        let hasRoot =
            try await webView.evaluateJavaScript(
                "Boolean(document.getElementById('den-json-viewer-root'))"
            ) as? Bool
        #expect(hasRoot == false)
    }
}

@MainActor
private final class NavigationCompletionDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForFinish() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
