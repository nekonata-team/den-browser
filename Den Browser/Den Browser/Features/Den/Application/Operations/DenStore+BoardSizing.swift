import DenDomain
import Foundation

extension DenStore {
    func adjustBoardWidth(_ boardID: BoardID, by delta: Double) {
        guard let indices = boardIndices(for: boardID) else { return }
        let deskIndex = indices.desk
        let boardIndex = indices.board
        let width = state.desks[deskIndex].boards[boardIndex].width + delta
        let constrainedWidth = BoardState.constrainedWidth(width)
        guard constrainedWidth != state.desks[deskIndex].boards[boardIndex].width else { return }
        state.desks[deskIndex].boards[boardIndex].width = constrainedWidth
        saveDeferredState()
    }

    func adjustDeskBoardWidths(_ deskID: DeskID, by delta: Double) {
        guard let deskIndex = state.desks.firstIndex(where: { $0.id == deskID }) else { return }
        var changed = false
        for boardIndex in state.desks[deskIndex].boards.indices {
            let width = state.desks[deskIndex].boards[boardIndex].width + delta
            let constrainedWidth = BoardState.constrainedWidth(width)
            changed = changed || constrainedWidth != state.desks[deskIndex].boards[boardIndex].width
            state.desks[deskIndex].boards[boardIndex].width = constrainedWidth
        }
        if changed { saveDeferredState() }
    }

    @discardableResult
    func resizeDeskBoards(_ deskID: DeskID, to width: Double) -> Bool {
        guard let deskIndex = state.desks.firstIndex(where: { $0.id == deskID }) else { return false }

        for boardIndex in state.desks[deskIndex].boards.indices {
            state.desks[deskIndex].boards[boardIndex].width = width
        }
        if state.desks[deskIndex].focusedBoardID != nil {
            state.desks[deskIndex].scrollOffsetX = nil
        }
        save()
        return true
    }

    func resizeBoard(_ boardID: BoardID, to width: Double) {
        guard let indices = boardIndices(for: boardID) else { return }
        state.desks[indices.desk].boards[indices.board].width = BoardState.constrainedWidth(width)
    }

    func resizeBoardPair(_ boardID: BoardID, to width: Double) {
        guard let indices = boardIndices(for: boardID) else { return }
        let nextBoardIndex = indices.board + 1
        guard state.desks[indices.desk].boards.indices.contains(nextBoardIndex) else { return }

        let boards = state.desks[indices.desk].boards
        let totalWidth = boards[indices.board].width + boards[nextBoardIndex].width
        let minimumWidth = max(BoardState.minimumWidth, totalWidth - BoardState.maximumWidth)
        let maximumWidth = min(BoardState.maximumWidth, totalWidth - BoardState.minimumWidth)
        let resizedWidth = min(max(width, minimumWidth), maximumWidth)

        state.desks[indices.desk].boards[indices.board].width = resizedWidth
        state.desks[indices.desk].boards[nextBoardIndex].width = totalWidth - resizedWidth
    }

    func saveBoardWidths() {
        save()
    }
}
