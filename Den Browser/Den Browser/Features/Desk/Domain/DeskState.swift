import Foundation

struct DeskState: Codable, Equatable, Identifiable {
    var id: UUID
    var label: String
    var boards: [BoardState]
    var focusedBoardID: UUID? {
        didSet {
            if focusedBoardID != oldValue {
                scrollOffsetX = nil
            }
        }
    }
    var scrollOffsetX: Double?
    var anchorBoardID: UUID?

    init(
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
