import Foundation

public struct DeskState: Codable, Equatable, Identifiable {
    public var id: DeskID
    public var label: String
    public var boards: [BoardState]
    public var focusedBoardID: BoardID? {
        didSet {
            if focusedBoardID != oldValue {
                scrollOffsetX = nil
            }
        }
    }
    public var scrollOffsetX: Double?
    public var anchorBoardID: BoardID?

    public func inheritedBoardWidth(for boardID: BoardID?) -> Double? {
        guard let board = boards.first(where: { $0.id == boardID }) else { return nil }
        let primaryID = board.sideBoardTargetBoardID ?? board.id
        return boards.first(where: { $0.id == primaryID })?.width
    }

    public init(
        id: DeskID = DeskID(),
        label: String,
        boards: [BoardState],
        focusedBoardID: BoardID? = nil,
        scrollOffsetX: Double? = nil,
        anchorBoardID: BoardID? = nil
    ) {
        self.id = id
        self.label = label
        self.boards = boards
        self.focusedBoardID = focusedBoardID ?? boards.first?.id
        self.scrollOffsetX = scrollOffsetX
        self.anchorBoardID = anchorBoardID
    }
}
