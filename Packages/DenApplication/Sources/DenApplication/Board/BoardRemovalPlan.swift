import DenDomain

public struct BoardRemovalPlan {
    public let desk: DeskState
    public let removedBoards: [BoardState]
    public let historyEntry: RecentlyRemovedBoard

    public static func make(
        _ boardID: BoardID,
        from source: DeskState,
        focusNext: Bool = false
    ) -> BoardRemovalPlan? {
        guard let boardOffset = source.boards.firstIndex(where: { $0.id == boardID }) else { return nil }
        let board = source.boards[boardOffset]
        let removedBoards =
            board.isSideBoard
            ? [board]
            : (BoardGroup.containing(board.id, in: source.boards)?.boards ?? [board])
        var desk = source
        for member in removedBoards.reversed() {
            guard let boardOffset = desk.boards.firstIndex(where: { $0.id == member.id }) else { continue }
            desk.boards.remove(at: boardOffset)
            if desk.anchorBoardID == member.id {
                desk.anchorBoardID = nil
            }
            if desk.boards.isEmpty {
                desk.scrollOffsetX = nil
            }
            guard desk.focusedBoardID == member.id else { continue }
            if focusNext && boardOffset < desk.boards.count {
                desk.focusedBoardID = desk.boards[boardOffset].id
            } else if boardOffset > 0 {
                desk.focusedBoardID = desk.boards[boardOffset - 1].id
            } else {
                desk.focusedBoardID = desk.boards.first?.id
            }
        }
        return BoardRemovalPlan(
            desk: desk,
            removedBoards: removedBoards,
            historyEntry: RecentlyRemovedBoard(
                board: board,
                sideBoard: removedBoards.first(where: { $0.id != board.id }),
                sourceDeskID: source.id,
                sourceBoardIndex: BoardIndex(rawValue: boardOffset)))
    }
}
