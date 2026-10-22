import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

extension DenController {
    func enterOverviewSelection(deskID: DeskID, boardID: BoardID?) {
        guard let deskIndex = state.desks.firstIndex(where: { $0.id == deskID }) else {
            onWindowEffect?(.dismissTemporaryPresentation)
            return
        }

        let previousFocusedDeskID = state.focusedDeskID
        let previousFocusedBoardID = state.desks[deskIndex].focusedBoardID
        if let boardID, state.desks[deskIndex].boards.contains(where: { $0.id == boardID }) {
            storage.state.desks[deskIndex].focusedBoardID = boardID
        } else if state.desks[deskIndex].focusedBoardID == nil {
            storage.state.desks[deskIndex].focusedBoardID = state.desks[deskIndex].boards.first?.id
        }
        let changedDesk = setFocusedDesk(deskID)
        if !changedDesk,
            presentedDeskID == deskID,
            let boardID = state.desks[deskIndex].focusedBoardID
        {
            markNotificationsRead(for: boardID)
        }
        onWindowEffect?(.dismissTemporaryPresentation)
        onWindowEffect?(.exitDenMode)
        if state.focusedDeskID != previousFocusedDeskID
            || state.desks[deskIndex].focusedBoardID != previousFocusedBoardID
        {
            saveDeferredState()
        }
    }

    func beginOverviewBoardDrag(_ boardID: BoardID) -> Bool {
        storage.boardMovement.beginOverviewDrag(boardID)
    }

    func finishOverviewBoardDrag(_ boardID: BoardID, toDeskID deskID: DeskID, at targetIndex: BoardIndex) {
        storage.boardMovement.finishOverviewDrag(boardID, to: deskID, at: targetIndex)
    }

    func cancelOverviewBoardDrag() {
        storage.boardMovement.cancelOverviewDrag()
    }

    func moveOverviewBoardGroup(_ boardID: BoardID, by delta: Int) {
        storage.boardMovement.shiftInOverview(boardID, by: delta)
    }

    func moveOverviewBoardGroupToDesk(_ boardID: BoardID, by delta: Int) {
        storage.boardMovement.transferInOverview(boardID, by: delta)
    }
}
