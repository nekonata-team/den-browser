import Foundation

extension DenStore {
    var filteredDrawerItems: [DrawerItem] {
        state.drawerItems.filter(matchesDrawerFilter)
    }

    var selectedDrawerItem: DrawerItem? {
        guard let selectedDrawerItemID else { return nil }
        return state.drawerItems.first { $0.id == selectedDrawerItemID }
    }

    func keepInDrawer(_ url: URL, title: String? = nil, opensDrawer: Bool = true) {
        guard SheetURLPolicy.isSupported(url) else {
            showToast("Only HTTP, HTTPS, and local file URLs are supported.", style: .warning)
            return
        }
        releaseDrawerPreview()
        drawerQuery = ""
        drawerFilterPhase = .inactive
        let item = DrawerItem(url: url, title: title)
        state.drawerItems.insert(item, at: 0)
        selectedDrawerItemID = item.id
        state.expandedDrawerItemID = item.id
        if opensDrawer {
            openDrawer()
        }
        save()
        showToast("Kept in Drawer.", style: .success)
    }

    func keepFocusedSheetInDrawer() {
        guard let board = focusedBoard, let url = board.currentSheetURL else { return }
        keepInDrawer(url, title: board.displayName, opensDrawer: false)
    }

    func toggleDrawer() {
        if isDrawerOpen {
            closeDrawer()
        } else {
            openDrawer()
        }
    }

    func openDrawer() {
        setTemporaryContext(.drawer)
        selectedDrawerItemID = selectedDrawerItemID ?? state.drawerItems.first?.id
        if expandedDrawerItemID != nil {
            isDenMode = false
        }
    }

    func closeDrawer() {
        if temporaryContext == .drawer {
            setTemporaryContext(nil)
        }
    }

    func setDrawerQuery(_ query: String) {
        drawerQuery = query
        updateDrawerSelectionForFilter()
    }

    func enterDrawerFilterMode() {
        drawerFilterPhase = .filtering
        updateDrawerSelectionForFilter()
    }

    func exitDrawerFilterMode() {
        drawerFilterPhase = .inactive
        drawerQuery = ""
        updateDrawerSelectionForFilter()
    }

    func confirmDrawerFilterQuery() {
        guard drawerFilterPhase == .filtering else { return }
        drawerFilterPhase = .selecting
    }

    func confirmDrawerFilterSelection() {
        guard
            drawerFilterPhase == .selecting,
            let selectedDrawerItemID,
            filteredDrawerItems.contains(where: { $0.id == selectedDrawerItemID })
        else { return }
        drawerFilterPhase = .inactive
        drawerQuery = ""
        toggleDrawerItem(selectedDrawerItemID)
    }

    func clearDrawerQuery() {
        drawerQuery = ""
        updateDrawerSelectionForFilter()
    }

    func matchesDrawerFilter(_ item: DrawerItem) -> Bool {
        guard !drawerQuery.isEmpty else { return true }
        return item.displayName.localizedCaseInsensitiveContains(drawerQuery)
            || item.url.absoluteString.localizedCaseInsensitiveContains(drawerQuery)
    }

    func toggleDrawerItem(_ itemID: UUID) {
        guard state.drawerItems.contains(where: { $0.id == itemID }) else { return }
        selectedDrawerItemID = itemID
        if expandedDrawerItemID == itemID {
            state.expandedDrawerItemID = nil
            releaseDrawerPreview()
        } else {
            state.expandedDrawerItemID = itemID
            isDenMode = false
            releaseDrawerPreview()
        }
        save()
    }

    func selectDrawerItem(by offset: Int) {
        let items = filteredDrawerItems
        guard !items.isEmpty else { return }
        let currentIndex =
            selectedDrawerItemID.flatMap { id in items.firstIndex { $0.id == id } }
            ?? 0
        let targetIndex = min(max(currentIndex + offset, 0), items.count - 1)
        let targetID = items[targetIndex].id
        guard selectedDrawerItemID != targetID else { return }
        selectedDrawerItemID = targetID
        if expandedDrawerItemID != nil {
            state.expandedDrawerItemID = targetID
            releaseDrawerPreview()
            save()
        }
    }

    func toggleSelectedDrawerItem() {
        guard let selectedDrawerItemID else { return }
        toggleDrawerItem(selectedDrawerItemID)
    }

    func discardDrawerItem(_ itemID: UUID) {
        discardDrawerItem(itemID, advancesPreview: true)
    }

    private func discardDrawerItem(_ itemID: UUID, advancesPreview: Bool) {
        guard let index = state.drawerItems.firstIndex(where: { $0.id == itemID }) else { return }
        let wasSelected = selectedDrawerItemID == itemID
        let wasExpanded = expandedDrawerItemID == itemID
        let nextPreviewID =
            advancesPreview && wasExpanded
            ? nextDrawerItemID(after: itemID)
            : nil

        if wasExpanded {
            state.expandedDrawerItemID = nil
            releaseDrawerPreview()
        }
        state.drawerItems.remove(at: index)

        if wasExpanded {
            state.expandedDrawerItemID = nextPreviewID
            selectedDrawerItemID = nextPreviewID ?? filteredDrawerItems.first?.id
        } else if wasSelected {
            selectedDrawerItemID = filteredDrawerItems.first?.id
        }

        if state.drawerItems.isEmpty {
            closeDrawer()
        }
        save()
    }

    func discardSelectedDrawerItem() {
        guard let selectedDrawerItemID else { return }
        discardDrawerItem(selectedDrawerItemID)
    }

    func requestDrawerClearConfirmation() {
        guard !state.drawerItems.isEmpty else { return }
        pendingConfirmation = .clearDrawer(state.drawerItems.count)
    }

    func confirmDrawerClear() {
        guard drawerPendingDeletionCount != nil else { return }
        releaseDrawerPreview()
        state.drawerItems = []
        state.expandedDrawerItemID = nil
        selectedDrawerItemID = nil
        drawerQuery = ""
        drawerFilterPhase = .inactive
        closeDrawer()
        pendingConfirmation = nil
        save()
    }

    func cancelDrawerClear() {
        if drawerPendingDeletionCount != nil {
            pendingConfirmation = nil
        }
    }

    func placeDrawerItemAsBoard(_ itemID: UUID) {
        guard let item = state.drawerItems.first(where: { $0.id == itemID }) else { return }
        addBoard(urlString: item.url.absoluteString, preferredWidth: focusedBoard?.width)
        discardDrawerItem(itemID, advancesPreview: false)
        closeDrawer()
    }

    func placeSelectedDrawerItemAsBoard() {
        guard let selectedDrawerItemID else { return }
        placeDrawerItemAsBoard(selectedDrawerItemID)
    }

    func drawerRuntime(for item: DrawerItem) -> DrawerPreviewRuntime {
        if let drawerPreviewRuntime, drawerPreviewRuntime.id == item.id {
            return drawerPreviewRuntime
        }
        releaseDrawerPreview()
        let runtime = DrawerPreviewRuntime(
            item: item,
            websiteDataStore: websiteDataStore,
            sheetNavigation: sheetNavigation,
            sheetScale: preferences.sheetScale,
            onKeepInDrawer: { [weak self] url in
                self?.keepInDrawer(url, opensDrawer: false)
            },
            onDiscard: { [weak self] in
                self?.discardDrawerItem(item.id)
            },
            onChange: { [weak self] itemID, url, title in
                self?.updateDrawerItem(itemID: itemID, url: url, title: title)
            },
            onDownloadFinished: { [weak self] filename in
                self?.showToast("Downloaded '\(filename)'", style: .success)
            },
            onDownloadFailed: { [weak self] filename in
                self?.showToast("Failed to download '\(filename)'", style: .warning)
            }
        )
        drawerPreviewRuntime = runtime
        return runtime
    }

    func releaseDrawerPreview() {
        guard let runtime = drawerPreviewRuntime else { return }
        runtime.dispose()
        drawerPreviewRuntime = nil
    }

    private func updateDrawerItem(itemID: UUID, url: URL?, title: String?) {
        guard let index = state.drawerItems.firstIndex(where: { $0.id == itemID }) else { return }
        var changed = false
        if let url, SheetURLPolicy.isSupported(url), state.drawerItems[index].url != url {
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

    private func updateDrawerSelectionForFilter() {
        let items = filteredDrawerItems
        if let selectedDrawerItemID, items.contains(where: { $0.id == selectedDrawerItemID }) {
            return
        }
        selectedDrawerItemID = items.first?.id
    }

    private func nextDrawerItemID(after itemID: UUID) -> UUID? {
        let items = filteredDrawerItems
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return nil }
        if items.indices.contains(index + 1) {
            return items[index + 1].id
        }
        guard index > items.startIndex else { return nil }
        return items[index - 1].id
    }
}
