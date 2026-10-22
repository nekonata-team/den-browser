import AppKit
import DenPresentationModels
import Foundation

public extension ShortcutModifiers {
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
}

public extension ShortcutKey {
    init?(event: NSEvent) {
        if let specialKey = event.specialKey, let key = Self(specialKey: specialKey) {
            self = key
            return
        }

        guard
            let characters = event.characters(byApplyingModifiers: [])?.lowercased(),
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
}

public extension ShortcutBinding {
    init?(event: NSEvent) {
        guard let key = ShortcutKey(event: event) else { return nil }
        self.init(key: key, modifiers: ShortcutModifiers(event.modifierFlags))
    }

    init?(keyEquivalent: String, modifiers: NSEvent.ModifierFlags) {
        guard let key = ShortcutKey(keyEquivalent: keyEquivalent) else { return nil }
        self.init(key: key, modifiers: ShortcutModifiers(modifiers))
    }
}
