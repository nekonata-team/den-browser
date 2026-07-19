import Foundation

extension DenStore {
    func toggleOverview() {
        if isOverviewPresented {
            hideOverview()
        } else {
            showOverview()
        }
    }

    func showOverview() {
        setTemporaryContext(.overview)
        overviewSelectionDeskID = state.focusedDeskID
        overviewSelectionBoardID = focusedDesk?.focusedBoardID
    }

    func hideOverview() {
        if temporaryContext == .overview {
            setTemporaryContext(nil)
        }
    }

    func enterOverviewSelection() {
        guard
            let deskID = overviewSelectionDeskID,
            let deskIndex = state.desks.firstIndex(where: { $0.id == deskID })
        else {
            hideOverview()
            return
        }

        let changed = state.focusedDeskID != deskID
        state.focusedDeskID = deskID
        if let boardID = overviewSelectionBoardID,
            state.desks[deskIndex].boards.contains(where: { $0.id == boardID })
        {
            state.desks[deskIndex].focusedBoardID = boardID
        }
        if changed {
            isDenMode = false
        }
        hideOverview()
        save()
    }

    func selectBoardInOverview(_ boardID: UUID) {
        guard let indices = boardIndices(for: boardID) else { return }
        overviewSelectionDeskID = state.desks[indices.desk].id
        overviewSelectionBoardID = boardID
    }

    func selectPreviousBoardInOverview() {
        moveOverviewBoardSelection(by: -1)
    }

    func selectNextBoardInOverview() {
        moveOverviewBoardSelection(by: 1)
    }

    func selectPreviousDeskInOverview() {
        moveOverviewDeskSelection(by: -1)
    }

    func selectNextDeskInOverview() {
        moveOverviewDeskSelection(by: 1)
    }

    func moveOverviewSelectionBoardLeft() {
        moveOverviewSelectionBoard(by: -1)
    }

    func moveOverviewSelectionBoardRight() {
        moveOverviewSelectionBoard(by: 1)
    }

    func moveOverviewSelectionBoardToPreviousDesk() {
        moveOverviewSelectionBoardToDesk(by: -1)
    }

    func moveOverviewSelectionBoardToNextDesk() {
        moveOverviewSelectionBoardToDesk(by: 1)
    }

    private func moveOverviewBoardSelection(by delta: Int) {
        guard
            let deskIndex = overviewSelectionDeskIndex,
            !state.desks[deskIndex].boards.isEmpty
        else { return }

        let boards = state.desks[deskIndex].boards
        let currentIndex =
            overviewSelectionBoardID
            .flatMap { boardID in boards.firstIndex { $0.id == boardID } } ?? 0
        let nextIndex = wrappedIndex(currentIndex + delta, count: boards.count)
        overviewSelectionBoardID = boards[nextIndex].id
    }

    private func moveOverviewDeskSelection(by delta: Int) {
        guard !state.desks.isEmpty else { return }
        let currentIndex = overviewSelectionDeskIndex ?? focusedDeskIndex ?? 0
        let nextIndex = wrappedIndex(currentIndex + delta, count: state.desks.count)
        overviewSelectionDeskID = state.desks[nextIndex].id
        overviewSelectionBoardID = state.desks[nextIndex].focusedBoardID ?? state.desks[nextIndex].boards.first?.id
    }

    private func moveOverviewSelectionBoard(by delta: Int) {
        guard
            let boardID = overviewSelectionBoardID,
            let indices = boardIndices(for: boardID)
        else { return }

        var boards = state.desks[indices.desk].boards
        guard boards.count > 1 else { return }

        let board = boards.remove(at: indices.board)
        let targetIndex = min(max(indices.board + delta, 0), boards.count)
        boards.insert(board, at: targetIndex)
        state.desks[indices.desk].boards = boards
        overviewSelectionDeskID = state.desks[indices.desk].id
        overviewSelectionBoardID = board.id
        save()
    }

    private func moveOverviewSelectionBoardToDesk(by delta: Int) {
        guard
            let boardID = overviewSelectionBoardID,
            state.desks.count > 1,
            let source = boardIndices(for: boardID)
        else { return }

        let board = removeBoard(at: source)

        let targetDeskIndex = wrappedIndex(source.desk + delta, count: state.desks.count)
        let insertIndex: Int
        if let focusedBoardID = state.desks[targetDeskIndex].focusedBoardID,
            let focusedIndex = state.desks[targetDeskIndex].boards.firstIndex(where: { $0.id == focusedBoardID })
        {
            insertIndex = focusedIndex + 1
        } else {
            insertIndex = state.desks[targetDeskIndex].boards.endIndex
        }

        state.desks[targetDeskIndex].boards.insert(board, at: insertIndex)
        overviewSelectionDeskID = state.desks[targetDeskIndex].id
        overviewSelectionBoardID = board.id
        save()
    }

    private var overviewSelectionDeskIndex: Int? {
        guard let overviewSelectionDeskID else { return nil }
        return state.desks.firstIndex { $0.id == overviewSelectionDeskID }
    }
}
