import AppKit
import Foundation
import WebKit

@MainActor
final class DrawerPreviewRuntime: BaseWebRuntime {
    private let onChange: (UUID, URL?, String?) -> Void
    private let onKeepInDrawer: (URL) -> Void
    private let onKeepInDrawerInBackground: (URL) -> Void
    private let onDiscard: () -> Void
    private let onDownloadFinished: (String) -> Void
    private let onDownloadFailed: (String) -> Void
    private unowned let sheetNavigation: SheetNavigationManager

    init(
        item: DrawerItem,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        sheetScale: Int,
        onKeepInDrawer: @escaping (URL) -> Void,
        onKeepInDrawerInBackground: @escaping (URL) -> Void,
        onDiscard: @escaping () -> Void,
        onChange: @escaping (UUID, URL?, String?) -> Void,
        onDownloadFinished: @escaping (String) -> Void,
        onDownloadFailed: @escaping (String) -> Void
    ) {
        self.onChange = onChange
        self.onKeepInDrawer = onKeepInDrawer
        self.onKeepInDrawerInBackground = onKeepInDrawerInBackground
        self.onDiscard = onDiscard
        self.onDownloadFinished = onDownloadFinished
        self.onDownloadFailed = onDownloadFailed
        self.sheetNavigation = sheetNavigation

        super.init(
            id: item.id,
            initialURL: item.url,
            websiteDataStore: websiteDataStore,
            userContentController: sheetNavigation.userContentController,
            sheetScale: sheetScale,
            enableElementFullscreen: false
        )

        sheetNavigation.didOpen(
            webView,
            actions: .init(
                onOpenBoard: { [weak self] url in self?.onKeepInDrawer(url) },
                onOpenBoardInBackground: { [weak self] url in self?.onKeepInDrawerInBackground(url) },
                onKeepInDrawer: { [weak self] url in self?.onKeepInDrawer(url) },
                onOpenCurrentSheetInNewBoard: { [weak self] url in self?.onKeepInDrawer(url) },
                onPasteURLInNewBoard: { [weak self] url in self?.onKeepInDrawer(url) },
                onRemoveBoard: { [weak self] in self?.onDiscard() },
                isSupportedSheetURL: SheetURLPolicy.isSupported,
                onNavigateCurrentSheet: { [weak self] url in self?.load(url) }
            )
        )
    }

    override func dispose() {
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
        buttonNumber: Int,
        opensNewContext: Bool
    ) -> Bool {
        if SheetNavigationPolicy.shouldOpenLinkInNewBoard(
            navigationType: navigationType,
            modifierFlags: modifierFlags,
            buttonNumber: buttonNumber,
            url: url
        ) {
            if modifierFlags.contains(.shift) {
                onKeepInDrawer(url)
            } else {
                onKeepInDrawerInBackground(url)
            }
            return true
        }

        if opensNewContext
            || SheetNavigationPolicy.shouldKeepLinkInDrawer(
                navigationType: navigationType,
                modifierFlags: modifierFlags,
                buttonNumber: buttonNumber,
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
