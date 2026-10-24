import DenDomain

public enum BoardInsertion {
    public static func groupBoundaryOffset(_ offset: Int, in boards: [BoardState]) -> Int {
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
        public let anchorBoardID: BoardID?
    }

    public static func insert(
        _ board: BoardState,
        in desks: [DeskState],
        presentedDeskID: DeskID,
        deskID: DeskID? = nil,
        afterBoardID: BoardID? = nil,
        beforeBoardID: BoardID? = nil,
        focus: Bool = true
    ) -> Result? {
        guard beforeBoardID == nil || afterBoardID == nil else { return nil }
        let requestedAnchor = beforeBoardID ?? afterBoardID
        let anchorDeskIndex = requestedAnchor.flatMap { boardID in
            desks.firstIndex { desk in desk.boards.contains { $0.id == boardID } }
        }
        let deskIndex: Int
        if let deskID {
            guard let index = desks.firstIndex(where: { $0.id == deskID }) else { return nil }
            deskIndex = index
        } else if requestedAnchor != nil {
            guard let anchorDeskIndex else { return nil }
            deskIndex = anchorDeskIndex
        } else {
            guard let index = desks.firstIndex(where: { $0.id == presentedDeskID }) else { return nil }
            deskIndex = index
        }

        if beforeBoardID != nil, anchorDeskIndex == nil || (deskID != nil && anchorDeskIndex != deskIndex) {
            return nil
        }
        let explicitAnchor: BoardID?
        if let requestedAnchor, anchorDeskIndex == deskIndex {
            explicitAnchor = requestedAnchor
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
        let boardIndex: Int
        if let beforeBoardID,
            let group = BoardGroup.containing(beforeBoardID, in: boards),
            let groupStart = boards.firstIndex(where: { $0.id == group.primaryBoard.id })
        {
            boardIndex = groupStart
        } else {
            boardIndex = (groupEndIndex ?? anchorIndex).map { $0 + 1 } ?? boards.endIndex
        }
        var desk = desks[deskIndex]
        desk.boards.insert(board, at: boardIndex)
        if focus || desk.focusedBoardID == nil {
            desk.focusedBoardID = board.id
        }
        return Result(deskIndex: DeskIndex(rawValue: deskIndex), desk: desk, anchorBoardID: explicitAnchor)
    }
}
