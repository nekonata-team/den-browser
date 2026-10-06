import Foundation

public struct PersonalDeskPreset: Codable, Equatable, Identifiable {
    public var id: UUID
    public var label: String
    public var boards: [DeskPresetBoard]
    public var focusedBoardIndex: Int?

    public init(id: UUID = UUID(), label: String, desk: DeskState) {
        self.id = id
        self.label = label
        let presetBoards = desk.boards.filter { !$0.isTutorial }
        boards = DeskPresetBoard.capture(from: presetBoards)
        focusedBoardIndex = desk.focusedBoardID.flatMap { focusedBoardID in
            presetBoards.firstIndex { $0.id == focusedBoardID }
        }
    }
}
