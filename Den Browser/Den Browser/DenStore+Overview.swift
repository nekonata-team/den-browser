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
        overviewQuery = ""
        isOverviewFilterMode = false
        overviewSelectionDeskID = state.focusedDeskID
        overviewSelectionBoardID = focusedDesk?.focusedBoardID
    }

    func hideOverview() {
        if temporaryContext == .overview {
            setTemporaryContext(nil)
            overviewQuery = ""
            isOverviewFilterMode = false
        }
    }

    func setOverviewQuery(_ query: String) {
        overviewQuery = query
        updateOverviewSelectionForFilter()
    }

    func enterOverviewFilterMode() {
        isOverviewFilterMode = true
        updateOverviewSelectionForFilter()
    }

    func exitOverviewFilterMode() {
        isOverviewFilterMode = false
        overviewQuery = ""
    }

    func confirmOverviewFilterQuery() {
        isOverviewFilterMode = false
    }

    func clearOverviewQuery() {
        overviewQuery = ""
        updateOverviewSelectionForFilter()
    }

    func matchesOverviewFilter(_ board: BoardState, in desk: DeskState) -> Bool {
        guard !overviewQuery.isEmpty else { return true }
        return board.displayName.localizedCaseInsensitiveContains(overviewQuery)
            || (board.currentSheetURL?.absoluteString.localizedCaseInsensitiveContains(overviewQuery) ?? false)
            || desk.label.localizedCaseInsensitiveContains(overviewQuery)
    }

    private func updateOverviewSelectionForFilter() {
        if let deskID = overviewSelectionDeskID,
            let boardID = overviewSelectionBoardID,
            let desk = state.desks.first(where: { $0.id == deskID }),
            let board = desk.boards.first(where: { $0.id == boardID }),
            matchesOverviewFilter(board, in: desk)
        {
            return
        }

        for desk in state.desks {
            let matchingBoards = desk.boards.filter { matchesOverviewFilter($0, in: desk) }
            if let firstBoard = matchingBoards.first {
                overviewSelectionDeskID = desk.id
                overviewSelectionBoardID = firstBoard.id
                return
            }
        }

        overviewSelectionDeskID = nil
        overviewSelectionBoardID = nil
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
            let deskIndex = overviewSelectionDeskIndex
        else { return }

        let boards = state.desks[deskIndex].boards.filter { matchesOverviewFilter($0, in: state.desks[deskIndex]) }
        guard !boards.isEmpty else { return }

        let currentIndex =
            overviewSelectionBoardID
            .flatMap { boardID in boards.firstIndex { $0.id == boardID } } ?? 0
        let nextIndex = wrappedIndex(currentIndex + delta, count: boards.count)
        overviewSelectionBoardID = boards[nextIndex].id
    }

    private func moveOverviewDeskSelection(by delta: Int) {
        let matchingDesks = state.desks.filter { desk in
            desk.boards.contains { matchesOverviewFilter($0, in: desk) }
        }
        guard !matchingDesks.isEmpty else { return }

        let currentIndex = matchingDesks.firstIndex { $0.id == overviewSelectionDeskID } ?? 0
        let nextIndex = wrappedIndex(currentIndex + delta, count: matchingDesks.count)

        let targetDesk = matchingDesks[nextIndex]
        overviewSelectionDeskID = targetDesk.id

        let targetBoards = targetDesk.boards.filter { matchesOverviewFilter($0, in: targetDesk) }
        overviewSelectionBoardID = targetBoards.first?.id
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
