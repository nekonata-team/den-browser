import AppKit
import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

extension DenController {
    func focusDesk(_ deskID: DeskID) {
        let changedDesk = setFocusedDesk(deskID)
        guard changedDesk || presentedDeskID == deskID else { return }
        if !changedDesk, let boardID = focusedDesk?.focusedBoardID {
            markNotificationsRead(for: boardID)
        }
        onWindowEffect?(.dismissDeskFilter)
        onWindowEffect?(.exitDenMode)
        if changedDesk { saveDeferredState() }
    }

    func focusBoard(_ boardID: BoardID, exitsDenMode: Bool = false) {
        guard let indices = boardIndices(for: boardID) else { return }
        let deskID = state.desks[indices.deskOffset].id
        let changed = presentedDeskID != deskID || state.desks[indices.deskOffset].focusedBoardID != boardID
        if !changed {
            markNotificationsRead(for: boardID)
            if exitsDenMode {
                onWindowEffect?(.exitDenMode)
            }
            return
        }
        onWindowEffect?(.clearBoardInputRequests)
        storage.state.desks[indices.deskOffset].focusedBoardID = boardID
        let changedDesk = setFocusedDesk(deskID)
        if !changedDesk && presentedDeskID == deskID {
            markNotificationsRead(for: boardID)
        }
        if exitsDenMode {
            onWindowEffect?(.exitDenMode)
        }
        saveDeferredState()
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

    func focusFirstBoardInDesk(containing boardID: BoardID) {
        guard
            let deskIndex = boardIndices(for: boardID)?.deskOffset,
            let firstBoardID = state.desks[deskIndex].boards.first?.id
        else { return }
        focusBoard(firstBoardID)
    }

    func focusLastBoardInDesk(containing boardID: BoardID) {
        guard
            let deskIndex = boardIndices(for: boardID)?.deskOffset,
            let lastBoardID = state.desks[deskIndex].boards.last?.id
        else { return }
        focusBoard(lastBoardID)
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

    func toggleFocusedBoardSheetNavigationPause() {
        guard let focusedBoardID = focusedDesk?.focusedBoardID else { return }
        toggleBoardSheetNavigationPause(focusedBoardID)
    }

    func toggleBoardSheetNavigationPause(_ boardID: BoardID) {
        guard
            let indices = boardIndices(for: boardID),
            state.desks[indices.deskOffset].boards[indices.boardOffset].isWeb
        else { return }

        storage.state.desks[indices.deskOffset].boards[indices.boardOffset].sheetNavigationPaused.toggle()
        let paused = state.desks[indices.deskOffset].boards[indices.boardOffset].sheetNavigationPaused
        sheetNavigation.setBoardPaused(paused, for: boardID)
        save()
    }

    func centerFocusedBoard() {
        guard let focusedDeskIndex, focusedDesk?.focusedBoardID != nil else { return }
        if state.desks[focusedDeskIndex.rawValue].scrollOffsetX != nil {
            storage.state.desks[focusedDeskIndex.rawValue].scrollOffsetX = nil
            save()
        }
        onWindowEffect?(.centerFocusedBoard)
    }

    func revealPreviousBoard() {
        guard focusedDesk?.focusedBoardID != nil else { return }
        onWindowEffect?(.revealPreviousBoard)
    }

    func revealNextBoard() {
        guard focusedDesk?.focusedBoardID != nil else { return }
        onWindowEffect?(.revealNextBoard)
    }

    func focusDesk(number: Int) {
        guard (1...Self.maximumDeskCount).contains(number) else { return }
        guard state.desks.indices.contains(number - 1) else {
            reportFeedback("Desk \(number) does not exist.", severity: .warning)
            return
        }
        focusDesk(state.desks[number - 1].id)
    }

    func moveFocusedBoard(toDeskNumber number: Int) {
        guard (1...Self.maximumDeskCount).contains(number) else { return }
        guard state.desks.indices.contains(number - 1) else {
            reportFeedback("Desk \(number) does not exist.", severity: .warning)
            return
        }
        moveFocusedBoard(toDeskAt: DeskIndex(rawValue: number - 1))
    }

    func focusedBoardIndex(in deskIndex: DeskIndex) -> BoardIndex? {
        let deskOffset = deskIndex.rawValue
        guard let focusedBoardID = state.desks[deskOffset].focusedBoardID else { return nil }
        return state.desks[deskOffset].boards.firstIndex { $0.id == focusedBoardID }
            .map { BoardIndex(rawValue: $0) }
    }

    func canMoveBoard(_ boardID: BoardID, by delta: Int) -> Bool {
        storage.boardMovement.canMove(boardID, by: delta)
    }

    func transferBoardGroup(
        containing boardID: BoardID,
        from sourceIndex: DeskIndex,
        to targetIndex: DeskIndex,
        at index: BoardIndex
    ) {
        storage.boardMovement.transfer(
            boardID,
            from: state.desks[sourceIndex.rawValue].id,
            to: state.desks[targetIndex.rawValue].id,
            at: index)
    }

    func beginBoardDrag(_ boardID: BoardID) -> Bool {
        guard
            activeDrag == nil,
            let indices = boardIndices(for: boardID),
            indices.desk == focusedDeskIndex
        else {
            return false
        }
        storage.state.desks[indices.deskOffset].focusedBoardID = boardID
        markNotificationsRead(for: boardID)
        onWindowEffect?(.clearMaximizedBoard)
        storage.activeDrag = .board(boardID)
        save()
        return true
    }

    func previewBoardMove(_ boardID: BoardID, to targetIndex: BoardIndex) {
        guard
            let deskIndex = focusedDeskIndex,
            (0..<state.desks[deskIndex.rawValue].boards.count).contains(targetIndex.rawValue)
        else { return }

        reorderBoardGroup(
            containing: boardID,
            to: targetIndex,
            in: deskIndex)
        storage.state.desks[deskIndex.rawValue].focusedBoardID = boardID
    }

    func reorderBoardGroup(containing boardID: BoardID, to targetIndex: BoardIndex, in deskIndex: DeskIndex) {
        storage.boardMovement.reorder(
            boardID,
            to: targetIndex,
            in: state.desks[deskIndex.rawValue].id)
    }

    func restoreBoardOrder(_ boardIDs: [BoardID], in deskID: DeskID) {
        storage.boardMovement.restoreOrder(boardIDs, in: deskID)
    }

    func finishBoardDrag() {
        guard case .board? = activeDrag else { return }
        storage.activeDrag = nil
        save()
    }

    func requestBoardDragCancellation() {
        guard case .board? = activeDrag else { return }
        onWindowEffect?(.cancelBoardDrag)
    }

    func beginDeskDrag(_ deskID: DeskID) -> Bool {
        guard
            activeDrag == nil,
            state.desks.contains(where: { $0.id == deskID })
        else {
            return false
        }

        storage.activeDrag = .desk(deskID)
        return true
    }

    func previewDeskMove(_ deskID: DeskID, to targetIndex: DeskIndex) {
        let targetOffset = targetIndex.rawValue
        guard
            let sourceIndex = state.desks.firstIndex(where: { $0.id == deskID }),
            state.desks.indices.contains(targetOffset),
            sourceIndex != targetOffset
        else { return }

        let desk = storage.state.desks.remove(at: sourceIndex)
        storage.state.desks.insert(desk, at: targetOffset)
    }

    func restoreDeskOrder(_ deskIDs: [DeskID]) {
        let order = Dictionary(uniqueKeysWithValues: deskIDs.enumerated().map { ($1, $0) })
        storage.state.desks.sort {
            (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max)
        }
    }

    func finishDeskDrag() {
        guard case .desk? = activeDrag else { return }
        storage.activeDrag = nil
        save()
    }

    func requestDeskDragCancellation() {
        guard case .desk? = activeDrag else { return }
        onWindowEffect?(.cancelDeskDrag)
    }

    func moveDesk(_ deskID: DeskID, by delta: Int) {
        guard
            activeDrag == nil,
            let deskIndex = state.desks.firstIndex(where: { $0.id == deskID }),
            state.desks.indices.contains(deskIndex + delta)
        else { return }

        storage.state.desks.swapAt(deskIndex, deskIndex + delta)
        save()
    }

    private func moveDeskFocus(by delta: Int) {
        guard let currentIndex = focusedDeskIndex, !state.desks.isEmpty else { return }
        onWindowEffect?(.dismissDeskFilter)
        let nextIndex = wrappedIndex(currentIndex.rawValue + delta, count: state.desks.count)
        let targetDeskID = state.desks[nextIndex].id
        guard setFocusedDesk(targetDeskID) else { return }
        saveDeferredState()
    }

    private func moveBoardFocus(by delta: Int) {
        guard let deskIndex = focusedDeskIndex else { return }
        let boards = state.desks[deskIndex.rawValue].boards
        guard !boards.isEmpty else { return }

        let nextIndex: BoardIndex
        if let currentIndex = focusedBoardIndex(in: deskIndex) {
            nextIndex = BoardIndex(rawValue: wrappedIndex(currentIndex.rawValue + delta, count: boards.count))
        } else {
            nextIndex = BoardIndex(rawValue: delta >= 0 ? 0 : boards.count - 1)
        }
        let boardID = boards[nextIndex.rawValue].id
        let changesFocus = state.desks[deskIndex.rawValue].focusedBoardID != boardID
        storage.state.desks[deskIndex.rawValue].focusedBoardID = boardID
        markNotificationsRead(for: boardID)
        guard changesFocus else { return }
        dispatchDenOperationEvent(.boardFocusMoved)
        saveDeferredState()
    }

    private func moveFocusedBoard(by delta: Int) {
        guard let deskIndex = focusedDeskIndex, let board = focusedBoard else { return }
        let boards = state.desks[deskIndex.rawValue].boards
        guard let group = BoardGroup.containing(board.id, in: boards),
            let first = group.boards.first,
            let last = group.boards.last,
            let firstIndex = boards.firstIndex(where: { $0.id == first.id }),
            let lastIndex = boards.firstIndex(where: { $0.id == last.id })
        else { return }
        let boundaryIndex = delta < 0 ? firstIndex - 1 : lastIndex + 1
        guard boards.indices.contains(boundaryIndex) else { return }
        reorderBoardGroup(
            containing: board.id,
            to: BoardIndex(rawValue: boundaryIndex),
            in: deskIndex)
        storage.state.desks[deskIndex.rawValue].scrollOffsetX = nil
        centerFocusedBoard()
        save()
    }

    private func moveFocusedBoardToDesk(by delta: Int) {
        guard
            state.desks.count > 1,
            let sourceDeskIndex = focusedDeskIndex
        else { return }

        moveFocusedBoard(
            toDeskAt: DeskIndex(rawValue: wrappedIndex(sourceDeskIndex.rawValue + delta, count: state.desks.count)))
    }

    private func moveFocusedBoard(toDeskAt targetDeskIndex: DeskIndex) {
        let targetOffset = targetDeskIndex.rawValue
        guard
            state.desks.indices.contains(targetOffset),
            let sourceDeskIndex = focusedDeskIndex,
            sourceDeskIndex != targetDeskIndex,
            let sourceBoardIndex = focusedBoardIndex(in: sourceDeskIndex)
        else { return }

        let boardID = state.desks[sourceDeskIndex.rawValue].boards[sourceBoardIndex.rawValue].id
        let insertIndex: BoardIndex
        if let focusedBoardID = state.desks[targetOffset].focusedBoardID,
            let focusedIndex = state.desks[targetOffset].boards.firstIndex(where: { $0.id == focusedBoardID })
        {
            insertIndex = BoardIndex(rawValue: focusedIndex + 1)
        } else {
            insertIndex = BoardIndex(rawValue: state.desks[targetOffset].boards.endIndex)
        }

        transferBoardGroup(containing: boardID, from: sourceDeskIndex, to: targetDeskIndex, at: insertIndex)
        storage.state.desks[targetOffset].focusedBoardID = boardID
        setFocusedDesk(state.desks[targetOffset].id, autoPIP: false)
        onWindowEffect?(.exitDenMode)
        save()
    }

    func copyBoardID(_ boardID: BoardID, pasteboard: NSPasteboard? = nil) {
        let pasteboard = pasteboard ?? self.pasteboard
        guard state.desks.contains(where: { $0.boards.contains { $0.id == boardID } }) else { return }
        pasteboard.clearContents()
        pasteboard.setString(boardID.rawValue.uuidString.lowercased(), forType: .string)
        reportFeedback("Copied Board ID.", severity: .success)
    }

    func copyBoardLocation(_ boardID: BoardID? = nil, pasteboard: NSPasteboard? = nil) {
        let pasteboard = pasteboard ?? self.pasteboard
        let board: BoardState?
        if let boardID {
            guard let indices = boardIndices(for: boardID) else { return }
            board = state.desks[indices.deskOffset].boards[indices.boardOffset]
        } else {
            board = focusedBoard
        }
        guard let board else { return }

        let value: String
        let message: String
        switch board.kind {
        case .web(let web):
            guard let url = web.currentSheetURL ?? web.firstSheetURL else { return }
            value = url.absoluteString
            message = "Copied Current Sheet URL."
        case .inspection:
            guard let targetBoardID = board.sideBoardTargetBoardID else { return }
            value = targetBoardID.rawValue.uuidString.lowercased()
            message = "Copied target Board ID."
        case .terminal(let terminal):
            switch terminal {
            case .shell(let workingDirectory):
                value = workingDirectory
                message = "Copied Terminal working directory."
            case .zellij(let zellij):
                guard let sessionName = zellij.sessionName, !sessionName.isEmpty else { return }
                value = sessionName
                message = "Copied Zellij session name."
            case .zmx(let zmx):
                value = zmx.sessionName
                message = "Copied zmx session name."
            }
        case .tutorial:
            return
        }

        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        reportFeedback(message, severity: .success)
    }

    func toggleAnchorBoard() {
        guard let desk = focusedDesk, let focusedBoardID = desk.focusedBoardID else { return }
        toggleAnchorBoard(focusedBoardID, in: desk.id)
    }

    func toggleAnchorBoard(_ boardID: BoardID, in deskID: DeskID) {
        guard let deskIndex = state.desks.firstIndex(where: { $0.id == deskID }),
            state.desks[deskIndex].boards.contains(where: { $0.id == boardID })
        else { return }

        if state.desks[deskIndex].anchorBoardID == boardID {
            storage.state.desks[deskIndex].anchorBoardID = nil
            reportFeedback("Cleared Anchor Board")
        } else {
            storage.state.desks[deskIndex].anchorBoardID = boardID
            reportFeedback("Set Anchor Board")
        }
        save()
    }

    func jumpToAnchorBoard() {
        guard let deskIndex = focusedDeskIndex else { return }
        let desk = state.desks[deskIndex.rawValue]
        guard let anchorBoardID = desk.anchorBoardID,
            desk.boards.contains(where: { $0.id == anchorBoardID })
        else {
            reportFeedback("No Anchor Board in Desk", severity: .warning)
            return
        }

        let currentBoardID = desk.focusedBoardID
        if currentBoardID != anchorBoardID {
            anchorJumpOriginBoardIDByDesk[desk.id] = currentBoardID
            focusBoard(anchorBoardID)
            centerFocusedBoard()
        } else if let originID = anchorJumpOriginBoardIDByDesk[desk.id],
            originID != anchorBoardID,
            desk.boards.contains(where: { $0.id == originID })
        {
            anchorJumpOriginBoardIDByDesk[desk.id] = anchorBoardID
            focusBoard(originID)
            centerFocusedBoard()
        }
    }
}
