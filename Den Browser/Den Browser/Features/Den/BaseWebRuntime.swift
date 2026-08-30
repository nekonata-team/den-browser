import AppKit
import Foundation
import WebKit

enum MouseButton: Int {
    case primary = 0
    case middle = 4
}

@MainActor
class BaseWebRuntime: NSObject, NSWindowDelegate, WKDownloadDelegate, WKNavigationDelegate, WKUIDelegate {
    static var defaultUserAgent: String {
        let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(operatingSystemVersion.majorVersion).\(operatingSystemVersion.minorVersion)"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Version/\(versionString) Safari/605.1.15"
    }

    let id: UUID
    let webView: WKWebView

    private var auxiliaryWindows: [ObjectIdentifier: NSWindow] = [:]
    private var downloadFilenames: [ObjectIdentifier: String] = [:]
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?

    init(
        id: UUID,
        initialURL: URL?,
        websiteDataStore: WKWebsiteDataStore,
        userContentController: WKUserContentController?,
        webExtensionController: WKWebExtensionController? = nil,
        sheetScale: Int,
        enableElementFullscreen: Bool = true
    ) {
        self.id = id

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        if let userContentController {
            configuration.userContentController = userContentController
        }
        configuration.webExtensionController = webExtensionController
        configuration.preferences.isElementFullscreenEnabled = enableElementFullscreen

        webView = WKWebView(frame: .zero, configuration: configuration)
        let fallbackColor = DenSurfaceColors.webViewFallbackBackground
        webView.underPageBackgroundColor = NSColor(
            calibratedRed: fallbackColor.red,
            green: fallbackColor.green,
            blue: fallbackColor.blue,
            alpha: 1
        )
        webView.customUserAgent = Self.defaultUserAgent
        webView.pageZoom = CGFloat(sheetScale) / 100
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

        if let initialURL {
            load(initialURL)
        }
    }

    @discardableResult
    func load(_ url: URL) -> WKNavigation? {
        webView.loadSheetURL(url)
    }

    func dispose() {
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
        return false
    }

    func notifyDownloadFinished(filename: String) {
        // Overridden by subclasses
    }

    func notifyDownloadFailed(filename: String) {
        // Overridden by subclasses
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {}
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {}
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {}

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
        download.delegate = self
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    // WebKit creates downloads from its macOS context menu outside the public navigation callbacks.
    @objc(_webView:contextMenuDidCreateDownload:)
    func webView(_ webView: WKWebView, contextMenuDidCreate download: WKDownload) {
        download.delegate = self
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
        } else if SheetURLPolicy.isSupported(url) {
            if !handleLinkNavigation(
                url,
                navigationType: navigationAction.navigationType,
                modifierFlags: navigationAction.modifierFlags,
                button: MouseButton(rawValue: navigationAction.buttonNumber),
                opensNewContext: true
            ) {
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

        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = auxiliaryWebView
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        auxiliaryWindows[ObjectIdentifier(auxiliaryWebView)] = window
        return auxiliaryWebView
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let window = auxiliaryWindows.removeValue(forKey: ObjectIdentifier(webView)) else {
            return
        }
        window.delegate = nil
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        auxiliaryWindows = auxiliaryWindows.filter { $0.value !== window }
    }

    // MARK: - WKDownloadDelegate

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename

        let complete: @MainActor @Sendable (NSApplication.ModalResponse) -> Void = {
            [weak self] response in
            guard response == .OK, let destination = panel.url else {
                completionHandler(nil)
                return
            }

            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                self?.downloadFilenames[ObjectIdentifier(download)] = destination.lastPathComponent
                completionHandler(destination)
            } catch {
                completionHandler(nil)
            }
        }

        if let window = webView.window ?? NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            panel.begin(completionHandler: complete)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        let filename = downloadFilenames.removeValue(forKey: ObjectIdentifier(download)) ?? "file"
        notifyDownloadFinished(filename: filename)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let filename = downloadFilenames.removeValue(forKey: ObjectIdentifier(download)) ?? "file"
        notifyDownloadFailed(filename: filename)
    }
}
