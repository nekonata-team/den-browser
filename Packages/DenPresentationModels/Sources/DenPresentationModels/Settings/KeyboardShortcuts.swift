import Foundation

public enum ConfigurableShortcut: String, CaseIterable, Codable, Identifiable {
    case toggleDenMode = "toggle-den-mode"
    case toggleBoardRail = "toggle-board-rail"
    case focusPreviousDesk = "focus-previous-desk"
    case focusNextDesk = "focus-next-desk"
    case returnToPreviousDesk = "return-to-previous-desk"
    case focusPreviousBoard = "focus-previous-board"
    case focusNextBoard = "focus-next-board"
    case moveFocusedBoardLeft = "move-focused-board-left"
    case moveFocusedBoardRight = "move-focused-board-right"

    public var id: Self { self }

    public var label: String {
        switch self {
        case .toggleDenMode: "Toggle Den Mode"
        case .toggleBoardRail: "Toggle Board Rail"
        case .focusPreviousDesk: "Focus Previous Desk"
        case .focusNextDesk: "Focus Next Desk"
        case .returnToPreviousDesk: "Return to Previous Desk"
        case .focusPreviousBoard: "Focus Previous Board"
        case .focusNextBoard: "Focus Next Board"
        case .moveFocusedBoardLeft: "Move Focused Board Left"
        case .moveFocusedBoardRight: "Move Focused Board Right"
        }
    }

    public var defaultBinding: ShortcutBinding {
        switch self {
        case .toggleDenMode:
            ShortcutBinding(key: .character(","), modifiers: [.control])
        case .toggleBoardRail:
            ShortcutBinding(key: .character("s"), modifiers: [.command])
        case .focusPreviousDesk:
            ShortcutBinding(key: .tab, modifiers: [.control, .shift])
        case .focusNextDesk:
            ShortcutBinding(key: .tab, modifiers: [.control])
        case .returnToPreviousDesk:
            ShortcutBinding(key: .tab, modifiers: [.command, .option])
        case .focusPreviousBoard:
            ShortcutBinding(key: .leftArrow, modifiers: [.command, .option])
        case .focusNextBoard:
            ShortcutBinding(key: .rightArrow, modifiers: [.command, .option])
        case .moveFocusedBoardLeft:
            ShortcutBinding(key: .leftArrow, modifiers: [.command, .option, .shift])
        case .moveFocusedBoardRight:
            ShortcutBinding(key: .rightArrow, modifiers: [.command, .option, .shift])
        }
    }

    public var canBeUnassigned: Bool { self != .toggleDenMode }
}

public struct ShortcutModifiers: OptionSet, Codable, Hashable {
    public let rawValue: Int

    public static let control = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let shift = Self(rawValue: 1 << 2)
    public static let command = Self(rawValue: 1 << 3)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public var hasPrimaryModifier: Bool {
        !intersection([.control, .option, .command]).isEmpty
    }

    public var displayTokens: [String] {
        [
            contains(.control) ? "⌃" : nil,
            contains(.option) ? "⌥" : nil,
            contains(.shift) ? "⇧" : nil,
            contains(.command) ? "⌘" : nil,
        ].compactMap(\.self)
    }

    public var accessibilityLabel: String {
        [
            contains(.control) ? "Control" : nil,
            contains(.option) ? "Option" : nil,
            contains(.shift) ? "Shift" : nil,
            contains(.command) ? "Command" : nil,
        ].compactMap(\.self).joined(separator: ", ")
    }
}

public enum ShortcutKey: Codable, Hashable {
    case character(String)
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case returnKey
    case tab
    case backspace
    case deleteForward
    case home
    case end
    case pageUp
    case pageDown
    case function(Int)

    public var displayName: String {
        switch self {
        case .character(" "): "Space"
        case .character(let character): character.uppercased()
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .returnKey: "Return"
        case .tab: "Tab"
        case .backspace: "Delete"
        case .deleteForward: "Forward Delete"
        case .home: "Home"
        case .end: "End"
        case .pageUp: "Page Up"
        case .pageDown: "Page Down"
        case .function(let number): "F\(number)"
        }
    }

    public var deskNumber: Int? {
        guard case .character(let character) = self else { return nil }
        guard character.count == 1, let number = Int(character), (0...9).contains(number) else {
            return nil
        }
        return number
    }
}

public struct ShortcutBinding: Codable, Hashable {
    public let key: ShortcutKey
    public let modifiers: ShortcutModifiers

    public init(key: ShortcutKey, modifiers: ShortcutModifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    public var isRecordable: Bool { modifiers.hasPrimaryModifier }

    public var displayTokens: [String] { modifiers.displayTokens + [key.displayName] }

    public var displayName: String { displayTokens.joined() }

    public var accessibilityLabel: String {
        [modifiers.accessibilityLabel, key.displayName]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

public enum ShortcutOverride: Codable, Equatable {
    case assigned(ShortcutBinding)
    case unassigned

    public var binding: ShortcutBinding? {
        switch self {
        case .assigned(let binding): binding
        case .unassigned: nil
        }
    }
}

public enum ShortcutValidationError: Equatable {
    case invalid
    case conflict(ConfigurableShortcut)
    case conflictWithDeskNumber
}
