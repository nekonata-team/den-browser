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
        overviewFilterPhase = .inactive
        overviewSelection = OverviewSelection(
            deskID: presentedDeskID,
            boardID: focusedDesk?.focusedBoardID)
    }

    func hideOverview() {
        if temporaryContext == .overview {
            cancelOverviewBoardDrag()
            setTemporaryContext(nil)
            overviewQuery = ""
            overviewFilterPhase = .inactive
        }
    }

    func setOverviewQuery(_ query: String) {
        overviewQuery = query
        updateOverviewSelectionForFilter()
    }

    func enterOverviewFilterMode() {
        overviewFilterPhase = .filtering
        updateOverviewSelectionForFilter()
    }

    func exitOverviewFilterMode() {
        overviewFilterPhase = .inactive
        overviewQuery = ""
    }

    func confirmOverviewFilterQuery() {
        guard overviewFilterPhase == .filtering else { return }
        overviewFilterPhase = .selecting
    }

    func clearOverviewQuery() {
        overviewFilterPhase = .inactive
        overviewQuery = ""
        updateOverviewSelectionForFilter()
    }

    func matchesOverviewFilter(_ board: BoardState, in desk: DeskState) -> Bool {
        guard !overviewQuery.isEmpty else { return true }
        return board.displayName.localizedCaseInsensitiveContains(overviewQuery)
            || (board.currentSheetURL?.absoluteString.localizedCaseInsensitiveContains(overviewQuery) ?? false)
            || (board.terminalWorkingDirectory?.localizedCaseInsensitiveContains(overviewQuery) ?? false)
            || (board.zellijSessionName?.localizedCaseInsensitiveContains(overviewQuery) ?? false)
            || (board.zmxSessionName?.localizedCaseInsensitiveContains(overviewQuery) ?? false)
            || desk.label.localizedCaseInsensitiveContains(overviewQuery)
    }

    private func updateOverviewSelectionForFilter() {
        if let selection = overviewSelection,
            let boardID = selection.boardID,
            let desk = state.desks.first(where: { $0.id == selection.deskID }),
            let board = desk.boards.first(where: { $0.id == boardID }),
            matchesOverviewFilter(board, in: desk)
        {
            return
        }

        for desk in state.desks {
            let matchingBoards = desk.boards.filter { matchesOverviewFilter($0, in: desk) }
            if let firstBoard = matchingBoards.first {
                overviewSelection = OverviewSelection(
                    deskID: desk.id,
                    boardID: firstBoard.id)
                return
            }
        }

        overviewSelection = nil
    }

    func enterOverviewSelection() {
        guard
            let selection = overviewSelection,
            let deskIndex = state.desks.firstIndex(where: { $0.id == selection.deskID })
        else {
            hideOverview()
            return
        }

        setFocusedDesk(selection.deskID)
        if let boardID = selection.boardID,
            state.desks[deskIndex].boards.contains(where: { $0.id == boardID })
        {
            state.desks[deskIndex].focusedBoardID = boardID
        }
        isDenMode = false
        hideOverview()
        save()
    }

    func selectBoardInOverview(_ boardID: UUID) {
        guard let indices = boardIndices(for: boardID) else { return }
        overviewSelection = OverviewSelection(
            deskID: state.desks[indices.desk].id,
            boardID: boardID)
    }

    func beginOverviewBoardDrag(_ boardID: UUID) -> Bool {
        guard
            activeDrag == nil,
            temporaryContext == .overview,
            overviewQuery.isEmpty,
            overviewFilterPhase == .inactive,
            let indices = boardIndices(for: boardID)
        else { return false }

        overviewSelection = OverviewSelection(
            deskID: state.desks[indices.desk].id,
            boardID: boardID)
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
        let board = removeBoard(at: source)
        let insertionIndex = min(max(targetIndex, 0), state.desks[targetDeskIndex].boards.count)
        state.desks[targetDeskIndex].boards.insert(board, at: insertionIndex)
        if keepsDeskFocus {
            state.desks[targetDeskIndex].focusedBoardID = boardID
        }
        overviewSelection = OverviewSelection(deskID: deskID, boardID: boardID)
        activeDrag = nil
        save()
    }

    func cancelOverviewBoardDrag() {
        guard case .board? = activeDrag else { return }
        activeDrag = nil
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
        overviewSelection = OverviewSelection(
            deskID: state.desks[deskIndex].id,
            boardID: boards[nextIndex].id)
    }

    private func moveOverviewDeskSelection(by delta: Int) {
        let matchingDesks = state.desks.filter { desk in
            desk.boards.contains { matchesOverviewFilter($0, in: desk) }
        }
        guard !matchingDesks.isEmpty else { return }

        let currentIndex = matchingDesks.firstIndex { $0.id == overviewSelectionDeskID } ?? 0
        let nextIndex = wrappedIndex(currentIndex + delta, count: matchingDesks.count)

        let targetDesk = matchingDesks[nextIndex]
        let targetBoards = targetDesk.boards.filter { matchesOverviewFilter($0, in: targetDesk) }
        overviewSelection = OverviewSelection(
            deskID: targetDesk.id,
            boardID: targetBoards.first?.id)
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
        overviewSelection = OverviewSelection(
            deskID: state.desks[indices.desk].id,
            boardID: board.id)
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
        overviewSelection = OverviewSelection(
            deskID: state.desks[targetDeskIndex].id,
            boardID: board.id)
        save()
    }

    private var overviewSelectionDeskIndex: Int? {
        guard let overviewSelection else { return nil }
        return state.desks.firstIndex { $0.id == overviewSelection.deskID }
    }
}
