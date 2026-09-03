import AppKit
import Combine
import Foundation
import WebKit

@MainActor
final class BoardRuntime: BaseWebRuntime, ObservableObject {
    struct Events {
        var onChange: (UUID, URL?, String?) -> Void
        var onFullscreenChange: ((UUID, Bool) -> Void)?
        var onLinkActivated: () -> Void = {}
        var onDownloadFinished: (String) -> Void = { _ in }
        var onDownloadFailed: (String) -> Void = { _ in }
    }

    @Published private(set) var faviconURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var estimatedProgress = 0.0
    @Published private(set) var isShowingInitialLoadFallback = false
    @Published private(set) var didTerminateContentProcess = false

    var webProcessIdentifier: pid_t? {
        guard webView.responds(to: NSSelectorFromString("_webProcessIdentifier")) else { return nil }
        let identifier = webView._webProcessIdentifier
        return identifier > 0 ? identifier : nil
    }

    var webProcessIsResponsive: Bool? {
        guard webView.responds(to: NSSelectorFromString("_webProcessIsResponsive")) else { return nil }
        return webView._webProcessIsResponsive
    }

    private var sheetNavigationActions: SheetNavigationManager.Actions
    private var events: Events
    private let sheetNavigation: SheetNavigationManager
    private let webExtensionHost: WebExtensionHost?
    private let webExtensionWindow: MV3WebExtensionWindow?

    private var loadingObservation: NSKeyValueObservation?
    private var progressObservation: NSKeyValueObservation?
    private var fullscreenObservation: NSKeyValueObservation?

    init(
        board: BoardState,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        webExtensionHost: WebExtensionHost? = nil,
        webExtensionWindow: MV3WebExtensionWindow? = nil,
        sheetScale: Int,
        sheetNavigationActions: SheetNavigationManager.Actions,
        events: Events
    ) {
        self.sheetNavigation = sheetNavigation
        self.webExtensionHost = webExtensionHost
        self.webExtensionWindow = webExtensionWindow
        self.sheetNavigationActions = sheetNavigationActions
        self.events = events
        PerformanceTrace.mark("BoardRuntime.init (\(board.id.uuidString.prefix(8)))", category: "Board")

        super.init(
            id: board.id,
            initialURL: webExtensionHost != nil && webExtensionWindow != nil
                ? nil
                : board.currentSheetURL,
            websiteDataStore: websiteDataStore,
            userContentController: sheetNavigation.userContentController,
            webExtensionController: webExtensionHost?.controller,
            sheetScale: sheetScale,
            enableElementFullscreen: true
        )

        Self.configureNativePictureInPicture(preferences: webView.configuration.preferences)

        sheetNavigation.didOpen(
            webView,
            boardID: id,
            paused: board.sheetNavigationPaused,
            actions: sheetNavigationActions
        )
        if let webExtensionHost, let webExtensionWindow {
            webExtensionHost.register(
                webView: webView,
                in: webExtensionWindow,
                initialURL: board.currentSheetURL
            ) { [weak self] url in
                self?.load(url)
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
                self.events.onFullscreenChange?(self.id, isFullscreen)
            }
        }

        if board.currentSheetURL != nil {
            isShowingInitialLoadFallback = true
        }
    }

    func updateOwner(
        sheetNavigationActions: SheetNavigationManager.Actions,
        events: Events
    ) {
        self.sheetNavigationActions = sheetNavigationActions
        self.events = events
        sheetNavigation.updateActions(sheetNavigationActions, for: webView)
    }

    func activateWebExtensionTab() {
        webExtensionHost?.activate(webView: webView)
    }

    private static func configureNativePictureInPicture(
        preferences: WKPreferences
    ) {
        let selector = NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")

        guard preferences.responds(to: selector) else {
            #if DEBUG
                print(
                    "[DenBrowser] Warning: WKPreferences does not respond to _setAllowsPictureInPictureMediaPlayback:"
                )
            #endif
            return
        }

        preferences._allowsPictureInPictureMediaPlayback = true
    }

    override func dispose() {
        webExtensionHost?.unregister(webView: webView)
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

    override func handleLinkActivation(navigationType: WKNavigationType) {
        guard navigationType == .linkActivated else { return }
        events.onLinkActivated()
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
        PerformanceTrace.mark("BoardRuntime.didFinish navigation (\(id.uuidString.prefix(8)))", category: "Board")
        sheetNavigation.refreshConfiguration(for: webView)
        updateFavicon()
    }

    override func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        PerformanceTrace.mark("BoardRuntime.didCommit navigation (\(id.uuidString.prefix(8)))", category: "Board")
        didTerminateContentProcess = false
        guard isShowingInitialLoadFallback else { return }
        DispatchQueue.main.async { [weak self] in
            self?.isShowingInitialLoadFallback = false
        }
    }

    override func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        didTerminateContentProcess = true
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
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
            return nil
        }

        handleLinkActivation(navigationType: navigationAction.navigationType)

        if SheetNavigationPolicy.shouldOpenExternalApplication(
            navigationType: navigationAction.navigationType,
            url: url
        ) {
            NSWorkspace.shared.open(url)
            return nil
        }

        if SheetNavigationPolicy.shouldOpenTargetlessNavigationInNewBoard(
            navigationType: navigationAction.navigationType,
            url: url
        ) {
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

        return makeAuxiliaryWebView(configuration: configuration, sourceWebView: webView)
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
