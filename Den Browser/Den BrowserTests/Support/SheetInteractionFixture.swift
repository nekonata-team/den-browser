import AppKit
import Foundation
import WebKit

@testable import Den_Browser

@MainActor
final class SheetInteractionWebViewLoadWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var pendingNavigation: WKNavigation?

    func load(_ html: String, baseURL: URL, in webView: WKWebView) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.navigationDelegate = self
            pendingNavigation = webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func load(_ content: String, mimeType: String, baseURL: URL, in webView: WKWebView) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.navigationDelegate = self
            pendingNavigation = webView.load(
                Data(content.utf8),
                mimeType: mimeType,
                characterEncodingName: "utf-8",
                baseURL: baseURL
            )
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === pendingNavigation else { return }
        resume()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard navigation === pendingNavigation else { return }
        resume()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard navigation === pendingNavigation else { return }
        resume()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        resume()
    }

    private func resume() {
        pendingNavigation = nil
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
func makeSheetInteractionWebView() -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    SheetDOMRuntime.install(on: configuration.userContentController)
    return WKWebView(
        frame: NSRect(x: 0, y: 0, width: 800, height: 600),
        configuration: configuration
    )
}
