import DenDomain

public enum DeskReplacement {
    public struct Result {
        public let deskIndex: DeskIndex
        public let desk: DeskState
        public let removedBoards: [BoardState]
    }

    public static func replace(
        _ deskID: DeskID,
        label: String,
        presetBoards: [DeskPresetBoard],
        focusedBoardIndex: BoardIndex?,
        in desks: [DeskState]
    ) -> Result? {
        guard
            let deskIndex = desks.firstIndex(where: { $0.id == deskID }),
            let boards = DeskPresetBoard.makeBoards(from: presetBoards)
        else { return nil }
        var desk = desks[deskIndex]
        let removedBoards = desk.boards
        desk.label = label
        desk.boards = boards
        desk.focusedBoardID =
            focusedBoardIndex.flatMap { index in
                boards.indices.contains(index.rawValue) ? boards[index.rawValue].id : nil
            }
            ?? boards.first?.id
        desk.anchorBoardID = nil
        return Result(deskIndex: DeskIndex(rawValue: deskIndex), desk: desk, removedBoards: removedBoards)
    }
}
