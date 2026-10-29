import DenApplication
import DenDomain
import DenModels
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
        storage: DenProfileResources,
        connection: RuntimeWindowConnection
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
            sheetNavigationActions: Self.drawerNavigationActions(itemID: item.id, connection: connection),
            events: Self.drawerEvents(itemID: item.id, storage: storage, connection: connection))
    }

    func updateDrawerOwner(itemID: UUID, storage: DenProfileResources, connection: RuntimeWindowConnection) {
        updateOwner(
            sheetNavigationActions: Self.drawerNavigationActions(itemID: itemID, connection: connection),
            events: Self.drawerEvents(itemID: itemID, storage: storage, connection: connection))
    }

    func attachToDrawer(itemID: UUID, storage: DenProfileResources, connection: RuntimeWindowConnection) {
        presentInDrawer(
            sheetNavigationActions: Self.drawerNavigationActions(itemID: itemID, connection: connection),
            events: Self.drawerEvents(itemID: itemID, storage: storage, connection: connection))
    }

    private static func drawerNavigationActions(itemID: UUID, connection: RuntimeWindowConnection)
        -> SheetNavigationManager.Actions
    {
        let keep: (URL) -> Void = { [connection] url in
            connection.drawer?.keepInDrawer(url, opensDrawer: false)
        }
        return .init(
            onOpenBoard: keep,
            onOpenBoardInBackground: { [connection] in connection.drawer?.keepInDrawerInBackground($0) },
            onKeepInDrawer: keep,
            onOpenCurrentSheetInNewBoard: keep,
            onPasteURLInNewBoard: keep,
            onCopyURLSucceeded: { [connection] in
                connection.feedback?.publish("Copied Current Sheet URL.", severity: .success)
            },
            onCopyURLFailed: { [connection] in
                connection.feedback?.publish("Could not copy Current Sheet URL.", severity: .error)
            },
            onCopyMarkdownLinkSucceeded: { [connection] in
                connection.feedback?.publish("Copied Current Sheet Markdown link.", severity: .success)
            },
            onCopyMarkdownLinkFailed: { [connection] in
                connection.feedback?.publish("Could not copy Current Sheet Markdown link.", severity: .error)
            },
            onPasteURLFailed: { [connection] in
                connection.feedback?.publish("Clipboard does not contain a supported URL.", severity: .warning)
            },
            onRemoveBoard: { [connection] in connection.drawer?.discardDrawerItem(itemID) },
            isSupportedSheetURL: WebURLPolicy.isSupported)
    }

    private static func drawerEvents(
        itemID: UUID, storage: DenProfileResources, connection: RuntimeWindowConnection
    ) -> Events {
        .init(
            onChange: { [weak storage] _, url, title in
                storage?.drawerItems.update(itemID, url: url, title: title)
            },
            downloadActivityOwnerID: ObjectIdentifier(connection),
            onDownloadActivity: { [connection] in connection.onDownloadActivity?($0) },
            onDownloadFinished: { [connection] filename in
                connection.feedback?.publish("Downloaded '\(filename)'", severity: .success)
            },
            onDownloadFailed: { [connection] filename in
                connection.feedback?.publish("Failed to download '\(filename)'", severity: .warning)
            },
            isFocused: { [connection] in connection.windowResources?.drawerPeek?.id == itemID })
    }
}
