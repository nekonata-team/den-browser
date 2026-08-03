import AppKit
import Foundation
import WebKit

@MainActor
final class DrawerPreviewRuntime: NSObject, WKNavigationDelegate, WKUIDelegate {
    let id: UUID
    let webView: WKWebView

    private let onChange: (UUID, URL?, String?) -> Void
    private unowned let sheetNavigation: SheetNavigationManager
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?

    init(
        item: DrawerItem,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        sheetScale: Int,
        onKeepInDrawer: @escaping (URL) -> Void,
        onDiscard: @escaping () -> Void,
        onChange: @escaping (UUID, URL?, String?) -> Void
    ) {
        id = item.id
        self.onChange = onChange
        self.sheetNavigation = sheetNavigation

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
                onOpenBoardInBackground: { [weak webView] url in webView?.load(URLRequest(url: url)) },
                onKeepInDrawer: onKeepInDrawer,
                onEditCurrentSheet: {},
                onOpenCurrentSheetInNewBoard: { [weak webView] url in webView?.load(URLRequest(url: url)) },
                onPasteURLInNewBoard: { [weak webView] url in webView?.load(URLRequest(url: url)) },
                onOpenBoardPanel: {},
                onShowOverview: {},
                onRemoveBoard: onDiscard,
                onRestoreBoard: {}
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

    func dispose() {
        sheetNavigation.didClose(webView)
        webView.closeAllMediaPresentations(completionHandler: nil)
        webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        urlObservation?.invalidate()
        titleObservation?.invalidate()
        urlObservation = nil
        titleObservation = nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
            let url = navigationAction.request.url,
            ExternalURLPolicy.isSupported(url)
        {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
            return nil
        }

        if navigationAction.navigationType == .linkActivated,
            ExternalURLPolicy.isSupported(url)
        {
            NSWorkspace.shared.open(url)
        } else if SheetURLPolicy.isSupported(url) {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
