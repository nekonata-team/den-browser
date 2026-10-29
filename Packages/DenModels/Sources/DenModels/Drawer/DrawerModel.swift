import DenDomain
import Foundation
import Observation

@MainActor
@Observable
public final class DrawerModel {
    @ObservationIgnored private let itemProvider: () -> [DrawerItem]
    @ObservationIgnored private let isBottomStyleProvider: () -> Bool
    @ObservationIgnored private let releasePeek: () -> Void
    @ObservationIgnored private let discardItemAction: (UUID, Bool) -> Void
    @ObservationIgnored private let toggleStyleAction: () -> Void
    @ObservationIgnored private let requestClearConfirmationAction: () -> Void
    public var query = ""
    public var filterPhase: FilterPhase = .inactive
    public var selectedItemID: UUID?
    public var expandedItemID: UUID?

    @ObservationIgnored public var onPeekExpanded: (() -> Void)?
    @ObservationIgnored public var onClose: (() -> Void)?
    @ObservationIgnored public var onAddItem: (() -> Void)?

    public init(
        items: @escaping () -> [DrawerItem],
        isBottomStyle: @escaping () -> Bool,
        releasePeek: @escaping () -> Void,
        discardItem: @escaping (UUID, Bool) -> Void,
        toggleStyle: @escaping () -> Void,
        requestClearConfirmation: @escaping () -> Void
    ) {
        itemProvider = items
        isBottomStyleProvider = isBottomStyle
        self.releasePeek = releasePeek
        discardItemAction = discardItem
        toggleStyleAction = toggleStyle
        requestClearConfirmationAction = requestClearConfirmation
    }

    public var items: [DrawerItem] { itemProvider() }

    public var filteredItems: [DrawerItem] {
        items.filter(matchesFilter)
    }

    public var itemCount: Int { items.count }
    public var filteredItemCount: Int { filteredItems.count }
    public var isBottomStyle: Bool { isBottomStyleProvider() }

    public var selectedItem: DrawerItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    public var isFilterPresented: Bool { filterPhase != .inactive }
    public var isFilterInputActive: Bool { filterPhase == .filtering }
    public var isFilterSelecting: Bool { filterPhase == .selecting }

    public func setQuery(_ query: String) {
        self.query = WebURLPolicy.stripNewlines(query)
        updateSelectionForFilter()
    }

    public func enterFilterMode() {
        filterPhase = .filtering
        updateSelectionForFilter()
    }

    public func exitFilterMode() {
        filterPhase = .inactive
        query = ""
        updateSelectionForFilter()
    }

    public func confirmFilterQuery() {
        guard filterPhase == .filtering else { return }
        filterPhase = .selecting
    }

    public func confirmFilterSelection() {
        guard
            filterPhase == .selecting,
            let selectedItemID,
            filteredItems.contains(where: { $0.id == selectedItemID })
        else { return }
        filterPhase = .inactive
        query = ""
        toggleItem(selectedItemID)
    }

    public func clearQuery() {
        query = ""
        updateSelectionForFilter()
    }

    public func matchesFilter(_ item: DrawerItem) -> Bool {
        guard !query.isEmpty else { return true }
        return item.displayName.localizedCaseInsensitiveContains(query)
            || item.detail.localizedCaseInsensitiveContains(query)
            || item.terminal?.zellijSessionName?.localizedCaseInsensitiveContains(query) == true
            || item.terminal?.zmxSessionName?.localizedCaseInsensitiveContains(query) == true
    }

    public func toggleItem(_ itemID: UUID) {
        guard items.contains(where: { $0.id == itemID }) else { return }
        selectedItemID = itemID
        if expandedItemID == itemID {
            expandedItemID = nil
            releasePeek()
        } else {
            expandedItemID = itemID
            releasePeek()
            onPeekExpanded?()
        }
    }

    public func selectItem(by offset: Int) {
        let items = filteredItems
        guard
            let targetID = SelectionNavigation.next(
                selectedItemID,
                among: items.map(\.id),
                by: offset),
            selectedItemID != targetID
        else { return }
        selectedItemID = targetID
        if expandedItemID != nil {
            expandedItemID = targetID
            releasePeek()
        }
    }

    public func toggleSelectedItem() {
        guard let selectedItemID else { return }
        toggleItem(selectedItemID)
    }

    public func discardSelectedItem(focusNext: Bool = true) {
        guard let selectedItemID else { return }
        discardItemAction(selectedItemID, focusNext)
    }

    public func discardItem(_ itemID: UUID) {
        discardItemAction(itemID, true)
    }

    public func toggleStyle() {
        toggleStyleAction()
    }

    public func addItem() {
        onAddItem?()
    }

    public func requestClearConfirmation() {
        requestClearConfirmationAction()
    }

    public func close() {
        onClose?()
    }

    public func preparePresentation() {
        selectedItemID = selectedItemID ?? items.first?.id
    }

    public func endPresentation() {
        query = ""
        filterPhase = .inactive
    }

    public func resetPresentation() {
        releasePeek()
        selectedItemID = nil
        expandedItemID = nil
        query = ""
        filterPhase = .inactive
    }

    @discardableResult
    public func focusItem(_ itemID: UUID) -> Bool {
        guard items.contains(where: { $0.id == itemID }) else { return false }
        query = ""
        filterPhase = .inactive
        releasePeek()
        selectedItemID = itemID
        expandedItemID = itemID
        return true
    }

    public func itemWasKept(_ itemID: UUID, selectsItem: Bool) {
        guard selectsItem else { return }
        query = ""
        filterPhase = .inactive
        selectedItemID = itemID
        expandedItemID = itemID
    }

    public func itemWasRestored(_ itemID: UUID) {
        selectedItemID = itemID
        expandedItemID = itemID
    }

    public func itemWasRemoved(
        _ itemID: UUID, previousItems: [DrawerItem], advancesPeek: Bool, focusNext: Bool
    ) {
        let wasSelected = selectedItemID == itemID
        let wasExpanded = expandedItemID == itemID
        let adjacentItemID =
            advancesPeek && (wasSelected || wasExpanded)
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
