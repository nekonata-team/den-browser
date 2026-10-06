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

struct BoardLayoutMetrics: Equatable {
    let availableWidth: Double
    let spacing: Double
}
