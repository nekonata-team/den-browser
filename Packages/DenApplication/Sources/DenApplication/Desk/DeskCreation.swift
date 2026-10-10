import DenDomain
import Foundation

public enum DeskCreation {
    public static let maximumDeskCount = 10

    public struct Result {
        public let desks: [DeskState]
        public let createdDesk: DeskState
    }

    public static func create(
        label: String,
        presetBoards: [DeskPresetBoard],
        focusedBoardIndex: BoardIndex?,
        in desks: [DeskState],
        presentedDeskID: DeskID
    ) -> Result? {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !label.isEmpty, desks.count < maximumDeskCount,
            let deskIndex = desks.firstIndex(where: { $0.id == presentedDeskID }),
            let boards = DeskPresetBoard.makeBoards(from: presetBoards)
        else { return nil }
        let focusedBoardID = focusedBoardIndex.flatMap { index in
            boards.indices.contains(index.rawValue) ? boards[index.rawValue].id : nil
        }
        let desk = DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
        var updatedDesks = desks
        updatedDesks.insert(desk, at: deskIndex + 1)
        return Result(desks: updatedDesks, createdDesk: desk)
    }
}
