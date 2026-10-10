import DenDomain

public enum BoardRestoration {
    public enum Failure {
        case sideBoardAlreadyExists
        case targetBoardMissing
        case destinationDeskMissing
    }

    public enum Outcome {
        case restored(deskIndex: DeskIndex, desk: DeskState)
        case focusExistingTutorial(BoardID)
        case rejected(Failure)
    }

    public static func restore(
        _ removed: RecentlyRemovedBoard,
        in desks: [DeskState],
        presentedDeskID: DeskID
    ) -> Outcome {
        if removed.board.isTutorial,
            let existing = desks.lazy.flatMap(\.boards).first(where: \.isTutorial)
        {
            return .focusExistingTutorial(existing.id)
        }

        let deskOffset: Int
        let insertOffset: Int
        if let targetBoardID = removed.board.sideBoardTargetBoardID,
            let targetDeskOffset = desks.firstIndex(where: { $0.boards.contains { $0.id == targetBoardID } }),
            let targetBoardOffset = desks[targetDeskOffset].boards.firstIndex(where: { $0.id == targetBoardID })
        {
            let targetBoards = desks[targetDeskOffset].boards
            guard !targetBoards.contains(where: { $0.sideBoardTargetBoardID == targetBoardID }) else {
                return .rejected(.sideBoardAlreadyExists)
            }
            deskOffset = targetDeskOffset
            insertOffset =
                BoardGroup.containing(targetBoardID, in: targetBoards)?.boards.last.flatMap { member in
                    targetBoards.firstIndex(where: { $0.id == member.id }).map { $0 + 1 }
                } ?? targetBoardOffset + 1
        } else if removed.board.isSideBoard {
            return .rejected(.targetBoardMissing)
        } else if let sourceDeskOffset = desks.firstIndex(where: { $0.id == removed.sourceDeskID }) {
            deskOffset = sourceDeskOffset
            insertOffset = min(removed.sourceBoardIndex.rawValue, desks[sourceDeskOffset].boards.endIndex)
        } else {
            guard let index = desks.firstIndex(where: { $0.id == presentedDeskID }) else {
                return .rejected(.destinationDeskMissing)
            }
            deskOffset = index
            let focusedBoardOffset = desks[index].focusedBoardID.flatMap { id in
                desks[index].boards.firstIndex(where: { $0.id == id })
            }
            insertOffset = focusedBoardOffset.map { $0 + 1 } ?? desks[index].boards.endIndex
        }

        let boards = desks[deskOffset].boards
        var insertionOffset = min(max(insertOffset, 0), boards.count)
        if insertionOffset > 0, insertionOffset < boards.count {
            let precedingGroup = BoardGroup.containing(boards[insertionOffset - 1].id, in: boards)
            if let lastMember = precedingGroup?.boards.last,
                let lastMemberIndex = boards.lastIndex(where: { $0.id == lastMember.id }),
                insertionOffset <= lastMemberIndex
            {
                insertionOffset = lastMemberIndex + 1
            }
        }
        var desk = desks[deskOffset]
        let restoredBoards = [removed.board] + (removed.sideBoard.map { [$0] } ?? [])
        desk.boards.insert(contentsOf: restoredBoards, at: insertionOffset)
        desk.focusedBoardID = removed.board.id
        return .restored(deskIndex: DeskIndex(rawValue: deskOffset), desk: desk)
    }
}
