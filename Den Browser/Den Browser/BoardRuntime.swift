import Foundation
import WebKit

@MainActor
final class BoardRuntime: NSObject, WKNavigationDelegate {
    let id: UUID
    let webView: WKWebView

    private let onChange: (UUID, URL?, String?) -> Void

    init(board: BoardState, onChange: @escaping (UUID, URL?, String?) -> Void) {
        id = board.id
        self.onChange = onChange

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true

        super.init()

        webView.navigationDelegate = self
        if let url = URL(string: board.currentURLString) {
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        onChange(id, webView.url, webView.title)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onChange(id, webView.url, webView.title)
    }
}
