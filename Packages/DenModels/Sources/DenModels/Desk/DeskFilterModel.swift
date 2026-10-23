import DenDomain
import Foundation
import Observation

@MainActor
@Observable
public final class DeskFilterModel {
    @ObservationIgnored private let focusedDesk: () -> DeskState?
    @ObservationIgnored private let focusBoard: (BoardID) -> Void
    public var query = ""
    public var phase: FilterPhase = .inactive
    public var selectionBoardID: BoardID?

    @ObservationIgnored private var centeringTask: Task<Void, Never>?
    @ObservationIgnored public var onCenterFocusedBoard: (() -> Void)?

    public init(focusedDesk: @escaping () -> DeskState?, focusBoard: @escaping (BoardID) -> Void) {
        self.focusedDesk = focusedDesk
        self.focusBoard = focusBoard
    }

    deinit {
        centeringTask?.cancel()
    }

    public var filteredBoards: [BoardState] {
        guard let focusedDesk = focusedDesk() else { return [] }
        return focusedDesk.boards.filter(matchesFilter)
    }

    public var totalBoardCount: Int { focusedDesk()?.boards.count ?? 0 }

    public var isPresented: Bool { phase != .inactive }
    public var isInputActive: Bool { phase == .filtering }
    public var isSelecting: Bool { phase == .selecting }

    public func enter() {
        guard focusedDesk()?.boards.isEmpty == false else { return }
        phase = .filtering
        updateSelection()
    }

    public func setQuery(_ query: String) {
        self.query = WebURLPolicy.stripNewlines(query)
        updateSelection()
    }

    public func confirmQuery() {
        guard phase == .filtering else { return }
        phase = .selecting
    }

    public func dismiss() {
        cancelCentering()
        phase = .inactive
        query = ""
        selectionBoardID = nil
    }

    public func cancelCentering() {
        centeringTask?.cancel()
        centeringTask = nil
    }

    public func selectBoard(by offset: Int) {
        let boards = filteredBoards
        selectionBoardID = SelectionNavigation.next(
            selectionBoardID,
            among: boards.map(\.id),
            by: offset)
    }

    public func confirmSelection(_ boardID: BoardID? = nil) {
        guard
            let boardID = boardID ?? selectionBoardID,
            filteredBoards.contains(where: { $0.id == boardID })
        else { return }
        dismiss()
        focusBoard(boardID)
        centeringTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled,
                let self,
                self.phase == .inactive,
                self.focusedDesk()?.focusedBoardID == boardID
            else { return }
            self.onCenterFocusedBoard?()
        }
    }

    public func matchesFilter(_ board: BoardState) -> Bool {
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
        if let focusedBoardID = focusedDesk()?.focusedBoardID,
            boards.contains(where: { $0.id == focusedBoardID })
        {
            selectionBoardID = focusedBoardID
        } else {
            selectionBoardID = boards.first?.id
        }
    }
}
