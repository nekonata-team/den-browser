import Foundation
import WebKit

@MainActor
final class BoardRuntime: NSObject, WKNavigationDelegate {
    let id: UUID
    let webView: WKWebView

    private let onChange: (UUID, URL?, String?) -> Void
    private unowned let sheetNavigation: SheetNavigationManager

    init(
        board: BoardState,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        onOpenBoard: @escaping (URL) -> Void,
        onChange: @escaping (UUID, URL?, String?) -> Void
    ) {
        id = board.id
        self.sheetNavigation = sheetNavigation
        self.onChange = onChange

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        configuration.userContentController = sheetNavigation.userContentController

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true

        super.init()

        webView.navigationDelegate = self
        sheetNavigation.didOpen(webView, onOpenBoard: onOpenBoard)
        if let url = board.currentSheetURL {
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
