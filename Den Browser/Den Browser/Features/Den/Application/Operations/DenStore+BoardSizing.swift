import Foundation

extension DenStore {
    func adjustFocusedBoardWidth(by delta: Double) {
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex)
        else { return }

        maximizedBoardID = nil
        let width = state.desks[deskIndex].boards[boardIndex].width + delta
        let constrainedWidth = BoardState.constrainedWidth(width)
        guard constrainedWidth != state.desks[deskIndex].boards[boardIndex].width else { return }
        state.desks[deskIndex].boards[boardIndex].width = constrainedWidth
        saveDeferredState()
    }

    func adjustFocusedDeskBoardWidths(by delta: Double) {
        guard let deskIndex = focusedDeskIndex else { return }

        maximizedBoardID = nil
        var changed = false
        for boardIndex in state.desks[deskIndex].boards.indices {
            let width = state.desks[deskIndex].boards[boardIndex].width + delta
            let constrainedWidth = BoardState.constrainedWidth(width)
            changed = changed || constrainedWidth != state.desks[deskIndex].boards[boardIndex].width
            state.desks[deskIndex].boards[boardIndex].width = constrainedWidth
        }
        if changed { saveDeferredState() }
    }

    func updateBoardLayout(availableWidth: Double, spacing: Double) {
        boardLayoutMetrics =
            availableWidth > 0
            ? BoardLayoutMetrics(availableWidth: availableWidth, spacing: spacing)
            : nil
    }

    func boardWidth(toFit count: Int) -> Double? {
        guard let boardLayoutMetrics else { return nil }
        return DenLayout.boardWidth(
            toFit: count,
            in: boardLayoutMetrics.availableWidth,
            spacing: boardLayoutMetrics.spacing
        )
    }

    func canResizeFocusedDeskBoards(toFit count: Int) -> Bool {
        focusedDesk?.boards.isEmpty == false
            && boardWidth(toFit: count) != nil
    }

    func showBoardWidthPanel() {
        guard focusedDesk?.boards.isEmpty == false else { return }
        boardWidthPanelMessage = nil
        setTemporaryContext(.boardWidth)
    }

    func hideBoardWidthPanel() {
        if temporaryContext == .boardWidth {
            setTemporaryContext(nil)
        }
    }

    @discardableResult
    func resizeFocusedDeskBoards(toFit count: Int) -> Bool {
        guard let deskIndex = focusedDeskIndex, let width = boardWidth(toFit: count) else {
            boardWidthPanelMessage = "\(count) Boards cannot fit at this window width"
            return false
        }

        for boardIndex in state.desks[deskIndex].boards.indices {
            state.desks[deskIndex].boards[boardIndex].width = width
        }
        maximizedBoardID = nil
        hideBoardWidthPanel()
        if focusedDesk?.focusedBoardID != nil {
            state.desks[deskIndex].scrollOffsetX = nil
        }
        centerFocusedBoard()
        save()
        return true
    }

    func resizeBoard(_ boardID: UUID, to width: Double) {
        guard let indices = boardIndices(for: boardID) else { return }
        state.desks[indices.desk].boards[indices.board].width = BoardState.constrainedWidth(width)
    }

    func resizeBoardPair(_ boardID: UUID, to width: Double) {
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
