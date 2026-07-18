import Foundation

extension DenStore {
    func focusDesk(_ deskID: UUID) {
        guard state.desks.contains(where: { $0.id == deskID }) else { return }
        state.focusedDeskID = deskID
        save()
    }

    func focusBoard(_ boardID: UUID) {
        guard let indices = boardIndices(for: boardID) else { return }
        let deskID = state.desks[indices.desk].id
        guard state.focusedDeskID != deskID || state.desks[indices.desk].focusedBoardID != boardID else { return }
        state.focusedDeskID = deskID
        state.desks[indices.desk].focusedBoardID = boardID
        save()
    }

    func focusPreviousDesk() {
        moveDeskFocus(by: -1)
    }

    func focusNextDesk() {
        moveDeskFocus(by: 1)
    }

    func focusPreviousBoard() {
        moveBoardFocus(by: -1)
    }

    func focusNextBoard() {
        moveBoardFocus(by: 1)
    }

    func moveFocusedBoardLeft() {
        moveFocusedBoard(by: -1)
    }

    func moveFocusedBoardRight() {
        moveFocusedBoard(by: 1)
    }

    func moveFocusedBoardToPreviousDesk() {
        moveFocusedBoardToDesk(by: -1)
    }

    func moveFocusedBoardToNextDesk() {
        moveFocusedBoardToDesk(by: 1)
    }

    func toggleFocusedBoardMaximized() {
        guard let focusedBoardID = focusedDesk?.focusedBoardID else { return }
        maximizedBoardID = maximizedBoardID == focusedBoardID ? nil : focusedBoardID
        centerFocusedBoard()
    }

    func centerFocusedBoard() {
        guard focusedDesk?.focusedBoardID != nil else { return }
        centerFocusedBoardRequest &+= 1
    }

    func focusDesk(number: Int) {
        guard (1...Self.maximumDeskCount).contains(number), state.desks.indices.contains(number - 1) else { return }
        state.focusedDeskID = state.desks[number - 1].id
        ensureFocusedObjects()
        save()
    }

    func moveFocusedBoard(toDeskNumber number: Int) {
        guard (1...Self.maximumDeskCount).contains(number), state.desks.indices.contains(number - 1) else { return }
        moveFocusedBoard(toDeskAt: number - 1)
    }

    func focusedBoardIndex(in deskIndex: Int) -> Int? {
        guard let focusedBoardID = state.desks[deskIndex].focusedBoardID else { return nil }
        return state.desks[deskIndex].boards.firstIndex { $0.id == focusedBoardID }
    }

    func canMoveBoard(_ boardID: UUID, by delta: Int) -> Bool {
        guard let indices = boardIndices(for: boardID) else { return false }
        return state.desks[indices.desk].boards.indices.contains(indices.board + delta)
    }

    func beginBoardDrag(_ boardID: UUID) -> Bool {
        guard
            !isBoardDragging,
            temporaryContext == nil,
            let indices = boardIndices(for: boardID),
            indices.desk == focusedDeskIndex
        else {
            return false
        }
        state.desks[indices.desk].focusedBoardID = boardID
        maximizedBoardID = nil
        isBoardDragging = true
        save()
        return true
    }

    func previewBoardMove(_ boardID: UUID, to targetIndex: Int) {
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = state.desks[deskIndex].boards.firstIndex(where: { $0.id == boardID }),
            (0..<state.desks[deskIndex].boards.count).contains(targetIndex)
        else { return }

        let board = state.desks[deskIndex].boards.remove(at: boardIndex)
        state.desks[deskIndex].boards.insert(board, at: targetIndex)
        state.desks[deskIndex].focusedBoardID = boardID
    }

    func restoreBoardOrder(_ boardIDs: [UUID], in deskID: UUID) {
        guard let deskIndex = state.desks.firstIndex(where: { $0.id == deskID }) else { return }
        let order = Dictionary(uniqueKeysWithValues: boardIDs.enumerated().map { ($1, $0) })
        state.desks[deskIndex].boards.sort {
            (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max)
        }
    }

    func finishBoardDrag() {
        guard isBoardDragging else { return }
        isBoardDragging = false
        save()
    }

    func requestBoardDragCancellation() {
        guard isBoardDragging else { return }
        boardDragCancellationRequest &+= 1
    }

    private func moveDeskFocus(by delta: Int) {
        guard let currentIndex = focusedDeskIndex, !state.desks.isEmpty else { return }
        let nextIndex = wrappedIndex(currentIndex + delta, count: state.desks.count)
        state.focusedDeskID = state.desks[nextIndex].id
        ensureFocusedObjects()
        save()
    }

    private func moveBoardFocus(by delta: Int) {
        guard
            let deskIndex = focusedDeskIndex,
            let currentIndex = focusedBoardIndex(in: deskIndex)
        else { return }

        let boards = state.desks[deskIndex].boards
        guard !boards.isEmpty else { return }

        let nextIndex = wrappedIndex(currentIndex + delta, count: boards.count)
        state.desks[deskIndex].focusedBoardID = boards[nextIndex].id
        save()
    }

    private func moveFocusedBoard(by delta: Int) {
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex),
            state.desks[deskIndex].boards.indices.contains(boardIndex + delta)
        else { return }

        var boards = state.desks[deskIndex].boards
        let board = boards.remove(at: boardIndex)
        boards.insert(board, at: boardIndex + delta)

        state.desks[deskIndex].boards = boards
        state.desks[deskIndex].focusedBoardID = board.id
        centerFocusedBoard()
        save()
    }

    private func moveFocusedBoardToDesk(by delta: Int) {
        guard
            state.desks.count > 1,
            let sourceDeskIndex = focusedDeskIndex
        else { return }

        moveFocusedBoard(toDeskAt: wrappedIndex(sourceDeskIndex + delta, count: state.desks.count))
    }

    private func moveFocusedBoard(toDeskAt targetDeskIndex: Int) {
        guard
            state.desks.indices.contains(targetDeskIndex),
            let sourceDeskIndex = focusedDeskIndex,
            sourceDeskIndex != targetDeskIndex,
            let sourceBoardIndex = focusedBoardIndex(in: sourceDeskIndex)
        else { return }

        let board = removeBoard(at: (desk: sourceDeskIndex, board: sourceBoardIndex))
        let insertIndex: Int
        if let focusedBoardID = state.desks[targetDeskIndex].focusedBoardID,
            let focusedIndex = state.desks[targetDeskIndex].boards.firstIndex(where: { $0.id == focusedBoardID })
        {
            insertIndex = focusedIndex + 1
        } else {
            insertIndex = state.desks[targetDeskIndex].boards.endIndex
        }

        state.desks[targetDeskIndex].boards.insert(board, at: insertIndex)
        state.desks[targetDeskIndex].focusedBoardID = board.id
        state.focusedDeskID = state.desks[targetDeskIndex].id
        save()
    }
}
