import DenDomain
import Foundation

public enum TemporaryContext: Equatable {
    case essentialsPrefix
    case openBoard
    case universalSearch
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

public struct SaveEssentialDraft: Equatable {
    public var name: String
    public var key: String
    public var input: String

    public init(name: String, key: String, input: String) {
        self.name = name
        self.key = key
        self.input = input
    }
}

public struct BoardLayoutMetrics: Equatable {
    public let availableWidth: Double
    public let spacing: Double

    public init(availableWidth: Double, spacing: Double) {
        self.availableWidth = availableWidth
        self.spacing = spacing
    }

    public func boardWidth(toFit count: Int) -> Double? {
        guard (1...9).contains(count), availableWidth > 0 else { return nil }
        let width = (availableWidth - spacing * Double(count - 1)) / Double(count)
        guard width >= BoardState.minimumWidth else { return nil }
        return width
    }
}
