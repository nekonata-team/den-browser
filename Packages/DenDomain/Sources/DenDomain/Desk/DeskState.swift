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
