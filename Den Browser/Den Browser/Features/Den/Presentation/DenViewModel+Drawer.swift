import DenDomain
import Foundation

extension DenViewModel {
    var drawerPendingDeletionCount: Int? {
        guard case .clearDrawer(let count)? = pendingConfirmation else { return nil }
        return count
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
        drawer.preparePresentation()
        if drawer.expandedItemID != nil { isDenMode = false }
    }

    func focusDrawerItem(_ itemID: UUID) {
        guard drawer.focusItem(itemID) else { return }
        setTemporaryContext(.drawer)
        isDenMode = false
    }

    func closeDrawer() {
        if temporaryContext == .drawer { setTemporaryContext(nil) }
    }

    func confirmDrawerClear() {
        guard drawerPendingDeletionCount != nil else { return }
        store.clearDrawer()
        pendingConfirmation = nil
    }

    func cancelDrawerClear() {
        if drawerPendingDeletionCount != nil { pendingConfirmation = nil }
    }

    @discardableResult
    func placeDrawerItemAsBoard(_ itemID: UUID) -> BoardID? {
        store.placeDrawerItemAsBoard(
            itemID, preferredWidth: store.focusedBoard?.width ?? boardWidth(toFit: 2))
    }

    func placeSelectedDrawerItemAsBoard() {
        guard let itemID = drawer.selectedItemID else { return }
        placeDrawerItemAsBoard(itemID)
    }
}
