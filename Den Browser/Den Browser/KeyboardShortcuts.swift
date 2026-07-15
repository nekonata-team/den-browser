import AppKit
import Foundation

enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    case toggleDenMode = "toggle-den-mode"
    case focusPreviousBoard = "focus-previous-board"
    case focusNextBoard = "focus-next-board"
    case moveFocusedBoardLeft = "move-focused-board-left"
    case moveFocusedBoardRight = "move-focused-board-right"

    var id: Self { self }

    var label: String {
        switch self {
        case .toggleDenMode: "Toggle Den Mode"
        case .focusPreviousBoard: "Focus Previous Board"
        case .focusNextBoard: "Focus Next Board"
        case .moveFocusedBoardLeft: "Move Focused Board Left"
        case .moveFocusedBoardRight: "Move Focused Board Right"
        }
    }

    var defaultBinding: ShortcutBinding {
        switch self {
        case .toggleDenMode:
            ShortcutBinding(key: .character(","), modifiers: [.control])
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

    var canBeUnassigned: Bool { self != .toggleDenMode }
}

struct ShortcutModifiers: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let control = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let shift = Self(rawValue: 1 << 2)
    static let command = Self(rawValue: 1 << 3)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(_ flags: NSEvent.ModifierFlags) {
        var value: Self = []
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.shift) { value.insert(.shift) }
        if flags.contains(.command) { value.insert(.command) }
        self = value
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.control) { flags.insert(.control) }
        if contains(.option) { flags.insert(.option) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.command) { flags.insert(.command) }
        return flags
    }

    var hasPrimaryModifier: Bool {
        !intersection([.control, .option, .command]).isEmpty
    }

    var displayTokens: [String] {
        [
            contains(.control) ? "⌃" : nil,
            contains(.option) ? "⌥" : nil,
            contains(.shift) ? "⇧" : nil,
            contains(.command) ? "⌘" : nil,
        ].compactMap(\.self)
    }

    var accessibilityLabel: String {
        [
            contains(.control) ? "Control" : nil,
            contains(.option) ? "Option" : nil,
            contains(.shift) ? "Shift" : nil,
            contains(.command) ? "Command" : nil,
        ].compactMap(\.self).joined(separator: ", ")
    }
}

enum ShortcutKey: Codable, Hashable {
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

    init?(event: NSEvent) {
        if let specialKey = event.specialKey, let key = Self(specialKey: specialKey) {
            self = key
            return
        }

        guard
            let characters = event.charactersIgnoringModifiers?.lowercased(),
            characters.count == 1,
            characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        self = .character(characters)
    }

    init?(keyEquivalent: String) {
        guard keyEquivalent.count == 1 else { return nil }
        if let scalar = keyEquivalent.unicodeScalars.first,
            let key = Self(specialKey: NSEvent.SpecialKey(rawValue: Int(scalar.value)))
        {
            self = key
            return
        }
        self = .character(keyEquivalent.lowercased())
    }

    private init?(specialKey: NSEvent.SpecialKey) {
        switch specialKey {
        case .leftArrow: self = .leftArrow
        case .rightArrow: self = .rightArrow
        case .upArrow: self = .upArrow
        case .downArrow: self = .downArrow
        case .carriageReturn, .enter, .newline: self = .returnKey
        case .tab, .backTab: self = .tab
        case .backspace, .delete: self = .backspace
        case .deleteForward: self = .deleteForward
        case .home: self = .home
        case .end: self = .end
        case .pageUp: self = .pageUp
        case .pageDown: self = .pageDown
        default:
            guard let number = Self.functionKeys.firstIndex(of: specialKey) else { return nil }
            self = .function(number + 1)
        }
    }

    private static let functionKeys: [NSEvent.SpecialKey] = [
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
        .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
    ]

    var displayName: String {
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
}

struct ShortcutBinding: Codable, Hashable {
    let key: ShortcutKey
    let modifiers: ShortcutModifiers

    init(key: ShortcutKey, modifiers: ShortcutModifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        guard let key = ShortcutKey(event: event) else { return nil }
        self.init(key: key, modifiers: ShortcutModifiers(event.modifierFlags))
    }

    init?(keyEquivalent: String, modifiers: NSEvent.ModifierFlags) {
        guard let key = ShortcutKey(keyEquivalent: keyEquivalent) else { return nil }
        self.init(key: key, modifiers: ShortcutModifiers(modifiers))
    }

    var isRecordable: Bool { modifiers.hasPrimaryModifier }

    var displayTokens: [String] { modifiers.displayTokens + [key.displayName] }

    var displayName: String { displayTokens.joined() }

    var accessibilityLabel: String {
        [modifiers.accessibilityLabel, key.displayName]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

enum ShortcutOverride: Codable, Equatable {
    case assigned(ShortcutBinding)
    case unassigned

    var binding: ShortcutBinding? {
        switch self {
        case .assigned(let binding): binding
        case .unassigned: nil
        }
    }
}

enum ShortcutValidationError: Equatable {
    case invalid
    case conflict(ShortcutAction)
}
