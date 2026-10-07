import Foundation

public struct BoardGroup: Equatable, Identifiable {
    public var primaryBoard: BoardState
    public var sideBoard: BoardState?

    public var id: BoardID { primaryBoard.id }

    public var boards: [BoardState] {
        if let sideBoard { [primaryBoard, sideBoard] } else { [primaryBoard] }
    }

    public static func containing(_ boardID: BoardID, in boards: [BoardState]) -> BoardGroup? {
        guard let selectedBoard = boards.first(where: { $0.id == boardID }) else { return nil }
        let primaryID = selectedBoard.sideBoardTargetBoardID ?? selectedBoard.id
        guard let primaryBoard = boards.first(where: { $0.id == primaryID }) else {
            return BoardGroup(primaryBoard: selectedBoard, sideBoard: nil)
        }
        let sideBoards = boards.filter {
            $0.id != primaryBoard.id && $0.sideBoardTargetBoardID == primaryBoard.id
        }
        guard sideBoards.count <= 1 else { return nil }
        return BoardGroup(primaryBoard: primaryBoard, sideBoard: sideBoards.first)
    }
}
