import AppKit
import Foundation
import WebKit

@MainActor
final class DrawerPreviewRuntime: BaseWebRuntime {
    private let onChange: (UUID, URL?, String?) -> Void
    private let onKeepInDrawer: (URL) -> Void
    private let onKeepInDrawerInBackground: (URL) -> Void
    private let onDiscard: () -> Void
    private let onCopyURLSucceeded: () -> Void
    private let onCopyURLFailed: () -> Void
    private let onPasteURLFailed: () -> Void
    private let onDownloadFinished: (String) -> Void
    private let onDownloadFailed: (String) -> Void
    private unowned let sheetNavigation: SheetNavigationManager
    private let webExtensionHost: MV3WebExtensionHost?
    private let webExtensionWindow: MV3WebExtensionWindow?

    init(
        item: DrawerItem,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        webExtensionHost: MV3WebExtensionHost? = nil,
        webExtensionWindow: MV3WebExtensionWindow? = nil,
        sheetScale: Int,
        onKeepInDrawer: @escaping (URL) -> Void,
        onKeepInDrawerInBackground: @escaping (URL) -> Void,
        onDiscard: @escaping () -> Void,
        onChange: @escaping (UUID, URL?, String?) -> Void,
        onCopyURLSucceeded: @escaping () -> Void = {},
        onCopyURLFailed: @escaping () -> Void = {},
        onPasteURLFailed: @escaping () -> Void = {},
        onDownloadFinished: @escaping (String) -> Void,
        onDownloadFailed: @escaping (String) -> Void
    ) {
        self.onChange = onChange
        self.onKeepInDrawer = onKeepInDrawer
        self.onKeepInDrawerInBackground = onKeepInDrawerInBackground
        self.onDiscard = onDiscard
        self.onCopyURLSucceeded = onCopyURLSucceeded
        self.onCopyURLFailed = onCopyURLFailed
        self.onPasteURLFailed = onPasteURLFailed
        self.onDownloadFinished = onDownloadFinished
        self.onDownloadFailed = onDownloadFailed
        self.sheetNavigation = sheetNavigation
        self.webExtensionHost = webExtensionHost
        self.webExtensionWindow = webExtensionWindow

        super.init(
            id: item.id,
            initialURL: webExtensionHost != nil && webExtensionWindow != nil ? nil : item.url,
            websiteDataStore: websiteDataStore,
            userContentController: sheetNavigation.userContentController,
            webExtensionController: webExtensionHost?.controller,
            sheetScale: sheetScale,
            enableElementFullscreen: false
        )
        if let webExtensionHost, let webExtensionWindow {
            webExtensionHost.register(runtime: self, in: webExtensionWindow)
            webExtensionHost.loadInitialURL(item.url, for: self)
        }

        sheetNavigation.didOpen(
            webView,
            actions: .init(
                onOpenBoard: { [weak self] url in self?.onKeepInDrawer(url) },
                onOpenBoardInBackground: { [weak self] url in self?.onKeepInDrawerInBackground(url) },
                onKeepInDrawer: { [weak self] url in self?.onKeepInDrawer(url) },
                onOpenCurrentSheetInNewBoard: { [weak self] url in self?.onKeepInDrawer(url) },
                onPasteURLInNewBoard: { [weak self] url in self?.onKeepInDrawer(url) },
                onCopyURLSucceeded: { [weak self] in self?.onCopyURLSucceeded() },
                onCopyURLFailed: { [weak self] in self?.onCopyURLFailed() },
                onPasteURLFailed: { [weak self] in self?.onPasteURLFailed() },
                onRemoveBoard: { [weak self] in self?.onDiscard() },
                isSupportedSheetURL: SheetURLPolicy.isSupported,
                onNavigateCurrentSheet: { [weak self] url in self?.load(url) }
            )
        )
    }

    override func dispose() {
        webExtensionHost?.unregister(runtime: self)
        sheetNavigation.didClose(webView)
        super.dispose()
    }

    override func handleURLOrTitleChange(url: URL?, title: String?) {
        onChange(id, url, title)
    }

    override func handleLinkNavigation(
        _ url: URL,
        navigationType: WKNavigationType,
        modifierFlags: NSEvent.ModifierFlags,
        button: MouseButton?,
        opensNewContext: Bool
    ) -> Bool {
        if SheetNavigationPolicy.shouldOpenLinkInNewBoard(
            navigationType: navigationType,
            modifierFlags: modifierFlags,
            button: button,
            url: url
        ) {
            if modifierFlags.contains(.shift) {
                onKeepInDrawer(url)
            } else {
                onKeepInDrawerInBackground(url)
            }
            return true
        }

        if (opensNewContext && navigationType == .linkActivated)
            || SheetNavigationPolicy.shouldKeepLinkInDrawer(
                navigationType: navigationType,
                modifierFlags: modifierFlags,
                button: button,
                url: url
            )
        {
            onKeepInDrawer(url)
            return true
        }
        return false
    }

    override func notifyDownloadFinished(filename: String) {
        onDownloadFinished(filename)
    }

    override func notifyDownloadFailed(filename: String) {
        onDownloadFailed(filename)
    }
}
