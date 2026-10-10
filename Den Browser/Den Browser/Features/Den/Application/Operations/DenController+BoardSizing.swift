import DenDomain
import Foundation

extension DenController {
    func adjustBoardWidth(_ boardID: BoardID, by delta: Double) {
        guard let indices = boardIndices(for: boardID) else { return }
        let deskIndex = indices.deskOffset
        let boardIndex = indices.boardOffset
        let width = state.desks[deskIndex].boards[boardIndex].width + delta
        let constrainedWidth = BoardState.constrainedWidth(width)
        guard constrainedWidth != state.desks[deskIndex].boards[boardIndex].width else { return }
        storage.state.desks[deskIndex].boards[boardIndex].width = constrainedWidth
        saveDeferredState()
    }

    func adjustDeskBoardWidths(_ deskID: DeskID, by delta: Double) {
        guard let deskIndex = state.desks.firstIndex(where: { $0.id == deskID }) else { return }
        var changed = false
        for boardIndex in state.desks[deskIndex].boards.indices {
            let width = state.desks[deskIndex].boards[boardIndex].width + delta
            let constrainedWidth = BoardState.constrainedWidth(width)
            changed = changed || constrainedWidth != state.desks[deskIndex].boards[boardIndex].width
            storage.state.desks[deskIndex].boards[boardIndex].width = constrainedWidth
        }
        if changed { saveDeferredState() }
    }

    @discardableResult
    func resizeDeskBoards(_ deskID: DeskID, to width: Double) -> Bool {
        guard let deskIndex = state.desks.firstIndex(where: { $0.id == deskID }) else { return false }

        for boardIndex in state.desks[deskIndex].boards.indices {
            storage.state.desks[deskIndex].boards[boardIndex].width = width
        }
        if state.desks[deskIndex].focusedBoardID != nil {
            storage.state.desks[deskIndex].scrollOffsetX = nil
        }
        save()
        return true
    }

    func resizeBoard(_ boardID: BoardID, to width: Double) {
        guard let indices = boardIndices(for: boardID) else { return }
        storage.state.desks[indices.deskOffset].boards[indices.boardOffset].width = BoardState.constrainedWidth(width)
    }

    func resizeBoardPair(_ boardID: BoardID, to width: Double) {
        guard let indices = boardIndices(for: boardID) else { return }
        let nextBoardIndex = indices.boardOffset + 1
        guard state.desks[indices.deskOffset].boards.indices.contains(nextBoardIndex) else { return }

        let boards = state.desks[indices.deskOffset].boards
        let totalWidth = boards[indices.boardOffset].width + boards[nextBoardIndex].width
        let minimumWidth = max(BoardState.minimumWidth, totalWidth - BoardState.maximumWidth)
        let maximumWidth = min(BoardState.maximumWidth, totalWidth - BoardState.minimumWidth)
        let resizedWidth = min(max(width, minimumWidth), maximumWidth)

        storage.state.desks[indices.deskOffset].boards[indices.boardOffset].width = resizedWidth
        storage.state.desks[indices.deskOffset].boards[nextBoardIndex].width = totalWidth - resizedWidth
    }

    func saveBoardWidths() {
        save()
    }
}
