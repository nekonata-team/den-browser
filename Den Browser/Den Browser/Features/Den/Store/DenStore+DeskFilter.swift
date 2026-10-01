import Foundation

extension DenStore {
    var filteredDeskBoards: [BoardState] {
        guard let focusedDesk else { return [] }
        return focusedDesk.boards.filter(matchesDeskFilter)
    }

    func enterDeskFilter() {
        guard focusedDesk?.boards.isEmpty == false else { return }
        deskFilterPhase = .filtering
        updateDeskFilterSelection()
    }

    func setDeskFilterQuery(_ query: String) {
        deskFilterQuery = SheetURLPolicy.stripNewlines(query)
        updateDeskFilterSelection()
    }

    func confirmDeskFilterQuery() {
        guard deskFilterPhase == .filtering else { return }
        deskFilterPhase = .selecting
    }

    func dismissDeskFilter() {
        cancelDeskFilterCentering()
        deskFilterPhase = .inactive
        deskFilterQuery = ""
        deskFilterSelectionBoardID = nil
    }

    func cancelDeskFilterCentering() {
        deskFilterCenteringTask?.cancel()
        deskFilterCenteringTask = nil
    }

    func selectDeskFilterBoard(by offset: Int) {
        let boards = filteredDeskBoards
        deskFilterSelectionBoardID = DenSelectionNavigation.next(
            deskFilterSelectionBoardID,
            among: boards.map(\.id),
            by: offset)
    }

    func confirmDeskFilterSelection(_ boardID: UUID? = nil) {
        guard
            let boardID = boardID ?? deskFilterSelectionBoardID,
            filteredDeskBoards.contains(where: { $0.id == boardID })
        else { return }
        dismissDeskFilter()
        focusBoard(boardID, exitsDenMode: true)
        deskFilterCenteringTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled,
                let self,
                self.deskFilterPhase == .inactive,
                self.focusedDesk?.focusedBoardID == boardID
            else { return }
            self.centerFocusedBoardRequest += 1
        }
    }

    func matchesDeskFilter(_ board: BoardState) -> Bool {
        guard !deskFilterQuery.isEmpty else { return true }
        return board.displayName.localizedCaseInsensitiveContains(deskFilterQuery)
            || (board.currentSheetURL?.absoluteString.localizedCaseInsensitiveContains(deskFilterQuery) ?? false)
            || (board.terminalWorkingDirectory?.localizedCaseInsensitiveContains(deskFilterQuery) ?? false)
            || (board.zellijSessionName?.localizedCaseInsensitiveContains(deskFilterQuery) ?? false)
            || (board.zmxSessionName?.localizedCaseInsensitiveContains(deskFilterQuery) ?? false)
    }

    private func updateDeskFilterSelection() {
        let boards = filteredDeskBoards
        if let deskFilterSelectionBoardID,
            boards.contains(where: { $0.id == deskFilterSelectionBoardID })
        {
            return
        }
        if let focusedBoardID = focusedDesk?.focusedBoardID,
            boards.contains(where: { $0.id == focusedBoardID })
        {
            deskFilterSelectionBoardID = focusedBoardID
        } else {
            deskFilterSelectionBoardID = boards.first?.id
        }
    }
}
