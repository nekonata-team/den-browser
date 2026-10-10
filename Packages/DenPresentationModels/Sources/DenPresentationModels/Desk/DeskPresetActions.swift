import Foundation

public enum DeskPresetSaveResult: Equatable {
    case created
    case replacementPending
    case invalidLabel
    case emptyDesk
    case reservedLabel
}

public enum DeskPresetRenameResult: Equatable {
    case renamed
    case unchanged
    case invalidLabel
    case reservedLabel
    case duplicateLabel
    case unavailable
}

public struct DeskPresetActions {
    public let save: (String) -> DeskPresetSaveResult
    public let rename: (UUID, String) -> DeskPresetRenameResult
    public let requestDeletion: (UUID) -> Void

    public init(
        save: @escaping (String) -> DeskPresetSaveResult,
        rename: @escaping (UUID, String) -> DeskPresetRenameResult,
        requestDeletion: @escaping (UUID) -> Void
    ) {
        self.save = save
        self.rename = rename
        self.requestDeletion = requestDeletion
    }
}
