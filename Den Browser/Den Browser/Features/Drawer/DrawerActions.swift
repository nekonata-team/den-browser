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

    func moveBoardToDrawer(_ boardID: BoardID) {
        let result = storage.drawerTransfer.move(boardID, notify: drawerTransferNotifications())
        context.feedback.publish(
            result == nil
                ? "Only Web or Terminal Primary Boards without a Side Board can move to Drawer." : "Moved to Drawer.",
            severity: result == nil ? .warning : .success)
    }

    func drawerTransferNotifications() -> (DrawerTransfer.Notice) -> Void {
        { [self] notice in
            switch notice {
            case .willMove(let board, let item):
                if let runtime = storage.webRuntimes.removeValue(forKey: board.id) {
                    runtime.webView.isHidden = true
                    runtime.webView.removeFromSuperview()
                    runtime.attachToDrawer(itemID: item.id, storage: storage, connection: context.connection)
                    storage.drawerRuntimes.web[item.id] = runtime
                }
                if let runtime = storage.terminalRuntimes.removeValue(forKey: board.id) {
                    runtime.setSurfaceVisible(false)
                    runtime.terminalView.isHidden = true
                    runtime.terminalView.removeFromSuperview()
                    runtime.updateOwner(
                        events: TerminalRuntime.drawerEvents(
                            itemID: item.id, storage: storage, connection: context.connection))
                    storage.drawerRuntimes.terminal[item.id] = runtime
                }
                storage.boardRuntimes.receivers.removeValue(forKey: board.id)
            case .didMove(let source, let plan, let item):
                let boardID = plan.historyEntry.board.id
                storage.facingCache.invalidate(for: boardID)
                context.inputSourceTracker.boardWillRemove(boardID)
                onWindowEffect?(
                    .overviewBoardRemoved(
                        boardID: boardID, deskID: source.id, oldIndex: plan.historyEntry.sourceBoardIndex))
                storage.invalidateReferences(toRemovedBoardIDs: [boardID])
                onWindowEffect?(.drawerItemKept(item.id, opensDrawer: false, selectsItem: true))
            }
        }
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
        precondition(item.url != nil, "Only Web Items can create a Web runtime")
        runtimes.ensureWebExtensionContext()
        selectRuntime(for: item.id)
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

    func drawerTerminalRuntime(for item: DrawerItem) -> TerminalRuntime {
        guard let session = item.terminal else {
            preconditionFailure("Only Terminal Items can create a Terminal runtime")
        }
        selectRuntime(for: item.id)
        let events = TerminalRuntime.drawerEvents(itemID: item.id, storage: storage, connection: context.connection)
        let runtime: TerminalRuntime
        if let existing = storage.drawerRuntimes.terminal[item.id] {
            runtime = existing
            runtime.updateOwner(events: events)
        } else {
            runtime = TerminalRuntime(
                workingDirectory: session.workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path,
                command: TerminalLaunchCommand.make(
                    for: .terminal(session), zellijClient: context.zellijClient, zmxClient: context.zmxClient),
                boardID: BoardID(item.id), profileID: context.configuration.profileID,
                socketPath: context.configuration.ipcSocketPath, events: events)
            runtime.setSurfaceVisible(false)
            storage.drawerRuntimes.terminal[item.id] = runtime
        }
        context.windowResources.drawerTerminalPeek = (item.id, runtime)
        return runtime
    }

    private func selectRuntime(for itemID: UUID) {
        for window in storage.windowConnections.allObjects
        where window !== context.connection && window.windowResources?.drawerItemID == itemID {
            window.runtimes?.releaseDrawerPeek()
            window.onWindowEffect?(.drawerPeekMoved(itemID))
        }
        if context.windowResources.drawerItemID != itemID { runtimes.releaseDrawerPeek() }
    }

    func clearDrawer() {
        storage.drawerItems.clear(notify: drawerItemNotifications())
    }

    func drawerBoardCreationNotifications(_ itemID: UUID) -> (BoardCreation.Notice) -> Void {
        let web = storage.drawerRuntimes.web[itemID]
        let terminal = storage.drawerRuntimes.terminal[itemID]
        let notify = boardOpening.boardCreationNotifications(existingRuntime: web)
        return { [self] notice in
            if case .willInsert(let board) = notice {
                storage.drawerRuntimes.web.removeValue(forKey: itemID)
                storage.drawerRuntimes.terminal.removeValue(forKey: itemID)
                for window in storage.windowConnections.allObjects
                where window.windowResources?.drawerItemID == itemID {
                    window.runtimes?.releaseDrawerPeek()
                }
                if let terminal { runtimes.attachTerminalRuntime(terminal, to: board) }
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
                    if presentation.windowResources?.drawerItemID == id { presentation.runtimes?.releaseDrawerPeek() }
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
