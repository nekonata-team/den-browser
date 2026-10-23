import DenDomain
import Foundation

public enum DenConfirmationRequest {
    case deleteDesk(DeskState)
    case replaceDesk(PendingDeskReplacement)
    case deleteDeskPreset(PersonalDeskPreset)
    case replaceDeskPreset(PersonalDeskPreset)
    case replaceEssential(existing: Essential, replacement: Essential)
    case endZmxSession(String)
    case clearDrawer(Int)
    case clearNotifications(Int)
    case resetDen
}

public struct PendingDeskReplacement {
    public let deskID: DeskID
    public let originalLabel: String
    public let originalBoardCount: Int
    public let presetLabel: String
    public let label: String
    public let boards: [DeskPresetBoard]
    public let focusedBoardIndex: BoardIndex?

    public init(
        deskID: DeskID,
        originalLabel: String,
        originalBoardCount: Int,
        presetLabel: String,
        label: String,
        boards: [DeskPresetBoard],
        focusedBoardIndex: BoardIndex?
    ) {
        self.deskID = deskID
        self.originalLabel = originalLabel
        self.originalBoardCount = originalBoardCount
        self.presetLabel = presetLabel
        self.label = label
        self.boards = boards
        self.focusedBoardIndex = focusedBoardIndex
    }
}
