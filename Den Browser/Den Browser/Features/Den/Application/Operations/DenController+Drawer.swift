import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

extension DenController {
    func openInDrawer(input: String) -> String? {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(":"),
            let resolved = BoardInputResolver.resolveOpenBoardInput(
                input, searchEngine: preferences.searchEngine)
        else { return "Enter a URL or search to open in Drawer. Commands require a Board." }
        guard keepInDrawer(resolved.url) != nil else { return "Could not open in Drawer." }
        return nil
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
            reportFeedback("Only HTTP, HTTPS, and local file URLs are supported.", severity: .warning)
            return nil
        }
        reportFeedback("Kept in Drawer.", severity: .success)
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
            reportFeedback("No discarded Drawer Item to restore.", severity: .warning)
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
                    itemID: itemID, width: preferredWidth ?? inheritedBoardWidth,
                    searchEngine: preferences.searchEngine,
                    target: boardCreationTarget(deskID: deskID)),
                notifyBoard: drawerBoardCreationNotifications(itemID), notifyDrawer: drawerItemNotifications())
        else { return nil }
        onWindowEffect?(.dismissTemporaryPresentation)
        return boardID
    }

    func drawerRuntime(for item: DrawerItem) -> WebRuntime {
        ensureWebExtensionContext()
        if let drawerPeekRuntime, drawerPeekRuntime.id == item.id {
            return drawerPeekRuntime
        }
        releaseDrawerPeek()
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
                self?.reportFeedback("Copied Current Sheet URL.", severity: .success)
            },
            onCopyURLFailed: { [weak self] in
                self?.reportFeedback("Could not copy Current Sheet URL.", severity: .error)
            },
            onCopyMarkdownLinkSucceeded: { [weak self] in
                self?.reportFeedback("Copied Current Sheet Markdown link.", severity: .success)
            },
            onCopyMarkdownLinkFailed: { [weak self] in
                self?.reportFeedback("Could not copy Current Sheet Markdown link.", severity: .error)
            },
            onPasteURLFailed: { [weak self] in
                self?.reportFeedback("Clipboard does not contain a supported URL.", severity: .warning)
            },
            downloadActivityOwnerID: ObjectIdentifier(self),
            onDownloadActivity: { [weak self] event in
                self?.handleDownloadActivity(event)
            },
            onDownloadFinished: { [weak self] filename in
                self?.reportFeedback("Downloaded '\(filename)'", severity: .success)
            },
            onDownloadFailed: { [weak self] filename in
                self?.reportFeedback("Failed to download '\(filename)'", severity: .warning)
            }
        )
        webExtensionHost?.activate(webView: runtime.webView)
        drawerPeekRuntime = runtime
        return runtime
    }

    func releaseDrawerPeek() {
        guard let runtime = drawerPeekRuntime else { return }
        runtime.dispose()
        drawerPeekRuntime = nil
        if let focusedBoardID = focusedBoard?.id, let focusedWebRuntime = webRuntimes[focusedBoardID] {
            webExtensionHost?.activate(webView: focusedWebRuntime.webView)
        }
    }

    private func updateDrawerItem(itemID: UUID, url: URL?, title: String?) {
        storage.drawerItems.update(itemID, url: url, title: title)
    }

    func clearDrawer() {
        storage.drawerItems.clear(notify: drawerItemNotifications())
    }

    func drawerBoardCreationNotifications(_ itemID: UUID) -> (BoardCreation.Notice) -> Void {
        boardCreationNotifications(existingRuntime: drawerPeekRuntime?.id == itemID ? drawerPeekRuntime : nil)
    }

    func drawerItemNotifications(opensDrawer: Bool = true, selectsItem: Bool = true) -> (DrawerItems.Notice) -> Void {
        { [self] notice in
            switch notice {
            case .willKeep:
                if selectsItem { releaseDrawerPeek() }
            case .didKeep(let id):
                onWindowEffect?(.drawerItemKept(id, opensDrawer: opensDrawer, selectsItem: selectsItem))
            case .willRestore:
                releaseDrawerPeek()
            case .didRestore(let id):
                onWindowEffect?(.drawerItemRestored(id))
            case .didDiscard(let id, let previousItems, let advancesPeek, let focusNext):
                for presentation in storage.drawerPresentations.allObjects {
                    if presentation.drawerPeekRuntime?.id == id { presentation.releaseDrawerPeek() }
                    presentation.onWindowEffect?(
                        .drawerItemRemoved(
                            id, previousItems: previousItems, advancesPeek: advancesPeek, focusNext: focusNext))
                }
            case .didClear:
                for presentation in storage.drawerPresentations.allObjects {
                    presentation.releaseDrawerPeek()
                    presentation.onWindowEffect?(.drawerCleared)
                }
            }
        }
    }
}
