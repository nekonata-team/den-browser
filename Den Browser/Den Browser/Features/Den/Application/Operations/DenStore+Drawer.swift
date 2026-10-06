import DenDomain
import Foundation

extension DenStore {
    @discardableResult
    func keepInDrawer(
        _ url: URL,
        title: String? = nil,
        opensDrawer: Bool = true,
        selectsItem: Bool = true
    ) -> UUID? {
        guard WebURLPolicy.isSupported(url) else {
            reportFeedback("Only HTTP, HTTPS, and local file URLs are supported.", severity: .warning)
            return nil
        }
        if selectsItem { releaseDrawerPreview() }
        let item = DrawerItem(url: url, title: title)
        state.drawerItems.insert(item, at: 0)
        onWindowEffect?(.drawerItemKept(item.id, opensDrawer: opensDrawer, selectsItem: selectsItem))
        save()
        reportFeedback("Kept in Drawer.", severity: .success)
        return item.id
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
        guard state.drawerItems.contains(where: { $0.id == itemID }) else { return false }
        discardDrawerItem(itemID, advancesPreview: true, focusNext: focusNext)
        return true
    }

    private func discardDrawerItem(
        _ itemID: UUID,
        advancesPreview: Bool,
        focusNext: Bool = true,
        recordsDiscardHistory: Bool = true
    ) {
        guard let index = state.drawerItems.firstIndex(where: { $0.id == itemID }) else { return }
        let item = state.drawerItems[index]
        let previousItems = state.drawerItems

        if recordsDiscardHistory {
            rememberDiscardedDrawerItems([item])
        }
        state.drawerItems.remove(at: index)
        for presentation in storage.drawerPresentations.allObjects {
            if presentation.drawerPreviewRuntime?.id == itemID { presentation.releaseDrawerPreview() }
            presentation.onWindowEffect?(
                .drawerItemRemoved(
                    itemID, previousItems: previousItems, advancesPreview: advancesPreview, focusNext: focusNext))
        }
        save()
    }

    func restoreRecentlyDiscardedDrawerItem() {
        guard let item = recentlyDiscardedDrawerItems.first else {
            reportFeedback("No discarded Drawer Item to restore.", severity: .warning)
            return
        }

        releaseDrawerPreview()
        state.drawerItems.insert(item, at: 0)
        recentlyDiscardedDrawerItems.removeFirst()
        onWindowEffect?(.drawerItemRestored(item.id))
        save()
    }

    private func rememberDiscardedDrawerItems(_ items: [DrawerItem]) {
        recentlyDiscardedDrawerItems.insert(contentsOf: items, at: 0)
        let overflow = recentlyDiscardedDrawerItems.count - Self.maximumRecentlyDiscardedDrawerItemCount
        if overflow > 0 {
            recentlyDiscardedDrawerItems.removeLast(overflow)
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
        deskID: UUID? = nil
    ) -> UUID? {
        guard let item = state.drawerItems.first(where: { $0.id == itemID }) else { return nil }
        guard
            let boardID = createBoard(
                urlString: item.url.absoluteString,
                preferredWidth: preferredWidth ?? focusedBoard?.width,
                recentItem: .url(WebURLPolicy.canonicalSheetURL(item.url)),
                deskID: deskID)
        else { return nil }
        discardDrawerItem(itemID, advancesPreview: false, recordsDiscardHistory: false)
        onWindowEffect?(.dismissTemporaryPresentation)
        return boardID
    }

    func drawerRuntime(for item: DrawerItem) -> DrawerPreviewRuntime {
        ensureWebExtensionContext()
        if let drawerPreviewRuntime, drawerPreviewRuntime.id == item.id {
            return drawerPreviewRuntime
        }
        releaseDrawerPreview()
        let runtime = DrawerPreviewRuntime(
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
        drawerPreviewRuntime = runtime
        return runtime
    }

    func releaseDrawerPreview() {
        guard let runtime = drawerPreviewRuntime else { return }
        runtime.dispose()
        drawerPreviewRuntime = nil
        if let focusedBoardID = focusedBoard?.id, let focusedWebRuntime = webRuntimes[focusedBoardID] {
            webExtensionHost?.activate(webView: focusedWebRuntime.webView)
        }
    }

    private func updateDrawerItem(itemID: UUID, url: URL?, title: String?) {
        guard let index = state.drawerItems.firstIndex(where: { $0.id == itemID }) else { return }
        var changed = false
        if let url, WebURLPolicy.isSupported(url), state.drawerItems[index].url != url {
            state.drawerItems[index].url = url
            changed = true
        }
        if let title, !title.isEmpty, state.drawerItems[index].title != title {
            state.drawerItems[index].title = title
            changed = true
        }
        if changed {
            save()
        }
    }

    func clearDrawer() {
        rememberDiscardedDrawerItems(state.drawerItems)
        state.drawerItems = []
        for presentation in storage.drawerPresentations.allObjects {
            presentation.releaseDrawerPreview()
            presentation.onWindowEffect?(.drawerCleared)
        }
        save()
    }
}
