import Foundation

enum TemporaryContext: Equatable {
    case essentialsPrefix
    case openBoard
    case zmxSessions
    case zmxDuplication
    case editBoardLink
    case newDesk
    case replaceDesk
    case deskPresetManagement
    case overview
    case boardActivity
    case keyboardShortcuts
    case boardWidth
    case saveDeskPreset
    case renameBoard
    case renameDesk
    case drawer
    case saveEssential
    case profilePicker
}

struct SaveEssentialDraft: Equatable {
    var name: String
    var key: String
    var input: String
}

enum DenFilterPhase: Equatable {
    case inactive
    case filtering
    case selecting
}

enum PendingConfirmation {
    case deleteDesk(DeskState)
    case replaceDesk(PendingDeskReplacement)
    case deleteDeskPreset(PersonalDeskPreset)
    case replaceDeskPreset(PersonalDeskPreset)
    case clearDrawer(Int)
    case clearNotifications(Int)
    case resetDen
}

enum ActiveDrag: Equatable {
    case board(UUID)
    case desk(UUID)
}

struct OverviewSelection: Equatable {
    let deskID: UUID
    let boardID: UUID?
}

struct BoardLayoutMetrics: Equatable {
    let availableWidth: Double
    let spacing: Double
}

struct RecentlyRemovedBoard {
    let board: BoardState
    var sideBoard: BoardState?
    let sourceDeskID: UUID
    let sourceBoardIndex: Int
}

struct PendingDeskReplacement {
    let deskID: UUID
    let originalLabel: String
    let originalBoardCount: Int
    let presetLabel: String
    let label: String
    let boards: [DeskPresetBoard]
    let focusedBoardIndex: Int?
}
