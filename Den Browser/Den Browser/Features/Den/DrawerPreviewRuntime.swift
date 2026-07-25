import Foundation
import WebKit

@MainActor
final class DrawerPreviewRuntime: NSObject, WKNavigationDelegate, WKUIDelegate {
    let id: UUID
    let webView: WKWebView

    private let onChange: (UUID, URL?, String?) -> Void
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?

    init(
        item: DrawerItem,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        sheetScale: Int,
        onChange: @escaping (UUID, URL?, String?) -> Void
    ) {
        id = item.id
        self.onChange = onChange

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        configuration.userContentController = sheetNavigation.userContentController
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = BoardRuntime.defaultUserAgent
        webView.pageZoom = CGFloat(sheetScale) / 100
        webView.allowsBackForwardNavigationGestures = true

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        sheetNavigation.didOpen(
            webView,
            actions: .init(
                onOpenBoard: { [weak webView] url in webView?.load(URLRequest(url: url)) },
                onEditCurrentSheet: {},
                onOpenCurrentSheetInNewBoard: { [weak webView] url in webView?.load(URLRequest(url: url)) },
                onPasteURLInNewBoard: { [weak webView] url in webView?.load(URLRequest(url: url)) }
            )
        )

        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onChange(self.id, self.webView.url, self.webView.title)
            }
        }
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onChange(self.id, self.webView.url, self.webView.title)
            }
        }

        webView.load(URLRequest(url: item.url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onChange(id, webView.url, webView.title)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil,
            let url = navigationAction.request.url,
            SheetURLPolicy.isSupported(url)
        {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
