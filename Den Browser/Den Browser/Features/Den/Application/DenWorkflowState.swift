import DenDomain
import Foundation

enum DenConfirmationRequest {
    case deleteDesk(DeskState)
    case replaceDesk(PendingDeskReplacement)
    case deleteDeskPreset(PersonalDeskPreset)
    case replaceDeskPreset(PersonalDeskPreset)
    case clearDrawer(Int)
    case clearNotifications(Int)
    case resetDen
}

enum ActiveDrag: Equatable {
    case board(BoardID)
    case desk(DeskID)
}

struct RecentlyRemovedBoard {
    let board: BoardState
    var sideBoard: BoardState?
    let sourceDeskID: DeskID
    let sourceBoardIndex: Int
}

struct PendingDeskReplacement {
    let deskID: DeskID
    let originalLabel: String
    let originalBoardCount: Int
    let presetLabel: String
    let label: String
    let boards: [DeskPresetBoard]
    let focusedBoardIndex: Int?
}
