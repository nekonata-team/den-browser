import Foundation

extension DenStore {
    var selectedDrawerItem: DrawerItem? {
        guard let selectedDrawerItemID else { return nil }
        return state.drawerItems.first { $0.id == selectedDrawerItemID }
    }

    func captureInDrawer(_ url: URL, title: String? = nil) {
        guard SheetURLPolicy.isSupported(url) else { return }
        releaseDrawerPreview()
        let item = DrawerItem(url: url, title: title)
        state.drawerItems.insert(item, at: 0)
        selectedDrawerItemID = item.id
        expandedDrawerItemID = item.id
        isDrawerOpen = true
        save()
    }

    func captureFocusedSheetInDrawer() {
        guard let board = focusedBoard, let url = board.currentSheetURL else { return }
        captureInDrawer(url, title: board.displayName)
    }

    func toggleDrawer() {
        if isDrawerOpen {
            closeDrawer()
        } else {
            isDrawerOpen = true
            selectedDrawerItemID = selectedDrawerItemID ?? state.drawerItems.first?.id
        }
    }

    func closeDrawer() {
        isDrawerOpen = false
        expandedDrawerItemID = nil
        releaseDrawerPreview()
    }

    func toggleDrawerItem(_ itemID: UUID) {
        guard state.drawerItems.contains(where: { $0.id == itemID }) else { return }
        selectedDrawerItemID = itemID
        if expandedDrawerItemID == itemID {
            expandedDrawerItemID = nil
            releaseDrawerPreview()
        } else {
            expandedDrawerItemID = itemID
            releaseDrawerPreview()
        }
    }

    func selectDrawerItem(by offset: Int) {
        guard !state.drawerItems.isEmpty else { return }
        let currentIndex =
            selectedDrawerItemID.flatMap { id in state.drawerItems.firstIndex { $0.id == id } }
            ?? 0
        let targetIndex = min(max(currentIndex + offset, 0), state.drawerItems.count - 1)
        let targetID = state.drawerItems[targetIndex].id
        guard selectedDrawerItemID != targetID else { return }
        selectedDrawerItemID = targetID
        if expandedDrawerItemID != nil {
            expandedDrawerItemID = targetID
            releaseDrawerPreview()
        }
    }

    func toggleSelectedDrawerItem() {
        guard let selectedDrawerItemID else { return }
        toggleDrawerItem(selectedDrawerItemID)
    }

    func discardDrawerItem(_ itemID: UUID) {
        guard let index = state.drawerItems.firstIndex(where: { $0.id == itemID }) else { return }
        let wasSelected = selectedDrawerItemID == itemID
        if expandedDrawerItemID == itemID {
            expandedDrawerItemID = nil
            releaseDrawerPreview()
        }
        state.drawerItems.remove(at: index)
        if wasSelected {
            selectedDrawerItemID =
                state.drawerItems.indices.contains(index)
                ? state.drawerItems[index].id
                : state.drawerItems.last?.id
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

    func placeDrawerItemAsBoard(_ itemID: UUID) {
        guard let item = state.drawerItems.first(where: { $0.id == itemID }) else { return }
        addBoard(urlString: item.url.absoluteString)
        discardDrawerItem(itemID)
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
            sheetScale: preferences.sheetScale
        ) { [weak self] itemID, url, title in
            self?.updateDrawerItem(itemID: itemID, url: url, title: title)
        }
        drawerPreviewRuntime = runtime
        return runtime
    }

    func releaseDrawerPreview() {
        guard let runtime = drawerPreviewRuntime else { return }
        sheetNavigation.didClose(runtime.webView)
        runtime.webView.stopLoading()
        runtime.webView.navigationDelegate = nil
        runtime.webView.uiDelegate = nil
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
}
