import DenDomain
import Foundation
import Observation

public struct OverviewSelection: Equatable {
    public let deskID: DeskID
    public let boardID: BoardID?

    public init(deskID: DeskID, boardID: BoardID?) {
        self.deskID = deskID
        self.boardID = boardID
    }
}

@MainActor
@Observable
public final class OverviewModel {
    public struct Actions {
        public let removeBoard: (BoardID, Bool) -> Void
        public let restoreBoard: () -> BoardID?
        public let enterSelection: (DeskID, BoardID?) -> Void
        public let beginDrag: (BoardID) -> Bool
        public let finishDrag: (BoardID, DeskID, BoardIndex) -> Void
        public let cancelDrag: () -> Void
        public let moveBoard: (BoardID, Int) -> Void
        public let moveBoardToDesk: (BoardID, Int) -> Void

        public init(
            removeBoard: @escaping (BoardID, Bool) -> Void,
            restoreBoard: @escaping () -> BoardID?,
            enterSelection: @escaping (DeskID, BoardID?) -> Void,
            beginDrag: @escaping (BoardID) -> Bool,
            finishDrag: @escaping (BoardID, DeskID, BoardIndex) -> Void,
            cancelDrag: @escaping () -> Void,
            moveBoard: @escaping (BoardID, Int) -> Void,
            moveBoardToDesk: @escaping (BoardID, Int) -> Void
        ) {
            self.removeBoard = removeBoard
            self.restoreBoard = restoreBoard
            self.enterSelection = enterSelection
            self.beginDrag = beginDrag
            self.finishDrag = finishDrag
            self.cancelDrag = cancelDrag
            self.moveBoard = moveBoard
            self.moveBoardToDesk = moveBoardToDesk
        }
    }

    @ObservationIgnored private let desks: () -> [DeskState]
    @ObservationIgnored private let presentedDeskID: () -> DeskID
    @ObservationIgnored private let focusedDesk: () -> DeskState?
    @ObservationIgnored private let activeBoardID: () -> BoardID?
    @ObservationIgnored private let isDragging: () -> Bool
    @ObservationIgnored private let actions: Actions

    public var query = ""
    public var filterPhase: FilterPhase = .inactive
    public private(set) var selection: OverviewSelection?
    public private(set) var selectionCenterRequest = 0
    public private(set) var canvasZoomSteps = 0
    public private(set) var canvasResetRequest = 0

    @ObservationIgnored public var onDismiss: (() -> Void)?
    @ObservationIgnored public var boardMidXs: [BoardID: CGFloat] = [:]

    public var allDesks: [DeskState] { desks() }
    public func removeBoard(_ id: BoardID) { actions.removeBoard(id, false) }

    public var isFilterPresented: Bool { filterPhase != .inactive }
    public var isFilterInputActive: Bool { filterPhase == .filtering }
    public var isFilterSelecting: Bool { filterPhase == .selecting }
    public var selectionDeskID: DeskID? { selection?.deskID }
    public var selectionBoardID: BoardID? { selection?.boardID }

    public init(
        desks: @escaping () -> [DeskState],
        presentedDeskID: @escaping () -> DeskID,
        focusedDesk: @escaping () -> DeskState?,
        activeBoardID: @escaping () -> BoardID?,
        isDragging: @escaping () -> Bool,
        actions: Actions
    ) {
        self.desks = desks
        self.presentedDeskID = presentedDeskID
        self.focusedDesk = focusedDesk
        self.activeBoardID = activeBoardID
        self.isDragging = isDragging
        self.actions = actions
    }

    public func preparePresentation(deskID: DeskID? = nil, boardID: BoardID? = nil) {
        query = ""
        filterPhase = .inactive
        selection = OverviewSelection(
            deskID: deskID ?? presentedDeskID(),
            boardID: boardID ?? focusedDesk()?.focusedBoardID)
    }

    public func endPresentation() {
        actions.cancelDrag()
        query = ""
        filterPhase = .inactive
        selection = nil
        boardMidXs = [:]
    }

    public func setQuery(_ query: String) {
        self.query = WebURLPolicy.stripNewlines(query)
        updateSelectionForFilter()
    }

    public func enterFilterMode() {
        filterPhase = .filtering
        updateSelectionForFilter()
    }

    public func exitFilterMode() {
        filterPhase = .inactive
        query = ""
    }

    public func confirmFilterQuery() {
        guard filterPhase == .filtering else { return }
        filterPhase = .selecting
    }

    public func clearQuery() {
        filterPhase = .inactive
        query = ""
        updateSelectionForFilter()
    }

    public func matchesFilter(_ board: BoardState, in desk: DeskState) -> Bool {
        guard !query.isEmpty else { return true }
        return board.displayName.localizedCaseInsensitiveContains(query)
            || (board.currentSheetURL?.absoluteString.localizedCaseInsensitiveContains(query) ?? false)
            || (board.terminalWorkingDirectory?.localizedCaseInsensitiveContains(query) ?? false)
            || (board.zellijSessionName?.localizedCaseInsensitiveContains(query) ?? false)
            || (board.zmxSessionName?.localizedCaseInsensitiveContains(query) ?? false)
            || desk.label.localizedCaseInsensitiveContains(query)
    }

    public func updateSelectionForFilter() {
        if let selection,
            let boardID = selection.boardID,
            let desk = desks().first(where: { $0.id == selection.deskID }),
            let board = desk.boards.first(where: { $0.id == boardID }),
            matchesFilter(board, in: desk)
        {
            return
        }

        for desk in desks() {
            if let board = desk.boards.first(where: { matchesFilter($0, in: desk) }) {
                setSelection(OverviewSelection(deskID: desk.id, boardID: board.id))
                return
            }
        }
        setSelection(nil)
    }

    public func removeSelectedBoard(focusNext: Bool) {
        guard !isDragging(), let selection, let boardID = selection.boardID,
            let desk = desks().first(where: { $0.id == selection.deskID })
        else { return }
        let boards = desk.boards.filter { matchesFilter($0, in: desk) }
        guard let index = boards.firstIndex(where: { $0.id == boardID }) else { return }
        actions.removeBoard(boardID, focusNext)
        let remainingIDs = Set(desks().first(where: { $0.id == desk.id })?.boards.map(\.id) ?? [])
        guard !remainingIDs.contains(boardID) else { return }
        let previous = boards[..<index].last { remainingIDs.contains($0.id) }?.id
        let next = boards.dropFirst(index + 1).first { remainingIDs.contains($0.id) }?.id
        setSelection(
            OverviewSelection(
                deskID: desk.id, boardID: focusNext ? (next ?? previous) : (previous ?? next)))
    }

    public func restoreRemovedBoard() {
        guard !isDragging(), let boardID = actions.restoreBoard() else { return }
        exitFilterMode()
        selectBoard(boardID)
    }

    public func enterSelection() {
        guard let selection else {
            onDismiss?()
            return
        }
        actions.enterSelection(selection.deskID, selection.boardID)
    }

    public func selectBoard(_ boardID: BoardID, center: Bool = true) {
        guard let desk = desks().first(where: { $0.boards.contains(where: { $0.id == boardID }) }) else { return }
        setSelection(OverviewSelection(deskID: desk.id, boardID: boardID), center: center)
    }

    public func enterBoard(_ boardID: BoardID) {
        selectBoard(boardID)
        enterSelection()
    }

    public func selectDesk(_ deskID: DeskID) {
        guard desks().contains(where: { $0.id == deskID }) else { return }
        setSelection(OverviewSelection(deskID: deskID, boardID: nil))
    }

    public func enterDesk(_ deskID: DeskID) {
        selectDesk(deskID)
        enterSelection()
    }

    public func beginBoardDrag(_ boardID: BoardID) -> Bool {
        guard query.isEmpty, filterPhase == .inactive, actions.beginDrag(boardID) else { return false }
        return true
    }

    public func finishBoardDrag(_ boardID: BoardID, toDeskID deskID: DeskID, at targetIndex: BoardIndex) {
        guard activeBoardID() == boardID else { return }
        actions.finishDrag(boardID, deskID, targetIndex)
        setSelection(OverviewSelection(deskID: deskID, boardID: boardID), center: false)
    }

    public func cancelBoardDrag() { actions.cancelDrag() }

    public func selectPreviousBoard() { moveBoardSelection(by: -1) }
    public func adjustCanvasZoom(by steps: Int) { canvasZoomSteps += steps }
    public func resetCanvasZoom() { canvasResetRequest += 1 }

    public func returnToCurrentDesk() {
        exitFilterMode()
        let deskID = presentedDeskID()
        let desk = desks().first { $0.id == deskID }
        selection = OverviewSelection(deskID: deskID, boardID: desk?.focusedBoardID)
        resetCanvasZoom()
    }

    public func selectNextBoard() { moveBoardSelection(by: 1) }
    public func selectPreviousDesk() { moveDeskSelection(by: -1) }
    public func selectNextDesk() { moveDeskSelection(by: 1) }
    public func moveSelectionBoardLeft() { moveSelectionBoard(by: -1) }
    public func moveSelectionBoardRight() { moveSelectionBoard(by: 1) }
    public func moveSelectionBoardToPreviousDesk() { moveSelectionBoardToDesk(by: -1) }
    public func moveSelectionBoardToNextDesk() { moveSelectionBoardToDesk(by: 1) }

    public func removedBoard(boardID: BoardID, deskID: DeskID, oldIndex: BoardIndex) {
        guard selection?.boardID == boardID,
            let desk = desks().first(where: { $0.id == deskID })
        else { return }
        let oldOffset = oldIndex.rawValue
        let nextBoardID =
            desk.boards.indices.contains(oldOffset)
            ? desk.boards[oldOffset].id
            : (oldOffset > 0 && desk.boards.indices.contains(oldOffset - 1)
                ? desk.boards[oldOffset - 1].id
                : nil)
        setSelection(OverviewSelection(deskID: deskID, boardID: nextBoardID))
    }

    public func invalidateBoard(_ boardID: BoardID) {
        guard selection?.boardID == boardID else { return }
        setSelection(nil)
    }

    public func invalidateDesk(_ deskID: DeskID) {
        guard selection?.deskID == deskID else { return }
        setSelection(nil)
    }

    private func setSelection(_ selection: OverviewSelection?, center: Bool = true) {
        self.selection = selection
        if center { selectionCenterRequest += 1 }
    }

    private func moveBoardSelection(by delta: Int) {
        guard let selection,
            let desk = desks().first(where: { $0.id == selection.deskID })
        else { return }
        let boards = desk.boards.filter { matchesFilter($0, in: desk) }
        guard !boards.isEmpty else { return }
        let index = selection.boardID.flatMap { id in boards.firstIndex { $0.id == id } } ?? 0
        setSelection(
            OverviewSelection(
                deskID: desk.id,
                boardID: boards[(index + delta % boards.count + boards.count) % boards.count].id))
    }

    private func moveDeskSelection(by delta: Int) {
        let desks = desks().filter { desk in
            query.isEmpty || desk.boards.contains { matchesFilter($0, in: desk) }
        }
        guard !desks.isEmpty else { return }
        let index = desks.firstIndex { $0.id == selection?.deskID } ?? 0
        let desk = desks[(index + delta % desks.count + desks.count) % desks.count]
        let boards = desk.boards.filter { matchesFilter($0, in: desk) }
        guard let firstBoard = boards.first else {
            setSelection(OverviewSelection(deskID: desk.id, boardID: nil))
            return
        }
        let currentMidX = selection?.boardID.flatMap { boardMidXs[$0] } ?? 0
        let targetBoard =
            boards.min {
                abs((boardMidXs[$0.id] ?? 0) - currentMidX) < abs((boardMidXs[$1.id] ?? 0) - currentMidX)
            } ?? firstBoard
        setSelection(OverviewSelection(deskID: desk.id, boardID: targetBoard.id))
    }

    private func moveSelectionBoard(by delta: Int) {
        guard !isDragging(), let boardID = selection?.boardID else { return }
        actions.moveBoard(boardID, delta)
        selectBoard(boardID)
    }

    private func moveSelectionBoardToDesk(by delta: Int) {
        guard !isDragging(), let boardID = selection?.boardID else { return }
        actions.moveBoardToDesk(boardID, delta)
        selectBoard(boardID)
    }
}
