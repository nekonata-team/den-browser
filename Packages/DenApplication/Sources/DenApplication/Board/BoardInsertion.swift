import DenDomain

public enum BoardInsertion {
    public struct Destination {
        public let deskIndex: Int
        public let boardIndex: Int
        /// The validated explicit anchor, excluding any implicit focused-Board fallback.
        public let afterBoardID: BoardID?
    }

    public static func resolve(
        in desks: [DeskState],
        presentedDeskID: DeskID,
        deskID: DeskID? = nil,
        afterBoardID: BoardID? = nil
    ) -> Destination? {
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
        return Destination(deskIndex: deskIndex, boardIndex: boardIndex, afterBoardID: explicitAnchor)
    }
}
