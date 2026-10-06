import DenDomain
import Foundation
import Observation

@MainActor
@Observable
final class DeskFilterViewModel {
    let store: DenStore
    var query = ""
    var phase: DenFilterPhase = .inactive
    var selectionBoardID: UUID?

    @ObservationIgnored private var centeringTask: Task<Void, Never>?
    @ObservationIgnored var onCenterFocusedBoard: (() -> Void)?

    init(store: DenStore) {
        self.store = store
    }

    deinit {
        centeringTask?.cancel()
    }

    var filteredBoards: [BoardState] {
        guard let focusedDesk = store.focusedDesk else { return [] }
        return focusedDesk.boards.filter(matchesFilter)
    }

    var totalBoardCount: Int { store.focusedDesk?.boards.count ?? 0 }

    var isPresented: Bool { phase != .inactive }
    var isInputActive: Bool { phase == .filtering }
    var isSelecting: Bool { phase == .selecting }

    func enter() {
        guard store.focusedDesk?.boards.isEmpty == false else { return }
        phase = .filtering
        updateSelection()
    }

    func setQuery(_ query: String) {
        self.query = WebURLPolicy.stripNewlines(query)
        updateSelection()
    }

    func confirmQuery() {
        guard phase == .filtering else { return }
        phase = .selecting
    }

    func dismiss() {
        cancelCentering()
        phase = .inactive
        query = ""
        selectionBoardID = nil
    }

    func cancelCentering() {
        centeringTask?.cancel()
        centeringTask = nil
    }

    func selectBoard(by offset: Int) {
        let boards = filteredBoards
        selectionBoardID = DenSelectionNavigation.next(
            selectionBoardID,
            among: boards.map(\.id),
            by: offset)
    }

    func confirmSelection(_ boardID: UUID? = nil) {
        guard
            let boardID = boardID ?? selectionBoardID,
            filteredBoards.contains(where: { $0.id == boardID })
        else { return }
        dismiss()
        store.focusBoard(boardID, exitsDenMode: true)
        centeringTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled,
                let self,
                self.phase == .inactive,
                self.store.focusedDesk?.focusedBoardID == boardID
            else { return }
            self.onCenterFocusedBoard?()
        }
    }

    func matchesFilter(_ board: BoardState) -> Bool {
        guard !query.isEmpty else { return true }
        return board.displayName.localizedCaseInsensitiveContains(query)
            || (board.currentSheetURL?.absoluteString.localizedCaseInsensitiveContains(query) ?? false)
            || (board.terminalWorkingDirectory?.localizedCaseInsensitiveContains(query) ?? false)
            || (board.zellijSessionName?.localizedCaseInsensitiveContains(query) ?? false)
            || (board.zmxSessionName?.localizedCaseInsensitiveContains(query) ?? false)
    }

    private func updateSelection() {
        let boards = filteredBoards
        if let selectionBoardID, boards.contains(where: { $0.id == selectionBoardID }) { return }
        if let focusedBoardID = store.focusedDesk?.focusedBoardID,
            boards.contains(where: { $0.id == focusedBoardID })
        {
            selectionBoardID = focusedBoardID
        } else {
            selectionBoardID = boards.first?.id
        }
    }
}
