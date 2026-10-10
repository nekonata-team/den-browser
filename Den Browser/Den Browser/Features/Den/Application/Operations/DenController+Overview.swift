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
        guard activeDrag == nil, boardIndices(for: boardID) != nil else { return false }
        storage.activeDrag = .board(boardID)
        return true
    }

    func finishOverviewBoardDrag(_ boardID: BoardID, toDeskID deskID: DeskID, at targetIndex: BoardIndex) {
        guard
            case .board(let activeBoardID)? = activeDrag,
            activeBoardID == boardID,
            let source = boardIndices(for: boardID),
            let targetDeskOffset = state.desks.firstIndex(where: { $0.id == deskID })
        else { return }

        let targetDeskIndex = DeskIndex(rawValue: targetDeskOffset)
        let keepsDeskFocus =
            source.desk == targetDeskIndex
            && state.desks[source.deskOffset].focusedBoardID == boardID
        if source.desk == targetDeskIndex {
            reorderBoardGroup(
                containing: boardID,
                to: targetIndex,
                in: source.desk)
        } else {
            transferBoardGroup(
                containing: boardID, from: source.desk, to: targetDeskIndex, at: targetIndex)
        }
        if keepsDeskFocus || state.desks[targetDeskOffset].focusedBoardID == nil {
            storage.state.desks[targetDeskOffset].focusedBoardID = boardID
        }
        storage.activeDrag = nil
        save()
    }

    func cancelOverviewBoardDrag() {
        guard case .board? = activeDrag else { return }
        storage.activeDrag = nil
    }

    func moveOverviewBoardGroup(_ boardID: BoardID, by delta: Int) {
        guard activeDrag == nil, let indices = boardIndices(for: boardID) else { return }
        let boards = state.desks[indices.deskOffset].boards
        guard boards.count > 1,
            let group = BoardGroup.containing(boardID, in: boards),
            let first = group.boards.first,
            let last = group.boards.last,
            let firstIndex = boards.firstIndex(where: { $0.id == first.id }),
            let lastIndex = boards.firstIndex(where: { $0.id == last.id })
        else { return }
        let targetIndex = delta < 0 ? firstIndex - 1 : lastIndex + 1
        guard boards.indices.contains(targetIndex) else { return }
        reorderBoardGroup(
            containing: boardID,
            to: BoardIndex(rawValue: targetIndex),
            in: indices.desk)
        save()
    }

    func moveOverviewBoardGroupToDesk(_ boardID: BoardID, by delta: Int) {
        guard activeDrag == nil, state.desks.count > 1, let source = boardIndices(for: boardID) else { return }
        let targetDeskIndex = DeskIndex(
            rawValue: wrappedIndex(source.desk.rawValue + delta, count: state.desks.count))
        let targetDeskOffset = targetDeskIndex.rawValue
        let insertIndex: BoardIndex
        if let focusedBoardID = state.desks[targetDeskOffset].focusedBoardID,
            let focusedIndex = state.desks[targetDeskOffset].boards.firstIndex(where: { $0.id == focusedBoardID })
        {
            insertIndex = BoardIndex(rawValue: focusedIndex + 1)
        } else {
            insertIndex = BoardIndex(rawValue: state.desks[targetDeskOffset].boards.endIndex)
        }

        transferBoardGroup(
            containing: boardID, from: source.desk, to: targetDeskIndex, at: insertIndex)
        if state.desks[targetDeskOffset].focusedBoardID == nil {
            storage.state.desks[targetDeskOffset].focusedBoardID = boardID
        }
        save()
    }
}
