import AppKit
import DenApplication
import DenDomain
import DenModels
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
        for window in storage.windowConnections.allObjects
        where window !== context.connection && window.windowResources?.drawerPeek?.id == item.id {
            window.runtimes?.releaseDrawerPeek()
            window.onWindowEffect?(.drawerPeekMoved(item.id))
        }
        if let runtime = storage.drawerRuntimes.web[item.id] {
            if drawerPeekRuntime !== runtime { runtimes.releaseDrawerPeek() }
            runtime.updateDrawerOwner(itemID: item.id, storage: storage, connection: context.connection)
            if let webExtensionHost, let webExtensionWindow {
                webExtensionHost.register(webView: runtime.webView, in: webExtensionWindow, initialURL: nil) {
                    [weak runtime] url in runtime?.load(url)
                }
            }
            webExtensionHost?.activate(webView: runtime.webView)
            drawerPeekRuntime = runtime
            return runtime
        }
        runtimes.releaseDrawerPeek()
        let runtime = WebRuntime(
            item: item,
            websiteDataStore: websiteDataStore,
            sheetNavigation: sheetNavigation,
            webExtensionHost: webExtensionHost,
            webExtensionWindow: webExtensionWindow,
            sheetScale: preferences.sheetScale,
            storage: storage,
            connection: context.connection)
        storage.drawerRuntimes.web[item.id] = runtime
        webExtensionHost?.activate(webView: runtime.webView)
        drawerPeekRuntime = runtime
        return runtime
    }

    func clearDrawer() {
        storage.drawerItems.clear(notify: drawerItemNotifications())
    }

    func drawerBoardCreationNotifications(_ itemID: UUID) -> (BoardCreation.Notice) -> Void {
        let runtime = storage.drawerRuntimes.web[itemID]
        let notify = boardOpening.boardCreationNotifications(existingRuntime: runtime)
        return { [self] notice in
            if case .willInsert = notice, let runtime {
                storage.drawerRuntimes.web.removeValue(forKey: itemID)
                for window in storage.windowConnections.allObjects
                where window.windowResources?.drawerPeek === runtime {
                    window.runtimes?.releaseDrawerPeek()
                }
            }
            notify(notice)
        }
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
                storage.drawerRuntimes.dispose(id)
                for presentation in storage.windowConnections.allObjects {
                    if presentation.windowResources?.drawerPeek?.id == id { presentation.runtimes?.releaseDrawerPeek() }
                    presentation.onWindowEffect?(
                        .drawerItemRemoved(
                            id, previousItems: previousItems, advancesPeek: advancesPeek, focusNext: focusNext))
                }
            case .didClear:
                storage.drawerRuntimes.releaseAll()
                for presentation in storage.windowConnections.allObjects {
                    presentation.runtimes?.releaseDrawerPeek()
                    presentation.onWindowEffect?(.drawerCleared)
                }
            }
        }
    }
}
