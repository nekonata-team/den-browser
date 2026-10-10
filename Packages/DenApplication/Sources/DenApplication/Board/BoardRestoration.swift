import DenDomain

public enum BoardRestoration {
    public enum Failure {
        case sideBoardAlreadyExists
        case targetBoardMissing
        case destinationDeskMissing
    }

    public enum Outcome {
        case insert(deskIndex: Int, boardIndex: Int)
        case focusExistingTutorial(BoardID)
        case rejected(Failure)
    }

    public static func resolve(
        _ removed: RecentlyRemovedBoard,
        in desks: [DeskState],
        presentedDeskID: DeskID
    ) -> Outcome {
        if removed.board.isTutorial,
            let existing = desks.lazy.flatMap(\.boards).first(where: \.isTutorial)
        {
            return .focusExistingTutorial(existing.id)
        }

        let deskIndex: Int
        let insertIndex: Int
        if let targetBoardID = removed.board.sideBoardTargetBoardID,
            let targetDeskIndex = desks.firstIndex(where: { $0.boards.contains { $0.id == targetBoardID } }),
            let targetBoardIndex = desks[targetDeskIndex].boards.firstIndex(where: { $0.id == targetBoardID })
        {
            let targetBoards = desks[targetDeskIndex].boards
            guard !targetBoards.contains(where: { $0.sideBoardTargetBoardID == targetBoardID }) else {
                return .rejected(.sideBoardAlreadyExists)
            }
            deskIndex = targetDeskIndex
            insertIndex =
                BoardGroup.containing(targetBoardID, in: targetBoards)?.boards.last.flatMap { member in
                    targetBoards.firstIndex(where: { $0.id == member.id }).map { $0 + 1 }
                } ?? targetBoardIndex + 1
        } else if removed.board.isSideBoard {
            return .rejected(.targetBoardMissing)
        } else if let sourceDeskIndex = desks.firstIndex(where: { $0.id == removed.sourceDeskID }) {
            deskIndex = sourceDeskIndex
            insertIndex = min(removed.sourceBoardIndex, desks[deskIndex].boards.endIndex)
        } else {
            guard let index = desks.firstIndex(where: { $0.id == presentedDeskID }) else {
                return .rejected(.destinationDeskMissing)
            }
            deskIndex = index
            let focusedBoardIndex = desks[index].focusedBoardID.flatMap { id in
                desks[index].boards.firstIndex(where: { $0.id == id })
            }
            insertIndex = focusedBoardIndex.map { $0 + 1 } ?? desks[index].boards.endIndex
        }

        let boards = desks[deskIndex].boards
        var insertionIndex = min(max(insertIndex, 0), boards.count)
        if insertionIndex > 0, insertionIndex < boards.count {
            let precedingGroup = BoardGroup.containing(boards[insertionIndex - 1].id, in: boards)
            if let lastMember = precedingGroup?.boards.last,
                let lastMemberIndex = boards.lastIndex(where: { $0.id == lastMember.id }),
                insertionIndex <= lastMemberIndex
            {
                insertionIndex = lastMemberIndex + 1
            }
        }
        return .insert(deskIndex: deskIndex, boardIndex: insertionIndex)
    }
}
