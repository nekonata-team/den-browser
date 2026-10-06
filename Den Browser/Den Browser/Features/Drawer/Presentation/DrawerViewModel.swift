import DenDomain
import Foundation
import Observation

@MainActor
@Observable
final class DrawerViewModel {
    let store: DenStore
    var query = ""
    var filterPhase: DenFilterPhase = .inactive
    var selectedItemID: UUID?
    var expandedItemID: UUID?

    @ObservationIgnored var onPreviewExpanded: (() -> Void)?

    init(store: DenStore) {
        self.store = store
    }

    var filteredItems: [DrawerItem] {
        store.state.drawerItems.filter(matchesFilter)
    }

    var selectedItem: DrawerItem? {
        guard let selectedItemID else { return nil }
        return store.state.drawerItems.first { $0.id == selectedItemID }
    }

    var isFilterPresented: Bool { filterPhase != .inactive }
    var isFilterInputActive: Bool { filterPhase == .filtering }
    var isFilterSelecting: Bool { filterPhase == .selecting }

    func setQuery(_ query: String) {
        self.query = WebURLPolicy.stripNewlines(query)
        updateSelectionForFilter()
    }

    func enterFilterMode() {
        filterPhase = .filtering
        updateSelectionForFilter()
    }

    func exitFilterMode() {
        filterPhase = .inactive
        query = ""
        updateSelectionForFilter()
    }

    func confirmFilterQuery() {
        guard filterPhase == .filtering else { return }
        filterPhase = .selecting
    }

    func confirmFilterSelection() {
        guard
            filterPhase == .selecting,
            let selectedItemID,
            filteredItems.contains(where: { $0.id == selectedItemID })
        else { return }
        filterPhase = .inactive
        query = ""
        toggleItem(selectedItemID)
    }

    func clearQuery() {
        query = ""
        updateSelectionForFilter()
    }

    func matchesFilter(_ item: DrawerItem) -> Bool {
        guard !query.isEmpty else { return true }
        return item.displayName.localizedCaseInsensitiveContains(query)
            || item.url.absoluteString.localizedCaseInsensitiveContains(query)
    }

    func toggleItem(_ itemID: UUID) {
        guard store.state.drawerItems.contains(where: { $0.id == itemID }) else { return }
        selectedItemID = itemID
        if expandedItemID == itemID {
            expandedItemID = nil
            store.releaseDrawerPreview()
        } else {
            expandedItemID = itemID
            store.releaseDrawerPreview()
            onPreviewExpanded?()
        }
    }

    func selectItem(by offset: Int) {
        let items = filteredItems
        guard
            let targetID = DenSelectionNavigation.next(
                selectedItemID,
                among: items.map(\.id),
                by: offset),
            selectedItemID != targetID
        else { return }
        selectedItemID = targetID
        if expandedItemID != nil {
            expandedItemID = targetID
            store.releaseDrawerPreview()
        }
    }

    func toggleSelectedItem() {
        guard let selectedItemID else { return }
        toggleItem(selectedItemID)
    }

    func discardSelectedItem(focusNext: Bool = true) {
        guard let selectedItemID else { return }
        store.discardDrawerItem(selectedItemID, focusNext: focusNext)
    }

    func toggleStyle() {
        store.preferences.toggleDrawerStyle()
    }

    func preparePresentation() {
        selectedItemID = selectedItemID ?? store.state.drawerItems.first?.id
    }

    func endPresentation() {
        query = ""
        filterPhase = .inactive
    }

    func resetPresentation() {
        store.releaseDrawerPreview()
        selectedItemID = nil
        expandedItemID = nil
        query = ""
        filterPhase = .inactive
    }

    @discardableResult
    func focusItem(_ itemID: UUID) -> Bool {
        guard store.state.drawerItems.contains(where: { $0.id == itemID }) else { return false }
        query = ""
        filterPhase = .inactive
        store.releaseDrawerPreview()
        selectedItemID = itemID
        expandedItemID = itemID
        return true
    }

    func itemWasKept(_ itemID: UUID, selectsItem: Bool) {
        guard selectsItem else { return }
        query = ""
        filterPhase = .inactive
        selectedItemID = itemID
        expandedItemID = itemID
    }

    func itemWasRestored(_ itemID: UUID) {
        selectedItemID = itemID
        expandedItemID = itemID
    }

    func itemWasRemoved(
        _ itemID: UUID, previousItems: [DrawerItem], advancesPreview: Bool, focusNext: Bool
    ) {
        let wasSelected = selectedItemID == itemID
        let wasExpanded = expandedItemID == itemID
        let adjacentItemID =
            advancesPreview && (wasSelected || wasExpanded)
            ? adjacentItemID(after: itemID, among: previousItems, focusNext: focusNext)
            : nil
        if wasExpanded {
            expandedItemID = adjacentItemID
            selectedItemID = adjacentItemID ?? filteredItems.first?.id
        } else if wasSelected {
            selectedItemID = adjacentItemID ?? filteredItems.first?.id
        }
    }

    private func updateSelectionForFilter() {
        let items = filteredItems
        if let selectedItemID, items.contains(where: { $0.id == selectedItemID }) { return }
        selectedItemID = items.first?.id
    }

    private func adjacentItemID(
        after itemID: UUID, among previousItems: [DrawerItem], focusNext: Bool
    ) -> UUID? {
        let items = previousItems.filter(matchesFilter)
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return nil }
        let preferredIndex = index + (focusNext ? 1 : -1)
        if items.indices.contains(preferredIndex) { return items[preferredIndex].id }
        let fallbackIndex = index + (focusNext ? -1 : 1)
        guard items.indices.contains(fallbackIndex) else { return nil }
        return items[fallbackIndex].id
    }
}
