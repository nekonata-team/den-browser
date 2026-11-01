import DenDomain
import Foundation

public extension DenWindowModel {
    var drawerPendingDiscardCount: Int? {
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
        guard let request = pendingConfirmation, case .clearDrawer = request else { return }
        _ = onConfirmOperation(request)
        pendingConfirmation = nil
    }

    func cancelDrawerClear() {
        if drawerPendingDiscardCount != nil { pendingConfirmation = nil }
    }

    @discardableResult
    func placeDrawerItemAsBoard(_ itemID: UUID) -> BoardID? {
        boardActions.placeDrawerItem(itemID, navigation.inheritedBoardWidth ?? boardWidth(toFit: 2), nil)
    }

    func placeSelectedDrawerItemAsBoard() {
        guard let itemID = drawer.selectedItemID else { return }
        placeDrawerItemAsBoard(itemID)
    }

    func chooseDrawerPlacementDesk(for itemID: UUID) {
        drawer.choosePlacementDesk(for: itemID, initialDeskID: desks.presentedDeskID)
    }

    func chooseSelectedDrawerItemPlacementDesk() {
        guard let itemID = drawer.selectedItemID else { return }
        chooseDrawerPlacementDesk(for: itemID)
    }

    func selectDrawerPlacementDesk(by offset: Int) {
        let candidates = desks.desks.filter { desks.canSelectDesk($0.id) }.map(\.id)
        drawer.placementDeskID = SelectionNavigation.next(drawer.placementDeskID, among: candidates, by: offset)
    }

    func confirmDrawerPlacementDesk() {
        guard let itemID = drawer.placementItemID, let deskID = drawer.placementDeskID else { return }
        guard desks.canSelectDesk(deskID), desks.desks.contains(where: { $0.id == deskID }) else {
            windowActions.reportWarning("Desk is no longer available.")
            return
        }
        _ = boardActions.placeDrawerItem(itemID, navigation.inheritedBoardWidth ?? boardWidth(toFit: 2), deskID)
    }

    func placeDrawerItem(inDeskNumber number: Int) {
        guard drawer.isChoosingPlacementDesk, (1...10).contains(number), desks.desks.indices.contains(number - 1)
        else { return }
        drawer.placementDeskID = desks.desks[number - 1].id
        confirmDrawerPlacementDesk()
    }
}
