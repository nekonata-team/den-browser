import AppKit
import Combine
import Foundation
import WebKit

@MainActor
final class BoardRuntime: NSObject, NSWindowDelegate, ObservableObject, WKDownloadDelegate,
    WKNavigationDelegate, WKUIDelegate
{
    static var defaultUserAgent: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(os.majorVersion).\(os.minorVersion)"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Version/\(versionString) Safari/605.1.15"
    }

    let id: UUID
    let webView: WKWebView
    @Published private(set) var faviconURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var estimatedProgress = 0.0

    private let onOpenBoard: (URL) -> Void
    private let onOpenBoardInBackground: (URL) -> Void
    private let onKeepInDrawer: (URL) -> Void
    private let onEditCurrentSheet: () -> Void
    private let onOpenCurrentSheetInNewBoard: (URL) -> Void
    private let onPasteURLInNewBoard: (URL) -> Void
    private let onOpenBoardPanel: () -> Void
    private let onShowOverview: () -> Void
    private let onChange: (UUID, URL?, String?) -> Void
    private let onFullscreenChange: ((UUID, Bool) -> Void)?
    private let onDownloadFinished: (String) -> Void
    private let onDownloadFailed: (String) -> Void
    private unowned let sheetNavigation: SheetNavigationManager

    private var downloadFilenames: [ObjectIdentifier: String] = [:]
    private var auxiliaryWindows: [ObjectIdentifier: NSWindow] = [:]
    private var loadingObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var progressObservation: NSKeyValueObservation?
    private var fullscreenObservation: NSKeyValueObservation?

    init(
        board: BoardState,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        sheetScale: Int,
        nativePictureInPictureEnabled: Bool = false,
        onOpenBoard: @escaping (URL) -> Void,
        onOpenBoardInBackground: @escaping (URL) -> Void = { _ in },
        onKeepInDrawer: @escaping (URL) -> Void = { _ in },
        onChange: @escaping (UUID, URL?, String?) -> Void,
        onFullscreenChange: ((UUID, Bool) -> Void)? = nil,
        onEditCurrentSheet: @escaping () -> Void = {},
        onOpenCurrentSheetInNewBoard: @escaping (URL) -> Void = { _ in },
        onPasteURLInNewBoard: @escaping (URL) -> Void = { _ in },
        onOpenBoardPanel: @escaping () -> Void = {},
        onShowOverview: @escaping () -> Void = {},
        onRemoveBoard: @escaping () -> Void = {},
        onRestoreBoard: @escaping () -> Void = {},
        onDownloadFinished: @escaping (String) -> Void = { _ in },
        onDownloadFailed: @escaping (String) -> Void = { _ in }
    ) {
        id = board.id
        self.sheetNavigation = sheetNavigation
        self.onOpenBoard = onOpenBoard
        self.onOpenBoardInBackground = onOpenBoardInBackground
        self.onKeepInDrawer = onKeepInDrawer
        self.onEditCurrentSheet = onEditCurrentSheet
        self.onOpenCurrentSheetInNewBoard = onOpenCurrentSheetInNewBoard
        self.onPasteURLInNewBoard = onPasteURLInNewBoard
        self.onOpenBoardPanel = onOpenBoardPanel
        self.onShowOverview = onShowOverview
        self.onChange = onChange
        self.onFullscreenChange = onFullscreenChange
        self.onDownloadFinished = onDownloadFinished
        self.onDownloadFailed = onDownloadFailed

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        configuration.userContentController = sheetNavigation.userContentController
        configuration.preferences.isElementFullscreenEnabled = true

        Self.configureNativePictureInPicture(
            preferences: configuration.preferences,
            enabled: nativePictureInPictureEnabled
        )

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.defaultUserAgent
        webView.pageZoom = CGFloat(sheetScale) / 100
        webView.allowsBackForwardNavigationGestures = true

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        sheetNavigation.didOpen(
            webView,
            boardID: id,
            actions: .init(
                onOpenBoard: onOpenBoard,
                onOpenBoardInBackground: onOpenBoardInBackground,
                onKeepInDrawer: onKeepInDrawer,
                onEditCurrentSheet: onEditCurrentSheet,
                onOpenCurrentSheetInNewBoard: onOpenCurrentSheetInNewBoard,
                onPasteURLInNewBoard: onPasteURLInNewBoard,
                onOpenBoardPanel: onOpenBoardPanel,
                onShowOverview: onShowOverview,
                onRemoveBoard: onRemoveBoard,
                onRestoreBoard: onRestoreBoard
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

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) {
            [weak self] webView, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.estimatedProgress = webView.estimatedProgress
            }
        }

        loadingObservation = webView.observe(\.isLoading, options: [.initial, .new]) {
            [weak self] webView, _ in
            Task { @MainActor [weak self] in
                self?.isLoading = webView.isLoading
            }
        }

        fullscreenObservation = webView.observe(\.fullscreenState, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let isFullscreen =
                    self.webView.fullscreenState == .inFullscreen
                    || self.webView.fullscreenState == .enteringFullscreen
                self.onFullscreenChange?(self.id, isFullscreen)
            }
        }

        if let url = board.currentSheetURL {
            webView.load(URLRequest(url: url))
        }
    }

    private static func configureNativePictureInPicture(
        preferences: WKPreferences,
        enabled: Bool
    ) {
        guard enabled else {
            return
        }

        let selector = NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")

        guard preferences.responds(to: selector) else {
            #if DEBUG
                print(
                    "[DenBrowser] Warning: nativePictureInPictureEnabled is true, but WKPreferences does not respond to _setAllowsPictureInPictureMediaPlayback:"
                )
            #endif
            return
        }

        preferences._allowsPictureInPictureMediaPlayback = true
    }

    func dispose() {
        for window in auxiliaryWindows.values {
            window.delegate = nil
            window.close()
        }
        auxiliaryWindows.removeAll()
        sheetNavigation.didClose(webView)
        webView.closeAllMediaPresentations(completionHandler: nil)
        webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        webView.stopLoading()
        isLoading = false
        estimatedProgress = 0
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        urlObservation?.invalidate()
        titleObservation?.invalidate()
        loadingObservation?.invalidate()
        progressObservation?.invalidate()
        fullscreenObservation?.invalidate()
        urlObservation = nil
        titleObservation = nil
        loadingObservation = nil
        progressObservation = nil
        fullscreenObservation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sheetNavigation.refreshConfiguration(for: webView)
        updateFavicon()
    }

    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        faviconURL = nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if Self.shouldKeepLinkInDrawer(
            navigationType: navigationAction.navigationType,
            modifierFlags: navigationAction.modifierFlags,
            buttonNumber: navigationAction.buttonNumber,
            url: navigationAction.request.url
        ), let url = navigationAction.request.url {
            onKeepInDrawer(url)
            decisionHandler(.cancel)
            return
        }

        if Self.shouldOpenLinkInNewBoard(
            navigationType: navigationAction.navigationType,
            modifierFlags: navigationAction.modifierFlags,
            buttonNumber: navigationAction.buttonNumber,
            url: navigationAction.request.url
        ), let url = navigationAction.request.url {
            if navigationAction.modifierFlags.contains(.shift) {
                onOpenBoard(url)
            } else {
                onOpenBoardInBackground(url)
            }
            decisionHandler(.cancel)
            return
        }

        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    static func shouldOpenLinkInNewBoard(
        navigationType: WKNavigationType,
        modifierFlags: NSEvent.ModifierFlags,
        buttonNumber: Int,
        url: URL?
    ) -> Bool {
        let clickModifiers = modifierFlags.intersection([.command, .control, .option, .shift])
        return navigationType == .linkActivated
            && buttonNumber == 0
            && (clickModifiers == .command || clickModifiers == [.command, .shift])
            && url.map(SheetURLPolicy.isSupported) == true
    }

    static func shouldKeepLinkInDrawer(
        navigationType: WKNavigationType,
        modifierFlags: NSEvent.ModifierFlags,
        buttonNumber: Int,
        url: URL?
    ) -> Bool {
        let clickModifiers = modifierFlags.intersection([.command, .control, .option, .shift])
        return navigationType == .linkActivated
            && buttonNumber == 0
            && clickModifiers == .option
            && url.map(SheetURLPolicy.isSupported) == true
    }

    static func shouldOpenTargetlessNavigationInNewBoard(
        navigationType: WKNavigationType,
        url: URL?
    ) -> Bool {
        navigationType == .linkActivated
            && url.map(SheetURLPolicy.isSupported) == true
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
                self?.onDownloadFailed(error.localizedDescription)
                completionHandler(nil)
            }
        }

        if let window = webView.window {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            panel.begin(completionHandler: complete)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        let filename = downloadFilenames.removeValue(forKey: ObjectIdentifier(download)) ?? "File"
        onDownloadFinished(filename)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadFilenames.removeValue(forKey: ObjectIdentifier(download))
        onDownloadFailed(error.localizedDescription)
    }

    private func updateFavicon() {
        let sheetURL = webView.url
        let script =
            """
            document.querySelector('link[rel~="icon"][href]')?.href
                ?? new URL('/favicon.ico', document.baseURI).href
            """

        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self,
                self.webView.url == sheetURL,
                let value = result as? String
            else {
                return
            }
            self.faviconURL = URL(string: value)
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }

        if Self.shouldOpenTargetlessNavigationInNewBoard(
            navigationType: navigationAction.navigationType,
            url: navigationAction.request.url
        ), let url = navigationAction.request.url {
            onOpenBoard(url)
            return nil
        }

        let auxiliaryWebView = WKWebView(frame: .zero, configuration: configuration)
        auxiliaryWebView.customUserAgent = Self.defaultUserAgent
        auxiliaryWebView.pageZoom = webView.pageZoom
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
        guard let window = webView.window else {
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

    func togglePictureInPicture() {
        let js = Self.pictureInPictureJavaScript
        guard !js.isEmpty else { return }

        webView.evaluateJavaScript(js) { result, error in
            #if DEBUG
                if let error {
                    print("[DenBrowser] PiP script error: \(error.localizedDescription)")
                } else if let result {
                    print("[DenBrowser] PiP script success: \(result)")
                }
            #endif
        }
    }

    private static let pictureInPictureJavaScript: String = {
        guard
            let url = Bundle.main.url(forResource: "PictureInPicture", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return source
    }()
}
