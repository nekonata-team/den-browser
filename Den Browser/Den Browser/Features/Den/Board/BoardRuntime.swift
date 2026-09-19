import AppKit
import Combine
import Foundation
import WebKit

final class BoardWKWebView: WKWebView {
    var isFocusAllowed: () -> Bool = { false }
    var onUserInteraction: (() -> Void)?
    var onRejectedFocus: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onUserInteraction?()
        super.mouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        onUserInteraction?()
        super.otherMouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onUserInteraction?()
        super.rightMouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        guard isFocusAllowed() else {
            onRejectedFocus?()
            return false
        }
        return super.becomeFirstResponder()
    }
}

@MainActor
final class BoardRuntime: BaseWebRuntime, ObservableObject {
    struct Events {
        var onChange: (UUID, URL?, String?) -> Void
        var onFullscreenChange: ((UUID, Bool) -> Void)?
        var onLinkActivated: () -> Void = {}
        var onDownloadFinished: (String) -> Void = { _ in }
        var onDownloadFailed: (String) -> Void = { _ in }
        var onFocus: () -> Void = {}
        var isFocused: () -> Bool = { false }
        var restoreFocusedFirstResponder: () -> Void = {}
    }

    struct ActionHighlight: Equatable {
        let id = UUID()
        let rect: CGRect
    }

    @Published private(set) var faviconURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var estimatedProgress = 0.0
    @Published private(set) var isShowingInitialLoadFallback = false
    @Published private(set) var didTerminateContentProcess = false
    @Published private(set) var actionHighlight: ActionHighlight?
    private var actionHighlightTask: Task<Void, Never>?

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
            enableElementFullscreen: true,
            makeWebView: { configuration in
                BoardWKWebView(frame: .zero, configuration: configuration)
            }
        )
        webView.allowsMagnification = true

        if let boardWebView = webView as? BoardWKWebView {
            boardWebView.isFocusAllowed = { [weak self] in
                self?.events.isFocused() ?? false
            }
            boardWebView.onUserInteraction = { [weak self] in
                self?.events.onFocus()
            }
            boardWebView.onRejectedFocus = { [weak self] in
                self?.events.restoreFocusedFirstResponder()
            }
        }

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
        if let boardWebView = webView as? BoardWKWebView {
            boardWebView.isFocusAllowed = { [weak self] in
                self?.events.isFocused() ?? false
            }
            boardWebView.onUserInteraction = { [weak self] in
                self?.events.onFocus()
            }
            boardWebView.onRejectedFocus = { [weak self] in
                self?.events.restoreFocusedFirstResponder()
            }
        }
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

    func triggerActionHighlight(_ rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        actionHighlightTask?.cancel()
        actionHighlight = ActionHighlight(rect: rect)
        actionHighlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.actionHighlight = nil
        }
    }

    override func dispose() {
        actionHighlightTask?.cancel()
        actionHighlightTask = nil
        actionHighlight = nil
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

    func togglePictureInPicture() {
        evaluatePictureInPicture(mode: "toggle")
    }

    func enterPictureInPictureIfPlaying() {
        evaluatePictureInPicture(mode: "enter")
    }

    private func evaluatePictureInPicture(mode: String) {
        let pictureInPictureScript = Self.pictureInPictureJavaScript(mode: mode)
        guard !pictureInPictureScript.isEmpty else { return }

        webView.evaluateJavaScript(pictureInPictureScript) { result, error in
            #if DEBUG
                if let error {
                    print("[DenBrowser] PiP \(mode) script error: \(error.localizedDescription)")
                } else if let result {
                    print("[DenBrowser] PiP \(mode) script success: \(result)")
                }
            #endif
        }
    }

    private static func pictureInPictureJavaScript(mode: String) -> String {
        pictureInPictureSource.replacingOccurrences(
            of: "__DEN_PICTURE_IN_PICTURE_MODE__",
            with: mode)
    }

    private static let pictureInPictureSource: String = {
        guard
            let url = Bundle.main.url(forResource: "PictureInPicture", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return source
    }()
}
