import AppKit
import DenDomain
import Foundation

extension DenStore {
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
        let deskID = state.desks[indices.desk].id
        let changed = presentedDeskID != deskID || state.desks[indices.desk].focusedBoardID != boardID
        if !changed {
            markNotificationsRead(for: boardID)
            if exitsDenMode {
                onWindowEffect?(.exitDenMode)
            }
            return
        }
        onWindowEffect?(.clearBoardInputRequests)
        state.desks[indices.desk].focusedBoardID = boardID
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
            let deskIndex = boardIndices(for: boardID)?.desk,
            let firstBoardID = state.desks[deskIndex].boards.first?.id
        else { return }
        focusBoard(firstBoardID)
    }

    func focusLastBoardInDesk(containing boardID: BoardID) {
        guard
            let deskIndex = boardIndices(for: boardID)?.desk,
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
            state.desks[indices.desk].boards[indices.board].isWeb
        else { return }

        state.desks[indices.desk].boards[indices.board].sheetNavigationPaused.toggle()
        let paused = state.desks[indices.desk].boards[indices.board].sheetNavigationPaused
        sheetNavigation.setBoardPaused(paused, for: boardID)
        save()
    }

    func centerFocusedBoard() {
        guard let focusedDeskIndex, focusedDesk?.focusedBoardID != nil else { return }
        if state.desks[focusedDeskIndex].scrollOffsetX != nil {
            state.desks[focusedDeskIndex].scrollOffsetX = nil
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
        moveFocusedBoard(toDeskAt: number - 1)
    }

    func focusedBoardIndex(in deskIndex: Int) -> Int? {
        guard let focusedBoardID = state.desks[deskIndex].focusedBoardID else { return nil }
        return state.desks[deskIndex].boards.firstIndex { $0.id == focusedBoardID }
    }

    func canMoveBoard(_ boardID: BoardID, by delta: Int) -> Bool {
        guard let indices = boardIndices(for: boardID), delta != 0 else { return false }
        let boards = state.desks[indices.desk].boards
        guard let group = BoardGroup.containing(boardID, in: boards),
            let first = group.boards.first,
            let last = group.boards.last,
            let firstIndex = boards.firstIndex(where: { $0.id == first.id }),
            let lastIndex = boards.firstIndex(where: { $0.id == last.id })
        else { return false }
        return delta < 0 ? firstIndex > 0 : lastIndex < boards.count - 1
    }

    func transferBoardGroup(containing boardID: BoardID, from sourceIndex: Int, to targetIndex: Int, at index: Int) {
        let sourceBoards = state.desks[sourceIndex].boards
        guard let group = BoardGroup.containing(boardID, in: sourceBoards) else { return }
        let groupBoards = group.boards
        let ids = Set(groupBoards.map(\.id))
        let removedIndex = sourceBoards.firstIndex { ids.contains($0.id) } ?? 0
        let sourceWasFocused = state.desks[sourceIndex].focusedBoardID.map(ids.contains) ?? false
        state.desks[sourceIndex].boards.removeAll { ids.contains($0.id) }
        if sourceWasFocused {
            let remaining = state.desks[sourceIndex].boards
            state.desks[sourceIndex].focusedBoardID =
                remaining.indices.contains(removedIndex)
                ? remaining[removedIndex].id
                : remaining.last?.id
        }
        let targetBoards = state.desks[targetIndex].boards
        var insertionIndex = min(max(index, 0), targetBoards.count)
        if insertionIndex > 0, insertionIndex < targetBoards.count {
            let precedingGroup = BoardGroup.containing(targetBoards[insertionIndex - 1].id, in: targetBoards)
            let precedingIDs = Set(precedingGroup?.boards.map(\.id) ?? [])
            if let lastMemberIndex = targetBoards.lastIndex(where: { precedingIDs.contains($0.id) }),
                insertionIndex <= lastMemberIndex
            {
                insertionIndex = lastMemberIndex + 1
            }
        }
        state.desks[targetIndex].boards.insert(contentsOf: groupBoards, at: insertionIndex)
    }

    func beginBoardDrag(_ boardID: BoardID) -> Bool {
        guard
            activeDrag == nil,
            let indices = boardIndices(for: boardID),
            indices.desk == focusedDeskIndex
        else {
            return false
        }
        state.desks[indices.desk].focusedBoardID = boardID
        markNotificationsRead(for: boardID)
        onWindowEffect?(.clearMaximizedBoard)
        activeDrag = .board(boardID)
        save()
        return true
    }

    func previewBoardMove(_ boardID: BoardID, to targetIndex: Int) {
        guard
            let deskIndex = focusedDeskIndex,
            (0..<state.desks[deskIndex].boards.count).contains(targetIndex)
        else { return }

        reorderBoardGroup(containing: boardID, to: targetIndex, in: deskIndex)
        state.desks[deskIndex].focusedBoardID = boardID
    }

    func reorderBoardGroup(containing boardID: BoardID, to targetIndex: Int, in deskIndex: Int) {
        let boards = state.desks[deskIndex].boards
        guard let group = BoardGroup.containing(boardID, in: boards), boards.indices.contains(targetIndex) else {
            return
        }
        let groupIDs = Set(group.boards.map(\.id))
        guard let firstIndex = boards.firstIndex(where: { groupIDs.contains($0.id) }) else { return }
        guard let destinationGroup = BoardGroup.containing(boards[targetIndex].id, in: boards) else { return }
        guard !destinationGroup.boards.contains(where: { groupIDs.contains($0.id) }) else { return }
        var remaining = boards.filter { !groupIDs.contains($0.id) }
        let insertionIndex: Int
        if targetIndex < firstIndex {
            insertionIndex =
                destinationGroup.boards.first.flatMap { member in
                    remaining.firstIndex(where: { $0.id == member.id })
                } ?? 0
        } else if let destinationLastID = destinationGroup.boards.last?.id,
            let index = remaining.firstIndex(where: { $0.id == destinationLastID })
        {
            insertionIndex = index + 1
        } else {
            insertionIndex = remaining.endIndex
        }
        remaining.insert(contentsOf: group.boards, at: insertionIndex)
        state.desks[deskIndex].boards = remaining
    }

    func restoreBoardOrder(_ boardIDs: [BoardID], in deskID: DeskID) {
        guard let deskIndex = state.desks.firstIndex(where: { $0.id == deskID }) else { return }
        let order = Dictionary(uniqueKeysWithValues: boardIDs.enumerated().map { ($1, $0) })
        state.desks[deskIndex].boards.sort {
            (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max)
        }
    }

    func finishBoardDrag() {
        guard case .board? = activeDrag else { return }
        activeDrag = nil
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

        activeDrag = .desk(deskID)
        return true
    }

    func previewDeskMove(_ deskID: DeskID, to targetIndex: Int) {
        guard
            let sourceIndex = state.desks.firstIndex(where: { $0.id == deskID }),
            state.desks.indices.contains(targetIndex),
            sourceIndex != targetIndex
        else { return }

        let desk = state.desks.remove(at: sourceIndex)
        state.desks.insert(desk, at: targetIndex)
    }

    func restoreDeskOrder(_ deskIDs: [DeskID]) {
        let order = Dictionary(uniqueKeysWithValues: deskIDs.enumerated().map { ($1, $0) })
        state.desks.sort {
            (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max)
        }
    }

    func finishDeskDrag() {
        guard case .desk? = activeDrag else { return }
        activeDrag = nil
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

        state.desks.swapAt(deskIndex, deskIndex + delta)
        save()
    }

    private func moveDeskFocus(by delta: Int) {
        guard let currentIndex = focusedDeskIndex, !state.desks.isEmpty else { return }
        onWindowEffect?(.dismissDeskFilter)
        let nextIndex = wrappedIndex(currentIndex + delta, count: state.desks.count)
        let targetDeskID = state.desks[nextIndex].id
        guard setFocusedDesk(targetDeskID) else { return }
        saveDeferredState()
    }

    private func moveBoardFocus(by delta: Int) {
        guard let deskIndex = focusedDeskIndex else { return }
        let boards = state.desks[deskIndex].boards
        guard !boards.isEmpty else { return }

        let nextIndex: Int
        if let currentIndex = focusedBoardIndex(in: deskIndex) {
            nextIndex = wrappedIndex(currentIndex + delta, count: boards.count)
        } else {
            nextIndex = delta >= 0 ? 0 : boards.count - 1
        }
        let boardID = boards[nextIndex].id
        let changesFocus = state.desks[deskIndex].focusedBoardID != boardID
        state.desks[deskIndex].focusedBoardID = boardID
        markNotificationsRead(for: boardID)
        guard changesFocus else { return }
        dispatchDenOperationEvent(.boardFocusMoved)
        saveDeferredState()
    }

    private func moveFocusedBoard(by delta: Int) {
        guard let deskIndex = focusedDeskIndex, let board = focusedBoard else { return }
        let boards = state.desks[deskIndex].boards
        guard let group = BoardGroup.containing(board.id, in: boards),
            let first = group.boards.first,
            let last = group.boards.last,
            let firstIndex = boards.firstIndex(where: { $0.id == first.id }),
            let lastIndex = boards.firstIndex(where: { $0.id == last.id })
        else { return }
        let boundaryIndex = delta < 0 ? firstIndex - 1 : lastIndex + 1
        guard boards.indices.contains(boundaryIndex) else { return }
        reorderBoardGroup(containing: board.id, to: boundaryIndex, in: deskIndex)
        state.desks[deskIndex].scrollOffsetX = nil
        centerFocusedBoard()
        save()
    }

    private func moveFocusedBoardToDesk(by delta: Int) {
        guard
            state.desks.count > 1,
            let sourceDeskIndex = focusedDeskIndex
        else { return }

        moveFocusedBoard(toDeskAt: wrappedIndex(sourceDeskIndex + delta, count: state.desks.count))
    }

    private func moveFocusedBoard(toDeskAt targetDeskIndex: Int) {
        guard
            state.desks.indices.contains(targetDeskIndex),
            let sourceDeskIndex = focusedDeskIndex,
            sourceDeskIndex != targetDeskIndex,
            let sourceBoardIndex = focusedBoardIndex(in: sourceDeskIndex)
        else { return }

        let boardID = state.desks[sourceDeskIndex].boards[sourceBoardIndex].id
        let insertIndex: Int
        if let focusedBoardID = state.desks[targetDeskIndex].focusedBoardID,
            let focusedIndex = state.desks[targetDeskIndex].boards.firstIndex(where: { $0.id == focusedBoardID })
        {
            insertIndex = focusedIndex + 1
        } else {
            insertIndex = state.desks[targetDeskIndex].boards.endIndex
        }

        transferBoardGroup(containing: boardID, from: sourceDeskIndex, to: targetDeskIndex, at: insertIndex)
        state.desks[targetDeskIndex].focusedBoardID = boardID
        setFocusedDesk(state.desks[targetDeskIndex].id, autoPIP: false)
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
            board = state.desks[indices.desk].boards[indices.board]
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
            state.desks[deskIndex].anchorBoardID = nil
            reportFeedback("Cleared Anchor Board")
        } else {
            state.desks[deskIndex].anchorBoardID = boardID
            reportFeedback("Set Anchor Board")
        }
        save()
    }

    func jumpToAnchorBoard() {
        guard let deskIndex = focusedDeskIndex else { return }
        let desk = state.desks[deskIndex]
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
