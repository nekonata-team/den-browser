import AppKit
import DenApplication
import DenDomain
import DenPresentationModels
import Foundation
import WebKit

@MainActor
final class DrawerActions {
    private let context: WindowNativeContext
    private let boardOpening: BoardOpeningActions
    private var runtimes: BoardRuntimeAccess { context.runtimes }
    private var storage: DenProfileResources { context.storage }
    private var state: DenState { context.storage.state }
    private var preferences: AppPreferences { context.configuration.preferences }
    private var focusedBoard: BoardState? { context.focusedBoard }
    private var sheetNavigation: SheetNavigationManager { context.configuration.sheetNavigation }
    private var webExtensionHost: WebExtensionHost? { context.runtimes.webExtensionHost }
    private var webExtensionWindow: MV3WebExtensionWindow? { context.runtimes.webExtensionWindow }
    private var websiteDataStore: WKWebsiteDataStore { context.configuration.websiteDataStore }
    private var onWindowEffect: ((DenWindowEffect) -> Void)? { context.connection.onWindowEffect }
    private var drawerPeekRuntime: WebRuntime? {
        get { context.windowResources.drawerPeek }
        set { context.windowResources.drawerPeek = newValue }
    }

    init(context: WindowNativeContext, boardOpening: BoardOpeningActions) {
        self.context = context
        self.boardOpening = boardOpening
    }

    @discardableResult
    func keepInDrawer(
        _ url: URL,
        title: String? = nil,
        opensDrawer: Bool = true,
        selectsItem: Bool = true
    ) -> UUID? {
        guard
            let itemID = storage.drawerItems.keep(
                url, title: title, notify: drawerItemNotifications(opensDrawer: opensDrawer, selectsItem: selectsItem))
        else {
            context.feedback.publish("Only HTTP, HTTPS, and local file URLs are supported.", severity: .warning)
            return nil
        }
        context.feedback.publish("Kept in Drawer.", severity: .success)
        return itemID
    }

    @discardableResult
    func keepInDrawerInBackground(_ url: URL, title: String? = nil) -> UUID? {
        keepInDrawer(url, title: title, opensDrawer: false, selectsItem: false)
    }

    func keepFocusedSheetInDrawer() {
        guard let board = focusedBoard, let url = board.currentSheetURL else { return }
        keepInDrawer(url, title: board.displayName, opensDrawer: false)
    }

    @discardableResult
    func discardDrawerItem(_ itemID: UUID, focusNext: Bool = true) -> Bool {
        storage.drawerItems.discard(itemID, focusNext: focusNext, notify: drawerItemNotifications())
    }

    func restoreRecentlyDiscardedDrawerItem() {
        if storage.drawerItems.restore(notify: drawerItemNotifications()) == nil {
            context.feedback.publish("No discarded Drawer Item to restore.", severity: .warning)
        }
    }

    func requestDrawerClearConfirmation() {
        guard !state.drawerItems.isEmpty else { return }
        onWindowEffect?(.requestConfirmation(.clearDrawer(state.drawerItems.count)))
    }

    @discardableResult
    func placeDrawerItemAsBoard(
        _ itemID: UUID,
        preferredWidth: Double? = nil,
        deskID: DeskID? = nil
    ) -> BoardID? {
        guard
            let boardID = storage.drawerPlacement.place(
                .init(
                    itemID: itemID, width: preferredWidth ?? boardOpening.inheritedBoardWidth,
                    searchEngine: preferences.searchEngine,
                    target: boardOpening.boardCreationTarget(deskID: deskID)),
                notifyBoard: drawerBoardCreationNotifications(itemID), notifyDrawer: drawerItemNotifications())
        else { return nil }
        onWindowEffect?(.dismissTemporaryPresentation)
        return boardID
    }

    func drawerRuntime(for item: DrawerItem) -> WebRuntime {
        runtimes.ensureWebExtensionContext()
        if let drawerPeekRuntime, drawerPeekRuntime.id == item.id {
            return drawerPeekRuntime
        }
        runtimes.releaseDrawerPeek()
        let runtime = WebRuntime(
            item: item,
            websiteDataStore: websiteDataStore,
            sheetNavigation: sheetNavigation,
            webExtensionHost: webExtensionHost,
            webExtensionWindow: webExtensionWindow,
            sheetScale: preferences.sheetScale,
            onKeepInDrawer: { [weak self] url in
                self?.keepInDrawer(url, opensDrawer: false)
            },
            onKeepInDrawerInBackground: { [weak self] url in
                self?.keepInDrawerInBackground(url)
            },
            onDiscard: { [weak self] in
                self?.discardDrawerItem(item.id)
            },
            onChange: { [weak self] itemID, url, title in
                self?.updateDrawerItem(itemID: itemID, url: url, title: title)
            },
            onCopyURLSucceeded: { [weak self] in
                self?.context.feedback.publish("Copied Current Sheet URL.", severity: .success)
            },
            onCopyURLFailed: { [weak self] in
                self?.context.feedback.publish("Could not copy Current Sheet URL.", severity: .error)
            },
            onCopyMarkdownLinkSucceeded: { [weak self] in
                self?.context.feedback.publish("Copied Current Sheet Markdown link.", severity: .success)
            },
            onCopyMarkdownLinkFailed: { [weak self] in
                self?.context.feedback.publish("Could not copy Current Sheet Markdown link.", severity: .error)
            },
            onPasteURLFailed: { [weak self] in
                self?.context.feedback.publish("Clipboard does not contain a supported URL.", severity: .warning)
            },
            downloadActivityOwnerID: ObjectIdentifier(self),
            onDownloadActivity: { [weak self] event in
                self?.context.connection.onDownloadActivity?(event)
            },
            onDownloadFinished: { [weak self] filename in
                self?.context.feedback.publish("Downloaded '\(filename)'", severity: .success)
            },
            onDownloadFailed: { [weak self] filename in
                self?.context.feedback.publish("Failed to download '\(filename)'", severity: .warning)
            }
        )
        webExtensionHost?.activate(webView: runtime.webView)
        drawerPeekRuntime = runtime
        return runtime
    }

    private func updateDrawerItem(itemID: UUID, url: URL?, title: String?) {
        storage.drawerItems.update(itemID, url: url, title: title)
    }

    func clearDrawer() {
        storage.drawerItems.clear(notify: drawerItemNotifications())
    }

    func drawerBoardCreationNotifications(_ itemID: UUID) -> (BoardCreation.Notice) -> Void {
        boardOpening.boardCreationNotifications(
            existingRuntime: drawerPeekRuntime?.id == itemID ? drawerPeekRuntime : nil)
    }

    func drawerItemNotifications(opensDrawer: Bool = true, selectsItem: Bool = true) -> (DrawerItems.Notice) -> Void {
        { [self] notice in
            switch notice {
            case .willKeep:
                if selectsItem { runtimes.releaseDrawerPeek() }
            case .didKeep(let id):
                onWindowEffect?(.drawerItemKept(id, opensDrawer: opensDrawer, selectsItem: selectsItem))
            case .willRestore:
                runtimes.releaseDrawerPeek()
            case .didRestore(let id):
                onWindowEffect?(.drawerItemRestored(id))
            case .didDiscard(let id, let previousItems, let advancesPeek, let focusNext):
                for presentation in storage.windowConnections.allObjects {
                    if presentation.windowResources?.drawerPeek?.id == id { presentation.runtimes?.releaseDrawerPeek() }
                    presentation.onWindowEffect?(
                        .drawerItemRemoved(
                            id, previousItems: previousItems, advancesPeek: advancesPeek, focusNext: focusNext))
                }
            case .didClear:
                for presentation in storage.windowConnections.allObjects {
                    presentation.runtimes?.releaseDrawerPeek()
                    presentation.onWindowEffect?(.drawerCleared)
                }
            }
        }
    }
}
