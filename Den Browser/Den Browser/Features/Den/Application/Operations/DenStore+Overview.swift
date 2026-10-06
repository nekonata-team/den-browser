import DenDomain
import Foundation

extension DenStore {
    func enterOverviewSelection(deskID: UUID, boardID: UUID?) {
        guard let deskIndex = state.desks.firstIndex(where: { $0.id == deskID }) else {
            onWindowEffect?(.dismissTemporaryPresentation)
            return
        }

        let previousFocusedDeskID = state.focusedDeskID
        let previousFocusedBoardID = state.desks[deskIndex].focusedBoardID
        if let boardID, state.desks[deskIndex].boards.contains(where: { $0.id == boardID }) {
            state.desks[deskIndex].focusedBoardID = boardID
        } else if state.desks[deskIndex].focusedBoardID == nil {
            state.desks[deskIndex].focusedBoardID = state.desks[deskIndex].boards.first?.id
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

    func beginOverviewBoardDrag(_ boardID: UUID) -> Bool {
        guard activeDrag == nil, boardIndices(for: boardID) != nil else { return false }
        activeDrag = .board(boardID)
        return true
    }

    func finishOverviewBoardDrag(_ boardID: UUID, toDeskID deskID: UUID, at targetIndex: Int) {
        guard
            case .board(let activeBoardID)? = activeDrag,
            activeBoardID == boardID,
            let source = boardIndices(for: boardID),
            let targetDeskIndex = state.desks.firstIndex(where: { $0.id == deskID })
        else { return }

        let keepsDeskFocus =
            source.desk == targetDeskIndex
            && state.desks[source.desk].focusedBoardID == boardID
        if source.desk == targetDeskIndex {
            reorderBoardGroup(containing: boardID, to: targetIndex, in: source.desk)
        } else {
            transferBoardGroup(containing: boardID, from: source.desk, to: targetDeskIndex, at: targetIndex)
        }
        if keepsDeskFocus || state.desks[targetDeskIndex].focusedBoardID == nil {
            state.desks[targetDeskIndex].focusedBoardID = boardID
        }
        activeDrag = nil
        save()
    }

    func cancelOverviewBoardDrag() {
        guard case .board? = activeDrag else { return }
        activeDrag = nil
    }

    func moveOverviewBoardGroup(_ boardID: UUID, by delta: Int) {
        guard activeDrag == nil, let indices = boardIndices(for: boardID) else { return }
        let boards = state.desks[indices.desk].boards
        guard boards.count > 1,
            let group = BoardGroup.containing(boardID, in: boards),
            let first = group.boards.first,
            let last = group.boards.last,
            let firstIndex = boards.firstIndex(where: { $0.id == first.id }),
            let lastIndex = boards.firstIndex(where: { $0.id == last.id })
        else { return }
        let targetIndex = delta < 0 ? firstIndex - 1 : lastIndex + 1
        guard boards.indices.contains(targetIndex) else { return }
        reorderBoardGroup(containing: boardID, to: targetIndex, in: indices.desk)
        save()
    }

    func moveOverviewBoardGroupToDesk(_ boardID: UUID, by delta: Int) {
        guard activeDrag == nil, state.desks.count > 1, let source = boardIndices(for: boardID) else { return }
        let targetDeskIndex = wrappedIndex(source.desk + delta, count: state.desks.count)
        let insertIndex: Int
        if let focusedBoardID = state.desks[targetDeskIndex].focusedBoardID,
            let focusedIndex = state.desks[targetDeskIndex].boards.firstIndex(where: { $0.id == focusedBoardID })
        {
            insertIndex = focusedIndex + 1
        } else {
            insertIndex = state.desks[targetDeskIndex].boards.endIndex
        }

        transferBoardGroup(containing: boardID, from: source.desk, to: targetDeskIndex, at: insertIndex)
        if state.desks[targetDeskIndex].focusedBoardID == nil {
            state.desks[targetDeskIndex].focusedBoardID = boardID
        }
        save()
    }
}
