import DenDomain
import Foundation
import WebKit

extension WebRuntime {
    convenience init(
        item: DrawerItem,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        webExtensionHost: WebExtensionHost? = nil,
        webExtensionWindow: MV3WebExtensionWindow? = nil,
        sheetScale: Int,
        onKeepInDrawer: @escaping (URL) -> Void,
        onKeepInDrawerInBackground: @escaping (URL) -> Void,
        onDiscard: @escaping () -> Void,
        onChange: @escaping (UUID, URL?, String?) -> Void,
        onCopyURLSucceeded: @escaping () -> Void = {},
        onCopyURLFailed: @escaping () -> Void = {},
        onCopyMarkdownLinkSucceeded: @escaping () -> Void = {},
        onCopyMarkdownLinkFailed: @escaping () -> Void = {},
        onPasteURLFailed: @escaping () -> Void = {},
        downloadActivityOwnerID: ObjectIdentifier? = nil,
        onDownloadActivity: @escaping (DownloadActivityEvent) -> Void = { _ in },
        onDownloadFinished: @escaping (String) -> Void,
        onDownloadFailed: @escaping (String) -> Void
    ) {
        self.init(
            id: item.id,
            initialURL: item.url,
            presentation: .drawer,
            websiteDataStore: websiteDataStore,
            sheetNavigation: sheetNavigation,
            webExtensionHost: webExtensionHost,
            webExtensionWindow: webExtensionWindow,
            sheetScale: sheetScale,
            sheetNavigationActions: .init(
                onOpenBoard: onKeepInDrawer,
                onOpenBoardInBackground: onKeepInDrawerInBackground,
                onKeepInDrawer: onKeepInDrawer,
                onOpenCurrentSheetInNewBoard: onKeepInDrawer,
                onPasteURLInNewBoard: onKeepInDrawer,
                onCopyURLSucceeded: onCopyURLSucceeded,
                onCopyURLFailed: onCopyURLFailed,
                onCopyMarkdownLinkSucceeded: onCopyMarkdownLinkSucceeded,
                onCopyMarkdownLinkFailed: onCopyMarkdownLinkFailed,
                onPasteURLFailed: onPasteURLFailed,
                onRemoveBoard: onDiscard,
                isSupportedSheetURL: WebURLPolicy.isSupported),
            events: .init(
                onChange: { _, url, title in onChange(item.id, url, title) },
                downloadActivityOwnerID: downloadActivityOwnerID,
                onDownloadActivity: onDownloadActivity,
                onDownloadFinished: onDownloadFinished,
                onDownloadFailed: onDownloadFailed))
    }
}
