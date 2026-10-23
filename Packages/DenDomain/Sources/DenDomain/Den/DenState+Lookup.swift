public struct BoardIndices {
    public let desk: DeskIndex
    public let board: BoardIndex

    public var deskOffset: Int { desk.rawValue }
    public var boardOffset: Int { board.rawValue }

    public init(desk: DeskIndex, board: BoardIndex) {
        self.desk = desk
        self.board = board
    }
}

extension DenState {
    public func boardIndices(for boardID: BoardID) -> BoardIndices? {
        for deskIndex in desks.indices {
            if let boardIndex = desks[deskIndex].boards.firstIndex(where: { $0.id == boardID }) {
                return BoardIndices(desk: DeskIndex(rawValue: deskIndex), board: BoardIndex(rawValue: boardIndex))
            }
        }
        return nil
    }

    public func board(for boardID: BoardID) -> BoardState? {
        guard let indices = boardIndices(for: boardID) else { return nil }
        return desks[indices.deskOffset].boards[indices.boardOffset]
    }
}
