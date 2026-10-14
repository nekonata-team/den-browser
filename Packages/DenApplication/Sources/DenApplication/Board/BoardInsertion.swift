import DenDomain

public enum BoardInsertion {
    static func groupBoundaryOffset(_ offset: Int, in boards: [BoardState]) -> Int {
        let offset = min(max(offset, 0), boards.count)
        guard offset > 0, offset < boards.count,
            let group = BoardGroup.containing(boards[offset - 1].id, in: boards),
            let lastMember = group.boards.last,
            let lastIndex = boards.lastIndex(where: { $0.id == lastMember.id })
        else { return offset }
        return max(offset, lastIndex + 1)
    }

    public struct Result {
        public let deskIndex: DeskIndex
        public let desk: DeskState
        /// The validated explicit anchor, excluding any implicit focused-Board fallback.
        public let afterBoardID: BoardID?
    }

    public static func insert(
        _ board: BoardState,
        in desks: [DeskState],
        presentedDeskID: DeskID,
        deskID: DeskID? = nil,
        afterBoardID: BoardID? = nil,
        focus: Bool = true
    ) -> Result? {
        let anchorDeskIndex = afterBoardID.flatMap { boardID in
            desks.firstIndex { desk in desk.boards.contains { $0.id == boardID } }
        }
        let deskIndex: Int
        if let deskID {
            guard let index = desks.firstIndex(where: { $0.id == deskID }) else { return nil }
            deskIndex = index
        } else if afterBoardID != nil {
            guard let anchorDeskIndex else { return nil }
            deskIndex = anchorDeskIndex
        } else {
            guard let index = desks.firstIndex(where: { $0.id == presentedDeskID }) else { return nil }
            deskIndex = index
        }

        let explicitAnchor: BoardID?
        if let afterBoardID, anchorDeskIndex == deskIndex {
            explicitAnchor = afterBoardID
        } else {
            guard deskID != nil || afterBoardID == nil else { return nil }
            explicitAnchor = nil
        }
        let boards = desks[deskIndex].boards
        let anchorBoardID = explicitAnchor ?? desks[deskIndex].focusedBoardID
        let anchorIndex = anchorBoardID.flatMap { id in boards.firstIndex { $0.id == id } }
        let groupEndIndex = anchorBoardID.flatMap { id in
            BoardGroup.containing(id, in: boards)?.boards.last.flatMap { member in
                boards.firstIndex { $0.id == member.id }
            }
        }
        let boardIndex = (groupEndIndex ?? anchorIndex).map { $0 + 1 } ?? boards.endIndex
        var desk = desks[deskIndex]
        desk.boards.insert(board, at: boardIndex)
        if focus || desk.focusedBoardID == nil {
            desk.focusedBoardID = board.id
        }
        return Result(deskIndex: DeskIndex(rawValue: deskIndex), desk: desk, afterBoardID: explicitAnchor)
    }
}
