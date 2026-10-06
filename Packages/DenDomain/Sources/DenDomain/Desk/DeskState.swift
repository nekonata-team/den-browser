import Foundation

public struct DeskState: Codable, Equatable, Identifiable {
    public var id: UUID
    public var label: String
    public var boards: [BoardState]
    public var focusedBoardID: UUID? {
        didSet {
            if focusedBoardID != oldValue {
                scrollOffsetX = nil
            }
        }
    }
    public var scrollOffsetX: Double?
    public var anchorBoardID: UUID?

    public init(
        id: UUID = UUID(),
        label: String,
        boards: [BoardState],
        focusedBoardID: UUID? = nil,
        scrollOffsetX: Double? = nil,
        anchorBoardID: UUID? = nil
    ) {
        self.id = id
        self.label = label
        self.boards = boards
        self.focusedBoardID = focusedBoardID ?? boards.first?.id
        self.scrollOffsetX = scrollOffsetX
        self.anchorBoardID = anchorBoardID
    }
}
