import AppKit
import Foundation
import WebKit

@MainActor
final class BoardRuntime: NSObject, WKNavigationDelegate, WKUIDelegate {
    let id: UUID
    let webView: WKWebView

    private let onOpenBoard: (URL) -> Void
    private let onEditCurrentSheet: () -> Void
    private let onOpenCurrentSheetInNewBoard: (URL) -> Void
    private let onPasteURLInNewBoard: (URL) -> Void
    private let onChange: (UUID, URL?, String?) -> Void
    private let onFullscreenChange: ((UUID, Bool) -> Void)?
    private unowned let sheetNavigation: SheetNavigationManager

    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var fullscreenObservation: NSKeyValueObservation?

    init(
        board: BoardState,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        sheetScale: Int,
        nativePictureInPictureEnabled: Bool = false,
        onOpenBoard: @escaping (URL) -> Void,
        onChange: @escaping (UUID, URL?, String?) -> Void,
        onFullscreenChange: ((UUID, Bool) -> Void)? = nil,
        onEditCurrentSheet: @escaping () -> Void = {},
        onOpenCurrentSheetInNewBoard: @escaping (URL) -> Void = { _ in },
        onPasteURLInNewBoard: @escaping (URL) -> Void = { _ in }
    ) {
        id = board.id
        self.sheetNavigation = sheetNavigation
        self.onOpenBoard = onOpenBoard
        self.onEditCurrentSheet = onEditCurrentSheet
        self.onOpenCurrentSheetInNewBoard = onOpenCurrentSheetInNewBoard
        self.onPasteURLInNewBoard = onPasteURLInNewBoard
        self.onChange = onChange
        self.onFullscreenChange = onFullscreenChange

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        configuration.userContentController = sheetNavigation.userContentController
        configuration.preferences.isElementFullscreenEnabled = true

        Self.configureNativePictureInPicture(
            preferences: configuration.preferences,
            enabled: nativePictureInPictureEnabled
        )

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.pageZoom = CGFloat(sheetScale) / 100
        webView.allowsBackForwardNavigationGestures = true

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        sheetNavigation.didOpen(
            webView,
            actions: .init(
                onOpenBoard: onOpenBoard,
                onEditCurrentSheet: onEditCurrentSheet,
                onOpenCurrentSheetInNewBoard: onOpenCurrentSheetInNewBoard,
                onPasteURLInNewBoard: onPasteURLInNewBoard
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

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        onChange(id, webView.url, webView.title)
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
            onOpenBoard(url)
        }
        return nil
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
        let js = """
            (async () => {
                const videos = Array.from(document.querySelectorAll("video"));

                const video =
                    videos.find(video =>
                        !video.paused &&
                        !video.ended &&
                        video.readyState >= 2
                    ) ??
                    videos.sort((a, b) =>
                        (b.clientWidth * b.clientHeight) -
                        (a.clientWidth * a.clientHeight)
                    )[0];

                if (!video) {
                    throw new Error("NO_VIDEO");
                }

                if (document.pictureInPictureElement) {
                    await document.exitPictureInPicture();
                    return "exited";
                }

                if (
                    document.pictureInPictureEnabled &&
                    typeof video.requestPictureInPicture === "function"
                ) {
                    await video.requestPictureInPicture();
                    return "entered-standard";
                }

                if (
                    typeof video.webkitSupportsPresentationMode === "function" &&
                    video.webkitSupportsPresentationMode("picture-in-picture") &&
                    typeof video.webkitSetPresentationMode === "function"
                ) {
                    video.webkitSetPresentationMode("picture-in-picture");
                    return "entered-webkit";
                }

                throw new Error("PIP_UNSUPPORTED");
            })();
            """

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
}
