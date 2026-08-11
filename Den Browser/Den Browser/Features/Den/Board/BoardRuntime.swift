import AppKit
import Combine
import Foundation
import WebKit

@MainActor
final class BoardRuntime: BaseWebRuntime, NSWindowDelegate, ObservableObject {
    struct Events {
        var onChange: (UUID, URL?, String?) -> Void
        var onFullscreenChange: ((UUID, Bool) -> Void)?
        var onDownloadFinished: (String) -> Void = { _ in }
        var onDownloadFailed: (String) -> Void = { _ in }
    }

    @Published private(set) var faviconURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var estimatedProgress = 0.0
    @Published private(set) var isShowingInitialLoadFallback = false

    private let sheetNavigationActions: SheetNavigationManager.Actions
    private let events: Events
    private let sheetNavigation: SheetNavigationManager

    private var auxiliaryWindows: [ObjectIdentifier: NSWindow] = [:]
    private var loadingObservation: NSKeyValueObservation?
    private var progressObservation: NSKeyValueObservation?
    private var fullscreenObservation: NSKeyValueObservation?

    init(
        board: BoardState,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        sheetScale: Int,
        nativePictureInPictureEnabled: Bool = false,
        sheetNavigationActions: SheetNavigationManager.Actions,
        events: Events
    ) {
        self.sheetNavigation = sheetNavigation
        self.sheetNavigationActions = sheetNavigationActions
        self.events = events

        super.init(
            id: board.id,
            initialURL: board.currentSheetURL,
            websiteDataStore: websiteDataStore,
            userContentController: sheetNavigation.userContentController,
            sheetScale: sheetScale,
            enableElementFullscreen: true
        )

        Self.configureNativePictureInPicture(
            preferences: webView.configuration.preferences,
            enabled: nativePictureInPictureEnabled
        )

        sheetNavigation.didOpen(
            webView,
            boardID: id,
            paused: board.sheetNavigationPaused,
            actions: sheetNavigationActions
        )

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
                self.events.onFullscreenChange?(self.id, isFullscreen)
            }
        }

        if board.currentSheetURL != nil {
            isShowingInitialLoadFallback = true
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

    override func dispose() {
        for window in auxiliaryWindows.values {
            window.delegate = nil
            window.close()
        }
        auxiliaryWindows.removeAll()
        sheetNavigation.didClose(webView)
        isLoading = false
        estimatedProgress = 0
        isShowingInitialLoadFallback = false
        loadingObservation?.invalidate()
        progressObservation?.invalidate()
        fullscreenObservation?.invalidate()
        loadingObservation = nil
        progressObservation = nil
        fullscreenObservation = nil

        super.dispose()
    }

    override func handleURLOrTitleChange(url: URL?, title: String?) {
        events.onChange(id, url, title)
    }

    override func handleLinkNavigation(
        _ url: URL,
        navigationType: WKNavigationType,
        modifierFlags: NSEvent.ModifierFlags,
        button: MouseButton?,
        opensNewContext: Bool
    ) -> Bool {
        if SheetNavigationPolicy.shouldKeepLinkInDrawer(
            navigationType: navigationType,
            modifierFlags: modifierFlags,
            button: button,
            url: url
        ) {
            sheetNavigationActions.onKeepInDrawer(url)
            return true
        }

        if SheetNavigationPolicy.shouldOpenLinkInNewBoard(
            navigationType: navigationType,
            modifierFlags: modifierFlags,
            button: button,
            url: url
        ) {
            openBoardFromModifierClick(url, modifierFlags: modifierFlags)
            return true
        }

        return false
    }

    private func openBoardFromModifierClick(_ url: URL, modifierFlags: NSEvent.ModifierFlags) {
        if modifierFlags.contains(.shift) {
            sheetNavigationActions.onOpenBoard(url)
        } else {
            sheetNavigationActions.onOpenBoardInBackground(url)
        }
    }

    override func notifyDownloadFinished(filename: String) {
        events.onDownloadFinished(filename)
    }

    override func notifyDownloadFailed(filename: String) {
        events.onDownloadFailed(filename)
    }

    override func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sheetNavigation.refreshConfiguration(for: webView)
        updateFavicon()
    }

    override func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard isShowingInitialLoadFallback else { return }
        DispatchQueue.main.async { [weak self] in
            self?.isShowingInitialLoadFallback = false
        }
    }

    override func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        faviconURL = nil
    }

    override func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isShowingInitialLoadFallback = false
        events.onChange(id, webView.url, webView.title)
    }

    override func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        isShowingInitialLoadFallback = false
        events.onChange(id, webView.url, webView.title)
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

    override func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }

        if SheetNavigationPolicy.shouldOpenExternalApplication(
            navigationType: navigationAction.navigationType,
            url: navigationAction.request.url
        ), let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            return nil
        }

        if let url = navigationAction.request.url,
            SheetNavigationPolicy.shouldOpenTargetlessNavigationInNewBoard(
                navigationType: navigationAction.navigationType,
                url: url
            )
        {
            if SheetNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: navigationAction.navigationType,
                modifierFlags: navigationAction.modifierFlags,
                button: MouseButton(rawValue: navigationAction.buttonNumber),
                url: url
            ) {
                openBoardFromModifierClick(url, modifierFlags: navigationAction.modifierFlags)
            } else {
                sheetNavigationActions.onOpenBoard(url)
            }
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
        let pictureInPictureScript = Self.pictureInPictureJavaScript
        guard !pictureInPictureScript.isEmpty else { return }

        webView.evaluateJavaScript(pictureInPictureScript) { result, error in
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
