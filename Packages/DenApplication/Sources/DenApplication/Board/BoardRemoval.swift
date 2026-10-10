import DenDomain

public enum BoardRemoval {
    public struct Result {
        public let desk: DeskState
        public let removedBoards: [BoardState]
        public let historyEntry: RecentlyRemovedBoard
    }

    public static func remove(
        _ boardID: BoardID,
        from source: DeskState,
        focusNext: Bool = false
    ) -> Result? {
        guard let boardIndex = source.boards.firstIndex(where: { $0.id == boardID }) else { return nil }
        let board = source.boards[boardIndex]
        let removedBoards =
            board.isSideBoard
            ? [board]
            : (BoardGroup.containing(board.id, in: source.boards)?.boards ?? [board])
        var desk = source
        for member in removedBoards.reversed() {
            guard let index = desk.boards.firstIndex(where: { $0.id == member.id }) else { continue }
            desk.boards.remove(at: index)
            if desk.anchorBoardID == member.id {
                desk.anchorBoardID = nil
            }
            if desk.boards.isEmpty {
                desk.scrollOffsetX = nil
            }
            guard desk.focusedBoardID == member.id else { continue }
            if focusNext && index < desk.boards.count {
                desk.focusedBoardID = desk.boards[index].id
            } else if index > 0 {
                desk.focusedBoardID = desk.boards[index - 1].id
            } else {
                desk.focusedBoardID = desk.boards.first?.id
            }
        }
        return Result(
            desk: desk,
            removedBoards: removedBoards,
            historyEntry: RecentlyRemovedBoard(
                board: board,
                sideBoard: removedBoards.first(where: { $0.id != board.id }),
                sourceDeskID: source.id,
                sourceBoardIndex: boardIndex))
    }
}
