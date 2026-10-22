public import DenDomain

public struct BoardFocusRequest: Equatable {
    public let deskID: DeskID
    public let boardID: BoardID

    public init(deskID: DeskID, boardID: BoardID) {
        self.deskID = deskID
        self.boardID = boardID
    }
}
