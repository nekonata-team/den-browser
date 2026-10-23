import AppKit
import DenDomain
import Foundation
import WebKit

@MainActor
class BaseWebRuntime: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    static var defaultUserAgent: String {
        let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(operatingSystemVersion.majorVersion).\(operatingSystemVersion.minorVersion)"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Version/\(versionString) Safari/605.1.15"
    }

    let id: UUID
    let webView: WKWebView
    let downloadHandler: DownloadHandler

    private var auxiliaryWindows: [ObjectIdentifier: NSWindow] = [:]
    private var authenticationPrompts: [HTTPBasicAuthenticationPrompt] = []
    var auxiliaryWindowFactory: (NSRect) -> NSWindow = { contentRect in
        NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
    }
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?

    init(
        id: UUID,
        initialURL: URL?,
        websiteDataStore: WKWebsiteDataStore,
        userContentController: WKUserContentController?,
        webExtensionController: WKWebExtensionController? = nil,
        sheetScale: Int,
        enableElementFullscreen: Bool = true,
        existingWebView: WKWebView? = nil,
        makeWebView: ((WKWebViewConfiguration) -> WKWebView)? = nil
    ) {
        self.id = id

        let webView: WKWebView
        if let existingWebView {
            webView = existingWebView
        } else {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = websiteDataStore
            if let userContentController {
                configuration.userContentController = userContentController
            }
            configuration.webExtensionController = webExtensionController
            configuration.preferences.isElementFullscreenEnabled = enableElementFullscreen
            webView = makeWebView?(configuration) ?? WKWebView(frame: .zero, configuration: configuration)
        }
        self.webView = webView
        downloadHandler = DownloadHandler(webView: webView)
        webView.customUserAgent = Self.defaultUserAgent
        if existingWebView == nil {
            webView.pageZoom = CGFloat(sheetScale) / 100
        }
        webView.allowsBackForwardNavigationGestures = true

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self

        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleURLOrTitleChange(url: self.webView.url, title: self.webView.title)
            }
        }
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleURLOrTitleChange(url: self.webView.url, title: self.webView.title)
            }
        }

        if existingWebView == nil, let initialURL {
            load(initialURL)
        }
    }

    @discardableResult
    func load(_ url: URL) -> WKNavigation? {
        webView.loadSheetURL(url)
    }

    func dispose() {
        let prompts = authenticationPrompts
        authenticationPrompts.removeAll()
        for prompt in prompts { prompt.finish(nil) }
        downloadHandler.dispose()
        for window in Array(auxiliaryWindows.values) {
            window.delegate = nil
            window.close()
        }
        auxiliaryWindows.removeAll()
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

    // MARK: - Hooks for Subclasses

    func handleURLOrTitleChange(url: URL?, title: String?) {
        // Overridden by subclasses
    }

    func handleLinkNavigation(
        _ url: URL,
        navigationType: WKNavigationType,
        modifierFlags: NSEvent.ModifierFlags,
        button: MouseButton?,
        opensNewContext: Bool
    ) -> Bool {
        // Overridden by subclasses if needed. Return true if handled.
        false
    }

    func handleLinkActivation(navigationType: WKNavigationType) {
        // Overridden by subclasses when link activation affects Board state.
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {}
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        cancelAuthentication(for: webView)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        cancelAuthentication(for: webView)
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        requestHTTPBasicCredential(for: challenge, in: webView) { credential in
            completionHandler(credential == nil ? .cancelAuthenticationChallenge : .useCredential, credential)
        }
    }

    func requestHTTPBasicCredential(
        for challenge: URLAuthenticationChallenge, in webView: WKWebView,
        completion: @escaping @MainActor (URLCredential?) -> Void
    ) {
        let id = UUID()
        let prompt = HTTPBasicAuthenticationPrompt(id: id, challenge: challenge, webView: webView) {
            [weak self] credential in
            self?.authenticationPrompts.removeAll { $0.id == id }
            completion(credential)
            DispatchQueue.main.async { [weak self] in self?.authenticationPrompts.first?.present() }
        }
        authenticationPrompts.append(prompt)
        authenticationPrompts.first?.present()
    }

    private func cancelAuthentication(for webView: WKWebView) {
        for prompt in authenticationPrompts.filter({ $0.webView === webView }) { prompt.finish(nil) }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }

        if navigationAction.navigationType == .linkActivated || navigationAction.navigationType == .other,
            ExternalURLPolicy.isSupported(url)
        {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        if handleLinkNavigation(
            url,
            navigationType: navigationAction.navigationType,
            modifierFlags: navigationAction.modifierFlags,
            button: MouseButton(rawValue: navigationAction.buttonNumber),
            opensNewContext: navigationAction.targetFrame == nil
        ) {
            decisionHandler(.cancel)
            return
        }

        handleLinkActivation(navigationType: navigationAction.navigationType)
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        download.delegate = downloadHandler
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = downloadHandler
    }

    // WebKit creates downloads from its macOS context menu outside the public navigation callbacks.
    @objc(_webView:contextMenuDidCreateDownload:)
    func webView(_ webView: WKWebView, contextMenuDidCreate download: WKDownload) {
        download.delegate = downloadHandler
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
            return nil
        }

        if navigationAction.shouldPerformDownload {
            load(url)
        } else if navigationAction.navigationType == .linkActivated,
            ExternalURLPolicy.isSupported(url)
        {
            NSWorkspace.shared.open(url)
        } else if WebURLPolicy.isSupported(url) {
            if !handleLinkNavigation(
                url,
                navigationType: navigationAction.navigationType,
                modifierFlags: navigationAction.modifierFlags,
                button: MouseButton(rawValue: navigationAction.buttonNumber),
                opensNewContext: true
            ) {
                handleLinkActivation(navigationType: navigationAction.navigationType)
                return makeAuxiliaryWebView(configuration: configuration, sourceWebView: webView)
            }
        } else {
            return makeAuxiliaryWebView(configuration: configuration, sourceWebView: webView)
        }
        return nil
    }

    func makeAuxiliaryWebView(
        configuration: WKWebViewConfiguration,
        sourceWebView: WKWebView
    ) -> WKWebView {
        let auxiliaryWebView = WKWebView(frame: .zero, configuration: configuration)
        auxiliaryWebView.customUserAgent = Self.defaultUserAgent
        auxiliaryWebView.pageZoom = sourceWebView.pageZoom
        auxiliaryWebView.uiDelegate = self
        auxiliaryWebView.navigationDelegate = self

        let window = auxiliaryWindowFactory(.init(x: 0, y: 0, width: 720, height: 640))
        window.contentView = auxiliaryWebView
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        auxiliaryWindows[ObjectIdentifier(auxiliaryWebView)] = window
        return auxiliaryWebView
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "Alert"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "Confirmation"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let input = NSTextField(string: defaultText ?? "")
        input.frame.size.width = 320

        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "Prompt"
        alert.informativeText = prompt
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = input
        completionHandler(
            alert.runModal() == .alertFirstButtonReturn
                ? input.stringValue
                : nil
        )
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        guard let window = webView.window ?? NSApp.keyWindow else {
            completionHandler(nil)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = !parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func webViewDidClose(_ webView: WKWebView) {
        cancelAuthentication(for: webView)
        if let window = auxiliaryWindows.removeValue(forKey: ObjectIdentifier(webView)) {
            window.delegate = nil
            window.close()
            return
        }
        handleWebViewDidClose(webView)
    }

    func handleWebViewDidClose(_ webView: WKWebView) {}

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        for prompt in authenticationPrompts.filter({ $0.webView?.window === window }) { prompt.finish(nil) }
        auxiliaryWindows = auxiliaryWindows.filter { $0.value !== window }
    }
}
