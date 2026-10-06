import DenDomain
import Foundation
import Observation

struct OverviewSelection: Equatable {
    let deskID: UUID
    let boardID: UUID?
}

@MainActor
@Observable
final class OverviewViewModel {
    let store: DenStore

    var query = ""
    var filterPhase: DenFilterPhase = .inactive
    private(set) var selection: OverviewSelection?

    @ObservationIgnored var onDismiss: (() -> Void)?

    var isFilterPresented: Bool { filterPhase != .inactive }
    var isFilterInputActive: Bool { filterPhase == .filtering }
    var isFilterSelecting: Bool { filterPhase == .selecting }
    var selectionDeskID: UUID? { selection?.deskID }
    var selectionBoardID: UUID? { selection?.boardID }

    init(store: DenStore) {
        self.store = store
    }

    func preparePresentation(deskID: UUID? = nil, boardID: UUID? = nil) {
        query = ""
        filterPhase = .inactive
        selection = OverviewSelection(
            deskID: deskID ?? store.presentedDeskID,
            boardID: boardID ?? store.focusedDesk?.focusedBoardID)
    }

    func endPresentation() {
        store.cancelOverviewBoardDrag()
        query = ""
        filterPhase = .inactive
        selection = nil
    }

    func setQuery(_ query: String) {
        self.query = WebURLPolicy.stripNewlines(query)
        updateSelectionForFilter()
    }

    func enterFilterMode() {
        filterPhase = .filtering
        updateSelectionForFilter()
    }

    func exitFilterMode() {
        filterPhase = .inactive
        query = ""
    }

    func confirmFilterQuery() {
        guard filterPhase == .filtering else { return }
        filterPhase = .selecting
    }

    func clearQuery() {
        filterPhase = .inactive
        query = ""
        updateSelectionForFilter()
    }

    func matchesFilter(_ board: BoardState, in desk: DeskState) -> Bool {
        guard !query.isEmpty else { return true }
        return board.displayName.localizedCaseInsensitiveContains(query)
            || (board.currentSheetURL?.absoluteString.localizedCaseInsensitiveContains(query) ?? false)
            || (board.terminalWorkingDirectory?.localizedCaseInsensitiveContains(query) ?? false)
            || (board.zellijSessionName?.localizedCaseInsensitiveContains(query) ?? false)
            || (board.zmxSessionName?.localizedCaseInsensitiveContains(query) ?? false)
            || desk.label.localizedCaseInsensitiveContains(query)
    }

    func updateSelectionForFilter() {
        if let selection,
            let boardID = selection.boardID,
            let desk = store.state.desks.first(where: { $0.id == selection.deskID }),
            let board = desk.boards.first(where: { $0.id == boardID }),
            matchesFilter(board, in: desk)
        {
            return
        }

        for desk in store.state.desks {
            if let board = desk.boards.first(where: { matchesFilter($0, in: desk) }) {
                selection = OverviewSelection(deskID: desk.id, boardID: board.id)
                return
            }
        }
        selection = nil
    }

    func enterSelection() {
        guard let selection else {
            onDismiss?()
            return
        }
        store.enterOverviewSelection(deskID: selection.deskID, boardID: selection.boardID)
    }

    func selectBoard(_ boardID: UUID) {
        guard let indices = store.boardIndices(for: boardID) else { return }
        selection = OverviewSelection(deskID: store.state.desks[indices.desk].id, boardID: boardID)
    }

    func enterBoard(_ boardID: UUID) {
        selectBoard(boardID)
        enterSelection()
    }

    func selectDesk(_ deskID: UUID) {
        guard store.state.desks.contains(where: { $0.id == deskID }) else { return }
        selection = OverviewSelection(deskID: deskID, boardID: nil)
    }

    func enterDesk(_ deskID: UUID) {
        selectDesk(deskID)
        enterSelection()
    }

    func beginBoardDrag(_ boardID: UUID) -> Bool {
        guard query.isEmpty, filterPhase == .inactive, store.beginOverviewBoardDrag(boardID) else { return false }
        selectBoard(boardID)
        return true
    }

    func finishBoardDrag(_ boardID: UUID, toDeskID deskID: UUID, at targetIndex: Int) {
        guard case .board(let activeBoardID)? = store.activeDrag, activeBoardID == boardID else { return }
        store.finishOverviewBoardDrag(boardID, toDeskID: deskID, at: targetIndex)
        selection = OverviewSelection(deskID: deskID, boardID: boardID)
    }

    func cancelBoardDrag() { store.cancelOverviewBoardDrag() }

    func selectPreviousBoard() { moveBoardSelection(by: -1) }
    func selectNextBoard() { moveBoardSelection(by: 1) }
    func selectPreviousDesk() { moveDeskSelection(by: -1) }
    func selectNextDesk() { moveDeskSelection(by: 1) }
    func moveSelectionBoardLeft() { moveSelectionBoard(by: -1) }
    func moveSelectionBoardRight() { moveSelectionBoard(by: 1) }
    func moveSelectionBoardToPreviousDesk() { moveSelectionBoardToDesk(by: -1) }
    func moveSelectionBoardToNextDesk() { moveSelectionBoardToDesk(by: 1) }

    func removedBoard(boardID: UUID, deskID: UUID, oldIndex: Int) {
        guard selection?.boardID == boardID,
            let desk = store.state.desks.first(where: { $0.id == deskID })
        else { return }
        let nextBoardID =
            desk.boards.indices.contains(oldIndex)
            ? desk.boards[oldIndex].id
            : (oldIndex > 0 && desk.boards.indices.contains(oldIndex - 1)
                ? desk.boards[oldIndex - 1].id
                : nil)
        selection = OverviewSelection(deskID: deskID, boardID: nextBoardID)
    }

    func invalidateBoard(_ boardID: UUID) {
        guard selection?.boardID == boardID else { return }
        selection = nil
    }

    func invalidateDesk(_ deskID: UUID) {
        guard selection?.deskID == deskID else { return }
        selection = nil
    }

    private func moveBoardSelection(by delta: Int) {
        guard let selection,
            let desk = store.state.desks.first(where: { $0.id == selection.deskID })
        else { return }
        let boards = desk.boards.filter { matchesFilter($0, in: desk) }
        guard !boards.isEmpty else { return }
        let index = selection.boardID.flatMap { id in boards.firstIndex { $0.id == id } } ?? 0
        self.selection = OverviewSelection(
            deskID: desk.id,
            boardID: boards[store.wrappedIndex(index + delta, count: boards.count)].id)
    }

    private func moveDeskSelection(by delta: Int) {
        let desks = store.state.desks.filter { desk in
            query.isEmpty || desk.boards.contains { matchesFilter($0, in: desk) }
        }
        guard !desks.isEmpty else { return }
        let index = desks.firstIndex { $0.id == selection?.deskID } ?? 0
        let desk = desks[store.wrappedIndex(index + delta, count: desks.count)]
        let boards = desk.boards.filter { matchesFilter($0, in: desk) }
        selection = OverviewSelection(
            deskID: desk.id,
            boardID: boards.first(where: { $0.id == desk.focusedBoardID })?.id ?? boards.first?.id)
    }

    private func moveSelectionBoard(by delta: Int) {
        guard store.activeDrag == nil, let boardID = selection?.boardID else { return }
        store.moveOverviewBoardGroup(boardID, by: delta)
        selectBoard(boardID)
    }

    private func moveSelectionBoardToDesk(by delta: Int) {
        guard store.activeDrag == nil, let boardID = selection?.boardID else { return }
        store.moveOverviewBoardGroupToDesk(boardID, by: delta)
        selectBoard(boardID)
    }
}
